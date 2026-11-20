import Foundation
import Testing

@testable import VoculaKit

private let anchor: UInt64 = 1_000_000_000
private let s: UInt64 = 1_000_000_000

@Suite(.timeLimit(.minutes(1))) struct MeetingRecorderStartTests {
  @Test func aStartPublishesRecordingAndHoldsPower() async {
    let h = MeetingHarness()
    await h.recorder.start()
    #expect(h.statuses == [MeetingStatus(isRecording: true, startedAt: h.wallClock)])
    #expect(h.power.holds == 1)
    #expect(h.kinds() == ["meeting.start"])
    #expect(await h.header()?.anchor == anchor)
  }

  @Test func aSecondCopyIsSilent() async {
    let h = MeetingHarness(cipher: CipherSource(error: MeetingFailure.secondCopy))
    await h.recorder.start()
    #expect(h.meetingDirectories.isEmpty)
    #expect(h.kinds().isEmpty)
    #expect(h.statuses.isEmpty)
    #expect(h.micsMade == 0)
    #expect(h.power.holds == 0)
    #expect(h.ended.isOpen)
  }

  @Test func anUnavailableKeyStartsNothing() async {
    let h = MeetingHarness(
      cipher: CipherSource(error: MeetingFailure.failed(step: "key", code: -25308)))
    await h.recorder.start()
    #expect(h.meetingDirectories.isEmpty)
    #expect(h.statuses == [MeetingStatus(notice: .cannotStart)])
    #expect(h.detail(of: "meeting.writeFailed") == "step=key code=-25308")
    #expect(h.micsMade == 0)
    #expect(h.ended.isOpen)
  }

  @Test func aHeaderThatCannotBeWrittenStartsNothing() async throws {
    let file = meetingTemporaryDirectory().appendingPathComponent("file")
    try Data().write(to: file)
    let h = MeetingHarness(root: file.appendingPathComponent("Meetings"))
    await h.recorder.start()
    #expect(h.statuses == [MeetingStatus(notice: .cannotStart)])
    #expect(h.detail(of: "meeting.writeFailed")?.hasPrefix("step=directory") == true)
    #expect(h.micsMade == 0)
    #expect(h.power.holds == 0)
    #expect(h.ended.isOpen)
  }

  @Test func aSecondStartIsIgnored() async {
    let cipher = CipherSource(gated: true)
    let h = MeetingHarness(cipher: cipher)
    let first = Task { await h.recorder.start() }
    await cipher.called.wait()
    #expect(await value(of: Task { await h.recorder.start() }) != nil)
    cipher.open()
    #expect(await value(of: first) != nil)
    #expect(h.meetingDirectories.count == 1)
    #expect(cipher.calls == 1)
  }

  @Test func aQuitDuringAPendingKeyLookupCreatesNothing() async {
    let cipher = CipherSource(gated: true)
    let h = MeetingHarness(cipher: cipher)
    let starting = Task { await h.recorder.start() }
    await cipher.called.wait()
    #expect(await value(of: Task { await h.recorder.stop(.quit) }) != nil)
    #expect(h.ended.isOpen == false)
    cipher.open()
    #expect(await value(of: starting) != nil)
    #expect(h.meetingDirectories.isEmpty)
    #expect(h.statuses.isEmpty)
    #expect(h.micsMade == 0)
    #expect(h.ended.isOpen)
  }

  @Test(arguments: [true, false]) func recoveryIsReported(recover: Bool) async throws {
    let root = meetingTemporaryDirectory()
    let interrupted = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: 700_000_000), anchor: 5)
    try plant(header: interrupted, chunks: [:], in: root)
    let h = MeetingHarness(recover: recover, root: root)
    await h.recorder.start()
    #expect(h.detail(of: "meeting.recovered") == (recover ? "count=1" : nil))
  }

  @Test(arguments: [MeetingEnd.sleep, .quit])
  func anEndDuringTheFirstPublishStartsNoTrack(end: MeetingEnd) async {
    let system = FakeTrackSource()
    let h = MeetingHarness(system: system, holdFirstPublish: true)
    let starting = Task { await h.recorder.start() }
    await h.publishHeld.wait()
    let ending = Task {
      if end == .sleep { await h.power.onWillSleep?() } else { await h.recorder.stop(end) }
    }
    #expect(await value(of: ending) != nil)
    h.releasePublish()
    #expect(await value(of: starting) != nil)
    await h.settleSystemStart()
    #expect(system.startCount == 0)
    #expect(h.micsMade == 0)
    #expect(h.clock.parked == 0)
    #expect(await h.header()?.endedBy == end)
  }

  @Test func aPowerFailureIsLoggedAndTheMeetingRecords() async {
    let h = MeetingHarness(power: PowerHoldSpy(failing: -536_870_211))
    await h.recorder.start()
    #expect(h.statuses.last?.isRecording == true)
    #expect(h.detail(of: "meeting.powerFailed") == "code=-536870211")
    #expect(h.kinds() == ["meeting.powerFailed", "meeting.start"])
    await h.recorder.stop(.stopped)
    #expect(await h.header()?.state == .recorded)
    #expect(h.power.releases == 0)
  }
}

private func voices(_ count: Int) -> [TrackDrain] {
  Array(repeating: voice(at: anchor), count: count)
}

private func dictate(_ session: Int, into h: MeetingHarness) async {
  let at = anchor + UInt64(session) * s
  await h.recorder.dictation(.start(session: session), generation: 1, at: at)
  await h.recorder.dictation(
    .stop(session: session, reason: .releasedHold), generation: 1, at: at + s / 2)
}

@Suite(.timeLimit(.minutes(1))) struct MeetingRecorderFlushTests {
  @Test func aChunkPerTrackEveryThreeSeconds() async {
    let h = MeetingHarness(
      mics: [FakeTrackSource(drains: voices(3))], system: FakeTrackSource(drains: voices(3)))
    await h.recorder.start()
    await h.tick(.seconds(3))
    #expect(h.audioFiles() == ["mic-000000.sealed", "system-000000.sealed"])
    await h.tick(.seconds(3))
    #expect(
      h.audioFiles() == [
        "mic-000000.sealed", "mic-000001.sealed", "system-000000.sealed", "system-000001.sealed",
      ])
    await h.tick(.seconds(1))
    #expect(h.audioFiles().count == 4)
  }

  @Test func theKeyIsAskedForOnce() async {
    let cipher = CipherSource()
    let h = MeetingHarness(
      cipher: cipher, mics: [FakeTrackSource(drains: voices(3))],
      system: FakeTrackSource(drains: voices(3)))
    await h.recorder.start()
    for _ in 0..<3 { await h.tick(.seconds(3)) }
    #expect(h.audioFiles().count == 6)
    #expect(cipher.calls == 1)
  }

  @Test func anEmptyDrainWritesNoChunk() async {
    let h = MeetingHarness(system: FakeTrackSource(drains: voices(1)))
    await h.recorder.start()
    await h.tick(.seconds(3))
    #expect(h.audioFiles() == ["system-000000.sealed"])
  }

  @Test func aWriteFailureIsLoggedOncePerEpisode() async {
    let marking = MarkingCipher()
    let h = MeetingHarness(
      cipher: CipherSource(marking), mics: [FakeTrackSource(drains: voices(4))],
      system: FakeTrackSource(drains: voices(4)))
    await h.recorder.start()
    marking.failNext(6)
    for _ in 0..<4 { await h.tick(.seconds(3)) }
    #expect(h.kinds().filter { $0 == "meeting.writeFailed" }.count == 1)
    #expect(h.detail(of: "meeting.writeFailed") == "step=seal code=0")
    #expect(h.audioFiles() == ["mic-000003.sealed", "system-000003.sealed"])
  }

  @Test func aHeaderWriteFailureIsLoggedOncePerEpisodeAndWarned() async {
    let marking = MarkingCipher()
    let h = MeetingHarness(cipher: CipherSource(marking))
    await h.recorder.start()
    marking.failNext(3)
    for session in 1...3 { await dictate(session, into: h) }
    await h.tick(.seconds(1))
    #expect(h.kinds().filter { $0 == "meeting.writeFailed" }.count == 1)
    #expect(h.detail(of: "meeting.writeFailed") == "step=seal code=0")
    #expect(h.statuses.last?.warnings.contains(.cannotSave) == true)
    await dictate(4, into: h)
    await h.tick(.seconds(1))
    #expect(h.statuses.last?.warnings.contains(.cannotSave) == false)
    #expect(await h.header()?.dictations.count == 4)
  }

  @Test func aBacklogDropIsAWriteFailure() async {
    let h = MeetingHarness(mics: [FakeTrackSource(drains: [TrackDrain(droppedNanos: s)])])
    await h.recorder.start()
    await h.tick(.seconds(3))
    #expect(h.detail(of: "meeting.writeFailed") == "step=backlog code=0")
    #expect(h.audioFiles().isEmpty)
  }

  @Test func aFailedTapIsLoggedAndTheMicKeepsRecording() async {
    let h = MeetingHarness(
      mics: [FakeTrackSource(drains: voices(1))],
      system: FakeTrackSource(start: .fail(.failed(step: "aggregate", code: -1))))
    await h.recorder.start()
    await h.settleSystemStart()
    #expect(h.detail(of: "meeting.tapFailed") == "step=aggregate code=-1")
    await h.tick(.seconds(3))
    #expect(h.audioFiles() == ["mic-000000.sealed"])
  }
}

@Suite(.timeLimit(.minutes(1))) struct MeetingRecorderStopTests {
  @Test func aStopEndsTheMeetingRecorded() async {
    let mic = FakeTrackSource()
    let system = FakeTrackSource()
    let h = MeetingHarness(mics: [mic], system: system)
    await h.recorder.start()
    await h.recorder.stop(.stopped)
    let header = await h.header()
    #expect(header?.state == .recorded)
    #expect(header?.endedBy == .stopped)
    #expect(header?.end != nil)
    #expect(mic.stopCount == 1)
    #expect(system.stopCount == 1)
    #expect(h.power.releases == 1)
    #expect(h.ended.isOpen)
    #expect(h.statuses.last == MeetingStatus())
  }

  @Test func theStopLineCarriesTheNumbers() async {
    let h = MeetingHarness(mics: [FakeTrackSource(drains: voices(1))])
    await h.recorder.start()
    await h.recorder.stop(.stopped)
    #expect(
      h.detail(of: "meeting.stop")
        == "reason=stopped micSeconds=0 micSoundSeconds=1 systemSeconds=0 systemSoundSeconds=0"
        + " runs=1 droppedSeconds=0")
    #expect(h.audioFiles() == ["mic-000000.sealed"])
  }

  @Test func stopDoesNotWaitForABlockedTap() async {
    let system = FakeTrackSource(start: .gated, finish: .never)
    let h = MeetingHarness(system: system)
    #expect(await value(of: Task { await h.recorder.start() }) != nil)
    Task { await h.recorder.stop(.stopped) }
    await h.ended.wait()
    #expect(await h.header()?.state == .recorded)
    #expect(system.stopCount == 1)
    await system.finishCalled.wait()
    #expect(system.finishedReturned == false)
  }

  @Test func theLastFlushFollowsTheOneInFlight() async {
    let cipher = GatedSealCipher()
    let mic = FakeTrackSource(drains: voices(1))
    let h = MeetingHarness(
      cipher: CipherSource(cipher), mics: [mic], system: FakeTrackSource(drains: voices(1)))
    await h.recorder.start()
    await h.clock.untilSleeping()
    cipher.holdNextSeal()
    h.clock.advance(by: .seconds(3))
    await cipher.sealHeld.wait()
    let stopping = Task { await h.recorder.stop(.stopped) }
    await mic.stopCalled.wait()
    cipher.releaseSeal()
    await h.ended.wait()
    #expect(
      h.detail(of: "meeting.stop")
        == "reason=stopped micSeconds=0 micSoundSeconds=1 systemSeconds=0 systemSoundSeconds=1"
        + " runs=2 droppedSeconds=0")
    #expect(h.audioFilesWhenEnded == ["mic-000000.sealed", "system-000000.sealed"])
    #expect(await value(of: stopping) != nil)
  }

  @Test func theStopAwaitsATeardownThatReturns() async {
    let system = FakeTrackSource(finish: .gated)
    let h = MeetingHarness(system: system)
    await h.recorder.start()
    let stopping = Task {
      await h.recorder.stop(.quit)
      return system.finishedReturned
    }
    await system.finishCalled.wait()
    system.openFinish()
    #expect(await value(of: stopping) == true)
  }

  @Test func aStopDuringTheMicrophoneOpenClosesIt() async {
    let mic = FakeTrackSource(start: .gated)
    let h = MeetingHarness(mics: [mic])
    let starting = Task { await h.recorder.start() }
    await mic.startCalled.wait()
    #expect(await value(of: Task { await h.recorder.stop(.stopped) }) != nil)
    mic.openStart()
    #expect(await value(of: starting) != nil)
    #expect(mic.stopCount == 2)
    #expect(await h.header()?.state == .recorded)
  }

  @Test func aStopAfterTheEndAwaitsTheTeardown() async {
    let system = FakeTrackSource(finish: .gated)
    let h = MeetingHarness(system: system)
    await h.recorder.start()
    let first = Task { await h.recorder.stop(.stopped) }
    await h.ended.wait()
    let second = Task {
      await h.recorder.stop(.quit)
      return system.finishedReturned
    }
    system.openFinish()
    #expect(await value(of: second) == true)
    #expect(await value(of: first) != nil)
    #expect(await h.header()?.endedBy == .stopped)
  }
}

private func askToSleep(
  _ recorder: isolated MeetingRecorder, after asked: Latch, in h: MeetingHarness
)
  async -> (files: [String], state: MeetingState?)
{
  asked.open()
  await recorder.systemWillSleep()
  let files = h.audioFiles()
  return (files, await h.header()?.state)
}

private func onRecorder(_ recorder: isolated MeetingRecorder) {}

@Suite(.timeLimit(.minutes(1))) struct MeetingRecorderSleepTests {
  @Test func sleepStopsTheMeetingThenLogsTheAllow() async {
    let system = FakeTrackSource(finish: .never)
    let h = MeetingHarness(system: system)
    await h.recorder.start()
    #expect(await value(of: Task { await h.power.onWillSleep?() }) != nil)
    #expect(await h.header()?.endedBy == .sleep)
    #expect(h.kinds() == ["meeting.start", "meeting.stop", "meeting.sleepAllowed"])
    #expect(h.statuses.last?.notice == .endedBySleep)
    #expect(h.power.releases == 1)
    #expect(system.stopCount == 1)
  }

  @Test func aSleepDuringAStopWaitsUntilTheStopIsWritten() async {
    let cipher = GatedSealCipher()
    let h = MeetingHarness(
      cipher: CipherSource(cipher), mics: [FakeTrackSource(drains: voices(1))])
    await h.recorder.start()
    cipher.holdNextSeal()
    let stopping = Task { await h.recorder.stop(.stopped) }
    await cipher.sealHeld.wait()
    let asked = Latch()
    let sleeping = Task { await askToSleep(h.recorder, after: asked, in: h) }
    await asked.wait()
    await onRecorder(h.recorder)
    cipher.releaseSeal()
    let atReturn = await value(of: sleeping)
    #expect(atReturn?.files == ["mic-000000.sealed"])
    #expect(atReturn?.state == .recorded)
    #expect(h.kinds() == ["meeting.start", "meeting.stop", "meeting.sleepAllowed"])
    #expect(await h.header()?.endedBy == .stopped)
    #expect(await value(of: stopping) != nil)
  }
}

@Suite(.timeLimit(.minutes(1))) struct MeetingRecorderSpanTests {
  @Test func spansAreWrittenWithTheHeader() async {
    let h = MeetingHarness()
    await h.recorder.start()
    await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor + s)
    await h.recorder.dictation(
      .stop(session: 1, reason: .releasedHold), generation: 1, at: anchor + 3 * s)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor + s, end: anchor + 3 * s)])
  }

  @Test func aDictationDuringTheStartIsNotASpan() async {
    let cipher = CipherSource(gated: true)
    let h = MeetingHarness(cipher: cipher)
    let starting = Task { await h.recorder.start() }
    await cipher.called.wait()
    #expect(
      await value(
        of: Task { await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor) })
        != nil)
    cipher.open()
    #expect(await value(of: starting) != nil)
    await h.recorder.dictation(.start(session: 2), generation: 1, at: anchor + s)
    await h.tick(.seconds(2))
    await h.recorder.stop(.stopped)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor + s, end: h.clock.now())])
  }

  @Test func aGenerationEndingDoesNotTouchTheMeeting() async {
    let mic = FakeTrackSource(drains: voices(1))
    let system = FakeTrackSource(drains: voices(1))
    let h = MeetingHarness(mics: [mic], system: system)
    await h.recorder.start()
    await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor + s)
    await h.recorder.generationEnded(1, at: anchor + 2 * s)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor + s, end: anchor + 2 * s)])
    #expect(h.statuses.last?.isRecording == true)
    #expect(mic.stopCount == 0)
    #expect(system.stopCount == 0)
    await h.tick(.seconds(3))
    #expect(h.audioFiles().contains("mic-000000.sealed"))
  }

  @Test func followingTheSignalsRecordsASpan() async {
    let h = MeetingHarness()
    await h.recorder.start()
    let fanout = StreamFanout<DictationSignal>(bufferingPolicy: .unbounded)
    let signals = fanout.subscribe()
    let following = Task { await h.recorder.follow(signals) }
    fanout.emit(.start(session: 1))
    fanout.finishAll()
    #expect(await value(of: following) != nil)
    let now = h.clock.now()
    #expect(await h.header()?.dictations == [DictationSpan(start: now, end: now)])
  }

  @Test func theMeetingEndClosesAnOpenSpan() async {
    let h = MeetingHarness()
    await h.recorder.start()
    await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor + s)
    await h.tick(.seconds(2))
    await h.recorder.stop(.stopped)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor + s, end: h.clock.now())])
  }

  @Test func aStaleGenerationEndLeavesTheNewStreamsSpanOpen() async {
    let h = MeetingHarness()
    await h.recorder.start()
    await h.recorder.dictation(.start(session: 1), generation: 2, at: anchor + s)
    await h.recorder.generationEnded(1, at: anchor + 2 * s)
    #expect(await h.header()?.dictations == [])
    await h.recorder.dictation(
      .stop(session: 1, reason: .releasedHold), generation: 2, at: anchor + 3 * s)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor + s, end: anchor + 3 * s)])
  }

  @Test func aSpanIsClippedToTheMeeting() async {
    let h = MeetingHarness()
    await h.recorder.start()
    await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor - s)
    await h.recorder.dictation(
      .cancel(session: 1, reason: .escape), generation: 1, at: anchor + s)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor, end: anchor + s)])
  }
}

private func failingMicrophones(_ count: Int) -> [FakeTrackSource] {
  (0..<count).map { _ in FakeTrackSource(start: .fail(.failed(step: "start", code: -1))) }
}

private func firstOf(
  _ a: @escaping @Sendable () async -> Void, _ b: @escaping @Sendable () async -> Void
)
  async
{
  await withTaskGroup(of: Void.self) { group in
    group.addTask { await a() }
    group.addTask { await b() }
    await group.next()
    group.cancelAll()
  }
}

private func pastFifteenMinutes(_ h: MeetingHarness) async {
  await h.tick(.seconds(600))
  h.clock.advance(by: .seconds(300))
  await firstOf({ await h.clock.untilSleeping() }, { await h.ended.wait() })
}

private func delivering(_ source: FakeTrackSource = FakeTrackSource()) -> FakeTrackSource {
  source.callbacks = 1
  return source
}

private func runSeconds(_ seconds: Int, _ h: MeetingHarness) async {
  for _ in 0..<seconds {
    await h.tick(.seconds(1))
    await h.settleReopen()
  }
}

private func details(of kind: String, in h: MeetingHarness) -> [String] {
  h.log.recent(100).reversed().filter { $0.kind == kind }.map(\.detail)
}

@Suite(.timeLimit(.minutes(1))) struct MeetingRecorderLivenessTests {
  @Test func aReopenThatNeverDeliversBacksOffUnderOneWarning() async {
    let mics = (0..<5).map { _ in FakeTrackSource() }
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await runSeconds(24, h)
    #expect(mics[1].stopCount == 0)
    await runSeconds(1, h)
    #expect(mics[1].stopCount == 1)
    await runSeconds(105, h)
    #expect(mics.map(\.stopCount) == [1, 1, 1, 1, 1])
    #expect(details(of: "meeting.micLost", in: h).count == 1)
    #expect(h.micsMadeAt == [0, 15, 35, 65, 115].map { anchor + $0 * s })
    #expect(details(of: "meeting.micReopened", in: h).isEmpty)
    #expect(
      details(of: "meeting.warning", in: h).filter { $0 == "reason=microphoneStopped" }.count == 1)
    let stopped = h.statuses.map { $0.warnings.contains(.microphoneStopped) }
    #expect(stopped.contains(true))
    #expect(stopped.drop { !$0 }.allSatisfy { $0 })
  }

  @Test func aReopenCountsOnceTheMicrophoneDelivers() async {
    let h = MeetingHarness(mics: [FakeTrackSource(), FakeTrackSource(), delivering(), delivering()])
    await h.recorder.start()
    await runSeconds(35, h)
    #expect(h.micsMadeAt == [0, 15, 35].map { anchor + $0 * s })
    #expect(details(of: "meeting.micReopened", in: h).isEmpty)
    await runSeconds(1, h)
    #expect(details(of: "meeting.micReopened", in: h) == ["count=2"])
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == false)
    #expect(h.deviceWatch == nil)
    await runSeconds(16, h)
    #expect(h.micsMadeAt == [0, 15, 35, 51].map { anchor + $0 * s })
    #expect(details(of: "meeting.micLost", in: h).count == 2)
    #expect(details(of: "meeting.micReopened", in: h) == ["count=2", "count=1"])
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == false)
  }

  @Test func aMicrophoneThatFailsAtRecordIsRetried() async {
    let h = MeetingHarness(mics: failingMicrophones(1) + [delivering()])
    await h.recorder.start()
    await runSeconds(5, h)
    #expect(h.micsMade == 2)
    await runSeconds(1, h)
    #expect(h.detail(of: "meeting.micReopened") == "count=1")
  }

  @Test func aMicrophoneThatEndsWhileOpeningIsLostAndReopened() async {
    let first = FakeTrackSource(start: .gated)
    let h = MeetingHarness(mics: [first, delivering()])
    let starting = Task { await h.recorder.start() }
    await first.startCalled.wait()
    await first.onEnded?()
    first.openStart()
    #expect(await value(of: starting) != nil)
    #expect(h.kinds().filter { $0 == "meeting.micLost" }.count == 1)
    #expect(first.stopCount == 1)
    await runSeconds(5, h)
    #expect(h.micsMade == 2)
    await runSeconds(1, h)
    #expect(h.detail(of: "meeting.micReopened") == "count=1")
  }

  @Test func aReopenedMicrophoneThatEndsWhileOpeningIsRetried() async {
    let slow = FakeTrackSource(start: .gated)
    let mics = [FakeTrackSource(), slow, delivering()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.tick(.seconds(5))
    await slow.startCalled.wait()
    await slow.onEnded?()
    slow.openStart()
    await h.settleReopen()
    #expect(h.detail(of: "meeting.micReopened") == nil)
    #expect(slow.stopCount == 1)
    await h.tick(.seconds(10))
    await h.settleReopen()
    #expect(h.micsMade == 3)
    await runSeconds(1, h)
    #expect(h.detail(of: "meeting.micReopened") == "count=2")
  }

  @Test func aMicrophoneThatNeverDeliversIsLostAndReopened() async {
    let mics = [FakeTrackSource(), delivering()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await h.tick(.seconds(9))
    #expect(!h.kinds().contains("meeting.micLost"))
    await h.tick(.seconds(1))
    #expect(h.kinds().filter { $0 == "meeting.micLost" }.count == 1)
    #expect(mics[0].stopCount == 1)
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == true)
    await h.tick(.seconds(1))
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == true)
    #expect(h.log.recent(100).filter { $0.detail == "reason=microphoneStopped" }.count == 1)
    await h.tick(.seconds(4))
    await h.settleReopen()
    #expect(h.micsMade == 2)
    await runSeconds(1, h)
    #expect(h.detail(of: "meeting.micReopened") == "count=1")
  }

  @Test func aDeviceListChangeReachesTheRecorder() async {
    let mics = [FakeTrackSource(), FakeTrackSource(start: .gated)]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    h.fireDeviceListChange()
    await mics[1].startCalled.wait()
    #expect(h.micsMade == 2)
    mics[1].openStart()
  }

  @Test func aReopenedMicrophoneThatEndsBeforeItIsConfirmedIsAFailedAttempt() async {
    let mics = [FakeTrackSource(), delivering()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await runSeconds(5, h)
    await mics[1].onEnded?()
    await runSeconds(1, h)
    #expect(details(of: "meeting.micReopened", in: h).isEmpty)
    #expect(mics[1].stopCount == 1)
    await runSeconds(10, h)
    #expect(h.micsMadeAt == [0, 5, 16].map { anchor + $0 * s })
    #expect(details(of: "meeting.micLost", in: h).count == 1)
  }

  @Test func aStaleEndFromAReplacedMicrophoneChangesNothing() async {
    let mics = [FakeTrackSource(), delivering()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.recorder.deviceListChanged()
    await runSeconds(1, h)
    #expect(details(of: "meeting.micReopened", in: h) == ["count=1"])
    await mics[0].onEnded?()
    #expect(h.kinds().filter { $0 == "meeting.micLost" }.count == 1)
    #expect(mics[1].stopCount == 0)
  }

  @Test func speechOnTheMicrophoneKeepsTheMeeting() async {
    let h = MeetingHarness(mics: [FakeTrackSource(drains: [voice(at: anchor)])])
    await h.recorder.start()
    await pastFifteenMinutes(h)
    #expect(h.ended.isOpen == false)
    #expect(!h.statuses.contains { $0.warnings.contains(.autoStopSoon) })
  }

  @Test func anyOtherAppSoundKeepsTheMeeting() async {
    let quiet = TrackDrain(runs: [MeetingRun(start: anchor, samples: [1])], freshRuns: 1)
    let h = MeetingHarness(system: FakeTrackSource(drains: [quiet]))
    await h.recorder.start()
    await pastFifteenMinutes(h)
    #expect(h.ended.isOpen == false)
    #expect(!h.statuses.contains { $0.warnings.contains(.autoStopSoon) })
  }

  @Test func speechOnAReopenedMicrophoneKeepsTheMeeting() async {
    let mics = [FakeTrackSource(), delivering(FakeTrackSource(drains: [voice(at: anchor)]))]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.recorder.deviceListChanged()
    await pastFifteenMinutes(h)
    #expect(h.ended.isOpen == false)
    #expect(!h.statuses.contains { $0.warnings.contains(.autoStopSoon) })
  }

  @Test func aLostMicrophoneIsReopenedOnADeviceChange() async {
    let mics = [FakeTrackSource(), delivering()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    #expect(h.kinds().contains("meeting.micLost"))
    await h.recorder.deviceListChanged()
    #expect(h.micsMade == 2)
    #expect(mics[1].startCount == 1)
    await runSeconds(1, h)
    #expect(h.detail(of: "meeting.micReopened") == "count=1")
  }

  @Test func aLostMicrophoneIsRetriedOnTheTimer() async {
    let mics = [FakeTrackSource(), FakeTrackSource()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.tick(.seconds(4))
    await h.settleReopen()
    #expect(h.micsMade == 1)
    await h.tick(.seconds(1))
    await h.settleReopen()
    #expect(h.micsMade == 2)
    #expect(mics[1].startCount == 1)
  }

  @Test func aFailedAttemptDoublesTheTimerAndADeviceChangeLeavesIt() async {
    let mics = [FakeTrackSource()] + failingMicrophones(5)
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.tick(.seconds(5))
    await h.settleReopen()
    #expect(h.micsMade == 2)
    await h.tick(.seconds(9))
    await h.settleReopen()
    #expect(h.micsMade == 2)
    await h.tick(.seconds(1))
    await h.settleReopen()
    #expect(h.micsMade == 3)
    await h.recorder.deviceListChanged()
    #expect(h.micsMade == 4)
    await h.tick(.seconds(19))
    await h.settleReopen()
    #expect(h.micsMade == 4)
    await h.tick(.seconds(1))
    await h.settleReopen()
    #expect(h.micsMade == 5)
  }

  @Test func aSlowReopenHoldsUpNeitherTheFlushNorTheSample() async {
    let slow = delivering(FakeTrackSource(start: .gated))
    let mics = [FakeTrackSource(drains: [TrackDrain(), voice(at: anchor)]), slow]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.tick(.seconds(5))
    await slow.startCalled.wait()
    await h.tick(.seconds(5))
    #expect(h.audioFiles() == ["mic-000000.sealed"])
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == true)
    #expect(await value(of: Task { await h.recorder.deviceListChanged() }) != nil)
    #expect(h.micsMade == 2)
    slow.openStart()
    await h.settleReopen()
    await runSeconds(1, h)
    #expect(h.detail(of: "meeting.micReopened") == "count=1")
    #expect(h.micsMade == 2)
  }

  @Test func aReopenThatRunsAfterTheEndMakesNoMicrophone() async {
    let mics = [FakeTrackSource(), FakeTrackSource()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.recorder.stop(.stopped)
    let late = Task { await h.recorder.reopenMicrophone(due: anchor + 5 * s, byTimer: true) }
    #expect(await value(of: late) != nil)
    #expect(h.micsMade == 1)
    #expect(mics[1].startCount == 0)
    #expect(mics[0].stopCount >= 1)
  }

  @Test func theDeviceListIsWatchedOnlyDuringALoss() async {
    let mics = [FakeTrackSource(), delivering()]
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    #expect(h.deviceWatches == 0)
    await mics[0].onEnded?()
    #expect(h.deviceWatches == 1)
    #expect(h.deviceWatch != nil)
    await h.recorder.deviceListChanged()
    #expect(h.micsMade == 2)
    #expect(h.deviceWatch != nil)
    await runSeconds(1, h)
    #expect(h.deviceWatch == nil)
  }

  @Test func anEndedMicrophoneIsStoppedAndFlushed() async throws {
    let marking = MarkingCipher()
    let mics = [FakeTrackSource(drains: [voice(at: anchor)]), FakeTrackSource()]
    let h = MeetingHarness(cipher: CipherSource(marking), mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    #expect(mics[0].stopCount == 1)
    await h.recorder.deviceListChanged()
    #expect(mics[1].startCount == 1)
    await h.tick(.seconds(3))
    await h.recorder.stop(.stopped)
    let meeting = try #require(h.meetingDirectories.first)
    let id = try #require(UUID(uuidString: meeting.lastPathComponent))
    let timeline = try await trackSamples(of: id, track: .mic, store: h.store, cipher: marking)
    #expect(Array(timeline.prefix(160)) == Array(repeating: 400, count: 160))
    #expect(h.micsMade == 2)
    for mic in mics {
      #expect(mic.stopCount >= 1)
      #expect(mic.finishedReturned)
    }
  }

  @Test func aMicrophoneStillLostAfterTenSecondsIsWarned() async {
    let mics = [FakeTrackSource()] + failingMicrophones(3)
    let h = MeetingHarness(mics: mics)
    await h.recorder.start()
    await mics[0].onEnded?()
    await h.tick(.seconds(9))
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == false)
    await h.tick(.seconds(1))
    #expect(h.statuses.last?.warnings.contains(.microphoneStopped) == true)
    await h.tick(.seconds(1))
    await h.settleReopen()
    let lines = h.log.recent(100).filter {
      $0.kind == "meeting.warning" && $0.detail == "reason=microphoneStopped"
    }
    #expect(lines.count == 1)
    #expect(h.micsMade == 2)
    #expect(mics[1].stopCount == 1)
  }

  @Test func anOnDemandMicrophoneIsNeverReopened() async {
    let h = MeetingHarness(mics: [FakeTrackSource(start: .fail(.notOpened))])
    await h.recorder.start()
    await h.tick(.seconds(120))
    await h.settleReopen()
    #expect(h.statuses.last?.warnings.contains(.microphoneNotOpened) == true)
    #expect(h.micsMade == 1)
    await h.recorder.deviceListChanged()
    #expect(h.micsMade == 1)
    #expect(h.deviceWatches == 0)
  }

  @Test func aPendingTapIsReportedAfterFifteenSeconds() async {
    let system = FakeTrackSource(start: .gated)
    let h = MeetingHarness(system: system)
    await h.recorder.start()
    await h.tick(.seconds(14))
    #expect(h.statuses.last?.warnings.contains(.waitingForPermission) == false)
    await h.tick(.seconds(1))
    #expect(h.statuses.last?.warnings.contains(.waitingForPermission) == true)
    system.openStart()
  }

  @Test func aSlowFirstMicrophoneOpenHoldsUpNeitherTheFlushNorTheTapWarning() async {
    let mic = FakeTrackSource(
      start: .gated, drains: [TrackDrain(), TrackDrain(), voice(at: anchor)])
    let system = FakeTrackSource(start: .gated, drains: voices(1))
    let h = MeetingHarness(mics: [mic], system: system)
    let starting = Task { await h.recorder.start() }
    await mic.startCalled.wait()
    await h.tick(.seconds(3))
    #expect(h.audioFiles() == ["system-000000.sealed"])
    await h.tick(.seconds(12))
    #expect(h.statuses.last?.warnings == [.waitingForPermission])
    mic.openStart()
    #expect(await value(of: starting) != nil)
    await h.tick(.seconds(3))
    #expect(h.audioFiles() == ["mic-000000.sealed", "system-000000.sealed"])
    #expect(h.statuses.last?.warnings == [.waitingForPermission])
    #expect(h.micsMade == 1)
    #expect(mic.stopCount == 0)
    system.openStart()
  }

  @Test func aWriteFailureShowsCannotSave() async {
    let marking = MarkingCipher()
    let h = MeetingHarness(
      cipher: CipherSource(marking), mics: [FakeTrackSource(drains: voices(2))],
      system: FakeTrackSource(drains: voices(2)))
    await h.recorder.start()
    marking.failNext(2)
    await h.tick(.seconds(3))
    #expect(h.statuses.last?.warnings.contains(.cannotSave) == true)
    #expect(!h.audioFiles().contains { $0.hasSuffix("-000000.sealed") })
    await h.tick(.seconds(3))
    #expect(h.statuses.last?.warnings.contains(.cannotSave) == false)
    #expect(h.audioFiles() == ["mic-000001.sealed", "system-000001.sealed"])
  }

  @Test func audioThatCouldNotBeSavedIsCountedAsDropped() async {
    let marking = MarkingCipher()
    let second = TrackDrain(
      runs: [MeetingRun(start: anchor, samples: Array(repeating: 400, count: 16_000))],
      freshRuns: 1)
    let h = MeetingHarness(
      cipher: CipherSource(marking), mics: [FakeTrackSource(drains: [second])],
      system: FakeTrackSource(drains: [second]))
    await h.recorder.start()
    marking.failNext(2)
    await h.tick(.seconds(3))
    await h.recorder.stop(.stopped)
    #expect(
      h.detail(of: "meeting.stop")
        == "reason=stopped micSeconds=0 micSoundSeconds=0 systemSeconds=0 systemSoundSeconds=0"
        + " runs=0 droppedSeconds=2")
  }

  @Test func aContendedWriteIsAGapNotAWarning() async {
    let contended = TrackDrain(runs: voice(at: anchor).runs, freshRuns: 1, contendedNanos: s)
    let h = MeetingHarness(mics: [FakeTrackSource(drains: [contended])])
    await h.recorder.start()
    await h.tick(.seconds(3))
    #expect(!h.kinds().contains("meeting.writeFailed"))
    #expect(h.statuses.last?.warnings.contains(.cannotSave) == false)
    await h.recorder.stop(.stopped)
    #expect(h.detail(of: "meeting.stop")?.contains("droppedSeconds=1") == true)
  }

  @Test func fifteenSilentMinutesStopTheMeeting() async {
    let h = MeetingHarness()
    await h.recorder.start()
    await h.tick(.seconds(840))
    #expect(h.statuses.last?.warnings.contains(.autoStopSoon) == true)
    #expect(h.ended.isOpen == false)
    h.clock.advance(by: .seconds(60))
    await h.ended.wait()
    #expect(await h.header()?.endedBy == .autoStopped)
    #expect(h.statuses.last?.notice == .autoStopped)
  }

  @Test func systemZerosAreLoggedOncePerEpisode() async {
    let h = MeetingHarness(system: FakeTrackSource(drains: voices(1)))
    await h.recorder.start()
    await h.settleSystemStart()
    await h.tick(.seconds(3))
    await h.tick(.seconds(60))
    await h.tick(.seconds(10))
    #expect(h.kinds().filter { $0 == "meeting.systemZeros" }.count == 1)
  }

  @Test func anUnchangedStatusIsNotPublishedAgain() async {
    let system = FakeTrackSource(start: .gated)
    let h = MeetingHarness(mics: [FakeTrackSource(start: .fail(.notOpened))], system: system)
    await h.recorder.start()
    await h.tick(.seconds(1))
    #expect(h.statuses.count == 2)
    #expect(h.statuses.last?.warnings == [.microphoneNotOpened])
    for _ in 0..<10 { await h.tick(.seconds(1)) }
    #expect(h.statuses.count == 2)
    system.openStart()
  }
}
