import Foundation

public struct DictationSpans: Sendable {
  public static let cap: UInt64 = HostTime.nanos(
    Double(Timings.default.maxRecording.components.seconds))

  private struct Open: Equatable {
    let generation: Int
    let session: Int
    let start: UInt64
  }

  private var open: [Open] = []

  public init() {}

  public mutating func received(
    _ signal: DictationSignal, generation: Int, at: UInt64
  ) -> [DictationSpan] {
    switch signal {
    case .start(let session):
      let closed = close({ _ in true }, at: at)
      open.append(Open(generation: generation, session: session, start: at))
      return closed
    case .stop(let session, _), .cancel(let session, _):
      return close({ $0.generation == generation && $0.session == session }, at: at)
    }
  }

  public mutating func generationEnded(_ generation: Int, at: UInt64) -> [DictationSpan] {
    close({ $0.generation == generation }, at: at)
  }

  public mutating func meetingEnded(at: UInt64) -> [DictationSpan] {
    close({ _ in true }, at: at)
  }

  private mutating func close(_ matches: (Open) -> Bool, at: UInt64) -> [DictationSpan] {
    let closing = open.filter(matches)
    open.removeAll(where: matches)
    return closing.map {
      DictationSpan(start: $0.start, end: min(at, HostTime.adding($0.start, Self.cap)))
    }
  }
}
