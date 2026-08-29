import Foundation

public struct HistoryGrid: Sendable, Equatable {
  public struct Cell: Sendable, Equatable {
    public let key: String?
    public let level: Int

    public init(key: String?, level: Int) {
      self.key = key
      self.level = level
    }
  }

  public struct MonthLabel: Sendable, Equatable {
    public let column: Int
    public let title: String

    public init(column: Int, title: String) {
      self.column = column
      self.title = title
    }
  }

  public static let levels = 4
  public static let empty = HistoryGrid(columns: [], months: [], weekdays: [])

  public let columns: [[Cell]]
  public let months: [MonthLabel]
  public let weekdays: [String]

  public init(columns: [[Cell]], months: [MonthLabel], weekdays: [String] = []) {
    self.columns = columns
    self.months = months
    self.weekdays = weekdays
  }

  public static func build(
    days: [HistoryDay],
    now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .interface
  ) -> HistoryGrid {
    let today = calendar.startOfDay(for: now)
    guard
      let oldest = calendar.date(
        byAdding: .day, value: -(HistoryRetention.days - 1),
        to: today)
    else { return .empty }
    let offset = (calendar.component(.weekday, from: oldest) - calendar.firstWeekday + 7) % 7
    guard let start = calendar.date(byAdding: .day, value: -offset, to: oldest),
      let span = calendar.dateComponents([.day], from: start, to: today).day
    else { return .empty }

    var words: [String: Int] = [:]
    for day in days { words[day.key] = day.words }

    var slots: [(key: String?, words: Int)] = []
    var months: [MonthLabel] = []
    var busiest = 0
    for index in 0..<(((span / 7) + 1) * 7) {
      guard let date = calendar.date(byAdding: .day, value: index, to: start) else { break }
      guard date >= oldest, date <= today else {
        slots.append((nil, 0))
        continue
      }
      let key = DayFileHistoryStore.dayFormatter.string(from: date)
      let count = words[key] ?? 0
      busiest = max(busiest, count)
      slots.append((key, count))
      if calendar.component(.day, from: date) == 1 {
        months.append(
          MonthLabel(
            column: index / 7,
            title: date.formatted(.dateTime.month(.abbreviated).locale(locale))))
      }
    }

    let cells = slots.map { Cell(key: $0.key, level: level(of: $0.words, busiest: busiest)) }
    let columns = stride(from: 0, to: cells.count, by: 7).map {
      Array(cells[$0..<min($0 + 7, cells.count)])
    }
    var localized = calendar
    localized.locale = locale
    let symbols = localized.shortWeekdaySymbols
    let weekdays = (0..<7).map { symbols[(localized.firstWeekday - 1 + $0) % 7] }
    return HistoryGrid(
      columns: columns.filter { $0.count == 7 }, months: months,
      weekdays: weekdays)
  }

  private static func level(of words: Int, busiest: Int) -> Int {
    guard words > 0, busiest > 0 else { return 0 }
    let step = Double(words) / Double(busiest) * Double(levels)
    return min(levels, max(1, Int(step.rounded(.up))))
  }
}
