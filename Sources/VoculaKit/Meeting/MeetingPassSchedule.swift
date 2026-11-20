import Foundation

public struct MeetingPassSchedule: Sendable {
  private var running = false
  private var wanted = false
  private var terminated = false

  public init() {}

  public mutating func requested() -> Bool {
    guard !terminated else { return false }
    wanted = true
    return startIfFree()
  }

  public mutating func passEnded() -> Bool {
    running = false
    return startIfFree()
  }

  public mutating func terminate() {
    terminated = true
    wanted = false
  }

  private mutating func startIfFree() -> Bool {
    guard wanted, !running, !terminated else { return false }
    running = true
    wanted = false
    return true
  }
}
