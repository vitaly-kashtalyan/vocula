import Testing

@testable import VoculaKit

@Suite struct MeetingTimelineTests {
  let s: UInt64 = 1_000_000_000
  let tick: UInt64 = 62_500

  @Test func offsetsRoundToTheNearestSample() {
    #expect(MeetingTimeline.offset(of: 31_249, anchor: 0) == 0)
    #expect(MeetingTimeline.offset(of: 31_250, anchor: 0) == 1)
  }

  @Test func aRunBeforeTheAnchorLandsAtZero() {
    #expect(MeetingTimeline.offset(of: 5, anchor: 10) == 0)
  }

  @Test func theStopNumbersArePinned() {
    var tally = MeetingTally(anchor: 0)
    tally.add(
      TrackDrain(
        runs: [MeetingRun(start: 0, samples: [Int16](repeating: 400, count: 32_000))],
        freshRuns: 1, contendedNanos: s),
      track: .mic, written: true)
    var tone = [Int16](repeating: 0, count: 16_000)
    tone[4_000] = 1
    tally.add(
      TrackDrain(
        runs: [
          MeetingRun(start: 0, samples: [Int16](repeating: 0, count: 16_000)),
          MeetingRun(start: s, samples: tone),
        ], freshRuns: 1),
      track: .system, written: true)
    tally.add(
      TrackDrain(
        runs: [MeetingRun(start: 2 * s, samples: [Int16](repeating: 9, count: 8_000))],
        freshRuns: 1, droppedNanos: 1_500_000_000),
      track: .system, written: false)
    #expect(
      tally.detail
        == "micSeconds=2 micSoundSeconds=2 systemSeconds=2 systemSoundSeconds=1 runs=2 droppedSeconds=3"
    )
  }

  @Test func aQuietMicrophoneSecondIsNotSound() {
    var tally = MeetingTally(anchor: 0)
    tally.add(
      TrackDrain(
        runs: [MeetingRun(start: 0, samples: [Int16](repeating: 327, count: 16_000))],
        freshRuns: 1),
      track: .mic, written: true)
    #expect(tally.detail.contains("micSoundSeconds=0"))
  }
}
