import Foundation

public struct AccessibilityWatch: Sendable {
  public enum Action: Equatable, Sendable { case tearDown, restart }

  private var armed: Bool
  private var revoked = false

  public init(trusted: Bool) {
    armed = trusted
  }

  public mutating func observe(trusted: Bool, monitorExists: Bool) -> Action? {
    if trusted {
      armed = true
      guard revoked else { return nil }
      revoked = false
      return .restart
    }
    guard armed else { return nil }
    revoked = true
    return monitorExists ? .tearDown : nil
  }
}
