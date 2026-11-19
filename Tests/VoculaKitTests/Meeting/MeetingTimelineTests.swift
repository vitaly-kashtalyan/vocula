import Testing

@testable import VoculaKit

@Suite struct MeetingTimelineTests {
  let s: UInt64 = 1_000_000_000
  let tick: UInt64 = 62_500

  private func chunk(_ sequence: UInt32, _ runs: [MeetingRun]) -> MeetingChunk {
    MeetingChunk(track: .mic, sequence: sequence, runs: runs)
  }

  @Test func runsLandAtTheirOffset() {
    let run = MeetingRun(start: s + 4 * tick, samples: [5, 6])
    #expect(
      MeetingTimeline.samples([chunk(0, [run])], anchor: s, limit: 100) == [0, 0, 0, 0, 5, 6])
  }

  @Test func aGapIsZeroFilled() {
    let chunks = [
      chunk(0, [MeetingRun(start: s, samples: [1, 1])]),
      chunk(1, [MeetingRun(start: s + 5 * tick, samples: [2])]),
    ]
    #expect(MeetingTimeline.samples(chunks, anchor: s, limit: 100) == [1, 1, 0, 0, 0, 2])
  }

  @Test func anOverlappingPrefixIsDropped() {
    let chunks = [
      chunk(0, [MeetingRun(start: s, samples: [1, 1, 1])]),
      chunk(1, [MeetingRun(start: s + 2 * tick, samples: [2, 2])]),
    ]
    #expect(MeetingTimeline.samples(chunks, anchor: s, limit: 100) == [1, 1, 1, 2])
  }

  @Test func offsetsRoundToTheNearestSample() {
    #expect(MeetingTimeline.offset(of: 31_249, anchor: 0) == 0)
    #expect(MeetingTimeline.offset(of: 31_250, anchor: 0) == 1)
  }

  @Test func aRunBeforeTheAnchorLandsAtZero() {
    #expect(MeetingTimeline.offset(of: 5, anchor: 10) == 0)
  }

  @Test func aMissingChunkIsAGap() {
    let chunks = [
      chunk(2, [MeetingRun(start: 4 * tick, samples: [3])]),
      chunk(0, [MeetingRun(start: 0, samples: [1])]),
    ]
    #expect(MeetingTimeline.samples(chunks, anchor: 0, limit: 100) == [1, 0, 0, 0, 3])
  }

  @Test func aRunStartingBeyondTheLimitIsSkipped() {
    let chunks = [
      chunk(0, [MeetingRun(start: 0, samples: [1, 1])]),
      chunk(1, [MeetingRun(start: .max, samples: [9])]),
    ]
    #expect(MeetingTimeline.samples(chunks, anchor: 0, limit: 10) == [1, 1])
  }

  @Test func aRunCrossingTheLimitIsCut() {
    let run = MeetingRun(start: 2 * tick, samples: [1, 2, 3, 4])
    #expect(MeetingTimeline.samples([chunk(0, [run])], anchor: 0, limit: 4) == [0, 0, 1, 2])
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
