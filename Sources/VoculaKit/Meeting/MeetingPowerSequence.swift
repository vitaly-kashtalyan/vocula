import Foundation

public struct MeetingPowerSequence: Sendable {
  // Workaround: kIOMessageCanSystemSleep and kIOMessageSystemWillSleep are IOKit's
  // iokit_common_msg() macros, which Swift does not import, so their values are literals.
  public static let canSystemSleep: UInt32 = 0xE000_0270
  public static let systemWillSleep: UInt32 = 0xE000_0280
  public static let allowWithin: Duration = .seconds(5)

  public enum Step: Equatable, Sendable {
    case allow(notification: Int)
    case stopMeeting
    case deregister
  }

  private var waitingSleep: Int?
  private var releaseWaits = false
  private var deregistered = false

  public init() {}

  public mutating func received(_ message: UInt32, notification: Int) -> [Step] {
    guard !deregistered else { return [] }
    switch message {
    case Self.canSystemSleep:
      return [.allow(notification: notification)]
    case Self.systemWillSleep:
      waitingSleep = notification
      return [.stopMeeting]
    default:
      return []
    }
  }

  public mutating func meetingStopped() -> [Step] {
    guard !deregistered, let notification = waitingSleep else { return [] }
    waitingSleep = nil
    guard releaseWaits else { return [.allow(notification: notification)] }
    deregistered = true
    return [.allow(notification: notification), .deregister]
  }

  public mutating func releaseRequested() -> [Step] {
    guard !deregistered else { return [] }
    guard waitingSleep == nil else {
      releaseWaits = true
      return []
    }
    deregistered = true
    return [.deregister]
  }
}
