import Foundation
import Testing

@testable import VoculaKit

private actor FakeAudio: AudioRecording {
  var started = 0
  var discarded = 0
  var samplesToReturn: [Float] = [Float](repeating: 0.2, count: 16_000)
  private var startDelay: Duration = .zero
  private var stopDelay: Duration = .zero
  private var failStart = false
  var stopCalls = 0
  private let levelFanout = StreamFanout<Float>()
  private let deviceFanout = StreamFanout<Void>()

  nonisolated func levelUpdates() -> AsyncStream<Float> { levelFanout.subscribe() }
  func emit(level: Float) { levelFanout.emit(level) }
  nonisolated func deviceChangeEvents() -> AsyncStream<Void> { deviceFanout.subscribe() }
  var isRunning: Bool = false

  func setSamples(_ samples: [Float]) { samplesToReturn = samples }
  func setStartDelay(_ delay: Duration) { startDelay = delay }
  func setStopDelay(_ delay: Duration) { stopDelay = delay }
  func setFailStart(_ value: Bool) { failStart = value }

  func start() async throws {
    started += 1
    if startDelay != .zero { try? await Task.sleep(for: startDelay) }
    if failStart { throw NSError(domain: "FakeAudio", code: 1) }
    guard !discardRequested else {
      discardRequested = false
      return
    }
    isRunning = true
  }

  private var discardRequested = false

  private var parked: [Float]?

  func waitUntilRunning() async {
    for _ in 0..<200 where !isRunning {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  func simulateDeviceLoss() {
    isRunning = false
    parked = samplesToReturn
  }

  func stop() async -> [Float] {
    stopCalls += 1
    if let parked {
      self.parked = nil
      return parked
    }
    guard isRunning else { return [] }
    if stopDelay != .zero { try? await Task.sleep(for: stopDelay) }
    isRunning = false
    return samplesToReturn
  }

  func discard() async {
    discarded += 1
    if isRunning { isRunning = false } else { discardRequested = true }
  }
}

private struct FakeDetector: SpeechDetecting {
  var hasSpeech = true
  var frameProbabilities: [Float] = []
  func markup(_ samples: [Float]) async throws -> SpeechMarkup {
    SpeechMarkup(
      segments: hasSpeech
        ? [SpeechSegment(start: .zero, end: .milliseconds(900), probability: 0.9)]
        : [],
      totalDuration: .milliseconds(1_000),
      frameProbabilities: frameProbabilities)
  }
}

private final class FakeEngine: Transcribing, @unchecked Sendable {
  var text = "hello"
  var language = "en"
  var error: TranscriptionError?
  var delay: Duration = .zero
  var calls = 0
  var lastSampleCount = 0
  var firstTokenProbability: Float?
  var languageScores: [String: Float] = [:]

  func transcribe(
    _ samples: [Float], languages: LanguageSelection,
    deadline: Duration
  ) async throws -> Transcription {
    calls += 1
    lastSampleCount = samples.count
    if delay != .zero { try? await Task.sleep(for: delay) }
    if let error { throw error }
    return Transcription(
      text: text, language: language,
      firstTokenProbability: firstTokenProbability,
      languageScores: languageScores)
  }
}

private struct FakeProbe: TargetProbing {
  var snapshotValue = TargetSnapshot(pid: 1, secureInputWasUp: false)
  var startSubrole = FocusedSubrole.other("AXTextField")
  var comparisonValue = TargetComparison(
    pid: 1, sameWindow: true, sameElement: true,
    subrole: .other("AXTextField"),
    secureInputIsUp: false)
  func snapshot(budget: Duration) async -> (TargetSnapshot, FocusedSubrole) {
    (snapshotValue, startSubrole)
  }
  func compare(_ snapshot: TargetSnapshot, budget: Duration) async -> TargetComparison {
    comparisonValue
  }
  func release(_ snapshot: TargetSnapshot) async {}
}

private final class FakeClipboard: Clipboard, @unchecked Sendable {
  var changeCount = 1
  var writes: [String] = []
  func snapshot() -> ClipboardSnapshot { ClipboardSnapshot(items: [], changeCount: changeCount) }
  func write(
    _ text: String, concealed: Bool,
    transient: Bool
  ) -> ClipboardWriteOutcome {
    writes.append(text)
    changeCount += 1
    return .written(changeCount: changeCount)
  }
  var restores = 0
  @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Int? {
    restores += 1
    changeCount += 1
    return changeCount
  }
}

private final class FlagBox: @unchecked Sendable {
  private let lock = NSLock()
  private var flag = false
  func set(_ value: Bool) { lock.withLock { flag = value } }
  var value: Bool { lock.withLock { flag } }
}

private struct FakePaste: PasteSending {
  var succeeds = true
  func sendPaste() -> Bool { succeeds }
}

private final class AbandonSpy: @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0
  func record() { lock.withLock { calls += 1 } }
  var count: Int { lock.withLock { calls } }
}

private actor FakeHistory: SessionRecording {
  var drafts: [Int: UUID] = [:]
  var states: [(UUID, SessionState, String?)] = []
  var rawTexts: [UUID: String] = [:]
  var finalTexts: [UUID: String] = [:]
  var metrics: [UUID: SpeechMetrics] = [:]

  func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int,
    targetBundleID: String?, modelID: String?
  ) async -> UUID? {
    let id = UUID()
    drafts[session] = id
    return id
  }
  var truncated: Set<UUID> = []
  func markTruncated(_ id: UUID) async { truncated.insert(id) }
  func attachMetrics(_ id: UUID, _ value: SpeechMetrics) async { metrics[id] = value }
  func attachRawText(_ id: UUID, _ text: String, language: String) async { rawTexts[id] = text }
  func attachFinalText(_ id: UUID, _ text: String) async { finalTexts[id] = text }
  func setState(_ id: UUID, _ state: SessionState, reason: String?) async {
    states.append((id, state, reason))
  }
}

private func makeController(
  audio: FakeAudio = FakeAudio(),
  detector: FakeDetector = FakeDetector(),
  engine: FakeEngine = FakeEngine(),
  probe: FakeProbe = FakeProbe(),
  clipboard: FakeClipboard = FakeClipboard(),
  paste: FakePaste = FakePaste(),
  history: FakeHistory = FakeHistory(),
  timings: Timings = .default,
  abandonGesture: @escaping @Sendable () -> Void = {},
  diagnose: @escaping @Sendable (String, String) -> Void = { _, _ in }
) -> DictationController {
  DictationController(
    dependencies: .init(
      audio: audio, detector: detector, engine: engine, probe: probe,
      inserter: TextInserter(
        clipboard: clipboard, paste: paste,
        timings: timings, sleep: { _ in }),
      filter: PassthroughFilter(),
      history: history, timings: timings, languages: { .default },
      abandonGesture: abandonGesture, diagnose: diagnose))
}

private final class StatusBox: @unchecked Sendable {
  private let lock = NSLock()
  private var seen: [ControllerStatus] = []
  func append(_ status: ControllerStatus) {
    lock.lock()
    seen.append(status)
    lock.unlock()
  }
  var sawListening: Bool {
    lock.lock()
    defer { lock.unlock() }
    return seen.contains { if case .listening = $0 { return true } else { return false } }
  }
}

@Suite("DictationController")
struct DictationControllerTests {
  @Test("a start signal raises the engine and snapshots the target")
  func startRaisesEngine() async {
    let audio = FakeAudio()
    let controller = makeController(audio: audio)
    await controller.handle(.start(session: 1))
    #expect(await audio.started == 1)
  }

  @Test("a secure field aborts the recording and throws the audio away")
  func secureFieldAbortsRecording() async {
    let audio = FakeAudio()
    var probe = FakeProbe()
    probe.startSubrole = .secureTextField
    let history = FakeHistory()
    let abandon = AbandonSpy()
    let controller = makeController(
      audio: audio, probe: probe, history: history,
      abandonGesture: { abandon.record() })
    await controller.handle(.start(session: 1))
    #expect(await audio.discarded == 1)
    #expect(await history.drafts.isEmpty)
    #expect(abandon.count == 1)
  }

  @Test("an audio-engine start failure releases the gesture machine")
  func engineStartFailureAbandonsGesture() async {
    let audio = FakeAudio()
    await audio.setFailStart(true)
    let abandon = AbandonSpy()
    let controller = makeController(
      audio: audio,
      abandonGesture: { abandon.record() })
    await controller.handle(.start(session: 1))
    #expect(abandon.count == 1)
    #expect(await audio.isRunning == false)
  }

  @Test("an audio-engine start failure is logged with VOC-ENG-01")
  func engineStartFailureIsLogged() async {
    let audio = FakeAudio()
    await audio.setFailStart(true)
    let recorded = EventBox()
    let controller = makeController(
      audio: audio,
      diagnose: { recorded.append($0, $1) })
    await controller.handle(.start(session: 1))
    #expect(recorded.all.count == 1)
    #expect(recorded.all.first?.0 == "session.failed")
    #expect(
      recorded.all.first?.1
        == "session=1 reason=engineFailed error=VOC-ENG-01 domain=FakeAudio code=1")
  }

  @Test("a secure field at the start is logged with VOC-PASTE-02")
  func secureFieldAtStartIsLogged() async {
    var probe = FakeProbe()
    probe.startSubrole = .secureTextField
    let recorded = EventBox()
    let controller = makeController(
      probe: probe,
      diagnose: { recorded.append($0, $1) })
    await controller.handle(.start(session: 1))
    #expect(recorded.all.count == 1)
    #expect(recorded.all.first?.0 == "guard.deny")
    #expect(recorded.all.first?.1 == "session=1 reason=secureField error=VOC-PASTE-02")
  }

  @Test("the draft exists before the detector runs")
  func draftIsCreatedFirst() async {
    let history = FakeHistory()
    let controller = makeController(history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(await history.drafts[1] != nil)
    let states = await history.states.map(\.1)
    #expect(states.first == .recorded)
  }

  @Test("no speech stops the pipeline and keeps a text-less record with metrics")
  func noSpeechStopsPipeline() async {
    let history = FakeHistory()
    let engine = FakeEngine()
    let controller = makeController(
      detector: FakeDetector(hasSpeech: false),
      engine: engine, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(engine.calls == 0)
    let states = await history.states.map(\.1)
    #expect(states.contains(.noSpeech))
    let id = await history.drafts[1]!
    #expect(await history.metrics[id] != nil)
  }

  static var liveFrameAt800ms: [Float] {
    var probabilities = [Float](repeating: 0.02, count: 31)
    probabilities[25] = 0.31
    return probabilities
  }

  @Test("no segments but live frames sends the whole recording to whisper")
  func salvagedRecordingIsTranscribedWhole() async {
    let history = FakeHistory()
    let engine = FakeEngine()
    let audio = FakeAudio()
    let controller = makeController(
      audio: audio,
      detector: FakeDetector(
        hasSpeech: false,
        frameProbabilities: Self.liveFrameAt800ms),
      engine: engine, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(engine.calls == 1)
    #expect(engine.lastSampleCount == 16_000)
    let states = await history.states.map(\.1)
    #expect(!states.contains(.noSpeech))
    #expect(states.contains(.sent))
  }

  @Test("no segments and dead frames is still noSpeech")
  func quietRoomIsStillDiscarded() async {
    let engine = FakeEngine()
    let controller = makeController(
      detector: FakeDetector(hasSpeech: false, frameProbabilities: [0.01, 0.054]),
      engine: engine)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(engine.calls == 0)
  }

  @Test("a full buffer of pure zeros is a dead input, not a silent room")
  func silentInputIsNotReportedAsNoSpeech() async {
    let history = FakeHistory()
    let audio = FakeAudio()
    await audio.setSamples([Float](repeating: 0, count: 16_000))
    let controller = makeController(
      audio: audio,
      detector: FakeDetector(hasSpeech: false),
      history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let states = await history.states
    #expect(!states.map(\.1).contains(.noSpeech))
    #expect(
      states.contains {
        $0.1 == .failed && $0.2 == SessionFailure.silentInput.rawValue
      })
  }

  @Test("a quiet room with a live microphone is still noSpeech")
  func quietRoomIsNotReportedAsSilentInput() async {
    let history = FakeHistory()
    let audio = FakeAudio()
    await audio.setSamples([Float](repeating: 0.001, count: 16_000))
    let controller = makeController(
      audio: audio,
      detector: FakeDetector(hasSpeech: false),
      history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(await history.states.map(\.1).contains(.noSpeech))
  }

  @Test("the recorded peak is the microphone's, not the boosted buffer's")
  func peakLevelIsRecorded() async {
    let history = FakeHistory()
    let audio = FakeAudio()
    await audio.setSamples([Float](repeating: 0.01, count: 16_000))
    let controller = makeController(audio: audio, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let id = await history.drafts[1]!
    let peak = await history.metrics[id]?.peakLevel
    #expect(peak != nil)
    #expect(abs((peak ?? 0) - 0.01) < 0.0001)
  }

  @Test("the first token's probability reaches the stored metrics")
  func firstTokenProbabilityIsRecorded() async {
    let history = FakeHistory()
    let engine = FakeEngine()
    engine.firstTokenProbability = 0.078
    let controller = makeController(engine: engine, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let id = await history.drafts[1]!
    #expect(await history.metrics[id]?.firstTokenProbability == 0.078)
    #expect(await history.metrics[id]?.peakLevel != nil)
  }

  @Test("a discarded recording records no first-token probability")
  func firstTokenProbabilityAbsentWithoutAPass() async {
    let history = FakeHistory()
    let controller = makeController(
      detector: FakeDetector(hasSpeech: false, frameProbabilities: [0.01, 0.054]),
      history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let id = await history.drafts[1]!
    #expect(await history.metrics[id] != nil)
    #expect(await history.metrics[id]?.firstTokenProbability == nil)
  }

  @Test("the raw text is written to history before filtering and insertion")
  func rawTextIsSavedFirst() async {
    let history = FakeHistory()
    let controller = makeController(history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let id = await history.drafts[1]!
    #expect(await history.rawTexts[id] == "hello")
  }

  @Test("the clipboard is put back, and only after the session has been concluded")
  func clipboardRestoreFollowsTheSession() async {
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let concludedFirst = FlagBox()
    let controller = DictationController(
      dependencies: .init(
        audio: FakeAudio(), detector: FakeDetector(), engine: FakeEngine(),
        probe: FakeProbe(),
        inserter: TextInserter(
          clipboard: clipboard, paste: FakePaste(),
          timings: .default,
          sleep: { _ in
            concludedFirst.set(
              await history.states.contains { $0.1 == .sent })
            try? await Task.sleep(for: .milliseconds(200))
          }),
        filter: PassthroughFilter(), history: history, timings: .default,
        languages: { .default }))
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    try? await Task.sleep(for: .milliseconds(60))
    await controller.drain()
    #expect(clipboard.restores == 1)
    #expect(concludedFirst.value)
  }

  @Test("an empty whisper result is a failure, never a sent insertion")
  func emptyTranscriptIsNotSent() async {
    let engine = FakeEngine()
    engine.text = "   "
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let controller = makeController(
      engine: engine, clipboard: clipboard,
      history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes.isEmpty)
    let states = await history.states
    #expect(states.contains { $0.1 == .sent } == false)
    #expect(
      states.contains {
        $0.1 == .failed && $0.2 == SessionFailure.emptyTranscript.rawValue
      })
  }

  @Test("an observable local paste failure is never recorded as sent")
  func localPasteFailureIsRecorded() async {
    let history = FakeHistory()
    let controller = makeController(
      paste: FakePaste(succeeds: false), history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let states = await history.states
    #expect(states.contains { $0.1 == .sent } == false)
    #expect(
      states.contains {
        $0.1 == .failed && $0.2 == SessionFailure.insertionFailed.rawValue
      })
  }

  @Test("a cancel discards the audio and writes nothing")
  func cancelDiscards() async {
    let audio = FakeAudio()
    let history = FakeHistory()
    let controller = makeController(audio: audio, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.cancel(session: 1, reason: .escape))
    #expect(await audio.discarded == 1)
    #expect(await history.drafts.isEmpty)
  }

  @Test("a refused target leaves the clipboard untouched")
  func refusedTargetDoesNotTouchClipboard() async {
    var probe = FakeProbe()
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    probe.snapshotValue = TargetSnapshot(pid: 1, secureInputWasUp: false)
    probe.comparisonValue = TargetComparison(
      pid: 999, sameWindow: true, sameElement: true,
      subrole: .other("AXTextField"),
      secureInputIsUp: false)
    let controller = makeController(probe: probe, clipboard: clipboard, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes.isEmpty)
    let states = await history.states.map(\.1)
    #expect(states.contains(.rejected))
  }

  @Test("an early refusal still remembers this session's filtered text")
  func earlyRefusalRemembersThisSessionsText() async {
    struct ReplacingFilter: TextFiltering {
      func evaluate(_ text: String, language: String?) -> FilterResult {
        FilterResult(text: "filtered", wasDroppedAsHallucination: false)
      }
    }
    var probe = FakeProbe()
    probe.comparisonValue = TargetComparison(
      pid: 1, sameWindow: true, sameElement: true,
      subrole: .secureTextField,
      secureInputIsUp: false)
    let clipboard = FakeClipboard()
    let controller = DictationController(
      dependencies: .init(
        audio: FakeAudio(), detector: FakeDetector(), engine: FakeEngine(), probe: probe,
        inserter: TextInserter(
          clipboard: clipboard, paste: FakePaste(),
          timings: .default, sleep: { _ in }),
        filter: ReplacingFilter(), history: FakeHistory(),
        timings: .default, languages: { .default }))
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes.isEmpty)
    #expect(await controller.lastTranscript == "filtered")
  }

  @Test("a stop arriving during engine start-up is honoured, not dropped")
  func stopDuringStartupIsHonoured() async {
    let audio = FakeAudio()
    await audio.setStartDelay(.milliseconds(120))
    let history = FakeHistory()
    let controller = makeController(audio: audio, history: history)

    async let starting: Void = controller.handle(.start(session: 1))
    try? await Task.sleep(for: .milliseconds(20))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await starting
    await controller.drain()

    #expect(await history.drafts[1] != nil)
    await controller.handle(.start(session: 2))
    #expect(await audio.started == 2)
  }

  @Test("a cancel arriving during engine start-up still shuts the microphone down")
  func cancelDuringStartupStopsTheMicrophone() async {
    let audio = FakeAudio()
    await audio.setStartDelay(.milliseconds(120))
    let controller = makeController(audio: audio)

    async let starting: Void = controller.handle(.start(session: 1))
    try? await Task.sleep(for: .milliseconds(20))
    await controller.handle(.cancel(session: 1, reason: .tooShort))
    await starting

    #expect(await audio.isRunning == false)
    #expect(await audio.discarded >= 1)
  }

  @Test("more pending sessions than the cap refuses the new dictation")
  func overflowRefuses() async {
    var timings = Timings.default
    timings.maxPending = 1
    let engine = FakeEngine()
    engine.delay = .milliseconds(400)
    let audio = FakeAudio()
    let controller = makeController(audio: audio, engine: engine, timings: timings)

    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.handle(.start(session: 2))
    #expect(await audio.started == 1)
    await controller.drain()
  }

  @Test("a pass that overruns its deadline is recorded as failed, not left hanging")
  func passTimeoutIsRecorded() async {
    let engine = FakeEngine()
    engine.error = .timedOut
    let history = FakeHistory()
    let controller = makeController(engine: engine, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let failures = await history.states.filter { $0.1 == .failed }
    #expect(failures.count == 1)
    #expect(failures.first?.2 == SessionFailure.passTimeout.rawValue)
  }

  @Test("a detector failure is recorded as engineFailed and does not strand the queue")
  func detectorFailureIsRecordedAsEngineFailed() async {
    final class FailingOnceDetector: SpeechDetecting, @unchecked Sendable {
      private let lock = NSLock()
      private var pendingError: SpeechDetectorError? = .failed("boom")
      func markup(_ samples: [Float]) async throws -> SpeechMarkup {
        let toThrow = lock.withLock { () -> SpeechDetectorError? in
          defer { pendingError = nil }
          return pendingError
        }
        if let toThrow { throw toThrow }
        return SpeechMarkup(
          segments: [
            SpeechSegment(
              start: .zero, end: .milliseconds(900),
              probability: 0.9)
          ],
          totalDuration: .milliseconds(1_000))
      }
    }
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let controller = DictationController(
      dependencies: .init(
        audio: FakeAudio(), detector: FailingOnceDetector(), engine: FakeEngine(),
        probe: FakeProbe(),
        inserter: TextInserter(
          clipboard: clipboard, paste: FakePaste(),
          timings: .default, sleep: { _ in }),
        filter: PassthroughFilter(),
        history: history, timings: .default, languages: { .default }))
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let failures = await history.states.filter { $0.1 == .failed }
    #expect(failures.count == 1)
    #expect(failures.first?.2 == SessionFailure.engineFailed.rawValue)

    await controller.handle(.start(session: 2))
    await controller.handle(.stop(session: 2, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes == ["hello"])
  }

  @Test("an engine failure other than a timeout is engineFailed, never passTimeout")
  func engineFailureIsRecordedAsEngineFailedNotPassTimeout() async {
    let engine = FakeEngine()
    engine.error = .engineFailed("boom")
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let controller = makeController(
      engine: engine, clipboard: clipboard,
      history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    let failures = await history.states.filter { $0.1 == .failed }
    #expect(failures.count == 1)
    #expect(failures.first?.2 == SessionFailure.engineFailed.rawValue)
    #expect(failures.first?.2 != SessionFailure.passTimeout.rawValue)

    engine.error = nil
    await controller.handle(.start(session: 2))
    await controller.handle(.stop(session: 2, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes == ["hello"])
  }

  @Test("a successful insert ends in the sent state")
  func successfulInsert() async {
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let controller = makeController(clipboard: clipboard, history: history)
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes == ["hello"])
    let states = await history.states.map(\.1)
    #expect(states.last == .sent)
  }

  @Test("with history disabled the text is still filtered, refined and inserted")
  func historyOffStillInserts() async {
    actor DecliningHistory: SessionRecording {
      func createDraft(
        session: Int, startedAt: Date, durationMilliseconds: Int,
        targetBundleID: String?, modelID: String?
      ) async -> UUID? { nil }
      func markTruncated(_ id: UUID) async {}
      func attachMetrics(_ id: UUID, _ metrics: SpeechMetrics) async {}
      func attachRawText(_ id: UUID, _ text: String, language: String) async {}
      func attachFinalText(_ id: UUID, _ text: String) async {}
      func setState(_ id: UUID, _ state: SessionState, reason: String?) async {}
    }
    let clipboard = FakeClipboard()
    let controller = DictationController(
      dependencies: .init(
        audio: FakeAudio(), detector: FakeDetector(), engine: FakeEngine(),
        probe: FakeProbe(),
        inserter: TextInserter(
          clipboard: clipboard, paste: FakePaste(),
          timings: .default, sleep: { _ in }),
        filter: PassthroughFilter(),
        history: DecliningHistory(), timings: .default, languages: { .default }))

    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes == ["hello"])
  }

  @Test("a session that waited past the queue deadline fails with queueTimeout")
  func queueTimeoutIsRecorded() async {
    var timings = Timings.default
    timings.queueWait = .milliseconds(50)
    let engine = FakeEngine()
    engine.delay = .milliseconds(300)
    let history = FakeHistory()
    let controller = makeController(engine: engine, history: history, timings: timings)

    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.handle(.start(session: 2))
    await controller.handle(.stop(session: 2, reason: .releasedHold))
    await controller.drain()

    let reasons = await history.states.compactMap(\.2)
    #expect(reasons.contains(SessionFailure.queueTimeout.rawValue))
    #expect(reasons.contains(SessionFailure.passTimeout.rawValue) == false)
  }

  @Test("a filter that flags a hallucination blocks the insert but keeps the record")
  func hallucinationIsMarkedNotInserted() async {
    struct DroppingFilter: TextFiltering {
      func evaluate(_ text: String, language: String?) -> FilterResult {
        FilterResult(text: "", wasDroppedAsHallucination: true)
      }
    }
    let engine = FakeEngine()
    engine.text = "Thanks for watching..."
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let controller = DictationController(
      dependencies: .init(
        audio: FakeAudio(), detector: FakeDetector(), engine: engine, probe: FakeProbe(),
        inserter: TextInserter(
          clipboard: clipboard, paste: FakePaste(),
          timings: .default, sleep: { _ in }),
        filter: DroppingFilter(), history: history,
        timings: .default, languages: { .default }))

    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    #expect(clipboard.writes.isEmpty)
    let rejected = await history.states.filter { $0.1 == .rejected }
    #expect(rejected.first?.2 == "hallucination")
    let id = await history.drafts[1]!
    #expect(await history.rawTexts[id] == "Thanks for watching...")
  }

  @Test("an audio device change closes the session and sends what was recorded")
  func deviceChangeClosesSession() async {
    let history = FakeHistory()
    let abandon = AbandonSpy()
    let controller = makeController(
      history: history,
      abandonGesture: { abandon.record() })
    await controller.handle(.start(session: 1))
    await controller.audioDeviceChanged()
    await controller.drain()
    let id = await history.drafts[1]!
    #expect(await history.truncated.contains(id))
    #expect(await history.states.last?.1 == .sent)
    #expect(abandon.count == 1)
  }

  @Test(
    "a device change announces .working, not a stale .listening",
    .timeLimit(.minutes(1)))
  func deviceChangeAnnouncesWorking() async {
    let controller = makeController()
    let statuses = controller.status
    let collected = Task {
      var seen: [ControllerStatus] = []
      for await status in statuses {
        seen.append(status)
        if status == .working { break }
      }
      return seen
    }
    await controller.handle(.start(session: 1))
    await controller.audioDeviceChanged()
    await controller.drain()

    let seen = await collected.value
    #expect(seen.last == .working)
  }

  @Test("a device change during engine startup also releases the gesture machine")
  func deviceChangeDuringStartAbandonsGesture() async {
    let audio = FakeAudio()
    await audio.setStartDelay(.milliseconds(120))
    let abandon = AbandonSpy()
    let controller = makeController(
      audio: audio,
      abandonGesture: { abandon.record() })

    async let start: Void = controller.handle(.start(session: 1))
    try? await Task.sleep(for: .milliseconds(20))
    await controller.audioDeviceChanged()
    await start

    #expect(abandon.count == 1)
    #expect(await audio.isRunning == false)
  }

  @Test(
    "a terminal outcome is announced on the status stream, with its reason",
    .timeLimit(.minutes(1)))
  func terminalOutcomeIsAnnounced() async {
    var probe = FakeProbe()
    probe.comparisonValue = TargetComparison(
      pid: 999, sameWindow: true,
      sameElement: true,
      subrole: .other("AXTextField"),
      secureInputIsUp: false)
    let controller = makeController(probe: probe)
    let statuses = controller.status
    let collected = Task {
      var found: (Int, SessionState, String?)?
      for await status in statuses {
        if case .finished(let session, let state, let reason) = status {
          found = (session, state, reason)
          break
        }
      }
      return found
    }
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()

    let outcome = await collected.value
    #expect(outcome?.0 == 1)
    #expect(outcome?.1 == .rejected)
    #expect(outcome?.2 == InsertDenyReason.appChanged.rawValue)
  }

  @Test("an abandoned gesture discards the audio and writes nothing to history or the clipboard")
  func gestureAbandonedDiscards() async {
    let audio = FakeAudio()
    let clipboard = FakeClipboard()
    let history = FakeHistory()
    let controller = makeController(audio: audio, clipboard: clipboard, history: history)
    await controller.handle(.start(session: 1))
    await controller.gestureAbandoned()
    #expect(await audio.discarded == 1)
    #expect(await history.drafts.isEmpty)
    #expect(clipboard.writes.isEmpty)
  }

  @Test(
    "a later dictation succeeds after a gesture is abandoned",
    .timeLimit(.minutes(1)))
  func laterDictationSucceedsAfterAbandon() async {
    let audio = FakeAudio()
    let clipboard = FakeClipboard()
    let controller = makeController(audio: audio, clipboard: clipboard)
    await controller.handle(.start(session: 1))
    await controller.gestureAbandoned()
    await controller.handle(.start(session: 2))
    await controller.handle(.stop(session: 2, reason: .releasedHold))
    await controller.drain()
    #expect(await audio.started == 2)
    #expect(clipboard.writes == ["hello"])
  }

  @Test("repeated abandons never accumulate a leaked pending-queue slot")
  func repeatedAbandonsDoNotLeakThePendingCap() async {
    var timings = Timings.default
    timings.maxPending = 1
    let audio = FakeAudio()
    let controller = makeController(audio: audio, timings: timings)
    for session in 1...5 {
      await controller.handle(.start(session: session))
      await controller.gestureAbandoned()
    }
    await controller.handle(.start(session: 6))
    #expect(await audio.started == 6)
  }

  @Test("a gesture abandoned during engine start-up still shuts the microphone down")
  func gestureAbandonedDuringStartupStopsTheMicrophone() async {
    let audio = FakeAudio()
    await audio.setStartDelay(.milliseconds(120))
    let controller = makeController(audio: audio)

    async let starting: Void = controller.handle(.start(session: 1))
    try? await Task.sleep(for: .milliseconds(20))
    await controller.gestureAbandoned()
    await starting

    #expect(await audio.isRunning == false)
    #expect(await audio.discarded >= 1)
  }

  @Test("a device change racing a normal stop owns one drain and one pipeline")
  func deviceChangeDuringStopDoesNotDuplicateTheSession() async {
    let audio = FakeAudio()
    await audio.setStopDelay(.milliseconds(120))
    let history = FakeHistory()
    let controller = makeController(audio: audio, history: history)
    await controller.handle(.start(session: 1))

    async let normalStop: Void = controller.handle(
      .stop(session: 1, reason: .releasedHold))
    try? await Task.sleep(for: .milliseconds(20))
    await controller.audioDeviceChanged()
    await normalStop
    await controller.drain()

    #expect(await audio.stopCalls == 1)
    #expect(await history.states.filter { $0.1 == .recorded }.count == 1)
    let id = await history.drafts[1]!
    #expect(await history.truncated.contains(id))
  }

  @Test("the listening signal waits for real audio, not for start() returning")
  func listeningWaitsForTheFirstSample() async throws {
    let audio = FakeAudio()
    let controller = makeController(audio: audio)
    let statuses = controller.status
    let seen = StatusBox()
    let collected = Task {
      for await status in statuses {
        seen.append(status)
        if case .listening = status { break }
      }
    }
    await controller.handle(.start(session: 1))
    try await Task.sleep(for: .milliseconds(80))
    #expect(seen.sawListening == false)

    await audio.emit(level: 0.4)
    _ = await collected.value
    #expect(seen.sawListening)
  }

}

private final class EventBox: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [(String, String)] = []
  func append(_ kind: String, _ detail: String) {
    lock.withLock { events.append((kind, detail)) }
  }
  var all: [(String, String)] { lock.withLock { events } }
}

@Suite("Reporting a slow pass")
struct SlowPassTests {
  private final class TimedEngine: Transcribing, @unchecked Sendable {
    let delay: Duration
    init(delay: Duration) { self.delay = delay }
    func transcribe(
      _ samples: [Float], languages: LanguageSelection,
      deadline: Duration
    ) async throws -> Transcription {
      try? await Task.sleep(for: delay)
      return Transcription(text: "hello", language: "en", firstTokenProbability: nil)
    }
  }

  private func run(delay: Duration) async -> [(String, String)] {
    let recorded = EventBox()
    let controller = DictationController(
      dependencies: .init(
        audio: FakeAudio(), detector: FakeDetector(), engine: TimedEngine(delay: delay),
        probe: FakeProbe(),
        inserter: TextInserter(
          clipboard: FakeClipboard(), paste: FakePaste(),
          timings: .default, sleep: { _ in }),
        filter: PassthroughFilter(), history: FakeHistory(), modelID: "largeV3Turbo",
        timings: .default, languages: { .default },
        diagnose: { kind, detail in recorded.append(kind, detail) }))
    await controller.handle(DictationSignal.start(session: 1))
    await controller.handle(DictationSignal.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    return recorded.all
  }

  @Test("a pass that eats a third of the audio is reported, with its model")
  func slow() async {
    let events = await run(delay: .milliseconds(400))
    #expect(events.count == 1)
    #expect(events.first?.0 == "session.transcribed")
    #expect(events.first?.1.contains("model=largeV3Turbo") == true)
    #expect(events.first?.1.contains("session=1") == true)
  }

  @Test("an ordinary pass is not reported at all")
  func fast() async {
    #expect(await run(delay: .zero).isEmpty)
  }
}

@Suite("Surviving a device change")
struct DeviceChangeSurvivalTests {
  @Test("what was captured before the device died still reaches transcription")
  func deviceChangeKeepsTheAudio() async {
    let audio = FakeAudio()
    let engine = FakeEngine()
    let controller = makeController(audio: audio, engine: engine)
    await audio.setSamples([Float](repeating: 0.2, count: 8_000))
    await controller.handle(.start(session: 1))
    await audio.waitUntilRunning()
    await audio.simulateDeviceLoss()
    await controller.audioDeviceChanged()
    await controller.drain()

    #expect(
      engine.lastSampleCount == 8_000,
      "the buffer parked by the device change was dropped on the way to transcription")
  }
}

@Suite("An unsure language detection reaches the log")
struct LanguageDetectionLoggingTests {
  private func detections(_ scores: [String: Float]) async -> [(String, String)] {
    let engine = FakeEngine()
    engine.languageScores = scores
    let recorded = EventBox()
    let controller = makeController(engine: engine, diagnose: { recorded.append($0, $1) })
    await controller.handle(.start(session: 1))
    await controller.handle(.stop(session: 1, reason: .releasedHold))
    await controller.drain()
    return recorded.all.filter { $0.0 == "language.detected" }
  }

  @Test("a lost detector writes one line, in the shape the log accepts")
  func aLostDetectorIsLogged() async throws {
    let lines = await detections(["en": 0.29, "ru": 0.10, "pl": 0.01])
    #expect(lines.count == 1)
    let detail = try #require(lines.first?.1)
    #expect(detail.hasPrefix("session=1 langs=3 pct=29 nextPct=10 selPct=40 gap=190"))
    #expect(
      DiagnosticLog.redact(detail) == detail,
      "the log would drop a field of the line the controller actually emits")
  }

  @Test("a confident detection writes nothing")
  func aConfidentDetectionIsSilent() async {
    #expect(await detections(["en": 0.99, "ru": 0.005]).isEmpty)
  }

  @Test("an engine that reports no scores writes nothing")
  func noScoresIsSilent() async {
    #expect(await detections([:]).isEmpty)
  }
}

@Suite("A refused engine must not strand the recorder")
struct EngineRefusalReleasesRecorderTests {
  @Test("a failed raise releases the recorder, so a parked buffer cannot wedge the record key")
  func failedRaiseDiscards() async {
    let audio = FakeAudio()
    await audio.setFailStart(true)
    let controller = makeController(audio: audio)
    await controller.handle(.start(session: 1))

    #expect(
      await audio.discarded == 1,
      "a parked buffer left in the recorder wedges every later press")
  }

  @Test(
    "a failed raise is refused in the user's language, never with a raw error",
    .timeLimit(.minutes(1)))
  func failedRaiseIsRefusedInWords() async {
    let audio = FakeAudio()
    await audio.setFailStart(true)
    let controller = makeController(audio: audio)
    let statuses = controller.status
    let collected = Task {
      for await status in statuses {
        if case .refused(let reason, _) = status { return reason }
      }
      return ""
    }
    await controller.handle(.start(session: 1))
    await controller.drain()

    #expect(await collected.value == RefusalCopy.engineFailedText)
  }
}

private actor ResumeOnce {
  private var continuation: CheckedContinuation<Bool, Never>?
  init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
  func fire(_ value: Bool) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}

private func finished(
  within bound: Duration,
  _ work: @escaping @Sendable () async -> Void
) async -> Bool {
  await withCheckedContinuation { continuation in
    let once = ResumeOnce(continuation)
    Task {
      await work()
      await once.fire(true)
    }
    Task {
      try? await Task.sleep(for: bound)
      await once.fire(false)
    }
  }
}

@Suite("A gesture refused before the controller ever saw it")
struct RefusedGestureTests {
  @Test("it does not wedge the insert order of every dictation after it")
  func refusedSessionDoesNotWedgeTheQueue() async {
    let history = FakeHistory()
    let controller = makeController(history: history)

    await controller.skip(session: 1)
    await controller.handle(.start(session: 2))
    await controller.handle(.stop(session: 2, reason: .releasedHold))

    let drained = await finished(within: .seconds(2)) { await controller.drain() }
    #expect(drained, "the insert queue was left waiting on a session that never ran")
    #expect(await history.states.contains { $0.1 == .sent })
  }
}
