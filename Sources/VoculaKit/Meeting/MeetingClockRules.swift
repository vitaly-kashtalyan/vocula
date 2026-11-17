import Foundation

public struct SilenceStop: Sendable {
  public enum Verdict: Equatable, Sendable { case recording, stopsSoon, stop }
  public static let warnAfter: UInt64 = 840_000_000_000
  public static let stopAfter: UInt64 = 900_000_000_000

  private var lastSound: UInt64

  public init(startedAt: UInt64) { lastSound = startedAt }

  public mutating func levels(micPeak: Int16, systemPeak: Int16, at now: UInt64) -> Verdict {
    if micPeak >= MeetingTrack.mic.soundFloor || systemPeak >= MeetingTrack.system.soundFloor {
      lastSound = now
    }
    let silent = HostTime.elapsed(from: lastSound, to: now)
    if silent >= Self.stopAfter { return .stop }
    return silent >= Self.warnAfter ? .stopsSoon : .recording
  }
}

public struct MicReopenSchedule: Equatable, Sendable {
  public static let firstDelay: UInt64 = 5_000_000_000
  public static let longestDelay: UInt64 = 60_000_000_000

  public private(set) var attempts: Int = 0
  private var timerFailures: Int = 0

  public init() {}

  public mutating func lost(at now: UInt64) -> UInt64 {
    timerFailures = 0
    return HostTime.adding(now, delay)
  }

  public mutating func timerAttemptFailed(at now: UInt64) -> UInt64 {
    attempts += 1
    timerFailures += 1
    return HostTime.adding(now, delay)
  }

  public mutating func deviceListAttemptFailed() { attempts += 1 }

  public mutating func reopened() -> Int {
    defer {
      attempts = 0
      timerFailures = 0
    }
    return attempts + 1
  }

  private var delay: UInt64 {
    min(Self.firstDelay << UInt64(min(timerFailures, 4)), Self.longestDelay)
  }
}

public enum MeetingBound {
  public static let termination: Duration = .seconds(3)

  public static func wait(
    for work: Task<Void, Never>, atMost bound: Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) async -> Bool {
    await withCheckedContinuation { continuation in
      let once = Once(continuation)
      let timer = Task {
        guard (try? await sleep(bound)) != nil else { return }
        once.resume(returning: false)
      }
      Task {
        await work.value
        timer.cancel()
        once.resume(returning: true)
      }
    }
  }

  private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func resume(returning value: Bool) {
      let taken = lock.withLock {
        defer { continuation = nil }
        return continuation
      }
      taken?.resume(returning: value)
    }
  }
}
