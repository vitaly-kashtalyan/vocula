import AppKit
import Carbon.HIToolbox
import VoculaKit

struct TapEvent {
  let kind: RawKeyEvent.Kind
  let keyCode: UInt16
  let flags: UInt64
  let isRepeat: Bool
  let userData: Int64
  let keyboardType: Int64

  var raw: RawKeyEvent { RawKeyEvent(kind: kind, keyCode: keyCode, flags: flags) }

  init(
    kind: RawKeyEvent.Kind, keyCode: UInt16, flags: UInt64,
    isRepeat: Bool, userData: Int64, keyboardType: Int64 = 0
  ) {
    self.kind = kind
    self.keyCode = keyCode
    self.flags = flags
    self.isRepeat = isRepeat
    self.userData = userData
    self.keyboardType = keyboardType
  }

  init?(type: CGEventType, event: CGEvent) {
    switch type {
    case .keyDown: kind = .keyDown
    case .keyUp: kind = .keyUp
    case .flagsChanged: kind = .flagsChanged
    default: return nil
    }
    keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    flags = event.flags.rawValue
    isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    userData = event.getIntegerValueField(.eventSourceUserData)
    keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
  }
}

@MainActor
final class HotkeyMonitor {
  private(set) var config: GestureConfig
  private var machine: GestureStateMachine
  private var ledger = SwallowLedger()
  private var reArm = ReArmCounter()
  private var passiveTap: EventTap!
  private var activeTap: EventTap!
  private var deadlineTimer: Timer?
  private var stuckHold = StuckHoldDetector()
  private var stuckHoldTimer: Timer?
  private let clock: () -> Timestamp
  private(set) var lastKeyboardType: Int64 = 0

  private let onSignal: (DictationSignal) -> Void
  private let onTapLost: (Int) -> Void
  private let onGestureAbandoned: () -> Void
  private let onTapReArmed: () -> Void
  private let onLanguageCycle: () -> Void
  private let onLanguageCycleEnded: () -> Void
  private var cycling = false

  init(
    config: GestureConfig,
    onSignal: @escaping (DictationSignal) -> Void,
    onTapLost: @escaping (Int) -> Void,
    onGestureAbandoned: @escaping () -> Void,
    onTapReArmed: @escaping () -> Void = {},
    onLanguageCycle: @escaping () -> Void = {},
    onLanguageCycleEnded: @escaping () -> Void = {},
    clock: (() -> Timestamp)? = nil
  ) {
    self.config = config
    self.machine = GestureStateMachine(config: config)
    self.onSignal = onSignal
    self.onTapLost = onTapLost
    self.onGestureAbandoned = onGestureAbandoned
    self.onTapReArmed = onTapReArmed
    self.onLanguageCycle = onLanguageCycle
    self.onLanguageCycleEnded = onLanguageCycleEnded
    let started = ContinuousClock.now
    self.clock = clock ?? { started.duration(to: .now) }
  }

  @discardableResult
  func start() -> Bool {
    if passiveTap == nil {
      passiveTap = EventTap(
        options: .defaultTap,
        handler: { [weak self] type, event in
          if let tapEvent = TapEvent(type: type, event: event) {
            _ = self?.consume(tapEvent)
          }
          return event
        },
        onDisabled: { [weak self] in self?.handleDisabled() })
    }
    if activeTap == nil {
      activeTap = EventTap(
        options: .defaultTap,
        handler: { [weak self] type, event in
          guard let self,
            let tapEvent = TapEvent(type: type, event: event)
          else { return event }
          return self.consume(tapEvent) ? nil : event
        },
        onDisabled: { [weak self] in self?.handleDisabled() })
    }
    guard passiveTap.install(), activeTap.install() else { return false }
    syncActiveTap()
    return true
  }

  func stop() {
    deadlineTimer?.invalidate()
    deadlineTimer = nil
    stuckHoldTimer?.invalidate()
    stuckHoldTimer = nil
    passiveTap?.uninstall()
    activeTap?.uninstall()
  }

  @discardableResult
  func reinstallAfterPermissionChange() -> Bool {
    stop()
    return start()
  }

  func update(config: GestureConfig) {
    self.config = config
    machine.config = config
    if machine.isRecording {
      machine.abandon()
      onGestureAbandoned()
    }
    ledger.reset()
    syncActiveTap()
    syncStuckHoldTimer()
  }

  func abandonCurrentGesture() {
    machine.abandon()
    syncActiveTap()
    syncStuckHoldTimer()
  }

  private enum Interception {
    case capture((CapturedKey) -> Void, cancelled: () -> Void)
    case liveCheck(KeyBinding, (LiveCheckEvent) -> Void, cancelled: () -> Void)
  }
  private var interception: Interception?
  private var capturePeakModifiers: ModifierSet = []
  private var captureReported = false

  func beginCapture(
    onCapture: @escaping (CapturedKey) -> Void,
    onCancel: @escaping () -> Void
  ) {
    capturePeakModifiers = []
    captureReported = false
    interception = .capture(onCapture, cancelled: onCancel)
    syncActiveTap()
  }

  func beginLiveCheck(
    of candidate: KeyBinding,
    onEvent: @escaping (LiveCheckEvent) -> Void,
    onCancel: @escaping () -> Void
  ) {
    interception = .liveCheck(candidate, onEvent, cancelled: onCancel)
    syncActiveTap()
  }

  func endInterception() {
    if case .liveCheck(let candidate, _, _) = interception,
      candidate.absorbsOwnEvent, let keyCode = candidate.keyCode
    {
      ledger.releaseBindingUp(keyCode, owner: .liveCheck)
    }
    interception = nil
    capturePeakModifiers = []
    captureReported = false
    syncActiveTap()
  }

  private func intercept(_ interception: Interception, _ event: TapEvent) -> Bool {
    let keyCode = event.keyCode
    if keyCode == UInt16(kVK_Escape) {
      if event.kind == .keyDown {
        switch interception {
        case .capture(_, let cancelled): cancelled()
        case .liveCheck(_, _, let cancelled): cancelled()
        }
        ledger.noteEscapeDown(swallowed: true)
        endInterception()
      }
      return true
    }

    switch interception {
    case .capture(let report, _):
      guard !captureReported else { return true }
      let modifiers = KeyMatching.sidedModifiers(in: event.flags)
      if event.kind == .flagsChanged {
        if modifiers.isEmpty {
          if !capturePeakModifiers.isEmpty {
            report(CapturedKey(keyCode: nil, modifiers: capturePeakModifiers))
            capturePeakModifiers = []
            captureReported = true
          }
        } else {
          capturePeakModifiers.formUnion(modifiers)
        }
      } else if event.kind == .keyDown {
        report(CapturedKey(keyCode: keyCode, modifiers: capturePeakModifiers))
        capturePeakModifiers = []
        captureReported = true
      }
      return true

    case .liveCheck(let candidate, let report, _):
      let raw = event.raw
      guard KeyMatching.matchesShape(candidate, raw),
        ownsRelease(candidate, raw, owner: .liveCheck)
      else {
        return false
      }
      let pressed = KeyMatching.isPress(raw)
      if candidate.absorbsOwnEvent {
        if pressed {
          ledger.claimBindingDown(keyCode, owner: .liveCheck)
        } else {
          ledger.releaseBindingUp(keyCode, owner: .liveCheck)
        }
      }
      report(pressed ? .press(at: now()) : .release(at: now()))
      return true
    }
  }

  func consume(_ event: TapEvent) -> Bool {
    guard !SelfEventFilter.isOurs(userData: event.userData) else { return false }

    lastKeyboardType = event.keyboardType
    let at = now()
    let keyCode = event.keyCode

    if let interception {
      return intercept(interception, event)
    }

    if event.isRepeat, ledger.ownsBindingUp(keyCode) { return true }

    let absorb = TapPolicy.absorbedKeys(config: config, isRecording: machine.isRecording)

    let raw = event.raw
    if cycling, let cycle = config.languageCycle,
      !KeyMatching.isBindingHeld(cycle, flags: raw.flags)
    {
      cycling = false
      onLanguageCycleEnded()
    }
    if KeyMatching.matchesLanguageCycle(config: config, event: raw) {
      var swallowCycle = false
      if KeyMatching.isPress(raw) {
        swallowCycle = absorb.languageCycle
        if swallowCycle { ledger.claimBindingDown(keyCode) }
        if !event.isRepeat {
          cycling = true
          onLanguageCycle()
        }
      } else if raw.kind == .keyUp {
        swallowCycle = ledger.releaseBindingUp(keyCode)
      }
      syncActiveTap()
      return swallowCycle
    }

    var swallow = false

    if let classified = classify(event, at: at) {
      switch classified.kind {
      case .binding:
        let absorbs = absorb.primaryBinding
        switch event.kind {
        case .keyDown:
          swallow = absorbs
          if absorbs { ledger.claimBindingDown(keyCode) }
        case .keyUp:
          swallow = ledger.releaseBindingUp(keyCode)
        case .flagsChanged:
          swallow = absorbs
        }
      case .escapeDown:
        swallow = absorb.escape
        ledger.noteEscapeDown(swallowed: swallow)
      case .escapeUp:
        swallow = ledger.consumeEscapeUp()
        syncActiveTap()
      case .foreign:
        swallow = false
      }
      if let input = classified.input { emit(machine.handle(input)) }
    }
    return swallow
  }

  private func classify(_ event: TapEvent, at: Timestamp) -> Classified? {
    let keyCode = event.keyCode
    if keyCode == UInt16(kVK_Escape) {
      switch event.kind {
      case .keyDown:
        return Classified(input: .escape(at), kind: .escapeDown)
      case .keyUp:
        return Classified(input: nil, kind: .escapeUp)
      default:
        return nil
      }
    }
    if isPrimary(event.raw) {
      let input: GestureInput =
        KeyMatching.isPress(event.raw)
        ? .bindingDown(at) : .bindingUp(at)
      return Classified(input: input, kind: .binding)
    }
    if event.kind == .keyDown { return Classified(input: .foreignKey(at), kind: .foreign) }
    if event.kind == .flagsChanged, KeyMatching.isDown(keyCode, in: event.flags) {
      return Classified(input: .foreignKey(at), kind: .foreign)
    }
    return nil
  }

  private struct Classified {
    enum Kind { case binding, escapeDown, escapeUp, foreign }
    let input: GestureInput?
    let kind: Kind
  }

  private func isPrimary(_ event: RawKeyEvent) -> Bool {
    guard KeyMatching.matchesPrimary(config: config, event: event) else { return false }
    return ownsRelease(config.primary, event, owner: .normal)
  }

  private func ownsRelease(
    _ binding: KeyBinding, _ event: RawKeyEvent,
    owner: SwallowLedger.Owner
  ) -> Bool {
    guard event.kind == .keyUp, binding.absorbsOwnEvent else { return true }
    return ledger.ownsBindingUp(event.keyCode, owner: owner)
  }

  private func emit(_ output: GestureOutput) {
    output.signals.forEach(onSignal)
    if output.signals.contains(where: {
      if case .start = $0 { return true }
      return false
    }) {
      stuckHold.reset()
    }
    arm(output.nextDeadline)
    syncActiveTap()
    syncStuckHoldTimer()
  }

  private func arm(_ deadline: Timestamp?) {
    deadlineTimer?.invalidate()
    deadlineTimer = nil
    guard let deadline else { return }
    let delay = max(0, Double((deadline - now()).milliseconds)) / 1000
    let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.emit(self.machine.handle(.tick(self.now())))
      }
    }
    // .common: a default-mode timer does not fire while a menu is tracking.
    RunLoop.main.add(timer, forMode: .common)
    deadlineTimer = timer
  }

  private func syncActiveTap() {
    let needsActive =
      TapPolicy.needsActiveTap(
        config: config,
        isRecording: machine.isRecording)
      || ledger.awaitsRelease
      || interception != nil
    activeTap?.setEnabled(needsActive)
    passiveTap?.setEnabled(!needsActive)
  }

  private static let stuckHoldPollInterval: TimeInterval = 0.25

  private func syncStuckHoldTimer() {
    let shouldPoll =
      machine.isHoldingBinding && config.primary.isBareModifier
      && KeyMatching.pollMask(for: config.primary) != nil
    guard shouldPoll else {
      stuckHoldTimer?.invalidate()
      stuckHoldTimer = nil
      return
    }
    guard stuckHoldTimer == nil else { return }
    let timer = Timer(timeInterval: Self.stuckHoldPollInterval, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.pollStuckHold() }
    }
    // .common: a default-mode timer does not fire while a menu is tracking.
    RunLoop.main.add(timer, forMode: .common)
    stuckHoldTimer = timer
  }

  private func pollStuckHold() {
    guard machine.isHoldingBinding, config.primary.isBareModifier else { return }
    let flags = CGEventSource.flagsState(.hidSystemState)
    if stuckHold.poll(
      modifierIsDown: KeyMatching.isBindingHeld(
        config.primary, flags: flags.rawValue)) == .releaseWasLost
    {
      emit(machine.handle(.bindingUp(now())))
    }
  }

  private func handleDisabled() {
    let passiveCameBack = passiveTap?.reArm() ?? false
    let activeCameBack = activeTap?.reArm() ?? false
    let cameBack = passiveCameBack && activeCameBack
    syncActiveTap()
    if !cameBack { onTapLost(0) }
    let verdict = reArm.disabled(at: now())
    onTapReArmed()
    if case .reArmAndWarn(let attempt) = verdict { onTapLost(attempt) }
  }

  private func now() -> Timestamp { clock() }
}
