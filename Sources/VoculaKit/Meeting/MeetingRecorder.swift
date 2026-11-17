import Foundation

public protocol MeetingTrackSource: AnyObject, Sendable {
  func start() async throws
  func stop()
  func finished() async
  func drain() -> TrackDrain
  var callbacks: Int { get }
}

public enum MeetingPowerHold: Sendable {
  case held(release: @Sendable () -> Void)
  case failed(code: Int32)
}

public actor MeetingRecorder {
  public static let sampleInterval: Duration = .seconds(1)
  public static let flushEvery: UInt64 = 3_000_000_000

  public struct Dependencies: Sendable {
    public var store: MeetingStore
    public var cipher: @Sendable () throws -> any HistoryCipher
    public var makeMicrophone:
      @Sendable (_ onEnded: @escaping @Sendable () async -> Void) -> any MeetingTrackSource
    public var makeSystemAudio: @Sendable () -> any MeetingTrackSource
    public var holdPower:
      @Sendable (_ onWillSleep: @escaping @Sendable () async -> Void) -> MeetingPowerHold
    public var watchDeviceList: @Sendable (_ onChange: @escaping @Sendable () -> Void) -> AnyObject?
    public var now: @Sendable () -> UInt64
    public var sleep: @Sendable (Duration) async throws -> Void
    public var wallClock: @Sendable () -> Date
    public var publish: @Sendable (MeetingStatus) async -> Void
    public var ended: @Sendable () async -> Void
    public var log: DiagnosticLog?
    public var recover: Bool

    public init(
      store: MeetingStore,
      cipher: @escaping @Sendable () throws -> any HistoryCipher,
      makeMicrophone:
        @escaping @Sendable (_ onEnded: @escaping @Sendable () async -> Void) ->
        any MeetingTrackSource,
      makeSystemAudio: @escaping @Sendable () -> any MeetingTrackSource,
      holdPower:
        @escaping @Sendable (_ onWillSleep: @escaping @Sendable () async -> Void) ->
        MeetingPowerHold,
      watchDeviceList:
        @escaping @Sendable (_ onChange: @escaping @Sendable () -> Void) ->
        AnyObject?,
      now: @escaping @Sendable () -> UInt64,
      sleep: @escaping @Sendable (Duration) async throws -> Void,
      wallClock: @escaping @Sendable () -> Date,
      publish: @escaping @Sendable (MeetingStatus) async -> Void,
      ended: @escaping @Sendable () async -> Void,
      log: DiagnosticLog?,
      recover: Bool
    ) {
      self.store = store
      self.cipher = cipher
      self.makeMicrophone = makeMicrophone
      self.makeSystemAudio = makeSystemAudio
      self.holdPower = holdPower
      self.watchDeviceList = watchDeviceList
      self.now = now
      self.sleep = sleep
      self.wallClock = wallClock
      self.publish = publish
      self.ended = ended
      self.log = log
      self.recover = recover
    }
  }

  private enum Phase { case fresh, starting, recording, ended }

  private let deps: Dependencies
  private var phase = Phase.fresh
  private var pendingEnd: MeetingEnd?
  private var cipher: (any HistoryCipher)?
  private var header: MeetingHeader?
  private var release: (@Sendable () -> Void)?
  private var microphones: [any MeetingTrackSource] = []
  private var system: (any MeetingTrackSource)?
  private var microphoneState = MicrophoneTrackState.notOpened
  private var systemState = SystemTrackState.failed
  private var systemStart: Task<Void, Never>?
  private var loop: Task<Void, Never>?
  private var finishing: Task<Void, Never>?
  private var flushing: Task<SilenceStop.Verdict, Never>?
  private var headerWrite: Task<String?, Never>?
  private var lastFlush: UInt64 = 0
  private var lastSystemSound: UInt64?
  private var sequences: [MeetingTrack: UInt32] = [:]
  private var tally = MeetingTally(anchor: 0)
  private var liveness = MeetingLiveness()
  private var silence = SilenceStop(startedAt: 0)
  private var silenceVerdict = SilenceStop.Verdict.recording
  private var shownWarnings: [MeetingWarning] = []
  private var schedule = MicReopenSchedule()
  private var reopenAt: UInt64?
  private var reopening: Task<Void, Never>?
  private var deviceWatch: AnyObject?
  private var spans = DictationSpans()
  private var generations = 0

  public init(_ dependencies: Dependencies) {
    deps = dependencies
  }

  public func start() async {
    guard phase == .fresh else { return }
    phase = .starting
    let cipher: any HistoryCipher
    do {
      cipher = try await Self.lookUp(deps.cipher)
    } catch MeetingFailure.secondCopy {
      return await conclude()
    } catch {
      return await refuse(Self.failure(error, otherwise: "key"))
    }
    guard pendingEnd == nil else { return await conclude() }

    var header = MeetingHeader(id: UUID(), startedAt: deps.wallClock(), anchor: deps.now())
    do {
      let recovered = try await deps.store.begin(header, cipher: cipher, recovering: deps.recover)
      if recovered > 0 { deps.log?.record("meeting.recovered", "count=\(recovered)") }
    } catch {
      return await refuse(Self.failure(error, otherwise: "directory"))
    }
    self.cipher = cipher
    if let end = pendingEnd {
      header.state = .recorded
      header.end = header.date(atHost: deps.now())
      header.endedBy = end
      self.header = header
      await save(header)
      return await conclude()
    }
    self.header = header
    tally = MeetingTally(anchor: header.anchor)
    silence = SilenceStop(startedAt: header.anchor)
    lastFlush = header.anchor

    switch deps.holdPower({ [weak self] in await self?.systemWillSleep() }) {
    case .held(let release): self.release = release
    case .failed(let code): deps.log?.record("meeting.powerFailed", "code=\(code)")
    }
    deps.log?.record("meeting.start", "")
    phase = .recording
    await deps.publish(MeetingStatus(isRecording: true, startedAt: header.startedAt))
    guard phase == .recording else { return }

    let system = deps.makeSystemAudio()
    self.system = system
    systemState = .starting(at: deps.now())
    systemStart = Task { [weak self] in
      do {
        try await system.start()
        await self?.systemStarted(nil)
      } catch {
        await self?.systemStarted(error)
      }
    }

    guard let microphone = await openMicrophone() else { return }
    microphoneState = microphone
    if microphone == .failedToOpen { microphoneLost() }
    loop = Task { [weak self, sleep = deps.sleep] in
      while !Task.isCancelled {
        do { try await sleep(Self.sampleInterval) } catch { return }
        guard let self else { return }
        await self.tick()
      }
    }
  }

  public func stop(_ end: MeetingEnd) async {
    switch phase {
    case .fresh:
      await conclude()
    case .starting:
      pendingEnd = end
    case .recording:
      await finishRecording(end)
      await awaitTeardown()
    case .ended:
      await finishing?.value
      await awaitTeardown()
    }
  }

  public func systemWillSleep() async {
    guard phase == .recording else { return }
    await finishRecording(.sleep)
    deps.log?.record("meeting.sleepAllowed", "")
  }

  public func follow(_ signals: AsyncStream<DictationSignal>) async {
    generations += 1
    let generation = generations
    for await signal in signals {
      await dictation(signal, generation: generation, at: deps.now())
    }
    await generationEnded(generation, at: deps.now())
  }

  public func dictation(_ signal: DictationSignal, generation: Int, at host: UInt64) async {
    guard phase == .recording else { return }
    await keep(spans.received(signal, generation: generation, at: host))
  }

  public func generationEnded(_ generation: Int, at host: UInt64) async {
    guard phase == .recording else { return }
    await keep(spans.generationEnded(generation, at: host))
  }

  public func deviceListChanged() async {
    guard let due = takeReopen(dueBy: .max) else { return }
    await reopenMicrophone(due: due, byTimer: false)
  }

  func systemStartSettled() async {
    await systemStart?.value
  }

  func reopenSettled() async {
    await reopening?.value
  }

  private static func lookUp(_ cipher: @escaping @Sendable () throws -> any HistoryCipher)
    async throws -> any HistoryCipher
  {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(with: Result { try cipher() })
      }
    }
  }

  private static func failure(_ error: any Error, otherwise step: String) -> String {
    switch error {
    case MeetingFailure.failed(let step, let code): fields(step: step, code: Int(code))
    case MeetingStoreError.failed(let step, let code): fields(step: step, code: code)
    default: fields(step: step, code: 0)
    }
  }

  private static func fields(step: String, code: Int) -> String {
    "step=\(step)" + " code=\(code)"
  }

  private func refuse(_ failure: String) async {
    phase = .ended
    deps.log?.record("meeting.writeFailed", failure)
    await deps.publish(MeetingStatus(notice: .cannotStart))
    await deps.ended()
  }

  private func conclude() async {
    phase = .ended
    await deps.ended()
  }

  private func openMicrophone() async -> MicrophoneTrackState? {
    guard phase == .recording else { return nil }
    let index = microphones.count
    let microphone = deps.makeMicrophone { [weak self] in await self?.microphoneEnded(index) }
    microphones.append(microphone)
    let state: MicrophoneTrackState
    do {
      try await microphone.start()
      state = .running(since: deps.now())
    } catch MeetingFailure.notOpened {
      state = .notOpened
    } catch {
      microphone.stop()
      state = .failedToOpen
    }
    guard phase == .recording else {
      microphone.stop()
      return nil
    }
    return state
  }

  private func systemStarted(_ error: (any Error)?) {
    guard phase == .recording else { return }
    if let error {
      deps.log?.record("meeting.tapFailed", Self.failure(error, otherwise: "start"))
      systemState = .failed
    } else {
      systemState = .running(since: deps.now())
    }
  }

  private func microphoneEnded(_ index: Int) {
    guard phase == .recording, index == microphones.count - 1, case .running = microphoneState
    else { return }
    microphones[index].stop()
    microphoneState = .lost(at: deps.now())
    microphoneLost()
  }

  private func microphoneLost() {
    deps.log?.record("meeting.micLost", "")
    reopenAt = schedule.lost(at: deps.now())
    deviceWatch = deps.watchDeviceList { [weak self] in
      Task { await self?.deviceListChanged() }
    }
  }

  private func takeReopen(dueBy now: UInt64) -> UInt64? {
    guard phase == .recording, let due = reopenAt, due <= now else { return nil }
    reopenAt = nil
    return due
  }

  func reopenMicrophone(due: UInt64, byTimer: Bool) async {
    guard let state = await openMicrophone() else { return }
    if case .running = state {
      deps.log?.record("meeting.micReopened", "count=\(schedule.reopened())")
      microphoneState = state
      deviceWatch = nil
    } else if byTimer {
      reopenAt = schedule.timerAttemptFailed(at: deps.now())
    } else {
      schedule.deviceListAttemptFailed()
      reopenAt = due
    }
  }

  private func tick() async {
    guard phase == .recording else { return }
    if HostTime.elapsed(from: lastFlush, to: deps.now()) >= Self.flushEvery {
      silenceVerdict = await flush()
      if silenceVerdict == .stop { return await finishRecording(.autoStopped) }
    }
    await sample()
  }

  private func sample() async {
    guard phase == .recording else { return }
    if let due = takeReopen(dueBy: deps.now()) {
      reopening = Task { [weak self] in await self?.reopenMicrophone(due: due, byTimer: true) }
    }
    let report = liveness.sample(
      MeetingSample(
        now: deps.now(), microphone: microphoneState,
        microphoneCallbacks: microphones.last?.callbacks ?? 0, system: systemState,
        systemCallbacks: system?.callbacks ?? 0, lastSystemSound: lastSystemSound,
        autoStopSoon: silenceVerdict == .stopsSoon))
    for warning in report.raised {
      deps.log?.record("meeting.warning", "reason=\(warning.rawValue)")
    }
    if report.systemZerosBegan { deps.log?.record("meeting.systemZeros", "") }
    guard report.warnings != shownWarnings else { return }
    shownWarnings = report.warnings
    await deps.publish(
      MeetingStatus(isRecording: true, startedAt: header?.startedAt, warnings: report.warnings))
  }

  private func flush() async -> SilenceStop.Verdict {
    let previous = flushing
    let flush = Task { [weak self] in
      _ = await previous?.value
      guard let self else { return SilenceStop.Verdict.recording }
      return await self.writeChunks()
    }
    flushing = flush
    return await flush.value
  }

  private func writeChunks() async -> SilenceStop.Verdict {
    lastFlush = deps.now()
    let micDrains = microphones.map { $0.drain() }
    let systemDrains = system.map { [$0.drain()] } ?? []
    let micFailure = await save(micDrains, as: .mic)
    let systemFailure = await save(systemDrains, as: .system)
    if systemDrains.contains(where: { $0.peak > 0 }) { lastSystemSound = deps.now() }
    let backlog = (micDrains + systemDrains).contains { $0.droppedNanos > 0 }
    settle(micFailure ?? systemFailure ?? (backlog ? Self.fields(step: "backlog", code: 0) : nil))
    return silence.levels(
      micPeak: micDrains.map(\.peak).max() ?? 0, systemPeak: systemDrains.map(\.peak).max() ?? 0,
      at: deps.now())
  }

  private func save(_ drains: [TrackDrain], as track: MeetingTrack) async -> String? {
    guard let header, let cipher else { return nil }
    let runs = drains.flatMap(\.runs)
    var failure: String?
    if !runs.isEmpty {
      let sequence = sequences[track, default: 0]
      sequences[track] = sequence &+ 1
      do {
        try await deps.store.write(
          MeetingChunk(track: track, sequence: sequence, runs: runs), of: header.id,
          cipher: cipher)
      } catch {
        failure = Self.failure(error, otherwise: "write")
      }
    }
    for drain in drains { tally.add(drain, track: track, written: failure == nil) }
    return failure
  }

  private func save(_ header: MeetingHeader) async {
    guard let cipher else { return }
    let previous = headerWrite
    let write = Task { [deps] () -> String? in
      _ = await previous?.value
      do {
        try await deps.store.update(header, cipher: cipher)
        return nil
      } catch {
        return Self.failure(error, otherwise: "write")
      }
    }
    headerWrite = write
    settle(await write.value)
  }

  private func settle(_ failure: String?) {
    if liveness.saved(failed: failure != nil), let failure {
      deps.log?.record("meeting.writeFailed", failure)
    }
  }

  private func keep(_ closed: [DictationSpan]) async {
    guard !closed.isEmpty, var header else { return }
    header.dictations += closed.map { clipped($0, to: .max) }
    self.header = header
    await save(header)
  }

  private func clipped(_ span: DictationSpan, to end: UInt64) -> DictationSpan {
    let anchor = header?.anchor ?? 0
    return DictationSpan(
      start: min(max(span.start, anchor), end), end: min(max(span.end, anchor), end))
  }

  private func finishRecording(_ end: MeetingEnd) async {
    guard phase == .recording else { return }
    phase = .ended
    loop?.cancel()
    systemStart?.cancel()
    deviceWatch = nil
    for microphone in microphones { microphone.stop() }
    system?.stop()
    let wrapUp = Task { [weak self] in
      guard let self else { return }
      await self.wrapUp(end)
    }
    finishing = wrapUp
    await wrapUp.value
  }

  private func wrapUp(_ end: MeetingEnd) async {
    _ = await flush()
    let host = deps.now()
    if var header {
      header.dictations += spans.meetingEnded(at: host).map { clipped($0, to: host) }
      header.state = .recorded
      header.end = header.date(atHost: host)
      header.endedBy = end
      self.header = header
      await save(header)
    }
    deps.log?.record("meeting.stop", "reason=\(end.rawValue) " + tally.detail)
    release?()
    release = nil
    let notice: MeetingNotice? =
      switch end {
      case .autoStopped: .autoStopped
      case .sleep: .endedBySleep
      case .stopped, .quit, .interrupted: nil
      }
    await deps.publish(MeetingStatus(notice: notice))
    await deps.ended()
  }

  private func awaitTeardown() async {
    for track in microphones + (system.map { [$0] } ?? []) { await track.finished() }
  }
}
