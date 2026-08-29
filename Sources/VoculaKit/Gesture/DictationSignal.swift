import Foundation

public enum StopReason: String, Sendable, Equatable {
  case releasedHold
  case durationLimit
}

public enum CancelReason: String, Sendable, Equatable {
  case tooShort
  case collision
  case escape
}

public enum DictationSignal: Sendable, Equatable {
  case start(session: Int)
  case stop(session: Int, reason: StopReason)
  case cancel(session: Int, reason: CancelReason)
}

public struct GestureOutput: Sendable, Equatable {
  public var signals: [DictationSignal]
  public var nextDeadline: Timestamp?

  public init(signals: [DictationSignal] = [], nextDeadline: Timestamp? = nil) {
    self.signals = signals
    self.nextDeadline = nextDeadline
  }
}
