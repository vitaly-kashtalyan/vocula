import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingTrackWindowsTests {
  let s: UInt64 = 1_000_000_000
  let anchor: UInt64 = 1_000_000_000

  private func chunk(_ runs: [MeetingRun], sequence: UInt32 = 0) -> MeetingChunk {
    MeetingChunk(track: .mic, sequence: sequence, runs: runs)
  }

  private func drain(_ windows: inout MeetingTrackWindows, final: Bool) -> [MeetingWindow] {
    var out: [MeetingWindow] = []
    while let window = windows.next(final: final) { out.append(window) }
    return out
  }

  @Test func runsArePlacedByHostTimeWithGapsAsSilence() throws {
    var windows = MeetingTrackWindows(anchor: anchor, end: anchor + 10 * s)
    try windows.add(chunk([MeetingRun(start: anchor + s / 2, samples: [1, 2, 3])]))
    #expect(drain(&windows, final: false).isEmpty)
    let out = drain(&windows, final: true)
    #expect(out.count == 1)
    #expect(out[0].start == 0)
    #expect(out[0].samples == Array(repeating: 0, count: 8_000) + [1, 2, 3])
  }

  @Test func overlappingSamplesAreDropped() throws {
    var windows = MeetingTrackWindows(anchor: anchor, end: anchor + 10 * s)
    try windows.add(chunk([MeetingRun(start: anchor, samples: [1, 2, 3, 4])]))
    try windows.add(
      chunk(
        [MeetingRun(start: anchor + 2 * MeetingRun.nanosPerSample, samples: [9, 9, 9])],
        sequence: 1))
    #expect(drain(&windows, final: true).first?.samples == [1, 2, 3, 4, 9])
  }

  @Test func windowsAreSixtySecondsAndContiguous() throws {
    var windows = MeetingTrackWindows(anchor: anchor, end: anchor + 130 * s)
    var out: [MeetingWindow] = []
    for second in stride(from: 0, to: 130, by: 10) {
      try windows.add(
        chunk(
          [
            MeetingRun(
              start: anchor + UInt64(second) * s, samples: Array(repeating: 5, count: 160_000))
          ], sequence: UInt32(second)))
      out += drain(&windows, final: false)
    }
    out += drain(&windows, final: true)
    #expect(out.map(\.start) == [0, 960_000, 1_920_000])
    #expect(out.map(\.samples.count) == [960_000, 960_000, 160_000])
  }

  @Test func aRunPastTheEndFails() {
    var windows = MeetingTrackWindows(anchor: anchor, end: anchor + 10 * s)
    #expect(throws: MeetingTrackWindows.Failure.pastEnd) {
      try windows.add(chunk([MeetingRun(start: anchor + 11 * s + s / 100, samples: [1])]))
    }
  }

  @Test func aRunWithinASecondOfTheEndIsKept() throws {
    var windows = MeetingTrackWindows(anchor: anchor, end: anchor + 10 * s)
    try windows.add(chunk([MeetingRun(start: anchor + 10 * s + 9 * s / 10, samples: [1])]))
    #expect(drain(&windows, final: true).last?.samples.last == 1)
  }

  @Test func noCeilingAtADay() throws {
    let at = 25 * 3600 * s
    var windows = MeetingTrackWindows(anchor: anchor, end: anchor + at + s / 2)
    try windows.add(
      chunk([MeetingRun(start: anchor + at, samples: Array(repeating: 4, count: 10))]))
    #expect(windows.placed == 25 * 3600 * 16_000 + 10)
    #expect(windows.next(final: false)?.samples.count == 960_000)
  }
}
