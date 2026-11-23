import Foundation
import Testing

@testable import VoculaKit

@Suite(.timeLimit(.minutes(1))) struct MeetingDiarizationTests {
  private func wholeCall(_ speaker: String = "S0") -> [SpeakerTurn] {
    [SpeakerTurn(speaker: speaker, start: 0, end: 60)]
  }

  private func lines(_ rig: TranscriberRig, _ header: MeetingHeader) async -> [MeetingUtterance] {
    await rig.transcript(of: header)?.utterances ?? []
  }

  private func untilIdle(_ state: MeetingDiarizerState) async {
    while await state.isBusy { await Task.yield() }
  }

  @Test func aSplitMeetingLabelsItsCallLines() async throws {
    let rig = TranscriberRig()
    rig.diarizer.turns = wholeCall()
    let header = try rig.meeting(
      mic: [rig.speech(at: 0.5, for: 0.5)], system: [rig.speech(at: 2, for: 0.5)])
    await rig.run()
    let split = await lines(rig, header)
    #expect(split.map(\.speaker) == [.me, .numbered(1)])
    #expect(rig.calls.all == ["isInstalled", "model", "makeRecognizer", "load"])

    let plain = TranscriberRig()
    let same = try plain.meeting(
      mic: [plain.speech(at: 0.5, for: 0.5)], system: [plain.speech(at: 2, for: 0.5)])
    await plain.run()
    let unsplit = await lines(plain, same)
    #expect(unsplit.map(\.speaker) == [.me, .others])
    #expect(split.filter { $0.speaker == .me } == unsplit.filter { $0.speaker == .me })
  }

  @Test func theDiarizerGetsTheRawTrack() async throws {
    let rig = TranscriberRig()
    try rig.meeting(
      lasting: 3,
      system: [rig.speech(at: 0.5, for: 0.5, value: 900), rig.speech(at: 2, for: 1, value: -700)])
    await rig.run()
    let track = try #require(rig.diarizer.samples.first)
    #expect(rig.diarizer.calls == 1)
    #expect(track.count == 48_000)
    #expect(track[0..<8_000].allSatisfy { $0 == 0 })
    #expect(track[8_000..<16_000].allSatisfy { $0 == 900 })
    #expect(track[16_000..<32_000].allSatisfy { $0 == 0 })
    #expect(track[32_000..<48_000].allSatisfy { $0 == -700 })
  }

  @Test func noSystemWordsMeansNoDiarization() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, header).map(\.speaker) == [.me])
    #expect(rig.diarizer.calls == 0)
    #expect(rig.calls.count("load") == 0)
  }

  @Test func noTurnsLeavesOthersAndLogsNothing() async throws {
    let rig = TranscriberRig()
    let header = try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.diarizer.calls == 1)
    #expect(await lines(rig, header).map(\.speaker) == [.others])
    #expect(rig.lines("meeting.diarizeFailed").isEmpty)
    #expect(!rig.hasAudio(header))
  }

  @Test func twoMeetingsInOnePassAreBothSplit() async throws {
    let rig = TranscriberRig()
    rig.diarizer.turns = wholeCall()
    let first = try rig.meeting(startedAt: 800_000_000, system: [rig.speech(at: 0.5, for: 1)])
    let second = try rig.meeting(startedAt: 800_000_050, system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, first).map(\.speaker) == [.numbered(1)])
    #expect(await lines(rig, second).map(\.speaker) == [.numbered(1)])
    #expect(rig.diarizer.calls == 2)
    #expect(rig.calls.count("load") == 1)
    #expect(await rig.state.isBusy == false)
  }

  @Test func aCancelledDiarizationWritesNothingAndTheNextPassSplits() async throws {
    let rig = TranscriberRig()
    rig.diarizer.turns = wholeCall()
    rig.diarizer.stall = rig.clock
    let header = try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.diarizer.called.wait()
    await rig.clock.untilSleeping(1)
    pass.cancel()
    await pass.value
    #expect(await rig.transcript(of: header) == nil)
    #expect(rig.hasAudio(header))
    #expect(rig.calls.count("discard") == 0)
    #expect(rig.diarizer.sawCancellation)
    #expect(rig.lines("meeting.diarizeFailed").isEmpty)

    rig.diarizer.stall = nil
    await rig.run()
    #expect(await lines(rig, header).map(\.speaker) == [.numbered(1)])
  }

  private func ended(_ secondsBeforeNow: Double, _ rig: TranscriberRig, lasting: Double = 3)
    -> TimeInterval
  {
    rig.wallNow.timeIntervalSinceReferenceDate - secondsBeforeNow - lasting
  }

  @Test func aMissingDiarizerKeepsAFreshMeetingPending() async throws {
    let rig = TranscriberRig()
    rig.diarizerInstalled = false
    let header = try rig.meeting(
      startedAt: ended(100, rig), system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await rig.transcript(of: header) == nil)
    #expect(rig.hasAudio(header))
    #expect(rig.lines("meeting.transcribeFailed") == ["step=diarizer code=0"])
    #expect(rig.calls.all == ["isInstalled"])
    #expect(rig.published.all == [.finished(transcribed: 0, failed: 1)])
  }

  @Test func aMeetingThatWaitedADayIsTranscribedWithoutSpeakers() async throws {
    let rig = TranscriberRig()
    rig.diarizerInstalled = false
    let waited = try rig.meeting(
      startedAt: ended(86_400, rig), system: [rig.speech(at: 0.5, for: 1)])
    let fresh = try rig.meeting(
      startedAt: ended(100, rig), system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, waited).map(\.speaker) == [.others])
    #expect(!rig.hasAudio(waited))
    #expect(await rig.transcript(of: fresh) == nil)
    #expect(rig.hasAudio(fresh))
    #expect(rig.lines("meeting.diarizeFailed") == ["step=waited code=0"])
    #expect(rig.lines("meeting.transcribeFailed") == ["step=diarizer code=0"])
    #expect(rig.published.all.last == .finished(transcribed: 1, failed: 1))
    #expect(Array(rig.calls.all.prefix(3)) == ["isInstalled", "model", "makeRecognizer"])
    #expect(rig.calls.count("load") == 0)
    #expect(rig.diarizer.calls == 0)
  }

  @Test func aMicOnlyMeetingThatWaitedLogsNoSplitFailure() async throws {
    let rig = TranscriberRig()
    rig.diarizerInstalled = false
    let header = try rig.meeting(
      startedAt: ended(90_000, rig), mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, header).map(\.speaker) == [.me])
    #expect(rig.lines("meeting.diarizeFailed").isEmpty)
    #expect(rig.lines("meeting.transcribeFailed").isEmpty)
  }

  @Test func aRecognizerThatWillNotLoadNeverLoadsTheDiarizer() async throws {
    let rig = TranscriberRig()
    rig.recognizerLoadError = MeetingFailure.failed(step: "load", code: 3)
    try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.calls.count("load") == 0)
    #expect(rig.lines("meeting.transcribeFailed") == ["step=model code=3"])
  }

  @Test func aDiarizerThatWillNotLoadGivesOthersAndDiscardsOnce() async throws {
    let rig = TranscriberRig()
    rig.diarizerLoadError = MeetingDiarizerError.model(code: -3)
    let first = try rig.meeting(startedAt: 800_000_000, system: [rig.speech(at: 0.5, for: 1)])
    let second = try rig.meeting(startedAt: 800_000_050, system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, first).map(\.speaker) == [.others])
    #expect(await lines(rig, second).map(\.speaker) == [.others])
    #expect(!rig.hasAudio(first))
    #expect(!rig.hasAudio(second))
    #expect(rig.lines("meeting.diarizeFailed") == ["step=load code=-3"])
    #expect(rig.calls.count("load") == 1)
    #expect(rig.calls.count("discard") == 1)
    #expect(rig.diarizer.calls == 0)
    #expect(rig.published.all.last == .finished(transcribed: 2, failed: 0))

    try rig.meeting(startedAt: 800_000_090, system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(rig.lines("meeting.diarizeFailed") == ["step=load code=-3", "step=load code=-3"])
    #expect(rig.calls.count("discard") == 1)
  }

  @Test func aLoadFailureThatIsNotTheModelsKeepsCodeZero() async throws {
    let rig = TranscriberRig()
    rig.diarizerLoadError = MeetingFailure.failed(step: "x", code: 9)
    let header = try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, header).map(\.speaker) == [.others])
    #expect(rig.lines("meeting.diarizeFailed") == ["step=load code=0"])
    #expect(rig.calls.count("discard") == 1)
  }

  @Test func aQuitDuringTheLoadNeverDiscards() async throws {
    let rig = TranscriberRig()
    rig.diarizerLoadStall = rig.clock
    let header = try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.loading.wait()
    await rig.clock.untilSleeping(1)
    pass.cancel()
    await pass.value
    #expect(await rig.transcript(of: header) == nil)
    #expect(rig.hasAudio(header))
    #expect(rig.calls.count("discard") == 0)
    #expect(rig.lines("meeting.diarizeFailed").isEmpty)
  }

  @Test func aPassCancelledDuringALoadStartsNoSplit() async throws {
    let rig = TranscriberRig()
    let gate = Gate()
    rig.diarizerLoadGate = gate
    let header = try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.loading.wait()
    pass.cancel()
    gate.open()
    await pass.value
    #expect(rig.diarizer.calls == 0)
    #expect(await rig.transcript(of: header) == nil)
    #expect(rig.lines("meeting.diarizeFailed").isEmpty)
  }

  @Test func aFailedSplitGivesOthers() async throws {
    let rig = TranscriberRig()
    rig.diarizer.error = MeetingDiarizerError.failed(code: 4)
    let header = try rig.meeting(system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, header).map(\.speaker) == [.others])
    #expect(!rig.hasAudio(header))
    #expect(rig.lines("meeting.diarizeFailed") == ["step=diarize code=4"])
    #expect(rig.calls.count("discard") == 0)

    rig.diarizer.error = MeetingDiarizerError.model(code: -1)
    let next = try rig.meeting(startedAt: 800_000_050, system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, next).map(\.speaker) == [.others])
    #expect(rig.lines("meeting.diarizeFailed") == ["step=diarize code=4", "step=diarize code=-1"])
    #expect(rig.calls.count("discard") == 1)
  }

  @Test func theBoundsAreTheMeasuredOnes() {
    #expect(MeetingDiarizationRules.maxDiarizedSeconds == 7_200)
    #expect(MeetingDiarizationRules.diarizeDeadlineFactor == 0.2)
  }

  @Test func theDeadlineGrowsWithTheTrack() {
    #expect(MeetingDiarizationRules.deadlineFloor == .seconds(60))
    #expect(MeetingDiarizationRules.deadline(forTrackSeconds: 10) == .seconds(60))
    let long = 600 * MeetingDiarizationRules.diarizeDeadlineFactor
    #expect(long > 60)
    #expect(MeetingDiarizationRules.deadline(forTrackSeconds: 600) == .seconds(long))
  }

  @Test func aStalledSplitStopsAtItsDeadlineWithoutJoining() async throws {
    let rig = TranscriberRig()
    let gate = Gate()
    rig.diarizer.gate = gate
    rig.diarizer.turns = wholeCall()
    let stalled = try rig.meeting(startedAt: 800_000_050, system: [rig.speech(at: 0.5, for: 1)])
    let next = try rig.meeting(startedAt: 800_000_000, system: [rig.speech(at: 0.5, for: 1)])
    let pass = Task { await rig.run() }
    await rig.diarizer.called.wait()
    await rig.clock.untilSleeping(1)
    rig.clock.advance(by: MeetingDiarizationRules.deadline(forTrackSeconds: 3) + .seconds(1))
    await pass.value
    #expect(await lines(rig, stalled).map(\.speaker) == [.others])
    #expect(await lines(rig, next).map(\.speaker) == [.others])
    #expect(rig.lines("meeting.diarizeFailed") == ["step=deadline code=0", "step=busy code=0"])
    #expect(rig.diarizer.calls == 1)
    #expect(await rig.state.isBusy)
    #expect(rig.recognizers.released == 1)

    gate.open()
    await untilIdle(rig.state)
    let later = try rig.meeting(startedAt: 800_000_090, system: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, later).map(\.speaker) == [.numbered(1)])
  }

  @Test func busyAtThePassStartLoadsLazily() async throws {
    let rig = TranscriberRig()
    let gate = Gate()
    rig.diarizer.gate = gate
    rig.diarizer.turns = wholeCall()
    try rig.meeting(startedAt: 799_999_000, system: [rig.speech(at: 0.5, for: 1)])
    let earlier = Task { await rig.run() }
    await rig.diarizer.called.wait()
    await rig.clock.untilSleeping(1)
    rig.clock.advance(by: MeetingDiarizationRules.deadline(forTrackSeconds: 3) + .seconds(1))
    await earlier.value
    #expect(await rig.state.isBusy)

    let busy = try rig.meeting(startedAt: 800_000_050, system: [rig.speech(at: 0.5, for: 1)])
    let freed = try rig.meeting(
      startedAt: 800_000_000, mic: [rig.speech(at: 0.2, for: 0.2)],
      system: [rig.speech(at: 1.5, for: 1)])
    let state = rig.state
    rig.recognizers.onCall = { call in
      guard call == 3 else { return }
      gate.open()
      await untilIdle(state)
    }
    let loadsBefore = rig.calls.count("load")
    await rig.run()
    #expect(await lines(rig, busy).map(\.speaker) == [.others])
    #expect(await lines(rig, freed).map(\.speaker) == [.me, .numbered(1)])
    #expect(rig.lines("meeting.diarizeFailed") == ["step=deadline code=0", "step=busy code=0"])
    #expect(rig.calls.count("load") == loadsBefore + 1)
  }

  @Test func aLongMeetingIsNotSplit() async throws {
    let rig = TranscriberRig()
    rig.maxTrackSeconds = 2
    let long = try rig.meeting(lasting: 3, system: [rig.speech(at: 0.5, for: 1)])
    let mine = try rig.meeting(
      startedAt: 800_000_050, lasting: 3, mic: [rig.speech(at: 0.5, for: 1)])
    await rig.run()
    #expect(await lines(rig, long).map(\.speaker) == [.others])
    #expect(await lines(rig, mine).map(\.speaker) == [.me])
    #expect(rig.diarizer.calls == 0)
    #expect(rig.lines("meeting.diarizeFailed") == ["step=length code=0"])
  }
}
