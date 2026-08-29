import Foundation

public enum Entitlement: Equatable, Sendable {
  case licensed
  case trial(daysLeft: Int)
  case limited(remainingToday: Int)

  public var allowsDictation: Bool {
    switch self {
    case .licensed, .trial: return true
    case .limited(let remaining): return remaining > 0
    }
  }
}

public enum TrialPolicy {
  public static let trialDays = 7
  public static let dictationsPerDayAfterTrial = 10

  public static func entitlement(
    licensed: Bool,
    firstRun: Date,
    now: Date,
    usedToday: Int,
    calendar: Calendar = .current
  ) -> Entitlement {
    if licensed { return .licensed }
    let elapsed =
      calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: firstRun),
        to: calendar.startOfDay(for: now)
      ).day ?? 0
    if elapsed < trialDays {
      return .trial(daysLeft: trialDays - elapsed)
    }
    return .limited(remainingToday: max(0, dictationsPerDayAfterTrial - usedToday))
  }
}
