import Foundation

public struct InputOnsetGate: Sendable {
  public static let bound = Duration.milliseconds(1_200)

  public enum Opening: String, Equatable, Sendable {
    case stillWaiting
    case signal
    case bound
  }

  private var opened = false

  public init() {}

  public var isOpen: Bool { opened }

  public mutating func level(_ level: Float) -> Opening {
    guard !opened, level > 0 else { return .stillWaiting }
    opened = true
    return .signal
  }

  public mutating func boundReached() -> Opening {
    guard !opened else { return .stillWaiting }
    opened = true
    return .bound
  }
}
