import Foundation
import Testing

@testable import VoculaKit

final class RecognizerLog: @unchecked Sendable {
  private let lock = NSLock()
  private var madeCount = 0
  private var releasedCount = 0
  private var sizes: [Int] = []
  private var moments: [UInt64] = []
  var failures: [Int: any Error] = [:]
  var stall: TestClock?
  var clock: TestClock?
  var onCall: (@Sendable (Int) async -> Void)?

  var made: Int { lock.withLock { madeCount } }
  var released: Int { lock.withLock { releasedCount } }
  var calls: [Int] { lock.withLock { sizes } }
  var times: [UInt64] { lock.withLock { moments } }

  func didMake() { lock.withLock { madeCount += 1 } }
  func didRelease() { lock.withLock { releasedCount += 1 } }

  func called(_ size: Int) throws -> Int {
    try lock.withLock {
      sizes.append(size)
      moments.append(clock?.now() ?? 0)
      if let failure = failures[sizes.count] { throw failure }
      return sizes.count
    }
  }
}

final class PassRecognizer: MeetingRecognizing, @unchecked Sendable {
  private let log: RecognizerLog

  init(_ log: RecognizerLog) {
    self.log = log
    log.didMake()
  }

  deinit { log.didRelease() }

  func recognize(_ samples: [Float], languages: LanguageSelection) async throws -> [TimedText] {
    let call = try log.called(samples.count)
    await log.onCall?(call)
    if let clock = log.stall { try await clock.sleep(for: .seconds(3_600)) }
    return [TimedText(start: 0.1, end: 0.3, text: "w\(call)")]
  }
}

final class DetectorLog: @unchecked Sendable {
  private let lock = NSLock()
  private var madeCount = 0
  private var releasedCount = 0
  private var callCount = 0
  private var moments: [UInt64] = []
  var failures: [Int: any Error] = [:]
  var always: (any Error)?
  var clock: TestClock?

  var made: Int { lock.withLock { madeCount } }
  var released: Int { lock.withLock { releasedCount } }
  var times: [UInt64] { lock.withLock { moments } }

  func didMake() { lock.withLock { madeCount += 1 } }
  func didRelease() { lock.withLock { releasedCount += 1 } }

  func called() throws {
    try lock.withLock {
      callCount += 1
      moments.append(clock?.now() ?? 0)
      if let always { throw always }
      if let failure = failures[callCount] { throw failure }
    }
  }
}

final class PassDetector: SpeechDetecting, @unchecked Sendable {
  private let log: DetectorLog

  init(_ log: DetectorLog) {
    self.log = log
    log.didMake()
  }

  deinit { log.didRelease() }

  func markup(_ samples: [Float]) async throws -> SpeechMarkup {
    try log.called()
    var segments: [SpeechSegment] = []
    var start: Int?
    for (index, sample) in samples.enumerated() {
      if sample != 0, start == nil { start = index }
      if sample == 0, let from = start {
        segments.append(segment(from, index))
        start = nil
      }
    }
    if let from = start { segments.append(segment(from, samples.count)) }
    return SpeechMarkup(segments: segments, totalDuration: .milliseconds(samples.count / 16))
  }

  private func segment(_ from: Int, _ to: Int) -> SpeechSegment {
    SpeechSegment(start: .milliseconds(from / 16), end: .milliseconds(to / 16), probability: 0.9)
  }
}

final class Published: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [MeetingTranscription?] = []

  var all: [MeetingTranscription?] { lock.withLock { values } }
  func add(_ value: MeetingTranscription?) { lock.withLock { values.append(value) } }
}

final class TranscriberRig: @unchecked Sendable {
  let s: UInt64 = 1_000_000_000
  let root = meetingTemporaryDirectory()
  let clock = TestClock(start: 0)
  let recognizers = RecognizerLog()
  let detectors = DetectorLog()
  let published = Published()
  let log: DiagnosticLog
  let store: MeetingStore
  var cipherError: (any Error)?
  var cipherWait: TestClock?
  let cipher = MarkingCipher()
  var model: MeetingModel? = MeetingModel(model: .largeV3Turbo, languages: .default)
  var recognizerLoadError: (any Error)?
  lazy var hold = MeetingHoldGate(
    hold: DictationHold(passDeadline: { max(.seconds(30), $0) }, refineWait: { nil }),
    now: { [clock] in clock.now() }, sleep: { [clock] in try await clock.sleep(for: $0) })

  init() {
    log = DiagnosticLog(fileURL: root.appendingPathComponent("diagnostics.json"))
    store = MeetingStore(directory: root.appendingPathComponent("Meetings"))
  }

  var meetings: URL { root.appendingPathComponent("Meetings") }

  func transcriber() -> MeetingTranscriber {
    MeetingTranscriber(
      MeetingTranscriber.Dependencies(
        store: store,
        cipher: { [self] in
          if let cipherWait { try await cipherWait.sleep(for: .seconds(60)) }
          if let cipherError { throw cipherError }
          return cipher
        },
        model: { [self] in model },
        makeRecognizer: { [self] _ in
          if let recognizerLoadError { throw recognizerLoadError }
          return PassRecognizer(recognizers)
        },
        makeDetector: { [self] in PassDetector(detectors) },
        hold: hold,
        now: { [clock] in clock.now() },
        sleep: { [clock] in try await clock.sleep(for: $0) },
        publish: { [published] in published.add($0) },
        log: log))
  }

  func run() async { await transcriber().run() }

  func drive(_ pass: Task<Void, Never>) async {
    let done = Published()
    Task {
      await pass.value
      done.add(nil)
    }
    while done.all.isEmpty {
      if clock.parked > 0 { clock.advance(by: .seconds(1)) }
      await Task.yield()
    }
  }

  func speech(at seconds: Double, for length: Double, value: Int16 = 1_000) -> MeetingRun {
    MeetingRun(
      start: s + HostTime.nanos(seconds),
      samples: Array(repeating: value, count: Int(length * 16_000)))
  }

  @discardableResult
  func meeting(
    startedAt: TimeInterval = 800_000_000, lasting: Double = 3, mic: [MeetingRun] = [],
    system: [MeetingRun] = [], dictations: [DictationSpan] = [], raw: [String: Data] = [:]
  ) throws -> MeetingHeader {
    var header = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: startedAt), anchor: s)
    header.dictations = dictations
    header.finish(atHost: s + HostTime.nanos(lasting), by: .stopped)
    var chunks = raw
    for (index, run) in mic.enumerated() {
      chunks[String(format: "audio/mic-%06d.sealed", index)] =
        MarkingCipher.mark
        + MeetingChunk(track: .mic, sequence: UInt32(index), runs: [run]).encoded()
    }
    for (index, run) in system.enumerated() {
      chunks[String(format: "audio/system-%06d.sealed", index)] =
        MarkingCipher.mark
        + MeetingChunk(track: .system, sequence: UInt32(index), runs: [run]).encoded()
    }
    try plant(header: header, chunks: chunks, in: meetings)
    return header
  }

  func transcript(of header: MeetingHeader) async -> MeetingTranscript? {
    try? await store.transcript(of: header.id, cipher: MarkingCipher())
  }

  func hasAudio(_ header: MeetingHeader) -> Bool {
    FileManager.default.fileExists(
      atPath: meetings.appendingPathComponent("\(header.id.uuidString)/audio").path)
  }

  func lines(_ kind: String) -> [String] {
    log.recent(100).reversed().filter { $0.kind == kind }.map(\.detail)
  }
}

@Suite struct MeetingTranscriberTests {
  @Test func nothingPendingLoadsNothing() async {
    let rig = TranscriberRig()
    await rig.run()
    #expect(rig.recognizers.made == 0)
    #expect(rig.detectors.made == 0)
    #expect(rig.published.all.isEmpty)
    #expect(rig.lines("meeting.transcribed").isEmpty)
  }

  @Test func transcribesNewestFirstAndRemovesAudio() async throws {
    let rig = TranscriberRig()
    let older = try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    let newer = try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 2)])
    await rig.run()
    #expect(rig.recognizers.calls == [32_000, 16_000])
    #expect(await rig.transcript(of: newer)?.utterances.map(\.speaker) == [.me])
    #expect(await rig.transcript(of: older)?.utterances.map(\.speaker) == [.me])
    #expect(await rig.transcript(of: newer)?.model == "largeV3Turbo")
    #expect(!rig.hasAudio(older))
    #expect(!rig.hasAudio(newer))
    #expect(rig.published.all.last == .finished(transcribed: 2, failed: 0))
    #expect(rig.recognizers.made == 1)
    #expect(rig.recognizers.released == 1)
    #expect(rig.detectors.made == 1)
    #expect(rig.detectors.released == 1)
  }

  @Test func wordsLandAtTheirTimeAndDictationsAreMarked() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(
      lasting: 8, mic: [rig.speech(at: 1, for: 1)], system: [rig.speech(at: 5, for: 1)],
      dictations: [DictationSpan(start: rig.s + rig.s / 2, end: rig.s * 5 / 2)])
    await rig.run()
    let utterances = try #require(await rig.transcript(of: header)?.utterances)
    #expect(utterances.map(\.speaker) == [.me, .others])
    #expect(abs(utterances[0].start - 1.1) < 0.001)
    #expect(abs(utterances[1].start - 5.1) < 0.001)
    #expect(utterances.map(\.dictation) == [true, false])
  }

  @Test func anEmptyMeetingNeedsNoModel() async throws {
    let rig = TranscriberRig()
    rig.model = nil
    let header = try rig.meeting()
    await rig.run()
    #expect(await rig.transcript(of: header)?.utterances == [])
    #expect(rig.recognizers.made == 0)
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 0))
  }

  @Test func removalsNeedNoModel() async throws {
    let rig = TranscriberRig()
    rig.model = nil
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    try await rig.store.writeTranscript(
      .empty, of: header.id, cipher: MarkingCipher())
    await rig.run()
    #expect(!rig.hasAudio(header))
    #expect(rig.recognizers.made == 0)
    #expect(rig.published.all.isEmpty)
  }

  @Test func aKeyFailureEndsThePass() async throws {
    let rig = TranscriberRig()
    rig.cipherError = MeetingFailure.failed(step: "key", code: -25300)
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=key code=-25300"])
    #expect(rig.published.all == [.finished(transcribed: 0, failed: 1)])
    #expect(rig.hasAudio(header))
    #expect(rig.recognizers.made == 0)
  }

  @Test func aCancelledKeyLookupPublishesNothing() async throws {
    let rig = TranscriberRig()
    rig.cipherWait = rig.clock
    try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.clock.untilSleeping(1)
    pass.cancel()
    await pass.value
    #expect(rig.published.all.isEmpty)
    #expect(rig.lines("meeting.transcribeFailed").isEmpty)
  }

  @Test func aListingFailureEndsThePass() async throws {
    let rig = TranscriberRig()
    try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    chmod(rig.meetings.path, 0)
    defer { chmod(rig.meetings.path, 0o700) }
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed").first?.hasPrefix("step=list") == true)
    #expect(rig.published.all == [.finished(transcribed: 0, failed: 1)])
  }

  @Test func noModelEndsThePass() async throws {
    let rig = TranscriberRig()
    rig.model = nil
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=model code=0"])
    #expect(rig.published.all.last == .finished(transcribed: 0, failed: 1))
    #expect(rig.hasAudio(header))
  }

  @Test func aRecogniserThatCannotLoadEndsThePass() async throws {
    let rig = TranscriberRig()
    rig.recognizerLoadError = MeetingFailure.failed(step: "load", code: 3)
    try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=model code=3"])
    #expect(rig.published.all.last == .finished(transcribed: 0, failed: 2))
  }

  @Test func aDetectorThatCannotLoadEndsThePass() async throws {
    let rig = TranscriberRig()
    rig.detectors.always = SpeechDetectorError.modelNotLoaded
    try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=vad code=0"])
    #expect(rig.published.all.last == .finished(transcribed: 0, failed: 2))
  }

  @Test func aDetectorFailingOnAWindowFailsTheMeeting() async throws {
    let rig = TranscriberRig()
    rig.detectors.failures = [1: SpeechDetectorError.failed("x")]
    let newer = try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    let older = try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=vad code=0"])
    #expect(rig.hasAudio(newer))
    #expect(await rig.transcript(of: older) != nil)
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 1))
  }

  @Test func aRecogniserErrorFailsOneMeetingAndMovesOn() async throws {
    let rig = TranscriberRig()
    rig.recognizers.failures = [1: MeetingFailure.failed(step: "whisper", code: -7)]
    let newer = try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    let older = try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=recognize code=-7"])
    #expect(rig.hasAudio(newer))
    #expect(await rig.transcript(of: newer) == nil)
    #expect(await rig.transcript(of: older) != nil)
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 1))
  }

  @Test func anUnreadableChunkFileFailsTheMeetingAndMovesOn() async throws {
    let rig = TranscriberRig()
    let newer = try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    let older = try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    let file = rig.meetings.appendingPathComponent("\(newer.id.uuidString)/audio/mic-000000.sealed")
    chmod(file.path, 0)
    defer { chmod(file.path, 0o600) }
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed").first?.hasPrefix("step=read") == true)
    #expect(rig.hasAudio(newer))
    #expect(await rig.transcript(of: older) != nil)
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 1))
  }

  @Test func aSealFailureFailsTheMeetingAndMovesOn() async throws {
    let rig = TranscriberRig()
    let newer = try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    let older = try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    rig.cipher.failNext(1)
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=seal code=0"])
    #expect(rig.hasAudio(newer))
    #expect(await rig.transcript(of: older) != nil)
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 1))
  }

  @Test("ACCEPTED COST: a chunk that will not open is lost with the audio")
  func aCorruptChunkIsSkippedAndCounted() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(
      mic: [rig.speech(at: 0.5, for: 1)], raw: ["audio/mic-000001.sealed": Data("junk".utf8)])
    await rig.run()
    #expect(await rig.transcript(of: header) != nil)
    #expect(!rig.hasAudio(header))
    #expect(rig.lines("meeting.transcribed").first?.contains("skippedChunks=1") == true)
  }

  @Test func aDictationBetweenPiecesHoldsTheNextPiece() async throws {
    let rig = TranscriberRig()
    rig.recognizers.clock = rig.clock
    try rig.meeting(lasting: 8, mic: [rig.speech(at: 0.5, for: 1), rig.speech(at: 4, for: 1)])
    let hold = rig.hold
    rig.recognizers.onCall = { call in
      guard call == 1 else { return }
      await hold.received(.start(session: 1))
      await hold.received(.stop(session: 1, reason: .releasedHold))
    }
    await rig.drive(Task { await rig.run() })
    #expect(rig.recognizers.times.count == 2)
    #expect((rig.recognizers.times.last ?? 0) >= 30 * rig.s)
  }

  @Test func aDictationBetweenWindowsHoldsTheNextWindow() async throws {
    let rig = TranscriberRig()
    rig.detectors.clock = rig.clock
    try rig.meeting(lasting: 70, mic: [rig.speech(at: 0.5, for: 1), rig.speech(at: 62, for: 1)])
    let hold = rig.hold
    rig.recognizers.onCall = { call in
      guard call == 1 else { return }
      await hold.received(.start(session: 1))
      await hold.received(.stop(session: 1, reason: .releasedHold))
    }
    await rig.drive(Task { await rig.run() })
    #expect(rig.detectors.times.count == 2)
    #expect((rig.detectors.times.last ?? 0) >= 30 * rig.s)
  }

  @Test func aWholeCorruptTrackFailsTheMeeting() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(
      system: [rig.speech(at: 0.5, for: 1)], raw: ["audio/mic-000000.sealed": Data("junk".utf8)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=open code=0"])
    #expect(rig.hasAudio(header))
    #expect(rig.published.all.last == .finished(transcribed: 0, failed: 1))
  }

  @Test func aRunPastTheEndFailsTheMeeting() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(lasting: 3, mic: [rig.speech(at: 5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.transcribeFailed") == ["step=open code=0"])
    #expect(rig.hasAudio(header))
  }

  @Test func aStalledPieceMissesItsDeadline() async throws {
    let rig = TranscriberRig()
    rig.recognizers.stall = rig.clock
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.clock.untilSleeping(2)
    rig.clock.advance(by: .seconds(30))
    await pass.value
    #expect(rig.lines("meeting.transcribeFailed") == ["step=recognize code=0"])
    #expect(rig.hasAudio(header))
  }

  @Test func cancellingWritesNothingAndReleases() async throws {
    let rig = TranscriberRig()
    rig.recognizers.stall = rig.clock
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.clock.untilSleeping(2)
    pass.cancel()
    await pass.value
    #expect(await rig.transcript(of: header) == nil)
    #expect(rig.hasAudio(header))
    #expect(rig.recognizers.made == 1)
    #expect(rig.recognizers.released == 1)
    #expect(rig.published.all.last == .some(nil))
  }

  @Test func cancellingWaitsForTheHoldBeforeReleasing() async throws {
    let rig = TranscriberRig()
    rig.recognizers.stall = rig.clock
    try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.clock.untilSleeping(2)
    await rig.hold.received(.start(session: 1))
    pass.cancel()
    await rig.clock.untilSleeping(1)
    #expect(rig.recognizers.released == 0)
    await rig.hold.received(.stop(session: 1, reason: .releasedHold))
    for _ in 0..<30 {
      await rig.clock.untilSleeping(1)
      rig.clock.advance(by: .seconds(1))
    }
    await pass.value
    #expect(rig.recognizers.released == 1)
  }

  @Test func theHoldGatesTheModelLoad() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    await rig.hold.received(.start(session: 1))
    await rig.hold.received(.stop(session: 1, reason: .releasedHold))
    let pass = Task { await rig.run() }
    await rig.clock.untilSleeping(1)
    #expect(rig.recognizers.made == 0)
    for _ in 0..<30 {
      await rig.clock.untilSleeping(1)
      rig.clock.advance(by: .seconds(1))
    }
    await pass.value
    #expect(await rig.transcript(of: header) != nil)
    #expect(rig.lines("meeting.transcribed").first?.contains("pausedSeconds=30") == true)
  }

  @Test func progressIsPublishedAsAWholePercent() async throws {
    let rig = TranscriberRig()
    try rig.meeting(
      lasting: 2, mic: [rig.speech(at: 0, for: 2)], system: [rig.speech(at: 0, for: 2)])
    await rig.run()
    #expect(rig.published.all.first == .running(percent: 0))
    #expect(rig.published.all.contains(.running(percent: 50)))
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 0))
  }

  @Test func silentTrackYieldsNoUtterances() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(
      mic: [rig.speech(at: 0.5, for: 1)], system: [rig.speech(at: 0, for: 2, value: 0)])
    await rig.run()
    #expect(await rig.transcript(of: header)?.utterances.map(\.speaker) == [.me])
    #expect(rig.recognizers.calls.count == 1)
  }

  @Test func aCarryAtTheTrackEndIsRecognised() async throws {
    let rig = TranscriberRig()
    var samples = [Int16](repeating: 0, count: 960_000)
    for index in 952_000..<960_000 { samples[index] = 1_000 }
    let header = try rig.meeting(lasting: 60, mic: [MeetingRun(start: rig.s, samples: samples)])
    await rig.run()
    #expect(rig.recognizers.calls == [8_000])
    #expect(await rig.transcript(of: header)?.utterances.count == 1)
  }

  @Test func oneLinePerPass() async throws {
    let rig = TranscriberRig()
    try rig.meeting(startedAt: 800_000_000, mic: [rig.speech(at: 0.5, for: 1)])
    try rig.meeting(startedAt: 800_000_600, mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    let lines = rig.lines("meeting.transcribed")
    #expect(lines.count == 1)
    #expect(
      lines.first
        == "meetings=2 audioSeconds=3 pieces=2 utterances=2 echoDropped=0 skippedChunks=0"
        + " pausedSeconds=0 tookSeconds=0 model=largeV3Turbo")
  }

  @Test func aRemoveFailureStillCountsAsTranscribed() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    let audio = rig.meetings.appendingPathComponent("\(header.id.uuidString)/audio")
    chmod(audio.path, 0o500)
    defer { chmod(audio.path, 0o700) }
    await rig.run()
    #expect(await rig.transcript(of: header) != nil)
    #expect(rig.lines("meeting.transcribeFailed").first?.hasPrefix("step=remove") == true)
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 0))
  }
}
