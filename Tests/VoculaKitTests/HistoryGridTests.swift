import Foundation
import Testing

@testable import VoculaKit

@Suite("History grid")
struct HistoryGridTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    return calendar
  }

  private var now: Date {
    DayFileHistoryStore.dayFormatter.date(from: "2026-08-25")!
  }

  private func key(_ daysBack: Int) -> String {
    let date = calendar.date(
      byAdding: .day, value: -daysBack,
      to: calendar.startOfDay(for: now))!
    return DayFileHistoryStore.dayFormatter.string(from: date)
  }

  private func level(_ grid: HistoryGrid, _ day: String) -> Int? {
    grid.columns.flatMap { $0 }.first { $0.key == day }?.level
  }

  private func date(_ day: String) -> Date? {
    DayFileHistoryStore.dayFormatter.date(from: day)
  }

  @Test("every column is a full week of seven cells")
  func columnsAreWeeks() {
    let grid = HistoryGrid.build(days: [], now: now, calendar: calendar)
    #expect(!grid.columns.isEmpty)
    #expect(grid.columns.allSatisfy { $0.count == 7 })
  }

  @Test("the window ends today and reaches back exactly the retention span")
  func windowBounds() {
    let grid = HistoryGrid.build(days: [], now: now, calendar: calendar)
    let keys = grid.columns.flatMap { $0 }.compactMap(\.key)
    #expect(keys.count == HistoryRetention.days)
    #expect(keys.first == key(HistoryRetention.days - 1))
    #expect(keys.last == key(0))
  }

  @Test("a row is one weekday all the way across")
  func rowsAreOneWeekday() {
    let grid = HistoryGrid.build(days: [], now: now, calendar: calendar)
    for row in 0..<7 {
      let weekdays = Set(
        grid.columns.compactMap { column in
          column[row].key.flatMap(date).map { calendar.component(.weekday, from: $0) }
        })
      #expect(weekdays.count == 1)
    }
  }

  @Test("levels run one to four against the busiest day")
  func levelsAgainstTheBusiestDay() {
    let grid = HistoryGrid.build(
      days: [
        HistoryDay(key: key(0), count: 1, words: 100),
        HistoryDay(key: key(1), count: 1, words: 75),
        HistoryDay(key: key(2), count: 1, words: 50),
        HistoryDay(key: key(3), count: 1, words: 25),
        HistoryDay(key: key(4), count: 1, words: 1),
      ], now: now, calendar: calendar)
    #expect(level(grid, key(0)) == 4)
    #expect(level(grid, key(1)) == 3)
    #expect(level(grid, key(2)) == 2)
    #expect(level(grid, key(3)) == 1)
    #expect(level(grid, key(4)) == 1)
  }

  @Test("a day inside the window with nothing in it is present and empty")
  func quietDayIsStillACell() {
    let grid = HistoryGrid.build(
      days: [HistoryDay(key: key(0), count: 1, words: 10)],
      now: now, calendar: calendar)
    #expect(level(grid, key(1)) == 0)
  }

  @Test("a day past the window is absent and does not set the scale")
  func aDayPastTheWindowIsIgnored() {
    let stale = key(HistoryRetention.days)
    let grid = HistoryGrid.build(
      days: [
        HistoryDay(key: stale, count: 9, words: 9000),
        HistoryDay(key: key(0), count: 1, words: 100),
      ], now: now, calendar: calendar)
    #expect(level(grid, stale) == nil)
    #expect(level(grid, key(0)) == 4)
  }

  @Test("cells outside the window carry no day at all")
  func paddingCarriesNoDay() {
    let grid = HistoryGrid.build(days: [], now: now, calendar: calendar)
    let cells = grid.columns.flatMap { $0 }
    #expect(cells.count % 7 == 0)
    #expect(cells.filter { $0.key == nil }.allSatisfy { $0.level == 0 })
  }

  @Test("a month label lands on the column that holds the first of that month")
  func monthLabelsFollowTheFirst() {
    let grid = HistoryGrid.build(days: [], now: now, calendar: calendar)
    #expect(grid.months.count == 12)
    #expect(grid.months.map(\.column) == grid.months.map(\.column).sorted())
    #expect(Set(grid.months.map(\.column)).count == grid.months.count)
    for label in grid.months {
      let firsts = grid.columns[label.column]
        .compactMap { $0.key.flatMap(date) }
        .filter { calendar.component(.day, from: $0) == 1 }
      #expect(firsts.count == 1)
    }
  }

  @Test("an empty history still draws the year")
  func emptyHistoryStillDrawsTheYear() {
    let grid = HistoryGrid.build(days: [], now: now, calendar: calendar)
    #expect(grid.columns.flatMap { $0 }.allSatisfy { $0.level == 0 })
    #expect(grid.columns.flatMap { $0 }.compactMap(\.key).count == HistoryRetention.days)
  }
}

@Suite("The heat map's labels come from one locale")
struct HistoryGridLocaleTests {
  private func grid(_ locale: Locale) -> HistoryGrid {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = locale
    return HistoryGrid.build(
      days: [], now: Date(timeIntervalSince1970: 1_770_000_000),
      calendar: calendar, locale: locale)
  }

  @Test("weekday labels follow the same locale as the month labels")
  func weekdaysFollowTheLocale() {
    let english = grid(Locale(identifier: "en_US"))
    let german = grid(Locale(identifier: "de_DE"))
    #expect(english.weekdays.count == 7)
    #expect(german.weekdays.count == 7)
    #expect(
      english.weekdays != german.weekdays,
      "the weekday row ignored the locale it was given")
  }

  @Test("the week starts where the calendar says it does")
  func weekStartsAtFirstWeekday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let built = HistoryGrid.build(
      days: [], now: Date(timeIntervalSince1970: 1_770_000_000),
      calendar: calendar, locale: Locale(identifier: "en_US"))
    #expect(built.weekdays.first == calendar.shortWeekdaySymbols[calendar.firstWeekday - 1])
  }
}
