import Foundation

public actor DictationController {
  public struct Dependencies: Sendable {
    public var audio: AudioRecording
    public var detector: SpeechDetecting
    public var engine: Transcribing
    public var probe: TargetProbing
    public var inserter: TextInserter
    public var filter: TextFiltering
    public var history: SessionRecording
    public var modelID: String?
    public var timings: Timings
    public var languages: @Sendable () -> LanguageSelection
    public var abandonGesture: @Sendable () -> Void
    public var diagnose: @Sendable (String, String) -> Void
    public var targetBundleID: @Sendable (Int32) -> String?

    public init(
      audio: AudioRecording, detector: SpeechDetecting, engine: Transcribing,
      probe: TargetProbing, inserter: TextInserter, filter: TextFiltering,
      history: SessionRecording, modelID: String? = nil,
      timings: Timings,
      languages: @escaping @Sendable () -> LanguageSelection,
      targetBundleID: @escaping @Sendable (Int32) -> String? = { _ in nil },
      abandonGesture: @escaping @Sendable () -> Void = {},
      diagnose: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) {
      self.audio = audio
      self.detector = detector
      self.engine = engine
      self.probe = probe
      self.inserter = inserter
      self.filter = filter
      self.history = history
      self.modelID = modelID
      self.timings = timings
      self.languages = languages
      self.targetBundleID = targetBundleID
      self.abandonGesture = abandonGesture
      self.diagnose = diagnose
    }
  }

  private let dependencies: Dependencies
  private let gate = InsertOrderGate()
  private let transcriptionGate = TranscriptionGate()
  private let statusStream = AsyncStream<ControllerStatus>.makeStream()
  public private(set) var lastTranscript: String?
  private var lastTranscriptSession = 0

  private func rememberTranscript(_ text: String, session: Int) {
    guard session >= lastTranscriptSession else { return }
    lastTranscriptSession = session
    lastTranscript = text
  }

  private enum Phase: Sendable {
    case idle
    case starting(session: Int, startedAt: Date)
    case live(session: Int, startedAt: Date, snapshot: TargetSnapshot)
    case stopping(
      session: Int, startedAt: Date, snapshot: TargetSnapshot,
      truncated: Bool)
  }
  private enum PendingTermination: Sendable { case stop, cancel }

  private var phase: Phase = .idle
  private var pendingTermination: (session: Int, kind: PendingTermination)?
  private var pending = 0
  private var running: [Int: Task<Void, Never>] = [:]
  private var levelForwarder: Task<Void, Never>?
  private var onset = InputOnsetGate()
  private var onsetBound: Task<Void, Never>?

  public nonisolated var status: AsyncStream<ControllerStatus> { statusStream.stream }

  public init(dependencies: Dependencies) { self.dependencies = dependencies }

  public func handle(_ signal: DictationSignal) async {
    switch signal {
    case .start(let session): await start(session)
    case .stop(let session, _): await stop(session)
    case .cancel(let session, _): await cancel(session)
    }
  }

  private func start(_ session: Int) async {
    guard case .idle = phase else {
      await gate.finish(session)
      dependencies.abandonGesture()
      return
    }
    guard pending < dependencies.timings.maxPending else {
      statusStream.continuation.yield(
        .refused(RefusalCopy.overflowText, session: session))
      statusStream.continuation.yield(
        .finished(
          session: session, state: .failed,
          reason: SessionFailure.overflow.rawValue))
      await gate.finish(session)
      dependencies.abandonGesture()
      return
    }
    let startedAt = Date()
    phase = .starting(session: session, startedAt: startedAt)
    pendingTermination = nil
    statusStream.continuation.yield(.raising)

    async let raised = raiseEngine(session: session)
    async let probed = dependencies.probe.snapshot(budget: dependencies.timings.roleQuery)

    let engineIsUp = await raised
    let (snapshot, subrole) = await probed

    guard case .starting(let current, let currentStartedAt) = phase, current == session else {
      await dependencies.audio.discard()
      await dependencies.probe.release(snapshot)
      await gate.finish(session)
      return
    }
    guard engineIsUp else {
      phase = .idle
      dependencies.abandonGesture()
      await dependencies.audio.discard()
      await dependencies.probe.release(snapshot)
      await gate.finish(session)
      return
    }
    if !TargetGuardPolicy.mayStart(focusedSubrole: subrole) {
      phase = .idle
      dependencies.abandonGesture()
      await dependencies.audio.discard()
      await dependencies.probe.release(snapshot)
      await gate.finish(session)
      dependencies.diagnose(
        "guard.deny",
        "session=\(session) reason=\(InsertDenyReason.secureField.rawValue)"
          + " error=\(ErrorCode.code(for: InsertDenyReason.secureField))")
      statusStream.continuation.yield(
        .refused(RefusalCopy.cause(.secureField), session: session))
      return
    }
    phase = .live(session: session, startedAt: currentStartedAt, snapshot: snapshot)

    if let termination = pendingTermination, termination.session == session {
      pendingTermination = nil
      switch termination.kind {
      case .stop: await stop(session)
      case .cancel: await cancel(session)
      }
      return
    }
    startLevelForwarding(for: session)
  }

  private func raiseEngine(session: Int) async -> Bool {
    do {
      try await dependencies.audio.start()
      return true
    } catch {
      let ns = error as NSError
      let cause = ns.userInfo[NSUnderlyingErrorKey] as? NSError ?? ns
      dependencies.diagnose(
        "session.failed",
        "session=\(session) reason=\(SessionFailure.engineFailed.rawValue)"
          + " error=\(ErrorCode.code(for: SessionFailure.engineFailed))"
          + " domain=\(cause.domain) code=\(cause.code)")
      statusStream.continuation.yield(
        .refused(RefusalCopy.engineFailedText, session: session))
      return false
    }
  }

  private func startLevelForwarding(for session: Int) {
    levelForwarder?.cancel()
    onset = InputOnsetGate()
    onsetBound?.cancel()
    onsetBound = Task { [weak self] in
      try? await Task.sleep(for: InputOnsetGate.bound)
      await self?.openOnsetByBound(session)
    }
    let updates = dependencies.audio.levelUpdates()
    levelForwarder = Task { [weak self] in
      for await level in updates {
        guard let self, await self.isLive(session) else { return }
        await self.yieldLevel(level)
      }
    }
  }

  private func isLive(_ session: Int) -> Bool {
    if case .live(let current, _, _) = phase { return current == session }
    return false
  }

  private func openOnsetByBound(_ session: Int) {
    guard isLive(session) else { return }
    _ = onset.boundReached()
  }

  private func yieldLevel(_ level: Float) {
    guard onset.isOpen || onset.level(level) != .stillWaiting else { return }
    statusStream.continuation.yield(.listening(level: level))
  }

  private func cancel(_ session: Int) async {
    switch phase {
    case .starting(let current, _) where current == session:
      pendingTermination = (session, .cancel)
    case .live(let current, _, let snapshot) where current == session:
      phase = .idle
      levelForwarder?.cancel()
      levelForwarder = nil
      onsetBound?.cancel()
      onsetBound = nil
      await dependencies.audio.discard()
      await dependencies.probe.release(snapshot)
      await gate.finish(session)
      statusStream.continuation.yield(.idle)
    case .stopping(let current, _, _, _) where current == session:
      return
    default:
      await gate.finish(session)
    }
  }

  private func stop(_ session: Int) async {
    switch phase {
    case .starting(let current, _) where current == session:
      pendingTermination = (session, .stop)
      return
    case .live(let current, let startedAt, let snapshot) where current == session:
      await drainAndLaunch(
        session: session, startedAt: startedAt,
        snapshot: snapshot, truncated: false)
    case .stopping(let current, _, _, _) where current == session:
      return
    default:
      await gate.finish(session)
    }
  }

  private func drainAndLaunch(
    session: Int, startedAt: Date,
    snapshot: TargetSnapshot, truncated: Bool
  ) async {
    phase = .stopping(
      session: session, startedAt: startedAt,
      snapshot: snapshot, truncated: truncated)
    levelForwarder?.cancel()
    levelForwarder = nil
    onsetBound?.cancel()
    onsetBound = nil
    let samples = await dependencies.audio.stop()
    guard case .stopping(let stoppingSession, _, _, let truncatedNow) = phase,
      stoppingSession == session
    else { return }
    phase = .idle
    statusStream.continuation.yield(.working)
    pending += 1
    running[session] = Task {
      let restore = await self.process(
        session: session, samples: samples,
        snapshot: snapshot, startedAt: startedAt,
        truncated: truncatedNow)
      await self.dependencies.probe.release(snapshot)
      await self.finishPending(session)
      if let restore {
        _ = await self.dependencies.inserter.restoreClipboard(restore)
      }
      self.forget(session)
    }
  }

  public func skip(session: Int) async {
    await gate.finish(session)
  }

  private func finishPending(_ session: Int) async {
    pending = max(0, pending - 1)
    await gate.finish(session)
    statusStream.continuation.yield(pending == 0 ? .idle : .working)
  }

  private func forget(_ session: Int) {
    running[session] = nil
  }

  public func drain() async {
    while let task = running.values.first {
      await task.value
    }
  }

  private func conclude(
    _ id: UUID, session: Int, _ state: SessionState,
    reason: String?
  ) async {
    await dependencies.history.setState(id, state, reason: reason)
    statusStream.continuation.yield(
      .finished(session: session, state: state, reason: reason))
  }

  private func reprobeAndApprove(
    id: UUID, session: Int, snapshot: TargetSnapshot,
    finalTextOnDeny: String?
  ) async -> InsertApproval? {
    let comparison = await dependencies.probe.compare(
      snapshot, budget: dependencies.timings.roleQuery)
    switch TargetGuardPolicy.decideInsert(snapshot: snapshot, comparison: comparison) {
    case .allow:
      return TargetGuardPolicy.approveInsert(snapshot: snapshot, comparison: comparison)
    case .deny(let reason):
      if let finalTextOnDeny {
        await dependencies.history.attachFinalText(id, finalTextOnDeny)
      }
      await conclude(id, session: session, .rejected, reason: reason.rawValue)
      return nil
    }
  }

  private func process(
    session: Int, samples captured: [Float], snapshot: TargetSnapshot,
    startedAt: Date, truncated: Bool = false
  ) async -> ClipboardRestore? {
    let samples = PCMSamples.boostedIfQuiet(
      captured,
      ignoringLeading: PCMSamples.sampleCount(
        inLeading: SpeechThresholds.default.salvageIgnoresLeadingMilliseconds))
    let duration = PCMSamples.duration(sampleCount: samples.count)

    let created = await dependencies.history.createDraft(
      session: session, startedAt: startedAt,
      durationMilliseconds: duration.milliseconds,
      targetBundleID: dependencies.targetBundleID(snapshot.pid),
      modelID: dependencies.modelID)
    let id = created ?? UUID()
    if created != nil {
      await dependencies.history.setState(id, .recorded, reason: nil)
      if truncated { await dependencies.history.markTruncated(id) }
    }

    let markup: SpeechMarkup
    do { markup = try await dependencies.detector.markup(samples) } catch {
      await conclude(
        id, session: session, .failed,
        reason: SessionFailure.engineFailed.rawValue)
      return nil
    }
    var metrics = markup.metrics
    metrics.peakLevel = PCMSamples.peak(captured)
    await dependencies.history.attachMetrics(id, metrics)

    let speech: [Float]
    if markup.hasSpeech {
      speech = SpeechMarkup.extract(markup.segments, from: samples)
    } else if markup.salvageWholeBuffer {
      speech = samples
    } else if !captured.isEmpty, metrics.peakLevel == 0 {
      await conclude(
        id, session: session, .failed,
        reason: SessionFailure.silentInput.rawValue)
      return nil
    } else {
      await conclude(id, session: session, .noSpeech, reason: nil)
      return nil
    }

    await dependencies.history.setState(id, .transcribing, reason: nil)

    guard await transcriptionGate.acquire(timeout: dependencies.timings.queueWait) else {
      await conclude(
        id, session: session, .failed,
        reason: SessionFailure.queueTimeout.rawValue)
      return nil
    }
    let transcription: Transcription
    let startedTranscribing = Date()
    do {
      transcription = try await dependencies.engine.transcribe(
        speech, languages: dependencies.languages(),
        deadline: dependencies.timings.passDeadline(
          forAudio: .seconds(Double(speech.count) / AudioFormat.sampleRate)))
    } catch {
      await transcriptionGate.release()
      let failure: SessionFailure
      switch error {
      case TranscriptionError.timedOut: failure = .passTimeout
      default: failure = .engineFailed
      }
      await conclude(id, session: session, .failed, reason: failure.rawValue)
      return nil
    }
    await transcriptionGate.release()
    reportIfSlow(
      session: session, speechSamples: speech.count,
      took: Date().timeIntervalSince(startedTranscribing))

    if let detail = LanguageDetectionReport.detail(
      session: session, chosen: transcription.language,
      scores: transcription.languageScores, peak: metrics.peakLevel)
    {
      dependencies.diagnose("language.detected", detail)
    }
    metrics.firstTokenProbability = transcription.firstTokenProbability
    await dependencies.history.attachMetrics(id, metrics)

    await dependencies.history.attachRawText(
      id, transcription.text,
      language: transcription.language)
    guard !transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      await conclude(
        id, session: session, .failed,
        reason: SessionFailure.emptyTranscript.rawValue)
      return nil
    }
    await dependencies.history.setState(id, .transcribed, reason: nil)
    rememberTranscript(transcription.text, session: session)

    let filtered = dependencies.filter.evaluate(
      transcription.text,
      language: transcription.language)
    guard !filtered.wasDroppedAsHallucination else {
      await conclude(id, session: session, .rejected, reason: RefusalCopy.hallucination)
      return nil
    }
    rememberTranscript(filtered.text, session: session)
    await gate.wait(for: session)

    guard
      await reprobeAndApprove(
        id: id, session: session, snapshot: snapshot,
        finalTextOnDeny: filtered.text) != nil
    else { return nil }

    await dependencies.history.attachFinalText(id, filtered.text)
    rememberTranscript(filtered.text, session: session)

    guard
      let approval = await reprobeAndApprove(
        id: id, session: session,
        snapshot: snapshot,
        finalTextOnDeny: nil)
    else { return nil }
    switch await dependencies.inserter.insert(filtered.text, approval: approval) {
    case .sent(let restore):
      await conclude(id, session: session, .sent, reason: nil)
      return restore
    case .skippedEmpty:
      await conclude(
        id, session: session, .failed,
        reason: SessionFailure.emptyTranscript.rawValue)
    case .failedLocally:
      await conclude(
        id, session: session, .failed,
        reason: SessionFailure.insertionFailed.rawValue)
    }
    return nil
  }

  private func reportIfSlow(session: Int, speechSamples: Int, took: TimeInterval) {
    let audio = Double(speechSamples) / AudioFormat.sampleRate
    guard audio > 0, took > audio * 0.33 else { return }
    let model = dependencies.modelID ?? "unknown"
    dependencies.diagnose(
      "session.transcribed",
      "session=\(session) ms=\(Int(took * 1000)) model=\(model)")
  }

  public func audioDeviceChanged() async {
    guard case .live(let session, let startedAt, let snapshot) = phase else {
      if case .starting(let session, _) = phase {
        pendingTermination = (session, .cancel)
        dependencies.abandonGesture()
      } else if case .stopping(let session, let startedAt, let snapshot, _) = phase {
        phase = .stopping(
          session: session, startedAt: startedAt,
          snapshot: snapshot, truncated: true)
      }
      return
    }
    dependencies.abandonGesture()
    await drainAndLaunch(
      session: session, startedAt: startedAt,
      snapshot: snapshot, truncated: true)
  }

  public func gestureAbandoned() async {
    switch phase {
    case .starting(let session, _), .live(let session, _, _):
      await cancel(session)
    case .stopping, .idle:
      break
    }
  }
}
