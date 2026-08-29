import Carbon.HIToolbox
import SwiftUI
import VoculaKit

@MainActor
final class BindingSettingsModel: ObservableObject {
  enum Slot: String, Identifiable, CaseIterable {
    case record, languageCycle
    var id: String { rawValue }

    var title: LocalizedStringResource {
      switch self {
      case .record:
        return .init(
          "binding.slot.record", defaultValue: "Record key",
          comment: "Keyboard row: the key held to dictate.")
      case .languageCycle:
        return .init(
          "binding.slot.languageCycle", defaultValue: "Cycle language",
          comment: "Keyboard row: the key that steps through languages.")
      }
    }

    var symbol: String {
      switch self {
      case .record: return "mic"
      case .languageCycle: return "globe"
      }
    }
  }

  @Published private(set) var bindings: [Slot: KeyBinding] = [:]
  @Published private(set) var notices: [Slot: String] = [:]
  @Published private(set) var recording: Slot?
  @Published private(set) var checking: Slot?
  @Published private(set) var outcomes: [Slot: LiveCheckOutcome] = [:]
  @Published private(set) var checkStartedAt: Date?

  private var store: BindingStore
  private var check = LiveCheck()
  private var timeoutTask: Task<Void, Never>?
  private var captureTimeout: Task<Void, Never>?
  private let monitor: HotkeyMonitor
  private let onSaved: (GestureConfig) -> Void

  init(
    monitor: HotkeyMonitor, defaults: UserDefaults = .standard,
    onSaved: @escaping (GestureConfig) -> Void
  ) {
    self.monitor = monitor
    self.store = BindingStore(defaults: defaults)
    self.onSaved = onSaved
    reload()
  }

  func binding(for slot: Slot) -> KeyBinding? { bindings[slot] }
  func notice(for slot: Slot) -> String? { notices[slot] }
  func outcome(for slot: Slot) -> LiveCheckOutcome? { outcomes[slot] }

  static var notSet: String {
    String(
      localized: "binding.notSet", defaultValue: "not set",
      comment:
        "Stands in for a key combination when nothing is bound. Lower case: it is read where a chord would be."
    )
  }

  func name(of slot: Slot) -> String {
    bindings[slot].map { KeyNames.describe($0) } ?? Self.notSet
  }

  func parts(of slot: Slot) -> [String] {
    bindings[slot].map { KeyNames.parts($0) } ?? [Self.notSet]
  }

  var checkDeadline: Date? {
    checkStartedAt?.addingTimeInterval(Self.timeoutSeconds)
  }

  private static let timeoutSeconds =
    Double(LiveCheckTiming.timeout.components.seconds)

  private func reload() {
    bindings = [.record: store.primary, .languageCycle: store.languageCycle]
  }

  @Published private(set) var lettersAreBlocked = false

  func record(_ slot: Slot) {
    recording = slot
    notices[slot] = nil
    outcomes[slot] = nil
    lettersAreBlocked = IsSecureEventInputEnabled()
    monitor.beginCapture(
      onCapture: { [weak self] key in
        Task { @MainActor in
          guard self?.recording == slot else { return }
          self?.capture(slot, key)
        }
      },
      onCancel: { [weak self] in
        Task { @MainActor in self?.recording = nil }
      })

    captureTimeout?.cancel()
    captureTimeout = Task { [weak self] in
      do { try await Task.sleep(for: LiveCheckTiming.timeout) } catch { return }
      await MainActor.run {
        guard let self, self.recording == slot else { return }
        self.monitor.endInterception()
        self.recording = nil
        self.notices[slot] = String(localized: KeyboardScreenCopy.noKeyArrived)
        Announce.say(self.notices[slot] ?? "")
      }
    }
  }

  func cancelCapture() {
    captureTimeout?.cancel()
    monitor.endInterception()
    recording = nil
  }

  func capture(_ slot: Slot, _ key: CapturedKey) {
    captureTimeout?.cancel()
    monitor.endInterception()
    recording = nil
    save(slot, BindingCapture.binding(from: key))
  }

  private func save(_ slot: Slot, _ binding: KeyBinding) {
    let verdict: BindingVerdict
    switch slot {
    case .record: verdict = store.save(primary: binding)
    case .languageCycle: verdict = store.save(languageCycle: binding)
    }
    reload()
    notices[slot] = Self.notice(for: binding, verdict: verdict)
    let announcement = String(
      localized: KeyboardScreenCopy.bindingChanged(
        String(localized: slot.title), name(of: slot)))
    Announce.say([announcement, notices[slot]].compactMap { $0 }.joined(separator: ". "))
    onSaved(store.config)
  }

  static func notice(for binding: KeyBinding, verdict: BindingVerdict) -> String? {
    var lines: [String] = []
    switch verdict {
    case .rejected(let key):
      lines.append(
        String(localized: KeyboardScreenCopy.notSaved) + " "
          + BindingBlacklist.text(forKey: key))
    case .warning(let key):
      lines.append(
        String(localized: KeyboardScreenCopy.warningPrefix) + " "
          + BindingBlacklist.text(forKey: key))
    case .allowed:
      break
    }
    if let conflict = SystemHotkeys.conflict(
      for: binding,
      in: SystemHotkeys.systemDefaults())
    {
      lines.append(String(localized: KeyboardScreenCopy.collides(conflict.displayName)))
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  func startLiveCheck(_ slot: Slot) {
    guard let binding = bindings[slot] else { return }
    check = LiveCheck()
    checking = slot
    outcomes[slot] = nil
    checkStartedAt = Date()

    monitor.beginLiveCheck(
      of: binding,
      onEvent: { [weak self] event in
        Task { @MainActor in self?.observe(slot, event) }
      },
      onCancel: { [weak self] in
        Task { @MainActor in self?.cancelCheck() }
      })

    timeoutTask?.cancel()
    timeoutTask = Task { [weak self] in
      do { try await Task.sleep(for: LiveCheckTiming.timeout) } catch { return }
      await MainActor.run { self?.observe(slot, .timeout(at: LiveCheckTiming.timeout)) }
    }
  }

  func cancelCheck() {
    timeoutTask?.cancel()
    monitor.endInterception()
    checking = nil
    checkStartedAt = nil
  }

  func observe(_ slot: Slot, _ event: LiveCheckEvent) {
    guard checking == slot else { return }
    check.observe(event)
    guard let outcome = check.outcome else { return }

    checking = nil
    checkStartedAt = nil
    timeoutTask?.cancel()
    monitor.endInterception()
    outcomes[slot] = outcome
    Announce.say(LiveCheck.explanation(for: outcome))
  }
}

struct BindingSettingsView: View {
  @ObservedObject var model: BindingSettingsModel

  var body: some View {
    Section {
      row(.record)
      row(.languageCycle)
    } footer: {
      Text(KeyboardScreenCopy.hold(model.name(of: .record)))
    }
  }

  @ViewBuilder
  private func row(_ slot: BindingSettingsModel.Slot) -> some View {
    LabeledContent {
      trailing(slot)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: slot.symbol)
          .font(.system(size: 13))
          .foregroundStyle(Theme.accentText)
          .frame(width: 30, height: 30)
          .background(Theme.tileFill, in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 5) {
          Text(slot.title)
            .accessibilityIdentifier("binding.\(slot.rawValue).title")
          state(slot)
        }
      }
    }
    if model.recording == slot, model.lettersAreBlocked {
      warning(
        String(
          localized: "binding.secureInput",
          defaultValue:
            "Secure input is on, so macOS is not passing key presses to any app but the one in front. Only modifiers can be recorded right now. It is usually Terminal's “Secure Keyboard Entry”, a password field, or a password manager — close or turn that off, then try again.",
          comment:
            "Shown while recording a binding. “Secure Keyboard Entry” is Terminal's own menu item and is translated as Terminal translates it."
        ))
    }
    if let notice = model.notice(for: slot) { warning(notice) }
    if let outcome = model.outcome(for: slot), outcome != .working {
      warning(LiveCheck.explanation(for: outcome))
    }
  }

  private func state(_ slot: BindingSettingsModel.Slot) -> some View {
    let state = rowState(slot)
    return HStack(spacing: 5) {
      Image(systemName: state.symbol)
        .font(.system(size: 9))
      Text(state.text)
        .textCase(.uppercase)
        .font(Theme.label)
        .tracking(1)
    }
    .foregroundStyle(state.colour)
  }

  private func rowState(_ slot: BindingSettingsModel.Slot)
    -> (text: LocalizedStringResource, symbol: String, colour: Color)
  {
    if model.recording == slot {
      return (KeyboardScreenCopy.listeningForAKey, "circle.fill", Theme.accentText)
    }
    if model.checking == slot {
      return (KeyboardScreenCopy.waitingForTheKey, "circle.fill", Theme.accentText)
    }
    switch model.outcome(for: slot) {
    case .none:
      return (KeyboardScreenCopy.notTested, "circle.fill", Theme.textMuted)
    case .working:
      return (KeyboardScreenCopy.arrivesCorrectly, "checkmark", .green)
    case .nothingArrived:
      return (KeyboardScreenCopy.neverArrives, "exclamationmark.triangle.fill", Theme.warning)
    case .pressWithoutRelease:
      return (KeyboardScreenCopy.onlyPress, "exclamationmark.triangle.fill", Theme.warning)
    case .releaseWithoutPress:
      return (KeyboardScreenCopy.onlyRelease, "exclamationmark.triangle.fill", Theme.warning)
    }
  }

  @ViewBuilder
  private func trailing(_ slot: BindingSettingsModel.Slot) -> some View {
    if model.recording == slot {
      HStack(spacing: 12) {
        KeycapView(name: "?", accented: true)
        Text(KeyboardScreenCopy.pressAnyKey)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Theme.accentText)
          .accessibilityIdentifier("binding.capturing")
        Button(CommonCopy.cancel) { model.cancelCapture() }
      }
    } else if model.checking == slot {
      HStack(spacing: 12) {
        VStack(alignment: .trailing, spacing: 6) {
          Text(KeyboardScreenCopy.pressNow(model.name(of: slot)))
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
          if let started = model.checkStartedAt, let deadline = model.checkDeadline {
            ProgressView(timerInterval: started...deadline, countsDown: true) {
              EmptyView()
            } currentValueLabel: {
              EmptyView()
            }
            .progressViewStyle(.linear)
            .frame(width: 140)
          }
        }
        Button(CommonCopy.cancel) { model.cancelCheck() }
      }
    } else {
      HStack(spacing: 14) {
        KeycapChord(parts: model.parts(of: slot))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text(verbatim: model.name(of: slot)))
          .accessibilityIdentifier("binding.\(slot.rawValue).value")
        controls(slot)
      }
    }
  }

  @ViewBuilder
  private func controls(_ slot: BindingSettingsModel.Slot) -> some View {
    let busy = model.recording != nil || model.checking != nil
    ControlGroup {
      Button(KeyboardScreenCopy.change) { model.record(slot) }
        .disabled(busy)
        .accessibilityIdentifier("binding.\(slot.rawValue).change")
      Button(KeyboardScreenCopy.test) { model.startLiveCheck(slot) }
        .disabled(busy)
        .accessibilityIdentifier("binding.\(slot.rawValue).check")
    }
    .fixedSize()
  }

  private func warning(_ text: String) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Theme.warning)
    }
    .font(.callout)
  }
}
