import Foundation

public struct DictationHold: Sendable {
  private let passDeadline: @Sendable (Duration) -> Duration
  private let refineWait: @Sendable () -> Duration?
  private var open: [Int: UInt64] = [:]
  private var heldUntil: UInt64 = 0

  public init(
    passDeadline: @escaping @Sendable (Duration) -> Duration,
    refineWait: @escaping @Sendable () -> Duration?
  ) {
    self.passDeadline = passDeadline
    self.refineWait = refineWait
  }

  public mutating func received(_ signal: DictationSignal, at: UInt64) {
    switch signal {
    case .start(let session):
      open[session] = at
    case .stop(let session, _), .cancel(let session, _):
      let start = open.removeValue(forKey: session) ?? at
      heldUntil = until(start: start, end: at, after: heldUntil)
    }
  }

  public mutating func streamEnded(at: UInt64) {
    for start in open.values.sorted() {
      heldUntil = until(start: start, end: max(start, at), after: heldUntil)
    }
    open = [:]
  }

  public func clearsAt(_ now: UInt64) -> UInt64? {
    var latest = heldUntil
    var nextCap: UInt64?
    for start in open.values.sorted() {
      let capped = HostTime.adding(start, DictationSpans.cap)
      if now < capped {
        nextCap = min(nextCap ?? capped, capped)
      } else {
        latest = until(start: start, end: capped, after: latest)
      }
    }
    if let nextCap { return nextCap }
    return now < latest ? latest : nil
  }

  private func until(start: UInt64, end: UInt64, after previous: UInt64) -> UInt64 {
    let spoken = Duration.nanoseconds(Int64(min(HostTime.elapsed(from: start, to: end), .max / 2)))
    let wait = passDeadline(spoken) + (refineWait() ?? .zero)
    return HostTime.adding(max(end, previous), Self.nanos(wait))
  }

  static func nanos(_ duration: Duration) -> UInt64 {
    let parts = duration.components
    return HostTime.nanos(Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
  }
}

public actor MeetingHoldGate {
  private static let step: UInt64 = 1_000_000_000

  private var hold: DictationHold
  private let now: @Sendable () -> UInt64
  private let sleep: @Sendable (Duration) async throws -> Void

  public init(
    hold: DictationHold, now: @escaping @Sendable () -> UInt64,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.hold = hold
    self.now = now
    self.sleep = sleep
  }

  public func received(_ signal: DictationSignal) {
    hold.received(signal, at: now())
  }

  public func streamEnded() {
    hold.streamEnded(at: now())
  }

  var isHeld: Bool { hold.clearsAt(now()) != nil }

  public func waitUntilClear() async -> Duration {
    let began = now()
    while let until = hold.clearsAt(now()) {
      let step = min(HostTime.elapsed(from: now(), to: until), Self.step)
      do { try await sleep(.nanoseconds(Int64(max(step, 1)))) } catch { break }
    }
    return .nanoseconds(Int64(HostTime.elapsed(from: began, to: now())))
  }
}
