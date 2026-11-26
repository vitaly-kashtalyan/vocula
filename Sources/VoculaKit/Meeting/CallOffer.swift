import Foundation

public struct AudioClient: Equatable, Sendable {
  public let pid: Int32
  public let input: Bool
  public let output: Bool

  public init(pid: Int32, input: Bool, output: Bool) {
    self.pid = pid
    self.input = input
    self.output = output
  }
}

public struct CallOffer: Sendable {
  public static let after = 10.0
  public static let grace = 30.0

  private var calls: [Int32: (since: Double, seen: Double)] = [:]
  private var offered: Set<Int32> = []

  public init() {}

  public mutating func observe(_ clients: [AudioClient], at now: Double, recording: Bool) -> Int32?
  {
    for client in clients where client.input && client.output {
      calls[client.pid] = (calls[client.pid]?.since ?? now, now)
    }
    for (pid, call) in calls where now - call.seen > Self.grace {
      calls[pid] = nil
      offered.remove(pid)
    }
    if recording { offered.formUnion(calls.keys) }
    let due = calls.filter { pid, call in
      !offered.contains(pid) && call.seen == now && now - call.since >= Self.after
    }
    guard let pid = due.min(by: { $0.value.since < $1.value.since })?.key else { return nil }
    offered.insert(pid)
    return pid
  }

  public static func appPath(ofExecutable path: String) -> String? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard let app = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    return parts[...app].joined(separator: "/")
  }
}
