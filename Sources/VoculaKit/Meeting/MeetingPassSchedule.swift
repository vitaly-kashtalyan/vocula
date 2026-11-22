import Foundation

public struct MeetingPassSchedule: Sendable {
  private var running = false
  private var wanted = false
  private var terminated = false
  private var deletesInFlight = 0

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

  public mutating func deleteBegan() -> Bool {
    guard !running, !terminated else { return false }
    deletesInFlight += 1
    return true
  }

  public mutating func deleteEnded() -> Bool {
    deletesInFlight = max(0, deletesInFlight - 1)
    return startIfFree()
  }

  public mutating func terminate() {
    terminated = true
    wanted = false
  }

  private mutating func startIfFree() -> Bool {
    guard wanted, !running, !terminated, deletesInFlight == 0 else { return false }
    running = true
    wanted = false
    return true
  }
}
