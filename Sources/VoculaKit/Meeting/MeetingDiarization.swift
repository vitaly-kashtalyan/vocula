import Foundation

public actor MeetingDiarizerState {
  private(set) var isBusy = false
  private var discarded = false

  public init() {}

  func begin() -> Bool {
    guard !isBusy else { return false }
    isBusy = true
    return true
  }

  func end() {
    isBusy = false
  }

  func mayDiscard() -> Bool {
    guard !discarded else { return false }
    discarded = true
    return true
  }
}

public struct MeetingDiarization: Sendable {
  public let state: MeetingDiarizerState
  public let isInstalled: @Sendable () async -> Bool
  public let load: @Sendable () async throws -> any MeetingDiarizing
  public let discard: @Sendable () async -> Void
  public let wallClock: @Sendable () -> Date
  public let maxTrackSeconds: Double

  public init(
    state: MeetingDiarizerState,
    isInstalled: @escaping @Sendable () async -> Bool,
    load: @escaping @Sendable () async throws -> any MeetingDiarizing,
    discard: @escaping @Sendable () async -> Void,
    wallClock: @escaping @Sendable () -> Date,
    maxTrackSeconds: Double = MeetingDiarizationRules.maxDiarizedSeconds
  ) {
    self.state = state
    self.isInstalled = isInstalled
    self.load = load
    self.discard = discard
    self.wallClock = wallClock
    self.maxTrackSeconds = maxTrackSeconds
  }
}

public enum MeetingDiarizationRules {
  public static let maxWait: TimeInterval = 86_400
  public static let maxDiarizedSeconds: Double = 7_200
  public static let deadlineFloor: Duration = .seconds(60)
  public static let diarizeDeadlineFactor: Double = 0.2

  public static func deadline(forTrackSeconds seconds: Double) -> Duration {
    max(deadlineFloor, .seconds(seconds * diarizeDeadlineFactor))
  }
}
