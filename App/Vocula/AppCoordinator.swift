import AppKit
import Carbon.HIToolbox
import VoculaKit
import VoculaWhisper

@MainActor
func withBound(_ bound: Duration, _ work: @escaping @Sendable () async -> Void) async {
  let job = Task { await work() }
  let timer = Task { try? await Task.sleep(for: bound) }
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    let once = ResumeOnce(continuation)
    Task {
      await job.value
      await once.fire()
    }
    Task {
      await timer.value
      await once.fire()
    }
  }
  job.cancel()
  timer.cancel()
}

private actor ResumeOnce {
  private var continuation: CheckedContinuation<Void, Never>?
  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }
  func fire() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
final class AppCoordinator: ObservableObject {
  let menu: MenuBarController
  private let indicator = IndicatorPanel()
  private let settings: AppSettings
  private var bindingStore = BindingStore(defaults: VoculaAppDelegate.bindingDefaults)
  private var monitor: HotkeyMonitor?
  private var controller: DictationController?
  private var inserter: TextInserter?

  func finishInFlightWork() async {
    guard let controller else { return }
    await withBound(.seconds(3)) { await controller.drain() }
    inserter?.settleOwedRestore()
  }
  private let recorder = AudioRecorder()
  let historyStore: DayFileHistoryStore
  private var retentionTask: Task<Void, Never>?
  private let signals = StreamFanout<DictationSignal>(bufferingPolicy: .unbounded)
  private var signalPump: Task<Void, Never>?
  private var pipelineTasks: [Task<Void, Never>] = []
  private var isStarting = false
  @Published private(set) var bindingModel: BindingSettingsModel?
  private var refusalDismissTask: Task<Void, Never>?
  private var refusalDedup = RefusalDedup()
  private var diagnosticLog: DiagnosticLog?

  private static var launchDetail: String {
    let version = Bundle.main.shortVersion
    let build = Bundle.main.buildNumber
    let os = ProcessInfo.processInfo.operatingSystemVersion
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var raw = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &raw, &size, nil, 0)
    let model = String(cString: raw).replacingOccurrences(of: ",", with: "-")
    return "version=\(version) build=\(build) "
      + "os=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion) mac=\(model)"
  }

  init(menu: MenuBarController) {
    let settings = AppSettings()
    let store = DayFileHistoryStore(
      directory: ApplicationSupport.directory.appendingPathComponent("History"),
      cipher: KeychainCipher(),
      isRecordingEnabled: { [settings] in settings.isRecordingHistory })
    self.menu = menu
    self.settings = settings
    self.historyStore = store
  }

  func log(_ kind: String, _ detail: String) {
    guard let diagnosticLog else { return }
    let timestamp = Date()
    Task.detached(priority: .utility) {
      diagnosticLog.record(kind, detail, at: timestamp)
    }
  }

  func start() async {
    guard monitor == nil, !isStarting else { return }
    isStarting = true
    defer { isStarting = false }
    await recorder.setDiagnose { [weak self] kind, detail in
      Task { @MainActor in self?.log(kind, detail) }
    }
    AudioDiagnostics.setSink { [weak self] kind, detail in
      Task { @MainActor in self?.log(kind, detail) }
    }
    if diagnosticLog == nil {
      let url = MenuBarController.diagnosticLogURL
      let log = await Task.detached(priority: .utility) {
        DiagnosticLog(fileURL: url)
      }.value
      diagnosticLog = log
      await historyStore.attach(diagnosticLog: log)
      log.record("app.launch", Self.launchDetail)
    }
    startRetentionIfNeeded()
    let inputs = await Task.detached(priority: .userInitiated) {
      AudioInputDevices.snapshot()
    }.value
    MicrophonePriorityMigration.runIfNeeded(settings: settings, snapshot: inputs)
    MicrophonePriorityMigration.blankLegacyNamesIfNeeded(settings: settings)
    MicrophonePriorityMigration.reconcile(settings: settings, snapshot: inputs)
    menu.watchInputDevices()
    let store = ModelStore(
      directory: ApplicationSupport.modelsDirectory,
      fileSystem: SystemModelFileSystem())
    let transcriptionModel = settings.transcriptionModel
    let modelsAreReady = await Task.detached(priority: .utility) {
      store.isReady([transcriptionModel, .speechDetector])
    }.value
    guard modelsAreReady else {
      menu.iconState = .error(MenuBarController.modelsNotDownloaded)
      menu.showsDownloadAction = true
      startMonitorOnly()
      return
    }
    menu.showsDownloadAction = false
    menu.iconState = .idle
    let engine = WhisperEngine(modelPath: store.url(for: transcriptionModel))
    let detector = WhisperVADDetector(modelPath: store.url(for: .speechDetector))

    let monitor = HotkeyMonitor(
      config: bindingStore.config,
      onSignal: { [weak self] signal in
        if case .stop(_, reason: .durationLimit) = signal {
          self?.indicator.note(
            String(
              localized: "indicator.durationLimit",
              defaultValue: "The recording reached the three-minute limit and stopped by itself.",
              comment:
                "Drawn on the indicator strip, which clamps at three lines; IndicatorChipSizeTests measures every locale against it."
            ),
            for: Self.refusalDismissDelay, alert: true)
        }
        self?.signals.emit(signal)
      },
      onTapLost: makeOnTapLost(),
      onGestureAbandoned: { [weak self] in
        Task { await self?.controller?.gestureAbandoned() }
      },
      onTapReArmed: { [weak self] in
        Task { @MainActor in self?.log("tap.rearm", "") }
      },
      onLanguageCycle: { [weak self] in self?.cycleLanguage() },
      onLanguageCycleEnded: { [weak self] in self?.indicator.clearStatus() })
    let inserter = TextInserter(
      clipboard: SystemClipboard(), paste: SyntheticPaste(),
      recordClipboardNotRestored: { [diagnosticLog] in
        let timestamp = Date()
        Task.detached(priority: .utility) {
          diagnosticLog?.record(
            "insert.clipboardNotRestored",
            "", at: timestamp)
        }
      })
    self.inserter = inserter
    let controller = DictationController(
      dependencies: .init(
        audio: recorder,
        detector: detector,
        engine: engine,
        probe: AXTargetProbe(),
        inserter: inserter,
        filter: TextFilter(),
        history: historyStore,
        modelID: transcriptionModel.rawValue,
        timings: .default,
        languages: { [settings] in settings.languages },
        targetBundleID: { pid in NSRunningApplication(processIdentifier: pid)?.bundleIdentifier },
        abandonGesture: { [weak monitor] in
          Task { @MainActor in monitor?.abandonCurrentGesture() }
        },
        diagnose: { [weak self] kind, detail in
          Task { @MainActor in self?.log(kind, detail) }
        }))
    self.controller = controller
    self.monitor = monitor
    bindingModel = makeBindingModel(for: monitor)
    signalPump?.cancel()
    let stream = signals.subscribe()
    signalPump = Task { [weak self] in
      for await signal in stream {
        self?.logSignal(signal)
        self?.noteGestureShape(signal)
        if let self {
          switch self.admits(signal) {
          case .refuse(let session):
            self.forgetGestureShape(signal)
            await controller.skip(session: session)
            continue
          case .swallow:
            self.forgetGestureShape(signal)
            continue
          case .admit:
            break
          }
        }
        self?.trackOnset(signal)
        Cue.play(for: signal)
        await controller.handle(signal)
      }
    }
    let installed = monitor.start()
    if !VoculaAppDelegate.isSecondCopy {
      log("tap.install", "ok=\(installed)")
      if !installed { menu.iconState = .error(MenuBarController.tapInstallFailed) }
    }

    pipelineTasks = [
      observe(controller),
      Task { await engine.warmUp() },
      Task {
        let shape = await recorder.prewarm()
        logInputFormat(rate: shape.rate, channels: shape.channels)
      },
      Task { [weak self] in await self?.forwardDeviceChanges(to: controller) },
    ]
    if installed { indicator.show(.idle) }
  }

  private func tearDownPipeline() {
    monitor?.stop()
    monitor = nil
    if let controller { Task { await controller.gestureAbandoned() } }
    signalPump?.cancel()
    signals.finishAll()
    signalPump = nil
    for task in pipelineTasks { task.cancel() }
    pipelineTasks = []
    refusalDismissTask?.cancel()
    refusalDismissTask = nil
    indicator.hide()
    controller = nil
    bindingModel = nil
  }

  private func startRetentionIfNeeded() {
    // The history directory is shared by every copy of this app, so a test or a
    // screenshot run would sweep the developer's own dictations on a schedule
    // nobody asked it to keep.
    guard !VoculaAppDelegate.isSecondCopy, retentionTask == nil else { return }
    retentionTask = Task { [historyStore, diagnosticLog] in
      while !Task.isCancelled {
        _ = await RetentionSweeper(
          store: historyStore,
          diagnosticLog: diagnosticLog
        ).sweep()
        do { try await Task.sleep(for: .seconds(86_400)) } catch { return }
      }
    }
  }

  private func logSignal(_ signal: DictationSignal) {
    switch signal {
    case .start(let session):
      pressedAt = (session, Date())
      let selection = settings.languages
      log(
        "session.start",
        "session=\(session) auto=\(selection.needsDetection) "
          + "langs=\(selection.codes.count)")
    case .stop(let session, let reason):
      if pressedAt?.session == session { pressedAt = nil }
      log("session.stop", "session=\(session) reason=\(reason.rawValue)")
    case .cancel(let session, let reason):
      let held = gestureBeganAt[session]
        .map { Int((ContinuousClock.now - $0) / .milliseconds(1)) }
      if pressedAt?.session == session { pressedAt = nil }
      log(
        "session.cancel",
        "session=\(session) reason=\(reason.rawValue)"
          + (held.map { " ms=\($0)" } ?? ""))
    }
  }

  private var pressedAt: (session: Int, at: Date)?

  private func noteMicrophoneReady() {
    guard let pressed = pressedAt else { return }
    pressedAt = nil
    let waited = Date().timeIntervalSince(pressed.at)
    guard waited >= Self.slowMicrophone else { return }
    log("audio.ready", "session=\(pressed.session) ms=\(Int(waited * 1000))")
  }

  private static let slowMicrophone: TimeInterval = 0.4

  private var onset = InputOnsetGate()
  private var onsetBound: Task<Void, Never>?
  private var awaitingLive: (session: Int, at: Date)?

  private func armOnset(session: Int) {
    onset = InputOnsetGate()
    awaitingLive = (session, Date())
    onsetBound?.cancel()
    onsetBound = Task { [weak self] in
      try? await Task.sleep(for: InputOnsetGate.bound)
      guard !Task.isCancelled, let self else { return }
      let opening = self.onset.boundReached()
      guard opening != .stillWaiting else { return }
      self.openInput(opening)
    }
  }

  private func disarmOnset() {
    onsetBound?.cancel()
    onsetBound = nil
    awaitingLive = nil
  }

  private func noteInputLive(_ level: Float) {
    guard awaitingLive != nil else { return }
    let opening = onset.level(level)
    guard opening != .stillWaiting else { return }
    openInput(opening)
  }

  private func openInput(_ opening: InputOnsetGate.Opening) {
    guard let waiting = awaitingLive else { return }
    disarmOnset()
    Cue.playStart()
    let waited = Int(Date().timeIntervalSince(waiting.at) * 1000)
    guard opening == .bound || Double(waited) / 1000 >= Self.slowMicrophone else { return }
    log("audio.live", "session=\(waiting.session) ms=\(waited) reason=\(opening.rawValue)")
  }

  func clearDiagnosticLog() {
    diagnosticLog?.clear()
  }

  func rebind(_ config: GestureConfig) { monitor?.update(config: config) }

  private static let gestureShapeMemory = 16
  private var gestureBeganAt: [Int: ContinuousClock.Instant] = [:]
  private var gestureHeldFor: [Int: Duration] = [:]
  private var lastGestureEndedAt: ContinuousClock.Instant?

  private func trackOnset(_ signal: DictationSignal) {
    switch signal {
    case .start(let session): armOnset(session: session)
    case .stop, .cancel: disarmOnset()
    }
  }

  // A gesture the trial wall refuses never reaches the controller, so it never
  // produces the outcome that would clear what noteGestureShape recorded.
  private func forgetGestureShape(_ signal: DictationSignal) {
    switch signal {
    case .start(let session), .stop(let session, _), .cancel(let session, _):
      gestureBeganAt[session] = nil
      gestureHeldFor[session] = nil
    }
  }

  private func noteGestureShape(_ signal: DictationSignal) {
    let now = ContinuousClock.now
    let kbd = monitor?.lastKeyboardType ?? 0
    switch signal {
    case .start(let session):
      if let ended = lastGestureEndedAt, now - ended < Timings.implausibleRetap {
        log(
          "gesture.rapidRetap",
          "ms=\(Self.milliseconds(now - ended)) kbd=\(kbd)")
      }
      gestureBeganAt[session] = now
      let stale = session - Self.gestureShapeMemory
      gestureBeganAt = gestureBeganAt.filter { $0.key > stale }
    case .stop(let session, _), .cancel(let session, _):
      defer {
        gestureBeganAt[session] = nil
        lastGestureEndedAt = now
      }
      guard let began = gestureBeganAt[session] else { return }
      let held = now - began
      if case .stop = signal { gestureHeldFor[session] = held }
      guard held > Timings.implausibleHold else { return }
      log("gesture.longHold", "ms=\(Self.milliseconds(held)) kbd=\(kbd)")
    }
  }

  private static func milliseconds(_ duration: Duration) -> Int {
    Int(duration / .milliseconds(1))
  }

  let usage = UsageLedger()

  private var blockedGestures = BlockedGestures()

  var presentLicence: (() -> Void)?

  private var licencePromptedDay: String {
    get { settings.defaults.string(forKey: "licence.promptedDay") ?? "" }
    set { settings.defaults.set(newValue, forKey: "licence.promptedDay") }
  }

  private func admits(_ signal: DictationSignal) -> GestureAdmission {
    let admission = blockedGestures.admits(signal) {
      usage.advance()
      return usage.entitlement(licensed: isLicensed).allowsDictation
    }
    guard case .refuse(let session) = admission else {
      return admission
    }
    log("session.blocked", "session=\(session)")
    indicator.note(
      String(
        localized: "indicator.dailyLimit",
        defaultValue: "Daily limit reached. More tomorrow, or add a licence.",
        comment:
          "Drawn on the indicator strip, which clamps at three lines; IndicatorChipSizeTests measures every locale against it."
      ),
      for: Self.refusalDismissDelay, alert: true)
    let today = UsageLedger.dayKey(usage.now(), calendar: .current)
    if licencePromptedDay != today {
      licencePromptedDay = today
      presentLicence?()
    }
    return admission
  }

  private var isLicensed: Bool {
    if case .licensed = LicenceVerifier.verdict(for: settings.licenceKey) { return true }
    return false
  }

  func cycleLanguage() {
    let next = settings.languages.cycled()
    settings.languages = next
    log("language.cycle", "auto=\(next.autoDetect)")
    indicator.showStatus(Self.languageName(of: next))
  }

  static func languageName(of selection: LanguageSelection) -> String {
    guard !selection.autoDetect else { return String(localized: LanguageScreenCopy.autoShort) }
    return WhisperLanguages.language(for: selection.pinned)?.displayName ?? selection.pinned
  }

  func reinstallHotkeyAfterPermissionChange() {
    guard let monitor else {
      Task { await start() }
      return
    }
    if !monitor.reinstallAfterPermissionChange() {
      menu.iconState = .error(MenuBarController.tapNotInstalled)
    }
  }

  func startMonitorOnly() {
    guard monitor == nil else { return }
    let monitor = HotkeyMonitor(
      config: bindingStore.config,
      onSignal: { [weak self] signal in
        guard case .start = signal else { return }
        self?.monitor?.abandonCurrentGesture()
        self?.indicator.note(
          String(
            localized: "indicator.modelsMissing",
            defaultValue: "The speech model is not downloaded yet. Open Settings → Models.",
            comment:
              "Shown when the record key is pressed before the weights exist. Drawn on the indicator strip, which clamps at three lines; IndicatorChipSizeTests measures every locale against it."
          ),
          for: Self.refusalDismissDelay, alert: true)
      },
      onTapLost: makeOnTapLost(),
      onGestureAbandoned: {},
      onTapReArmed: { [weak self] in
        Task { @MainActor in self?.log("tap.rearm", "") }
      },
      onLanguageCycle: { [weak self] in self?.cycleLanguage() },
      onLanguageCycleEnded: { [weak self] in self?.indicator.clearStatus() })
    self.monitor = monitor
    bindingModel = makeBindingModel(for: monitor)
    let installed = monitor.start()
    if !VoculaAppDelegate.isSecondCopy {
      log("tap.install", "ok=\(installed)")
      if !installed { menu.iconState = .error(MenuBarController.tapInstallFailed) }
    }
  }

  private func makeOnTapLost() -> (Int) -> Void {
    { [weak self] attempt in
      guard let self else { return }
      self.log("tap.rearm", "attempt=\(attempt)")
      if PermissionState.current().accessibility != .granted {
        self.log("permission.accessibility", "ok=false")
        self.menu.iconState = .keyLost(MenuBarController.accessibilityRevoked)
        return
      }
      self.menu.iconState = .keyLost(
        self.menu.explainKeyLoss(secureInputActive: IsSecureEventInputEnabled()))
    }
  }

  private func makeBindingModel(for monitor: HotkeyMonitor) -> BindingSettingsModel {
    BindingSettingsModel(
      monitor: monitor,
      defaults: VoculaAppDelegate.bindingDefaults
    ) { [weak self] config in
      self?.log("binding.saved", "class=\(config.primary.klass.rawValue)")
      self?.rebind(config)
    }
  }

  private var isSwitchingModels = false

  func modelsDidBecomeReady() async {
    guard !isSwitchingModels else { return }
    isSwitchingModels = true
    defer { isSwitchingModels = false }
    log("model.download", "outcome=ready")
    await finishInFlightWork()
    tearDownPipeline()
    await start()
  }

  private func observe(_ controller: DictationController) -> Task<Void, Never> {
    Task { [weak self] in
      for await status in controller.status {
        guard let self else { return }
        if case .finished(let session, let state, let reason) = status {
          await self.handleOutcome(
            session: session, state: state,
            reason: reason,
            controller: controller)
          continue
        }
        if case .listening(let level) = status {
          self.noteMicrophoneReady()
          self.noteInputLive(level)
        }
        self.indicator.show(status)
        let icon = Self.iconState(for: status)
        if self.menu.iconState != icon { self.menu.iconState = icon }
        let transcript = await controller.lastTranscript
        if self.menu.lastTranscript != transcript {
          self.menu.lastTranscript = transcript
        }
        self.refusalDismissTask?.cancel()
        self.refusalDismissTask = nil
        if case .refused(_, let session) = status {
          self.scheduleRefusalAutoDismiss()
          self.refusalDedup.noted(session: session)
        }
      }
    }
  }

  private static let refusalDismissDelay: Duration = .seconds(4)

  private func scheduleRefusalAutoDismiss() {
    refusalDismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.refusalDismissDelay)
      guard let self, !Task.isCancelled else { return }
      self.indicator.show(.idle)
    }
  }

  private func handleOutcome(
    session: Int,
    state: SessionState, reason: String?,
    controller: DictationController
  ) async {
    menu.lastTranscript = await controller.lastTranscript
    let plan = OutcomePolicy.plan(
      session: session, state: state, reason: reason,
      heldFor: gestureHeldFor[session] ?? .zero,
      inputIsSilenced:
        AudioInputDevices
        .resolvedDeviceID(for: settings.microphonePriority)
        .flatMap { AudioInputDevices.inputIsSilenced($0) } ?? false,
      historyIsRecording: settings.isRecordingHistory,
      alreadyExplained: refusalDedup.alreadyExplained(session: session))
    gestureHeldFor[session] = nil
    if plan.recordsUsage {
      usage.recordDictation()
      if case .limited(1) = usage.entitlement(licensed: isLicensed) {
        indicator.note(
          CountedText.text(LicenceCopy.dictationsLeftNotice(count: 1)),
          alert: true)
      }
    }
    if let line = plan.line { log(line.event, line.detail) }
    if let notice = plan.notice {
      indicator.note(notice, for: Self.refusalDismissDelay, alert: true)
    }
  }

  private func forwardDeviceChanges(to controller: DictationController) async {
    for await _ in recorder.deviceChangeEvents() {
      await controller.audioDeviceChanged()
      let copy = String(
        localized: "indicator.deviceChanged",
        defaultValue:
          "The microphone stopped delivering audio. What was recorded was transcribed; press the key to try again.",
        comment:
          "Shown in the indicator strip when the microphone stops mid-session. Drawn on the indicator strip, which clamps at three lines; IndicatorChipSizeTests measures every locale against it."
      )
      indicator.note(copy, for: Self.refusalDismissDelay, alert: true)
    }
  }

  private static func iconState(for status: ControllerStatus) -> MenuIconState {
    switch status {
    case .idle: return .idle
    case .raising, .listening: return .recording
    case .working: return .working
    case .refused(let reason, _): return .error(reason)
    case .finished: return .idle
    }
  }

  private func logInputFormat(rate: Int, channels: Int) {
    log("audio.input", "rate=\(rate) channels=\(channels)")
  }

  func recheckAccessibility() {
    let state = PermissionState.current()
    let granted = state.accessibility == .granted
    log("permission.accessibility", "ok=\(granted) listen=\(state.inputMonitoring == .granted)")
    let next = KeyLossRecovery.next(
      current: menu.iconState,
      accessibilityGranted: granted,
      revokedNotice: MenuBarController.accessibilityRevoked,
      tapInstalled: self.monitor?.reinstallAfterPermissionChange() ?? false)
    if menu.iconState != next { menu.iconState = next }
  }

  func shutdown() {
    tearDownPipeline()
    retentionTask?.cancel()
    retentionTask = nil
  }
}
