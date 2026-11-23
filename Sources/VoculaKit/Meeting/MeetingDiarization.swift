import Foundation

public actor MeetingDiarizerState {
  private var inFlight = false
  private var discarded = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  public init() {}

  var isBusy: Bool { inFlight }

  func begin() -> Bool {
    guard !inFlight else { return false }
    inFlight = true
    return true
  }

  func end() {
    inFlight = false
    let resumed = waiting
    waiting = []
    resumed.forEach { $0.resume() }
  }

  func mayDiscard() -> Bool {
    guard !discarded else { return false }
    discarded = true
    return true
  }

  func waitUntilIdle() async {
    guard inFlight else { return }
    await withCheckedContinuation { waiting.append($0) }
  }
}

public struct MeetingDiarization: Sendable {
  public var state: MeetingDiarizerState
  public var isInstalled: @Sendable () async -> Bool
  public var load: @Sendable () async throws -> any MeetingDiarizing
  public var discard: @Sendable () async -> Void
  public var wallClock: @Sendable () -> Date
  public var maxTrackSeconds: Double

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
