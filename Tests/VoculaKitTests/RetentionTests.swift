import Foundation
import Testing

@testable import VoculaKit

private actor FakeHistory: HistoryStoring {
  var records: [DictationRecord] = []
  var deletedBefore: Date?

  func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int,
    targetBundleID: String?, modelID: String?
  ) async -> UUID? { nil }
  func markTruncated(_ id: UUID) async {}
  func attachMetrics(_ id: UUID, _ metrics: SpeechMetrics) async {}
  func attachRawText(_ id: UUID, _ text: String, language: String) async {}
  func attachFinalText(_ id: UUID, _ text: String) async {}
  func setState(_ id: UUID, _ state: SessionState, reason: String?) async {}
  func fetch(limit: Int) async -> [DictationRecord] { records }
  func days() async -> [HistoryDay] { [] }
  func records(on day: String) async -> [DictationRecord] { [] }
  @discardableResult
  func deleteDay(_ day: String) async throws -> Int { 0 }
  func delete(_ id: UUID) async -> Bool {
    records.removeAll { $0.id == id }
    return true
  }
  @discardableResult
  func deleteOlderThan(_ date: Date) async -> Int {
    deletedBefore = date
    let before = records.count
    records.removeAll { $0.createdAt < date }
    return before - records.count
  }
  @discardableResult
  func deleteAll() async -> Int {
    let before = records.count
    records.removeAll()
    return before
  }
  func seed(_ values: [DictationRecord]) { records = values }
}

private func record(daysAgo: Int, now: Date) -> DictationRecord {
  let date = now.addingTimeInterval(-Double(daysAgo) * 86_400)
  return DictationRecord(
    id: UUID(), session: 1, createdAt: date, updatedAt: date,
    owner: nil, state: .sent, reason: nil,
    rawText: "text", finalText: "text", language: "ru",
    durationMilliseconds: 900, targetBundleID: nil, metrics: nil,
    truncated: false, modelID: nil)
}

@Suite("Retention")
struct RetentionTests {
  @Test("records older than the retention window are removed")
  func oldRecordsRemoved() async {
    let now = Date()
    let history = FakeHistory()
    await history.seed([record(daysAgo: 100, now: now), record(daysAgo: 10, now: now)])
    let removed = await RetentionSweeper(store: history, days: 90).sweep(now: now)
    #expect(removed == 1)
    #expect(await history.records.count == 1)
  }

  @Test("the default window is a year")
  func defaultWindow() {
    #expect(HistoryRetention.days == 365)
  }

  @Test("a retention figure left over from the stepper has no say")
  func aStaleStoredRetentionIsIgnored() async {
    let defaults = UserDefaults(suiteName: "test.retention.stale")!
    defaults.removePersistentDomain(forName: "test.retention.stale")
    defaults.set(7, forKey: "history.retentionDays")
    let now = Date()
    let history = FakeHistory()
    await history.seed([record(daysAgo: 30, now: now)])
    _ = await RetentionSweeper(store: history).sweep(now: now)
    #expect(await history.records.count == 1)
  }

  @Test("the cut-off is computed from the window, not hard-coded")
  func cutoffFollowsTheWindow() async {
    let now = Date()
    let history = FakeHistory()
    await history.seed([record(daysAgo: 10, now: now)])
    _ = await RetentionSweeper(store: history, days: 7).sweep(now: now)
    #expect(await history.records.isEmpty)
  }

  @Test("nothing is removed when everything is inside the window")
  func nothingToRemove() async {
    let now = Date()
    let history = FakeHistory()
    await history.seed([record(daysAgo: 1, now: now)])
    #expect(await RetentionSweeper(store: history, days: 90).sweep(now: now) == 0)
  }

  @Test("a successful sweep records no failure")
  func successfulSweepRecordsNoFailure() async {
    let now = Date()
    let history = FakeHistory()
    await history.seed([record(daysAgo: 100, now: now)])
    let logURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID()).json")
    let log = DiagnosticLog(fileURL: logURL)
    let sweeper = RetentionSweeper(store: history, days: 90, diagnosticLog: log)
    #expect(await sweeper.sweep(now: now) == 1)
    #expect(log.recent(10).isEmpty)
  }

  @Test("the cutoff is a calendar day back, not 86,400 seconds, across a DST change")
  func cutoffIsCalendarDaysAcrossDaylightSaving() async {
    var rome = Calendar(identifier: .gregorian)
    rome.timeZone = TimeZone(identifier: "Europe/Rome")!
    let now = rome.date(
      from: DateComponents(
        year: 2026, month: 4, day: 1,
        hour: 12, minute: 0))!
    let history = FakeHistory()
    _ = await RetentionSweeper(store: history, days: 7, calendar: rome).sweep(now: now)

    let cutoff = await history.deletedBefore
    let parts = rome.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: try! #require(cutoff))
    #expect(parts.month == 3)
    #expect(parts.day == 25)
    #expect(parts.hour == 12)
    #expect(parts.minute == 0)
  }
}
