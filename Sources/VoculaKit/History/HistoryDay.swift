import Foundation

public struct HistoryDay: Sendable, Equatable, Identifiable {
  public let key: String
  public let count: Int
  public let words: Int
  public let insertedCharacters: Int

  public var id: String { key }

  public init(key: String, count: Int, words: Int = 0, insertedCharacters: Int = 0) {
    self.key = key
    self.count = count
    self.words = words
    self.insertedCharacters = insertedCharacters
  }

  public var date: Date? { DayFileHistoryStore.dayFormatter.date(from: key) }

  public func title(now: Date = Date(), locale: Locale = .interface) -> String {
    guard let date else { return key }
    var calendar = Calendar.current
    calendar.locale = locale
    if calendar.isDate(date, inSameDayAs: now) {
      return String(
        localized: "history.day.today", defaultValue: "Today", bundle: .module,
        locale: locale,
        comment: "History day heading for the current day.")
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      return String(
        localized: "history.day.yesterday", defaultValue: "Yesterday", bundle: .module,
        locale: locale,
        comment: "History day heading for the day before the current one.")
    }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
  }

  public static func averageWordsPerDay(
    _ days: [HistoryDay], withinDays window: Int,
    now: Date = Date()
  ) -> Int? {
    let cutoff = now.addingTimeInterval(-Double(window) * 86_400)
    let inWindow = days.filter { day in
      guard let date = day.date else { return false }
      return date >= cutoff
    }
    guard !inWindow.isEmpty else { return nil }
    return Int(
      (Double(inWindow.reduce(0) { $0 + $1.words }) / Double(inWindow.count))
        .rounded())
  }

  public static func resolve(
    selected: String?, previousNewest: String?, in days: [HistoryDay]
  ) -> String? {
    guard let selected, selected != previousNewest,
      days.contains(where: { $0.key == selected })
    else { return days.first?.key }
    return selected
  }
}
