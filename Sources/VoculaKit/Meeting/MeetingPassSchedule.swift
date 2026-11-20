import Foundation

public struct MeetingPassSchedule: Sendable {
  public enum Action: Equatable, Sendable { case none, start, cancel }

  public private(set) var running = false
  private var wanted = false
  private var terminated = false

  public init() {}

  public var isIdle: Bool { !running && !wanted }

  public mutating func requested(recording: Bool) -> Action {
    guard !terminated else { return .none }
    wanted = true
    return startIfFree(recording: recording)
  }

  public mutating func recordingStarted() -> Action {
    guard running else { return .none }
    wanted = true
    return .cancel
  }

  public mutating func passEnded(recording: Bool) -> Action {
    running = false
    return startIfFree(recording: recording)
  }

  public mutating func terminate() {
    terminated = true
    wanted = false
  }

  private mutating func startIfFree(recording: Bool) -> Action {
    guard wanted, !running, !recording, !terminated else { return .none }
    running = true
    wanted = false
    return .start
  }
}
