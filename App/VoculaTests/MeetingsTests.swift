import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

private final class Latch: @unchecked Sendable {
  private let lock = NSLock()
  private var opened = false
  private var nextWaiter = 0
  private var cancelled: Set<Int> = []
  private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

  var isOpen: Bool { lock.withLock { opened } }

  func open() {
    let resumed = lock.withLock {
      opened = true
      defer { waiting = [:] }
      return Array(waiting.values)
    }
    resumed.forEach { $0.resume() }
  }

  func wait() async {
    let id = lock.withLock {
      defer { nextWaiter += 1 }
      return nextWaiter
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let already = lock.withLock {
          if opened || cancelled.remove(id) != nil { return true }
          waiting[id] = continuation
          return false
        }
        if already { continuation.resume() }
      }
    } onCancel: {
      let parked: CheckedContinuation<Void, Never>? = lock.withLock {
        guard let continuation = waiting.removeValue(forKey: id) else {
          cancelled.insert(id)
          return nil
        }
        return continuation
      }
      parked?.resume()
    }
  }
}

private final class Gate: @unchecked Sendable {
  private let lock = NSLock()
  private var opened = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func open() {
    let resumed = lock.withLock {
      opened = true
      defer { waiting = [] }
      return waiting
    }
    resumed.forEach { $0.resume() }
  }

  func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let already = lock.withLock {
        if opened { return true }
        waiting.append(continuation)
        return false
      }
      if already { continuation.resume() }
    }
  }
}

private final class ManualSleeper: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  private var parked: [Int: CheckedContinuation<Void, any Error>] = [:]
  private var cancelledEarly: Set<Int> = []
  private var waiters: [(count: Int, latch: Latch)] = []

  var calls: Int { lock.withLock { count } }

  func sleep(for _: Duration) async throws {
    let id = lock.withLock {
      count += 1
      return count
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let (cancelled, ready): (Bool, [Latch]) = lock.withLock {
          if cancelledEarly.remove(id) != nil { return (true, []) }
          parked[id] = continuation
          let ready = waiters.filter { $0.count <= parked.count }.map(\.latch)
          waiters.removeAll { $0.count <= parked.count }
          return (false, ready)
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
        ready.forEach { $0.open() }
      }
    } onCancel: {
      let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
        guard let continuation = parked.removeValue(forKey: id) else {
          cancelledEarly.insert(id)
          return nil
        }
        return continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  func fire() {
    let woken = lock.withLock {
      defer { parked = [:] }
      return Array(parked.values)
    }
    woken.forEach { $0.resume() }
  }

  func untilSleeping(_ count: Int = 1) async {
    let latch = Latch()
    let ready = lock.withLock {
      if parked.count >= count { return true }
      waiters.append((count, latch))
      return false
    }
    if !ready { await latch.wait() }
  }
}

private final class StubTrack: MeetingTrackSource, @unchecked Sendable {
  enum Finish { case immediate, gated, never }

  let finishCalled = Latch()
  private let finish: Finish
  private let gate = Gate()
  private let lock = NSLock()
  private var stops = 0
  private var returned = false

  init(finish: Finish = .immediate) { self.finish = finish }

  var stopCount: Int { lock.withLock { stops } }
  var finishedReturned: Bool { lock.withLock { returned } }
  var callbacks: Int { 0 }

  func openFinish() { gate.open() }

  func start() async throws {}

  func stop() { lock.withLock { stops += 1 } }

  func finished() async {
    finishCalled.open()
    switch finish {
    case .immediate: break
    case .gated: await gate.wait()
    case .never: await Gate().wait()
    }
    lock.withLock { returned = true }
  }

  func drain() -> TrackDrain { TrackDrain() }
}

private final class KeySource: @unchecked Sendable {
  let called = Latch()
  private let gate: DispatchSemaphore?
  private let lock = NSLock()
  private var failing: MeetingFailure?

  var failure: MeetingFailure? {
    get { lock.withLock { failing } }
    set { lock.withLock { failing = newValue } }
  }

  init(gated: Bool = false, failure: MeetingFailure? = nil) {
    gate = gated ? DispatchSemaphore(value: 0) : nil
    failing = failure
  }

  func open() { gate?.signal() }

  func cipher() throws -> any HistoryCipher {
    called.open()
    gate?.wait()
    if let failure { throw failure }
    return PassthroughCipher()
  }
}

private final class PowerSpy: @unchecked Sendable {
  private let lock = NSLock()
  private var released = 0

  var releases: Int { lock.withLock { released } }

  func hold() -> MeetingPowerHold {
    .held(release: { [self] in lock.withLock { released += 1 } })
  }
}

private struct NoSpeech: SpeechDetecting {
  func markup(_ samples: [Float]) async throws -> SpeechMarkup {
    SpeechMarkup(segments: [], totalDuration: .zero)
  }
}

@MainActor
private final class PassProbe {
  var made = 0
  var blocking = false
  var listing: [MeetingListing]?
  var transcript: MeetingTranscript?
  var pasted: [String] = []
  var holds: [MeetingHoldGate] = []
  let cipherGate = Latch()

  func parts(store: MeetingStore) -> MeetingTranscriptionParts {
    MeetingTranscriptionParts(
      makeHold: { [self] in
        let hold = MeetingHoldGate(
          hold: DictationHold(passDeadline: { _ in .zero }, refineWait: { nil }),
          now: { 0 }, sleep: { try await Task.sleep(for: $0) })
        holds.append(hold)
        return hold
      },
      makeTranscriber: { [self] log, hold, publish in
        made += 1
        guard blocking else { return nil }
        let gate = cipherGate
        return MeetingTranscriber(
          MeetingTranscriber.Dependencies(
            store: store,
            cipher: {
              await gate.wait()
              return PassthroughCipher()
            },
            model: { nil }, makeRecognizer: { _ in throw CancellationError() },
            makeDetector: { NoSpeech() }, hold: hold, now: { 0 },
            sleep: { try await Task.sleep(for: $0) }, publish: publish, log: log))
      },
      listing: { [self] _ in await self.listing },
      transcript: { [self] _, _ in await self.transcript },
      paste: { [self] in pasted.append($0) })
  }
}

@discardableResult
private func finishes(_ task: Task<Void, Never>?) async -> Bool {
  guard let task else { return true }
  let done = Latch()
  Task {
    await task.value
    done.open()
  }
  await done.wait()
  return done.isOpen
}

@MainActor
private final class Rig {
  let key: KeySource
  let power = PowerSpy()
  let quit = ManualSleeper()
  let ticks = ManualSleeper()
  let fanout = StreamFanout<DictationSignal>(bufferingPolicy: .unbounded)
  let passes = PassProbe()
  let root: URL
  let store: MeetingStore
  let log: DiagnosticLog
  private let temporary: URL
  private let systemFinishes: [StubTrack.Finish]
  private(set) var recoverFlags: [Bool] = []
  private(set) var mics: [StubTrack] = []
  private(set) var systems: [StubTrack] = []

  var mic: StubTrack { mics[0] }
  var system: StubTrack { systems[0] }

  lazy var meetings = Meetings(
    diagnosticLog: { [log] in log },
    status: MeetingStatusModel(announce: { _ in }),
    makeDependencies: { [weak self] log, recover in
      self?.dependencies(log: log, recover: recover)
    },
    sleep: { [quit] in try await quit.sleep(for: $0) },
    transcription: passes.parts(store: store))

  init(key: KeySource = KeySource(), systemFinish: StubTrack.Finish...) {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent("vocula-meetings-\(UUID().uuidString)", isDirectory: true)
    self.key = key
    self.temporary = temporary
    systemFinishes = systemFinish
    root = temporary.appendingPathComponent("Meetings", isDirectory: true)
    store = MeetingStore(directory: root)
    log = DiagnosticLog(fileURL: temporary.appendingPathComponent("diagnostics.json"))
    try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: temporary) }

  var meetingIDs: [UUID] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
      .compactMap(UUID.init(uuidString:))
  }

  func headers() async -> [MeetingHeader] {
    var headers: [MeetingHeader] = []
    for id in meetingIDs {
      if let header = await store.header(of: id, cipher: PassthroughCipher()) {
        headers.append(header)
      }
    }
    return headers
  }

  func header() async -> MeetingHeader? {
    let headers = await headers()
    return headers.count == 1 ? headers[0] : nil
  }

  func record() async throws {
    await finishes(meetings.toggle())
    try #require(meetings.status.isRecording)
  }

  private func dependencies(log: DiagnosticLog?, recover: Bool) -> MeetingRecorder.Dependencies {
    recoverFlags.append(recover)
    let mic = StubTrack()
    let system = StubTrack(
      finish: mics.count < systemFinishes.count ? systemFinishes[mics.count] : .immediate)
    mics.append(mic)
    systems.append(system)
    let (key, power, ticks) = (key, power, ticks)
    return MeetingRecorder.Dependencies(
      store: store, cipher: { try key.cipher() }, makeMicrophone: { _ in mic },
      makeSystemAudio: { system }, holdPower: { _ in power.hold() },
      watchDeviceList: { _ in nil }, now: { 1_000 }, sleep: { try await ticks.sleep(for: $0) },
      wallClock: { Date(timeIntervalSinceReferenceDate: 800_000_000) }, publish: { _ in },
      ended: {}, log: log, recover: recover)
  }
}

@MainActor
@Suite("A meeting exists from Record to its end and not a moment longer", .timeLimit(.minutes(1)))
struct MeetingsTests {
  @Test func nothingExistsUntilRecord() {
    let rig = Rig()
    rig.meetings.pipelineStarted(rig.fanout)
    rig.fanout.emit(.start(session: 1))
    rig.fanout.emit(.stop(session: 1, reason: .releasedHold))
    #expect(rig.recoverFlags.isEmpty)
    #expect(rig.fanout.subscriberCount == 0)
    #expect(!rig.meetings.holdsAMeeting)
    #expect(rig.passes.made == 0)
    #expect(rig.meetings.refreshing == nil)
  }

  @Test func everythingIsReleasedWhenTheMeetingEnds() async throws {
    let rig = Rig()
    rig.meetings.pipelineStarted(rig.fanout)
    try await rig.record()
    #expect(rig.fanout.subscriberCount == 2)
    #expect(rig.meetings.holdsAMeeting)
    await finishes(rig.meetings.toggle())
    #expect(!rig.meetings.holdsAMeeting)
    #expect(rig.fanout.subscriberCount == 0)
    #expect(rig.mic.stopCount == 1)
    #expect(rig.system.stopCount == 1)
    #expect(rig.mic.finishedReturned)
    #expect(rig.system.finishedReturned)
    #expect(rig.power.releases == 1)
  }

  @Test func aUserStopHidesTheItemAtOnce() async throws {
    let rig = Rig()
    try await rig.record()
    #expect(rig.meetings.status.statusItemShown)
    let stop = rig.meetings.toggle()
    #expect(!rig.meetings.status.statusItemShown)
    await finishes(stop)
  }

  @Test func aPressDuringAPendingStartIsIgnored() async throws {
    let rig = Rig(key: KeySource(gated: true))
    let start = try #require(rig.meetings.toggle())
    await rig.key.called.wait()
    #expect(rig.meetings.toggle() == nil)
    rig.key.open()
    await finishes(start)
    #expect(rig.meetingIDs.count == 1)
    #expect(rig.recoverFlags.count == 1)
    await finishes(rig.meetings.toggle())
  }

  @Test func aPipelineTearDownDoesNotTouchTheMeeting() async throws {
    let rig = Rig()
    rig.meetings.pipelineStarted(rig.fanout)
    try await rig.record()
    rig.fanout.finishAll()
    #expect(rig.fanout.subscriberCount == 0)
    #expect(rig.meetings.status.isRecording)
    #expect(rig.mic.stopCount == 0)
    #expect(rig.system.stopCount == 0)
    rig.meetings.pipelineStarted(rig.fanout)
    #expect(rig.fanout.subscriberCount == 2)
    rig.fanout.emit(.start(session: 2))
    rig.fanout.finishAll()
    await finishes(rig.meetings.toggle())
    #expect(await rig.header()?.endedBy == .stopped)
  }

  @Test func aStopRequestsAPass() async throws {
    let rig = Rig()
    try await rig.record()
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.made == 1)
  }

  @Test func quitRequestsNoPass() async throws {
    let rig = Rig()
    try await rig.record()
    await rig.meetings.stopForTermination()
    await finishes(rig.meetings.stopping)
    #expect(rig.passes.made == 0)
  }

  @Test func recordCancelsAPassAndTheNextStopRunsIt() async throws {
    let rig = Rig()
    rig.passes.blocking = true
    try await rig.record()
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.made == 1)
    let first = try #require(rig.meetings.pass)
    try await rig.record()
    await first.value
    #expect(rig.meetings.pass == nil)
    #expect(rig.passes.made == 1)
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.made == 2)
    rig.passes.cipherGate.open()
    await rig.meetings.pass?.value
  }

  @Test func theListingRefreshesWhenRecordingStarts() async throws {
    let rig = Rig()
    let listing = MeetingListing(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 0), duration: 60)
    rig.passes.listing = [listing]
    try await rig.record()
    await rig.meetings.refreshing?.value
    #expect(rig.meetings.status.transcripts == [listing])
    rig.passes.listing = nil
    await finishes(rig.meetings.toggle())
    await rig.meetings.refreshing?.value
    #expect(rig.meetings.status.transcripts == [listing])
  }

  @Test func dictationSignalsReachTheHold() async throws {
    let rig = Rig()
    rig.meetings.pipelineStarted(rig.fanout)
    try await rig.record()
    let hold = try #require(rig.passes.holds.last)
    rig.fanout.emit(.start(session: 1))
    var waited = 0
    while await !hold.isHeld, waited < 200 {
      try await Task.sleep(for: .milliseconds(5))
      waited += 1
    }
    #expect(await hold.isHeld)
    rig.fanout.emit(.stop(session: 1, reason: .releasedHold))
    waited = 0
    while await hold.isHeld, waited < 200 {
      try await Task.sleep(for: .milliseconds(5))
      waited += 1
    }
    #expect(await !hold.isHeld)
    await finishes(rig.meetings.toggle())
    #expect(rig.fanout.subscriberCount == 0)
  }

  @Test func copyPutsMarkdownOnThePasteboard() async {
    let rig = Rig()
    let id = UUID()
    rig.meetings.status.transcriptUnreadable()
    rig.meetings.status.update(transcripts: [
      MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 3)
    ])
    rig.passes.transcript = MeetingTranscript(
      model: "largeV3Turbo",
      utterances: [
        MeetingUtterance(start: 1, end: 2, speaker: .me, text: "hello")
      ])
    await rig.meetings.copyTranscript(id, includeMe: true).value
    let me = String(localized: MenuCopy.meetingSpeakerMe)
    #expect(rig.passes.pasted.count == 1)
    #expect(rig.passes.pasted.first?.hasPrefix("---\ndate: 1970-01-01T00:00:00Z\n") == true)
    #expect(rig.passes.pasted.first?.contains("**\(me)** [00:00:01]: hello") == true)
    #expect(!rig.meetings.status.copyFailed)
    #expect(!rig.meetings.status.statusItemShown)
  }

  @Test func aCopyCanLeaveMyLinesOut() async {
    let rig = Rig()
    let id = UUID()
    rig.meetings.status.update(transcripts: [
      MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 9)
    ])
    rig.passes.transcript = MeetingTranscript(
      model: "largeV3Turbo",
      utterances: [
        MeetingUtterance(start: 1, end: 2, speaker: .me, text: "mine"),
        MeetingUtterance(start: 3, end: 4, speaker: .others, text: "theirs"),
      ])
    await rig.meetings.copyTranscript(id, includeMe: false).value
    #expect(rig.passes.pasted.first?.contains("theirs") == true)
    #expect(rig.passes.pasted.first?.contains("mine") == false)
  }

  @Test func anUnreadableCopyIsShown() async {
    let rig = Rig()
    let id = UUID()
    rig.meetings.status.update(transcripts: [
      MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 3)
    ])
    await rig.meetings.copyTranscript(id, includeMe: true).value
    #expect(rig.passes.pasted.isEmpty)
    #expect(rig.meetings.status.copyFailed)
    #expect(rig.meetings.status.statusItemShown)
  }

  @Test func recordClearsAFinishedPass() async throws {
    let rig = Rig()
    rig.meetings.status.update(transcription: .finished(transcribed: 1, failed: 0))
    try await rig.record()
    #expect(rig.meetings.status.transcription == nil)
    await finishes(rig.meetings.toggle())
  }

  @Test func theRecoveryFlagReachesTheDependencies() async throws {
    let rig = Rig()
    try await rig.record()
    await finishes(rig.meetings.toggle())
    try await rig.record()
    #expect(rig.recoverFlags == [true, false])
    await finishes(rig.meetings.toggle())
  }

  @Test func aMeetingThatFailedToStartLeavesItsNotice() async {
    let rig = Rig(key: KeySource(failure: .failed(step: "key", code: -25308)))
    await finishes(rig.meetings.toggle())
    #expect(rig.meetings.status.notice == .cannotStart)
    #expect(rig.meetings.status.statusItemShown)
    await finishes(rig.meetings.stopping)
    #expect(!rig.meetings.holdsAMeeting)
    #expect(rig.meetings.status.statusItemShown)
    #expect(rig.passes.made == 0)
  }

  @Test func aRefusedStartDoesNotSuppressTheNextMeetingsPass() async throws {
    let rig = Rig(key: KeySource(failure: .failed(step: "key", code: -25308)))
    await finishes(rig.meetings.toggle())
    await finishes(rig.meetings.stopping)
    #expect(rig.passes.made == 0)
    rig.key.failure = nil
    try await rig.record()
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.made == 1)
  }

  @Test func aStatusTrailingTheFinalOneIsDropped() async throws {
    let rig = Rig()
    try await rig.record()
    let trailing = MeetingStatus(isRecording: true, startedAt: rig.meetings.status.startedAt)
    rig.meetings.apply(MeetingStatus(notice: .autoStopped), of: 1)
    rig.meetings.apply(trailing, of: 1)
    #expect(!rig.meetings.status.isRecording)
    #expect(rig.meetings.status.notice == .autoStopped)
    await finishes(rig.meetings.toggle())
  }

  @Test func aStatusOfAnEarlierMeetingChangesNothing() async throws {
    let rig = Rig()
    try await rig.record()
    await finishes(rig.meetings.toggle())
    try await rig.record()
    let startedAt = rig.meetings.status.startedAt
    rig.meetings.apply(MeetingStatus(notice: .autoStopped), of: 1)
    rig.meetings.apply(
      MeetingStatus(
        isRecording: true, startedAt: Date(timeIntervalSince1970: 1), warnings: [.noSystemAudio]),
      of: 1)
    #expect(rig.meetings.status.isRecording)
    #expect(rig.meetings.status.notice == nil)
    #expect(rig.meetings.status.warnings.isEmpty)
    #expect(rig.meetings.status.startedAt == startedAt)
    await finishes(rig.meetings.toggle())
    #expect(!rig.meetings.status.isRecording)
    #expect(rig.mics[1].stopCount == 1)
  }

  @Test func aStartWithNoDependenciesLeavesTheSwitchIdle() {
    let calls = MeetingCallCounter()
    let meetings = Meetings(
      diagnosticLog: { nil }, status: MeetingStatusModel(announce: { _ in }),
      makeDependencies: { _, _ in
        calls.increment()
        return nil
      })
    #expect(meetings.toggle() == nil)
    #expect(meetings.toggle() == nil)
    #expect(calls.value == 2)
    #expect(!meetings.holdsAMeeting)
  }

  @Test func aSecondCopyListsNoTranscripts() async {
    #expect(await MeetingTranscriptionParts.liveListing(log: nil) == nil)
    #expect(await MeetingTranscriptionParts.liveTranscript(UUID(), log: nil) == nil)
  }

  @Test func aSecondCopyCreatesNoStore() {
    #expect(Meetings.makeStore() == nil)
    #expect(
      MeetingTranscriptionParts.liveTranscriber(
        log: nil, hold: MeetingTranscriptionParts.liveHold(), publish: { _ in }) == nil)
    #expect(Meetings.live(log: nil, recover: true) == nil)
  }

  @Test func quitWithNoMeetingReturnsAtOnce() async throws {
    let rig = Rig()
    #expect(await finishes(Task { await rig.meetings.stopForTermination() }))
    #expect(rig.quit.calls == 0)
    try await rig.record()
    await finishes(rig.meetings.toggle())
    await finishes(rig.meetings.stopping)
    #expect(await finishes(Task { await rig.meetings.stopForTermination() }))
  }

  @Test func quitAwaitsAQuickTeardown() async throws {
    let rig = Rig(systemFinish: .gated)
    try await rig.record()
    let returned = Latch()
    let quit = Task {
      await rig.meetings.stopForTermination()
      returned.open()
    }
    await rig.system.finishCalled.wait()
    await rig.quit.untilSleeping()
    #expect(!returned.isOpen)
    rig.system.openFinish()
    #expect(await finishes(quit))
    #expect(await rig.header()?.endedBy == .quit)
  }

  @Test func quitAbandonsAHungTeardownAtTheBound() async throws {
    let rig = Rig(systemFinish: .never)
    try await rig.record()
    let quit = Task { await rig.meetings.stopForTermination() }
    await rig.system.finishCalled.wait()
    await rig.quit.untilSleeping()
    rig.quit.fire()
    #expect(await finishes(quit))
    let header = await rig.header()
    #expect(header?.state == .recorded)
    #expect(header?.endedBy == .quit)
  }

  @Test func quitAwaitsAUserStartedStop() async throws {
    let rig = Rig(systemFinish: .gated)
    try await rig.record()
    let stop = rig.meetings.toggle()
    let returned = Latch()
    let quit = Task {
      await rig.meetings.stopForTermination()
      returned.open()
    }
    await rig.system.finishCalled.wait()
    await rig.quit.untilSleeping()
    #expect(!returned.isOpen)
    rig.system.openFinish()
    #expect(await finishes(quit))
    #expect(await rig.header()?.endedBy == .stopped)
    #expect(await finishes(stop))
  }

  @Test func aHungTeardownDoesNotHoldUpTheNextMeetingsStop() async throws {
    let rig = Rig(systemFinish: .never)
    try await rig.record()
    rig.meetings.toggle()
    await rig.systems[0].finishCalled.wait()
    try await rig.record()
    rig.meetings.toggle()
    await rig.systems[1].finishCalled.wait()
    #expect(rig.mics[1].stopCount == 1)
    let headers = await rig.headers()
    #expect(headers.map(\.state) == [.recorded, .recorded])
    #expect(headers.map(\.endedBy) == [.stopped, .stopped])
  }

  @Test func aHungTeardownDoesNotHoldUpTheNextMeetingsQuit() async throws {
    let rig = Rig(systemFinish: .never)
    try await rig.record()
    rig.meetings.toggle()
    await rig.systems[0].finishCalled.wait()
    try await rig.record()
    let quit = Task { await rig.meetings.stopForTermination() }
    await rig.systems[1].finishCalled.wait()
    await rig.quit.untilSleeping()
    rig.quit.fire()
    #expect(await finishes(quit))
    let headers = await rig.headers()
    #expect(headers.map(\.state) == [.recorded, .recorded])
    #expect(Set(headers.compactMap(\.endedBy)) == [.stopped, .quit])
  }
}
