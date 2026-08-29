import Foundation
import Testing

@testable import VoculaKit

@Suite("History by day")
struct HistoryDayTests {
  private let english = Locale(identifier: "en_US_POSIX")
  private func day(_ key: String, _ count: Int = 1) -> HistoryDay {
    HistoryDay(key: key, count: count)
  }
  private func date(_ key: String) -> Date {
    DayFileHistoryStore.dayFormatter.date(from: key)!
  }

  @Test("today and yesterday are named, not dated")
  func relativeTitles() {
    let now = date("2026-08-19")
    #expect(day("2026-08-19").title(now: now, locale: english) == "Today")
    #expect(day("2026-08-18").title(now: now, locale: english) == "Yesterday")
  }

  @Test("an older day is written out with its weekday")
  func absoluteTitle() {
    let title = day("2026-08-14").title(now: date("2026-08-19"), locale: english)
    #expect(title.contains("14"))
    #expect(title.contains("August"))
    #expect(title.contains("Friday"))
  }

  @Test("a key that will not parse is shown as itself")
  func unparseableKey() {
    #expect(day("not-a-day").title(now: Date(), locale: english) == "not-a-day")
  }

  @Test("a day that has gone falls back to the newest that is left")
  func vanishedDayFallsBack() {
    let days = [day("2026-08-19"), day("2026-08-14")]
    #expect(HistoryDay.resolve(selected: "2026-08-18", in: days) == "2026-08-19")
    #expect(HistoryDay.resolve(selected: "2026-08-14", in: days) == "2026-08-14")
    #expect(HistoryDay.resolve(selected: nil, in: []) == nil)
  }
}

private func temporaryStore() -> DayFileHistoryStore {
  DayFileHistoryStore(
    directory: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID())"),
    cipher: PassthroughCipher(), isRecordingEnabled: { true })
}

private func date(_ text: String) -> Date {
  DayFileHistoryStore.dayFormatter.date(from: text)!
}

@Suite("History store — days")
struct HistoryStoreDayTests {
  private func seed(_ store: DayFileHistoryStore) async {
    _ = await store.createDraft(
      session: 1, startedAt: date("2026-08-14"),
      durationMilliseconds: 100, targetBundleID: nil)
    _ = await store.createDraft(
      session: 2, startedAt: date("2026-08-18"),
      durationMilliseconds: 100, targetBundleID: nil)
    _ = await store.createDraft(
      session: 3,
      startedAt: date("2026-08-18").addingTimeInterval(3600),
      durationMilliseconds: 100, targetBundleID: nil)
  }

  @Test("the days are listed newest first, each with how much is in it")
  func daysAreListedNewestFirst() async {
    let store = temporaryStore()
    await seed(store)
    let days = await store.days()
    #expect(days.map(\.key) == ["2026-08-18", "2026-08-14"])
    #expect(days.map(\.count) == [2, 1])
  }

  @Test("characters count only what was inserted, words count it all")
  func insertedTextIsCountedApart() async {
    let store = temporaryStore()
    let sent = await store.createDraft(
      session: 1, startedAt: date("2026-08-14"),
      durationMilliseconds: 4_000, targetBundleID: nil)
    let refused = await store.createDraft(
      session: 2,
      startedAt: date("2026-08-14").addingTimeInterval(60),
      durationMilliseconds: 9_000, targetBundleID: nil)
    let sentID = try! #require(sent)
    let refusedID = try! #require(refused)
    await store.attachFinalText(sentID, "hello you")
    await store.setState(sentID, .sent, reason: nil)
    await store.attachFinalText(refusedID, "not sent")
    await store.setState(refusedID, .rejected, reason: "target")

    let day = try! #require(await store.days().first)
    #expect(day.count == 2)
    #expect(day.words == 4)
    #expect(day.insertedCharacters == 9)
  }

  @Test("one day's records come back on their own, newest first")
  func recordsOfOneDay() async {
    let store = temporaryStore()
    await seed(store)
    let records = await store.records(on: "2026-08-18")
    #expect(records.count == 2)
    #expect(records.first!.createdAt > records.last!.createdAt)
    #expect(await store.records(on: "2026-08-14").map(\.session) == [1])
  }

  @Test("a day that was never written has no records and is not listed")
  func unknownDay() async {
    let store = temporaryStore()
    await seed(store)
    #expect(await store.records(on: "2026-01-01").isEmpty)
  }

  @Test("deleting a day takes its file and everything in it")
  func deleteDay() async throws {
    let store = temporaryStore()
    await seed(store)
    #expect(try await store.deleteDay("2026-08-18") == 2)
    #expect(await store.days().map(\.key) == ["2026-08-14"])
    #expect(await store.records(on: "2026-08-18").isEmpty)
    #expect(await store.fetch(limit: 10).count == 1)
  }

  @Test("deleting a day that is not there removes nothing and says so")
  func deleteMissingDay() async throws {
    let store = temporaryStore()
    await seed(store)
    #expect(try await store.deleteDay("2026-01-01") == 0)
    #expect(await store.days().count == 2)
  }
}

@Suite("History — words a day")
struct HistoryWordsTests {
  private func date(_ key: String) -> Date { DayFileHistoryStore.dayFormatter.date(from: key)! }
  private func day(_ key: String, words: Int) -> HistoryDay {
    HistoryDay(key: key, count: 1, words: words)
  }

  @Test("words are whitespace-separated, and nothing is not zero words")
  func counting() {
    #expect(HistoryWords.count(in: nil) == 0)
    #expect(HistoryWords.count(in: "") == 0)
    #expect(HistoryWords.count(in: "   \n ") == 0)
    #expect(HistoryWords.count(in: "dos palabras") == 2)
    #expect(HistoryWords.count(in: "  spaced   out\nand wrapped ") == 4)
  }

  @Test("the average is over the days that have something in them")
  func averageOverPresentDays() {
    let now = date("2026-08-19")
    let days = [day("2026-08-19", words: 100), day("2026-08-18", words: 200)]
    #expect(HistoryDay.averageWordsPerDay(days, withinDays: 30, now: now) == 150)
  }

  @Test("days outside the window are not counted, in either direction")
  func windowExcludes() {
    let now = date("2026-08-19")
    let days = [day("2026-08-19", words: 100), day("2026-01-01", words: 900)]
    #expect(HistoryDay.averageWordsPerDay(days, withinDays: 30, now: now) == 100)
    #expect(HistoryDay.averageWordsPerDay(days, withinDays: 365, now: now) == 500)
  }

  @Test("no days in the window is no answer, not zero")
  func emptyWindow() {
    let now = date("2026-08-19")
    #expect(HistoryDay.averageWordsPerDay([], withinDays: 30, now: now) == nil)
    #expect(
      HistoryDay.averageWordsPerDay(
        [day("2020-01-01", words: 10)],
        withinDays: 30, now: now) == nil)
  }

  @Test("a day whose key will not parse is left out of the average")
  func unparseableDayIsExcluded() {
    let now = date("2026-08-19")
    let days = [day("2026-08-19", words: 100), day("not-a-day", words: 900)]
    #expect(HistoryDay.averageWordsPerDay(days, withinDays: 30, now: now) == 100)
  }

}
