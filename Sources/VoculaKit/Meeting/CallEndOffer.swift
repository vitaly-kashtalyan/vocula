import Foundation

public struct CallEndOffer: Sendable {
  public static let after = 30.0

  public enum Change: Equatable, Sendable {
    case offer(Int32)
    case offerQuiet
    case withdraw
  }

  private var since: [Int32: Double] = [:]
  private var calls: Set<Int32> = []
  private var heard: (pid: Int32, at: Double)?
  private var shown = false
  private var done = false
  private var quietShown = false
  private var quietKept = false

  public init() {}

  public mutating func observe(
    _ clients: [AudioClient], at now: Double, recording: Bool, quiet: Bool = false
  ) -> Change? {
    guard recording else {
      defer { self = CallEndOffer() }
      return shown || quietShown ? .withdraw : nil
    }
    if !quiet { quietKept = false }
    let call = callEnd(clients, at: now)
    if case .offer = call {
      quietShown = false
      return call
    }
    let wantsQuiet = quiet && !quietKept && !shown
    guard wantsQuiet != quietShown else { return call }
    quietShown = wantsQuiet
    return wantsQuiet ? .offerQuiet : .withdraw
  }

  public mutating func answered() {
    if quietShown {
      quietShown = false
    } else {
      shown = false
      done = true
    }
    quietKept = true
  }

  private mutating func callEnd(_ clients: [AudioClient], at now: Double) -> Change? {
    let calling = Set(clients.filter { $0.input && $0.output }.map(\.pid))
    since = since.filter { calling.contains($0.key) }
    for pid in calling where since[pid] == nil { since[pid] = now }
    calls.formUnion(since.filter { now - $0.value >= CallOffer.after }.keys)
    if let pid = clients.first(where: { $0.input && calls.contains($0.pid) })?.pid {
      heard = (pid, now)
      guard shown else { return nil }
      shown = false
      return .withdraw
    }
    guard let heard, !shown, !done, now - heard.at >= Self.after else { return nil }
    shown = true
    return .offer(heard.pid)
  }
}
