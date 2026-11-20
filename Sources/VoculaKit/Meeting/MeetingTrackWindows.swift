import Foundation

public struct MeetingWindow: Equatable, Sendable {
  public let start: Int
  public let samples: [Int16]

  public init(start: Int, samples: [Int16]) {
    self.start = start
    self.samples = samples
  }
}

public struct MeetingTrackWindows: Sendable {
  public enum Failure: Error, Equatable { case pastEnd }

  public static let windowSamples = 960_000
  static let endSlack = 16_000

  private enum Part: Sendable {
    case silence(Int)
    case samples(ArraySlice<Int16>)

    var count: Int {
      switch self {
      case .silence(let n): n
      case .samples(let s): s.count
      }
    }
  }

  private let anchor: UInt64
  private let lastStart: Int
  private var parts: [Part] = []
  private var emitted = 0
  private var buffered = 0

  public init(anchor: UInt64, end: UInt64) {
    self.anchor = anchor
    lastStart = MeetingTimeline.offset(of: end, anchor: anchor) + Self.endSlack
  }

  var placed: Int { emitted + buffered }

  public mutating func add(_ chunk: MeetingChunk) throws {
    for run in chunk.runs {
      let at = MeetingTimeline.offset(of: run.start, anchor: anchor)
      guard at <= lastStart else { throw Failure.pastEnd }
      let placed = placed
      if at > placed { append(.silence(at - placed)) }
      let skip = max(0, placed - at)
      if skip < run.samples.count { append(.samples(run.samples.dropFirst(skip))) }
    }
  }

  public mutating func next(final: Bool) -> MeetingWindow? {
    guard buffered >= Self.windowSamples || (final && buffered > 0) else { return nil }
    var wanted = min(Self.windowSamples, buffered)
    var samples: [Int16] = []
    samples.reserveCapacity(wanted)
    while wanted > 0 {
      let part = parts.removeFirst()
      let taken = min(wanted, part.count)
      switch part {
      case .silence(let n):
        samples.append(contentsOf: repeatElement(0, count: taken))
        if taken < n { parts.insert(.silence(n - taken), at: 0) }
      case .samples(let slice):
        samples.append(contentsOf: slice.prefix(taken))
        if taken < slice.count { parts.insert(.samples(slice.dropFirst(taken)), at: 0) }
      }
      wanted -= taken
    }
    let window = MeetingWindow(start: emitted, samples: samples)
    emitted += samples.count
    buffered -= samples.count
    return window
  }

  private mutating func append(_ part: Part) {
    parts.append(part)
    buffered += part.count
  }
}
