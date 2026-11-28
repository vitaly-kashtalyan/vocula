import Foundation

public struct CallEndOffer: Sendable {
  public static let after = 30.0

  public enum Change: Equatable, Sendable {
    case offer(Int32)
    case withdraw
  }

  private var since: [Int32: Double] = [:]
  private var calls: Set<Int32> = []
  private var heard: (pid: Int32, at: Double)?
  private var shown = false
  private var done = false

  public init() {}

  public mutating func observe(_ clients: [AudioClient], at now: Double, recording: Bool)
    -> Change?
  {
    guard recording else {
      defer { self = CallEndOffer() }
      return shown ? .withdraw : nil
    }
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

  public mutating func answered() {
    shown = false
    done = true
  }
}
