import Foundation

public enum InputLivenessVerdict: Equatable, Sendable {
  case alive
  case dead
}

public struct InputLivenessWatchdog: Equatable, Sendable {
  public static let checkInterval = Duration.milliseconds(250)

  private var lastCount = 0
  private var everDelivered = false
  private var quietChecks = 0
  private let tolerance: Int

  public init(tolerance: Int = 2) {
    self.tolerance = tolerance
  }

  public mutating func check(buffersDelivered: Int) -> InputLivenessVerdict {
    defer { lastCount = buffersDelivered }
    guard everDelivered || buffersDelivered > 0 else { return .alive }
    everDelivered = true

    guard buffersDelivered == lastCount else {
      quietChecks = 0
      return .alive
    }
    quietChecks += 1
    guard quietChecks >= tolerance else { return .alive }
    quietChecks = 0
    return .dead
  }
}
