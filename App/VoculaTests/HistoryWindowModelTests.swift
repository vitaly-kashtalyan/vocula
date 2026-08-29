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
