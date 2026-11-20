import Foundation

public enum MeetingTimeline {
  public static func offset(of host: UInt64, anchor: UInt64) -> Int {
    let elapsed = HostTime.elapsed(from: anchor, to: host)
    return Int(
      HostTime.adding(elapsed, MeetingRun.nanosPerSample / 2) / MeetingRun.nanosPerSample)
  }
}

public struct MeetingTally: Equatable, Sendable {
  private struct Side: Equatable, Sendable {
    var written = 0
    var lastSoundSecond: UInt64?
    var soundSeconds = 0
  }

  private let anchor: UInt64
  private var mic = Side()
  private var system = Side()
  private var runs = 0
  private var droppedNanos: UInt64 = 0

  public init(anchor: UInt64) {
    self.anchor = anchor
  }

  public mutating func add(_ drain: TrackDrain, track: MeetingTrack, written: Bool) {
    droppedNanos = HostTime.adding(
      HostTime.adding(droppedNanos, drain.droppedNanos), drain.contendedNanos)
    if !written {
      let count = drain.runs.reduce(0) { $0 + $1.samples.count }
      droppedNanos = HostTime.adding(droppedNanos, UInt64(count) * MeetingRun.nanosPerSample)
      return
    }
    runs += drain.freshRuns
    var side = track == .mic ? mic : system
    let floor = Int(track.soundFloor)
    for run in drain.runs {
      side.written += run.samples.count
      for (i, sample) in run.samples.enumerated() where abs(Int(sample)) >= floor {
        let at = HostTime.adding(run.start, UInt64(i) * MeetingRun.nanosPerSample)
        let second = HostTime.elapsed(from: anchor, to: at) / 1_000_000_000
        if second != side.lastSoundSecond {
          side.lastSoundSecond = second
          side.soundSeconds += 1
        }
      }
    }
    if track == .mic { mic = side } else { system = side }
  }

  public var detail: String {
    [
      "micSeconds=\(mic.written / 16_000)",
      "micSoundSeconds=\(mic.soundSeconds)",
      "systemSeconds=\(system.written / 16_000)",
      "systemSoundSeconds=\(system.soundSeconds)",
      "runs=\(runs)",
      "droppedSeconds=\(droppedNanos / 1_000_000_000)",
    ].joined(separator: " ")
  }
}
