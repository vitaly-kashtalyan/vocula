import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

final class Latch: @unchecked Sendable {
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
  var outcome: MeetingListingOutcome = .meetings([])
  var listings = 0
  var listingGate: Latch?
  var transcript: MeetingTranscript?
  var headerResult: MeetingActionResult = .done
  var editedHeaders: [MeetingHeader] = []
  var deleteResult: MeetingActionResult = .done
  var deletes = 0
  var deleteGate: Latch?
  var writeResult: MeetingActionResult = .done
  var written: [(Data, URL)] = []
  var pasted: [String] = []
  let cipherGate = Latch()
  var states: [MeetingDiarizerState] = []
  var fetched: [DiagnosticLog?] = []

  func parts(store: MeetingStore) -> MeetingTranscriptionParts {
    MeetingTranscriptionParts(
      makeTranscriber: { [self] log, state, publish in
        made += 1
        states.append(state)
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
            makeDetector: { NoSpeech() },
            diarization: MeetingDiarization(
              state: MeetingDiarizerState(), isInstalled: { true },
              load: { throw CancellationError() },
              discard: {}, wallClock: { Date() }),
            now: { 0 },
            sleep: { try await Task.sleep(for: $0) }, publish: publish, log: log))
      },
      listing: { [self] _ in
        let gate = await MainActor.run {
          listings += 1
          return listingGate
        }
        await gate?.wait()
        return await self.outcome
      },
      transcript: { [self] _ in
        await self.transcript.map(MeetingReadResult.transcript) ?? .failed(step: "read", code: 5)
      },
      updateHeader: { [self] id, _, change in
        await MainActor.run {
          var header = MeetingHeader(id: id, startedAt: Date(timeIntervalSince1970: 0), anchor: 0)
          change(&header)
          editedHeaders.append(header)
          return headerResult
        }
      },
      delete: { [self] _, _ in
        let gate = await MainActor.run {
          deletes += 1
          return deleteGate
        }
        await gate?.wait()
        return await deleteResult
      },
      write: { [self] data, url in
        await MainActor.run {
          written.append((data, url))
          return writeResult
        }
      },
      paste: { [self] in pasted.append($0) },
      fetchDiarizer: { [self] in fetched.append($0) })
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
  var spoken: [String] = []
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
    status: MeetingStatusModel(announce: { [weak self] in self?.spoken.append($0) }),
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
    #expect(rig.fanout.subscriberCount == 1)
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
    #expect(rig.fanout.subscriberCount == 1)
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

  @Test func aStartedMeetingAsksForTheDiarizerOnce() async throws {
    let rig = Rig()
    try await rig.record()
    #expect(rig.passes.fetched.count == 1)
    #expect(rig.passes.fetched.first.flatMap { $0 } === rig.log)
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.fetched.count == 1)
  }

  @Test func aStartThatNeverRecordsAsksForNothing() async {
    let rig = Rig(key: KeySource(failure: .failed(step: "key", code: -25308)))
    await finishes(rig.meetings.toggle())
    await finishes(rig.meetings.stopping)
    #expect(rig.passes.fetched.isEmpty)
  }

  @Test func everyPassGetsTheSameDiarizerState() async throws {
    let rig = Rig()
    try await rig.record()
    await finishes(rig.meetings.toggle())
    await rig.meetings.pass?.value
    try await rig.record()
    await finishes(rig.meetings.toggle())
    await rig.meetings.pass?.value
    #expect(rig.passes.states.count == 2)
    #expect(rig.passes.states.first === rig.passes.states.last)
  }

  @Test func quitRequestsNoPass() async throws {
    let rig = Rig()
    try await rig.record()
    await rig.meetings.stopForTermination()
    await finishes(rig.meetings.stopping)
    #expect(rig.passes.made == 0)
  }

  @Test func recordLeavesARunningPassAloneAndTheNextStopRunsAnotherAfterIt() async throws {
    let rig = Rig()
    rig.passes.blocking = true
    try await rig.record()
    await finishes(rig.meetings.toggle())
    let first = try #require(rig.meetings.pass)
    try await rig.record()
    #expect(!first.isCancelled)
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.made == 1)
    rig.passes.cipherGate.open()
    await first.value
    await rig.meetings.pass?.value
    #expect(rig.passes.made == 2)
  }

  @Test func theListingRefreshesWhenRecordingStarts() async throws {
    let rig = Rig()
    let listing = MeetingListing(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 0), duration: 60)
    rig.passes.outcome = .meetings([listing])
    try await rig.record()
    await rig.meetings.refreshing?.value
    #expect(rig.meetings.status.transcripts == [listing])
    rig.passes.outcome = .unreadable(step: "key", code: -25308)
    await finishes(rig.meetings.toggle())
    await rig.meetings.refreshing?.value
    #expect(rig.meetings.status.transcripts == [listing])
  }

  @Test func renameStoresTheRuledName() async {
    let rig = Rig()
    await rig.meetings.rename(UUID(), to: "  Sync\n").value
    #expect(rig.passes.editedHeaders.map(\.title) == ["Sync"])
    await rig.meetings.rename(UUID(), to: " ").value
    #expect(rig.passes.editedHeaders.last?.title == nil)
  }

  @Test func pinIsStored() async {
    let rig = Rig()
    await rig.meetings.setPinned(UUID(), true).value
    await rig.meetings.setPinned(UUID(), false).value
    #expect(rig.passes.editedHeaders.map(\.isPinned) == [true, false])
  }

  @Test func aFailedRenameShowsTheLineAndClearsOnTheNextSuccess() async {
    let rig = Rig()
    rig.passes.headerResult = .failed(step: "write", code: 28)
    await rig.meetings.rename(UUID(), to: "Sync").value
    #expect(rig.meetings.status.sectionFailure == .notSaved)
    #expect(rig.spoken.count == 1)
    rig.passes.headerResult = .done
    await rig.meetings.setPinned(UUID(), true).value
    #expect(rig.meetings.status.sectionFailure == nil)
  }

  @Test func aFailedRenameLogsItsStepButNeverTheName() async {
    let rig = Rig()
    rig.passes.headerResult = .failed(step: "write", code: 28)
    await rig.meetings.rename(UUID(), to: "Quarterly review").value
    let lines = rig.log.recent(10).filter { $0.kind == "meeting.storeFailed" }.map(\.detail)
    #expect(lines == ["action=rename step=write code=28"])
    #expect(rig.log.recent(10).allSatisfy { !$0.detail.contains("Quarterly") })
  }

  @Test func aRefusedRenameShowsNothingAndRelists() async {
    let rig = Rig()
    rig.passes.headerResult = .refused
    await rig.meetings.rename(UUID(), to: "Sync").value
    await rig.meetings.refreshing?.value
    #expect(rig.meetings.status.sectionFailure == nil)
    #expect(rig.spoken.isEmpty)
    #expect(rig.passes.listings == 1)
  }

  private func listed(_ rig: Rig) -> UUID {
    let id = UUID()
    rig.meetings.status.update(
      listing: .meetings([
        MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 60)
      ]))
    return id
  }

  @Test func deleteIsRefusedDuringAPass() async throws {
    let rig = Rig()
    rig.passes.blocking = true
    try await rig.record()
    await finishes(rig.meetings.toggle())
    let id = listed(rig)
    await rig.meetings.delete(id).value
    #expect(rig.passes.deletes == 0)
    rig.passes.cipherGate.open()
    await rig.meetings.pass?.value
  }

  @Test func aPassWaitsForADeleteInFlight() async throws {
    let rig = Rig()
    let gate = Latch()
    rig.passes.deleteGate = gate
    try await rig.record()
    let id = listed(rig)
    let deleting = rig.meetings.delete(id)
    for _ in 0..<50 where rig.passes.deletes == 0 { await Task.yield() }
    await finishes(rig.meetings.toggle())
    #expect(rig.passes.made == 0)
    gate.open()
    await deleting.value
    #expect(rig.passes.made == 1)
  }

  @Test func aRefusedDeleteShowsNothingAndRelists() async {
    let rig = Rig()
    rig.passes.deleteResult = .refused
    await rig.meetings.delete(listed(rig)).value
    await rig.meetings.refreshing?.value
    #expect(rig.passes.deletes == 1)
    #expect(rig.meetings.status.sectionFailure == nil)
    #expect(rig.spoken.isEmpty)
    #expect(rig.passes.listings == 1)
  }

  @Test func aPinnedMeetingIsNeverSentToTheStore() async {
    let rig = Rig()
    let id = UUID()
    rig.meetings.status.update(
      listing: .meetings([
        MeetingListing(
          id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 60, isPinned: true)
      ]))
    await rig.meetings.delete(id).value
    #expect(rig.passes.deletes == 0)
  }

  private func named(_ rig: Rig, _ title: String?) -> UUID {
    let id = UUID()
    rig.meetings.status.update(
      listing: .meetings([
        MeetingListing(
          id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 3, title: title)
      ]))
    rig.passes.transcript = MeetingTranscript(
      model: "m", utterances: [MeetingUtterance(start: 1, end: 2, speaker: .others, text: "hi")])
    return id
  }

  @Test func aNamedMeetingCopiesWithItsTitle() async {
    let rig = Rig()
    let id = named(rig, "Sync")
    await rig.meetings.copyTranscript(id, includeMe: true).value
    await rig.meetings.copyFromSection(id, includeMe: true).value
    #expect(rig.passes.pasted.count == 2)
    #expect(rig.passes.pasted.allSatisfy { $0.hasPrefix("---\ntitle: \"Sync\"\ndate: ") })
  }

  @Test func anUnnamedMeetingCopiesWithoutATitle() async {
    let rig = Rig()
    await rig.meetings.copyFromSection(named(rig, nil), includeMe: true).value
    #expect(rig.passes.pasted.first?.hasPrefix("---\ndate: ") == true)
  }

  @Test func exportDataIsTheCopyMarkdown() async {
    let rig = Rig()
    let id = named(rig, "Sync")
    await rig.meetings.copyFromSection(id, includeMe: false).value
    let data = await rig.meetings.exportData(id, includeMe: false)
    #expect(data.map { String(decoding: $0, as: UTF8.self) } == rig.passes.pasted.first)
  }

  @Test func anExportThatCannotBeWrittenShowsTheLine() async {
    let rig = Rig()
    rig.passes.writeResult = .failed(step: "write", code: 13)
    await rig.meetings.write(Data("x".utf8), to: URL(fileURLWithPath: "/tmp/x.md")).value
    #expect(rig.meetings.status.sectionFailure == .exportNotWritten)
    #expect(
      rig.log.recent(10).filter { $0.kind == "meeting.storeFailed" }.map(\.detail)
        == ["action=export step=write code=13"])
  }

  @Test func aTranscriptThatWillNotOpenShowsTheLine() async {
    let rig = Rig()
    let id = named(rig, nil)
    rig.passes.transcript = nil
    #expect(await rig.meetings.open(id) == nil)
    #expect(rig.meetings.status.sectionFailure == .transcriptUnreadable)
    #expect(
      rig.log.recent(10).filter { $0.kind == "meeting.storeFailed" }.map(\.detail)
        == ["action=open step=read code=5"])
  }

  @Test func theMenuCopyStillLogsTranscribeFailed() async {
    let rig = Rig()
    let id = named(rig, nil)
    rig.passes.transcript = nil
    await rig.meetings.copyTranscript(id, includeMe: true).value
    #expect(rig.meetings.status.copyFailed)
    #expect(rig.meetings.status.sectionFailure == nil)
    #expect(
      rig.log.recent(10).filter { $0.kind == "meeting.transcribeFailed" }.map(\.detail)
        == ["step=read code=5"])
  }

  @Test func theSectionAppearingLists() async {
    let rig = Rig()
    let listing = MeetingListing(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 0), duration: 60)
    rig.passes.outcome = .meetings([listing])
    rig.meetings.sectionAppeared()
    await rig.meetings.refreshing?.value
    #expect(rig.passes.listings == 1)
    #expect(rig.meetings.status.meetings == [listing])
    #expect(rig.meetings.status.sectionContent == .list)
  }

  @Test func listingsNeverOverlapAndRunOnceMore() async {
    let rig = Rig()
    let gate = Latch()
    rig.passes.listingGate = gate
    rig.meetings.sectionAppeared()
    for _ in 0..<50 where rig.passes.listings == 0 { await Task.yield() }
    rig.meetings.sectionAppeared()
    rig.meetings.sectionAppeared()
    #expect(rig.passes.listings == 1)
    rig.passes.listingGate = nil
    gate.open()
    await rig.meetings.refreshing?.value
    #expect(rig.passes.listings == 2)
  }

  @Test func noKeyWithAnEmptyFolderIsEmptyAndUnlogged() async {
    let rig = Rig()
    rig.passes.outcome = .noKey(holdsMeetings: false)
    rig.meetings.sectionAppeared()
    await rig.meetings.refreshing?.value
    #expect(rig.meetings.status.sectionContent == .empty)
    #expect(rig.log.recent(10).allSatisfy { !$0.kind.hasPrefix("meeting.") })
  }

  @Test func noKeyWithMeetingsIsLoggedOnce() async {
    let rig = Rig()
    rig.passes.outcome = .noKey(holdsMeetings: true)
    for _ in 0..<2 {
      rig.meetings.sectionAppeared()
      await rig.meetings.refreshing?.value
    }
    #expect(rig.meetings.status.sectionContent == .lineAlone)
    #expect(
      rig.log.recent(10).filter { $0.kind == "meeting.transcribeFailed" }.map(\.detail)
        == ["step=key code=-25300"])
  }

  @Test func anUnreadableListingLogsOnChangeOnly() async {
    let rig = Rig()
    rig.passes.outcome = .unreadable(step: "key", code: -25308)
    for _ in 0..<2 {
      rig.meetings.sectionAppeared()
      await rig.meetings.refreshing?.value
    }
    #expect(
      rig.log.recent(10).filter { $0.kind == "meeting.transcribeFailed" }.map(\.detail)
        == ["step=key code=-25308"])
    rig.passes.outcome = .meetings([])
    rig.meetings.sectionAppeared()
    await rig.meetings.refreshing?.value
    rig.passes.outcome = .unreadable(step: "key", code: -25308)
    rig.meetings.sectionAppeared()
    await rig.meetings.refreshing?.value
    #expect(rig.log.recent(10).filter { $0.kind == "meeting.transcribeFailed" }.count == 2)
  }

  @Test func aStopFinishingLists() async throws {
    let rig = Rig()
    rig.passes.blocking = true
    try await rig.record()
    await rig.meetings.refreshing?.value
    let before = rig.passes.listings
    await finishes(rig.meetings.toggle())
    await rig.meetings.refreshing?.value
    #expect(rig.passes.listings == before + 1)
    rig.passes.cipherGate.open()
    await rig.meetings.pass?.value
  }

  @Test func busyCoversOverlappingStops() async throws {
    let rig = Rig(systemFinish: .gated, .gated)
    try await rig.record()
    #expect(rig.meetings.status.busy)
    rig.meetings.toggle()
    await rig.systems[0].finishCalled.wait()
    try await rig.record()
    let second = rig.meetings.toggle()
    await rig.systems[1].finishCalled.wait()
    rig.systems[0].openFinish()
    for _ in 0..<200 where rig.passes.made == 0 { await Task.yield() }
    #expect(rig.meetings.status.busy)
    rig.systems[1].openFinish()
    await finishes(second)
    #expect(!rig.meetings.status.busy)
  }

  @Test func passRunningIsMirrored() async throws {
    let rig = Rig()
    rig.passes.blocking = true
    try await rig.record()
    await finishes(rig.meetings.toggle())
    #expect(rig.meetings.status.passRunning)
    rig.passes.cipherGate.open()
    await rig.meetings.pass?.value
    #expect(!rig.meetings.status.passRunning)
  }

  @Test func copyPutsMarkdownOnThePasteboard() async {
    let rig = Rig()
    let id = UUID()
    rig.meetings.status.transcriptUnreadable()
    rig.meetings.status.update(
      listing: .meetings([
        MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 3)
      ]))
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
    rig.meetings.status.update(
      listing: .meetings([
        MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 9)
      ]))
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
    rig.meetings.status.update(
      listing: .meetings([
        MeetingListing(id: id, startedAt: Date(timeIntervalSince1970: 0), duration: 3)
      ]))
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
    #expect(await MeetingTranscriptionParts.liveListing(log: nil) == .meetings([]))
    #expect(await MeetingTranscriptionParts.liveRead(UUID()) == .unavailable)
    #expect(
      await MeetingTranscriptionParts.liveUpdateHeader(UUID(), busy: false) { _ in } == .refused)
    #expect(await MeetingTranscriptionParts.liveDelete(UUID(), busy: false) == .refused)
  }

  @Test func aSecondCopyCreatesNoStore() {
    #expect(Meetings.makeStore() == nil)
    #expect(
      MeetingTranscriptionParts.liveTranscriber(
        log: nil, state: MeetingDiarizerState(), publish: { _ in }) == nil)
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
