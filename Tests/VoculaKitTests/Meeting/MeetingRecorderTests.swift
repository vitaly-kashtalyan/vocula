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
    await h.recorder.start()
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
    await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor)
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

  @Test func aSpanIsClippedToTheMeeting() async {
    let h = MeetingHarness()
    await h.recorder.start()
    await h.recorder.dictation(.start(session: 1), generation: 1, at: anchor - s)
    await h.recorder.dictation(
      .cancel(session: 1, reason: .escape), generation: 1, at: anchor + s)
    #expect(await h.header()?.dictations == [DictationSpan(start: anchor, end: anchor + s)])
  }
}
