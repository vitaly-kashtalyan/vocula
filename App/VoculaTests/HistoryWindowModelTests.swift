import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@MainActor
struct HistoryWindowModelTests {
  private func store() -> DayFileHistoryStore {
    DayFileHistoryStore(
      directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID())"),
      cipher: PassthroughCipher(), isRecordingEnabled: { true })
  }

  private func day(_ text: String) -> Date {
    DayFileHistoryStore.dayFormatter.date(from: text)!
  }

  private func seeded() async -> (HistoryWindowModel, DayFileHistoryStore) {
    let store = self.store()
    _ = await store.createDraft(
      session: 1, startedAt: day("2026-08-14"),
      durationMilliseconds: 100, targetBundleID: nil)
    _ = await store.createDraft(
      session: 2, startedAt: day("2026-08-18"),
      durationMilliseconds: 100, targetBundleID: nil)
    _ = await store.createDraft(
      session: 3,
      startedAt: day("2026-08-18").addingTimeInterval(3600),
      durationMilliseconds: 100, targetBundleID: nil)
    let model = HistoryWindowModel(store: store)
    await model.reload()
    return (model, store)
  }

  @Test("a visit lands on the newest day, showing only that day")
  func landsOnTheNewestDay() async {
    let (model, _) = await seeded()
    #expect(model.days.map(\.key) == ["2026-08-18", "2026-08-14"])
    #expect(model.selectedDay == "2026-08-18")
    #expect(model.records.count == 2)
    #expect(model.day?.count == 2)
  }

  @Test("choosing another day shows that day instead")
  func selectsAnotherDay() async {
    let (model, _) = await seeded()
    await model.select("2026-08-14")
    #expect(model.selectedDay == "2026-08-14")
    #expect(model.records.map(\.session) == [1])
    await model.select("2026-08-18")
    #expect(model.records.count == 2)
  }

  @Test("opening the screen again lands on the newest day, not the one last read")
  func openingAgainLeavesTheOldDay() async {
    let (model, _) = await seeded()
    await model.select("2026-08-14")
    await model.openNewestDay()
    #expect(model.selectedDay == "2026-08-18")
    #expect(model.records.count == 2)
  }

  @Test("a refresh while the screen is open keeps the day being read")
  func refreshKeepsTheDayBeingRead() async {
    let (model, _) = await seeded()
    await model.select("2026-08-14")
    await model.reload()
    #expect(model.selectedDay == "2026-08-14")
    #expect(model.records.map(\.session) == [1])
  }

  @Test("an activation refresh arriving while the screen opens still lands on the newest day")
  func openingWinsOverAConcurrentRefresh() async {
    let (model, _) = await seeded()
    await model.select("2026-08-14")
    async let opening: Void = model.openNewestDay()
    async let refreshing: Void = model.reload()
    _ = await (opening, refreshing)
    #expect(model.selectedDay == "2026-08-18")
    #expect(model.records.count == 2)
  }

  @Test("a day whose records arrive late never lands on top of a newer choice")
  func supersededSelectionIsDropped() async {
    let (_, disk) = await seeded()
    let slow = SlowDayHistory(
      byDay: [
        "2026-08-14": await disk.records(on: "2026-08-14"),
        "2026-08-18": await disk.records(on: "2026-08-18"),
      ], slowDay: "2026-08-18")
    let model = HistoryWindowModel(store: slow)
    await model.reload()
    let stale = Task { await model.select("2026-08-18") }
    let chosen = Task { await model.select("2026-08-14") }
    await stale.value
    await chosen.value
    #expect(model.selectedDay == "2026-08-14")
    #expect(model.records.map(\.session) == [1])
  }

  @Test("a screen left open on the live day follows it when the day rolls over")
  func theLiveDayIsFollowedOnRefresh() async {
    let (model, store) = await seeded()
    #expect(model.selectedDay == "2026-08-18")
    _ = await store.createDraft(
      session: 4, startedAt: day("2026-08-19"),
      durationMilliseconds: 100, targetBundleID: nil)
    await model.reload()
    #expect(model.selectedDay == "2026-08-19")
  }

  @Test("a screen left open on an OLDER day is not dragged forward with it")
  func anOlderDayIsKeptOnRefresh() async {
    let (model, store) = await seeded()
    await model.select("2026-08-14")
    _ = await store.createDraft(
      session: 4, startedAt: day("2026-08-19"),
      durationMilliseconds: 100, targetBundleID: nil)
    await model.reload()
    #expect(model.selectedDay == "2026-08-14")
  }

  @Test("a day carries what was dictated, not just how many records")
  func daysCarryWords() async {
    let (model, store) = await seeded()
    let record = await store.records(on: "2026-08-14")[0]
    await store.attachFinalText(record.id, "tres palabras cortas")
    await model.reload()
    #expect(model.days.first { $0.key == "2026-08-14" }?.words == 3)
    #expect(model.averageWordsThisYear != nil)
  }

  @Test("emptying a day drops it and moves to the newest day left")
  func emptyingADayMovesTheSelection() async {
    let (model, _) = await seeded()
    await model.select("2026-08-14")
    #expect(model.selectedDay == "2026-08-14")
    await model.delete(model.records[0])
    #expect(model.days.map(\.key) == ["2026-08-18"])
    #expect(model.selectedDay == "2026-08-18")
    #expect(model.records.count == 2)
  }

  @Test("deleting the day removes the day and everything in it")
  func deleteDay() async {
    let (model, store) = await seeded()
    await model.deleteDay()
    #expect(model.days.map(\.key) == ["2026-08-14"])
    #expect(model.selectedDay == "2026-08-14")
    #expect(await store.records(on: "2026-08-18").isEmpty)
  }

  @Test("deleting everything leaves no days at all")
  func deleteAll() async {
    let (model, _) = await seeded()
    await model.deleteAll()
    #expect(model.days.isEmpty)
    #expect(model.selectedDay == nil)
    #expect(model.records.isEmpty)
  }

  @Test("an empty history has no day to show and says nothing went wrong")
  func emptyHistory() async {
    let model = HistoryWindowModel(store: store())
    await model.reload()
    #expect(model.days.isEmpty)
    #expect(model.selectedDay == nil)
    #expect(model.errorNotice == nil)
  }
}

private actor SlowDayHistory: HistoryStoring {
  private let byDay: [String: [DictationRecord]]
  private let slowDay: String

  init(byDay: [String: [DictationRecord]], slowDay: String) {
    self.byDay = byDay
    self.slowDay = slowDay
  }

  func days() async -> [HistoryDay] {
    byDay.map { HistoryDay(key: $0.key, count: $0.value.count) }.sorted { $0.key > $1.key }
  }

  func records(on day: String) async -> [DictationRecord] {
    if day == slowDay { try? await Task.sleep(for: .milliseconds(80)) }
    return byDay[day] ?? []
  }

  func fetch(limit: Int) async -> [DictationRecord] { [] }
  func deleteDay(_ day: String) async throws -> Int { 0 }
  func delete(_ id: UUID) async -> Bool { false }
  func deleteAll() async throws -> Int { 0 }
  func deleteOlderThan(_ date: Date) async throws -> Int { 0 }
  func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int,
    targetBundleID: String?, modelID: String?
  ) async -> UUID? { nil }
  func markTruncated(_ id: UUID) async {}
  func attachMetrics(_ id: UUID, _ metrics: SpeechMetrics) async {}
  func attachRawText(_ id: UUID, _ text: String, language: String) async {}
  func attachFinalText(_ id: UUID, _ text: String) async {}
  func setState(_ id: UUID, _ state: SessionState, reason: String?) async {}
}
