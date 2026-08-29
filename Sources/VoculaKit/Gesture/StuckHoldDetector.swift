import Foundation

public enum StuckHoldVerdict: Equatable, Sendable {
  case fine
  case releaseWasLost
}

public struct StuckHoldDetector: Sendable {
  private var alreadyReported = false

  public init() {}

  public mutating func poll(modifierIsDown: Bool) -> StuckHoldVerdict {
    guard !alreadyReported else { return .fine }
    guard !modifierIsDown else { return .fine }
    alreadyReported = true
    return .releaseWasLost
  }

  public mutating func reset() { alreadyReported = false }
}
