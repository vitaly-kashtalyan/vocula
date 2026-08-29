import Foundation

public protocol TargetProbing: Sendable {
  func snapshot(budget: Duration) async -> (TargetSnapshot, FocusedSubrole)
  func compare(_ snapshot: TargetSnapshot, budget: Duration) async -> TargetComparison
  func release(_ snapshot: TargetSnapshot) async
}

public enum SubroleAnswer {
  public static func from(subrole: String?, secureSubroleIdentifier: String) -> FocusedSubrole {
    guard let subrole else { return .unknown }
    return subrole == secureSubroleIdentifier ? .secureTextField : .other(subrole)
  }
}

public enum QueryBudget {
  public static func secondsRemaining(
    until deadline: ContinuousClock.Instant,
    now: ContinuousClock.Instant
  ) -> Float? {
    let remaining = now.duration(to: deadline).milliseconds
    guard remaining > 0 else { return nil }
    return Float(remaining) / 1000
  }
}

public enum IdentityComparison {
  public static func same<T>(pinned: T?, now: T?, isEqual: (T, T) -> Bool) -> Bool {
    guard let pinned else { return true }
    guard let now else { return false }
    return isEqual(pinned, now)
  }
}
