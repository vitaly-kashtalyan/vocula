import Foundation

public struct UsageLedger: @unchecked Sendable {
  public static let firstRunKey = "trial.firstRun"
  public static let highWaterKey = "trial.highWater"
  public static let usageDayKey = "usage.day"
  public static let usageCountKey = "usage.count"

  private let defaults: UserDefaults
  private let clock: @Sendable () -> Date
  private let calendar: Calendar

  public init(
    defaults: UserDefaults = .standard,
    calendar: Calendar = .current,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.defaults = defaults
    self.calendar = Self.gregorian(like: calendar)
    self.clock = clock
  }

  public func now() -> Date {
    let system = clock()
    guard let stored = defaults.object(forKey: Self.highWaterKey) as? Double else {
      return system
    }
    return max(system, Date(timeIntervalSinceReferenceDate: stored))
  }

  public func advance() {
    let effective = now()
    let stored = defaults.object(forKey: Self.highWaterKey) as? Double
    if stored == nil || effective.timeIntervalSinceReferenceDate > stored! {
      defaults.set(effective.timeIntervalSinceReferenceDate, forKey: Self.highWaterKey)
    }
  }

  public func clockOvershoot() -> Date? {
    guard let stored = defaults.object(forKey: Self.highWaterKey) as? Double else {
      return nil
    }
    let mark = Date(timeIntervalSinceReferenceDate: stored)
    guard mark.timeIntervalSince(clock()) > Self.overshootThreshold else { return nil }
    return mark
  }

  private static let overshootThreshold: TimeInterval = 24 * 60 * 60

  public func forgetClockHistory() {
    defaults.removeObject(forKey: Self.highWaterKey)
  }

  public func firstRun() -> Date {
    guard let stored = defaults.object(forKey: Self.firstRunKey) as? Double else {
      return now()
    }
    return Date(timeIntervalSinceReferenceDate: stored)
  }

  public func startTrialIfNeeded() {
    advance()
    guard defaults.object(forKey: Self.firstRunKey) == nil else { return }
    defaults.set(now().timeIntervalSinceReferenceDate, forKey: Self.firstRunKey)
  }

  public func usedToday() -> Int {
    guard defaults.string(forKey: Self.usageDayKey) == dayKey(now()) else { return 0 }
    return defaults.integer(forKey: Self.usageCountKey)
  }

  public func recordDictation() {
    advance()
    let key = dayKey(now())
    let used =
      defaults.string(forKey: Self.usageDayKey) == key
      ? defaults.integer(forKey: Self.usageCountKey) : 0
    defaults.set(key, forKey: Self.usageDayKey)
    defaults.set(used + 1, forKey: Self.usageCountKey)
  }

  public func entitlement(licensed: Bool) -> Entitlement {
    TrialPolicy.entitlement(
      licensed: licensed, firstRun: firstRun(), now: now(),
      usedToday: usedToday(), calendar: calendar)
  }

  private func dayKey(_ date: Date) -> String { Self.dayKey(date, calendar: calendar) }

  public static func dayKey(_ date: Date, calendar: Calendar) -> String {
    let c = gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  private static func gregorian(like calendar: Calendar) -> Calendar {
    guard calendar.identifier != .gregorian else { return calendar }
    var pinned = Calendar(identifier: .gregorian)
    pinned.timeZone = calendar.timeZone
    return pinned
  }
}
