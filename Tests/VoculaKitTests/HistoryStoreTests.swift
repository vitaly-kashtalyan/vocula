import Foundation
import Testing

@testable import VoculaKit

private func temporaryStore(enabled: Bool = true) -> DayFileHistoryStore {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(UUID())")
  return DayFileHistoryStore(
    directory: url, cipher: PassthroughCipher(),
    isRecordingEnabled: { enabled })
}

@Suite("HistoryStore")
struct HistoryStoreTests {
  @Test("delete-all removes a record filed under a future day too")
  func deleteAllRemovesFutureDays() async throws {
    let store = temporaryStore()
    let tomorrow = Date().addingTimeInterval(86_400)
    _ = await store.createDraft(
      session: 1, startedAt: tomorrow,
      durationMilliseconds: 1_000, targetBundleID: nil)
    _ = await store.createDraft(
      session: 2, startedAt: Date(),
      durationMilliseconds: 1_000, targetBundleID: nil)
    #expect(await store.fetch(limit: 10).count == 2)

    _ = try await store.deleteAll()

    #expect(await store.fetch(limit: 10).isEmpty)
  }

  @Test("the day formatter pins its calendar and locale rather than inheriting the region")
  func dayFormatterIsPinned() {
    #expect(DayFileHistoryStore.dayFormatter.calendar.identifier == .gregorian)
    #expect(DayFileHistoryStore.dayFormatter.locale.identifier == "en_US_POSIX")
  }

  @Test("the day file is named on the Gregorian calendar whatever the region is")
  func dayFileIsNamedOnTheGregorianCalendar() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    let moment = Date(timeIntervalSince1970: 1_755_500_000)
    _ = await store.createDraft(
      session: 1, startedAt: moment,
      durationMilliseconds: 1_000, targetBundleID: nil)

    let parts = Calendar(identifier: .gregorian)
      .dateComponents([.year, .month, .day], from: moment)
    let expected = String(
      format: "%04d-%02d-%02d.history",
      parts.year!, parts.month!, parts.day!)
    #expect(
      try FileManager.default
        .contentsOfDirectory(atPath: directory.path) == [expected])
  }

  @Test("a draft is created with no text and the recorded state")
  func draftHasNoText() async {
    let store = temporaryStore()
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 1_200,
      targetBundleID: "com.apple.TextEdit")!
    await store.setState(id, .recorded, reason: nil)
    let record = await store.fetch(limit: 1).first
    #expect(record?.rawText == nil)
    #expect(record?.finalText == nil)
    #expect(record?.state == .recorded)
    #expect(record?.durationMilliseconds == 1_200)
  }

  @Test("the outcome is appended to an existing record rather than a new one")
  func outcomeIsAppended() async {
    let store = temporaryStore()
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 900,
      targetBundleID: nil)!
    await store.attachRawText(id, "raw text", language: "en")
    await store.attachFinalText(id, "final text")
    await store.setState(id, .sent, reason: nil)
    let all = await store.fetch(limit: 10)
    #expect(all.count == 1)
    #expect(all[0].rawText == "raw text")
    #expect(all[0].finalText == "final text")
    #expect(all[0].state == .sent)
  }

  @Test("a text-less record marked no-speech keeps its metrics")
  func noSpeechRecordKeepsMetrics() async {
    let store = temporaryStore()
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 4_000,
      targetBundleID: nil)!
    await store.attachMetrics(
      id,
      SpeechMetrics(
        segmentCount: 0, speechFraction: 0,
        maxProbability: 0.2, meanProbability: 0.1,
        totalMilliseconds: 4_000))
    await store.setState(id, .noSpeech, reason: nil)
    let record = await store.fetch(limit: 1).first
    #expect(record?.state == .noSpeech)
    #expect(record?.rawText == nil)
    #expect(record?.metrics?.maxProbability == 0.2)
  }

  @Test("with history off nothing is written at all")
  func historySwitchIsRespected() async {
    let store = temporaryStore(enabled: false)
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 900, targetBundleID: nil)
    #expect(id == nil)
    #expect(await store.fetch(limit: 10).isEmpty)
  }

  @Test("the owner field exists and stays nil")
  func ownerStaysEmpty() async {
    let store = temporaryStore()
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 900, targetBundleID: nil)!
    await store.setState(id, .recorded, reason: nil)
    let record = await store.fetch(limit: 1).first
    #expect(record?.owner == nil)
  }

  @Test("every record has a stable identifier and both timestamps")
  func identityAndTimestamps() async {
    let store = temporaryStore()
    let id = await store.createDraft(
      session: 7, startedAt: Date(),
      durationMilliseconds: 900, targetBundleID: nil)!
    await store.setState(id, .recorded, reason: nil)
    try? await Task.sleep(for: .milliseconds(20))
    await store.setState(id, .sent, reason: nil)
    let record = await store.fetch(limit: 1).first!
    #expect(record.id == id)
    #expect(record.session == 7)
    #expect(record.updatedAt > record.createdAt)
  }

  @Test("a refusal reason is stored alongside the state")
  func reasonIsStored() async {
    let store = temporaryStore()
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 900, targetBundleID: nil)!
    await store.setState(id, .rejected, reason: InsertDenyReason.secureField.rawValue)
    #expect(await store.fetch(limit: 1).first?.reason == "secureField")
  }

  @Test("a day that will not decrypt is never overwritten by a later dictation")
  func unreadableDayIsNotOverwritten() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    let moment = Date(timeIntervalSince1970: 1_755_500_000)
    let day = DayFileHistoryStore.dayFormatter.string(from: moment)
    let file = directory.appendingPathComponent("\(day).history")
    let ciphertext = Data("not this cipher's plaintext".utf8)
    try ciphertext.write(to: file)

    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    let id = await store.createDraft(
      session: 1, startedAt: moment,
      durationMilliseconds: 900, targetBundleID: nil)
    #expect(id == nil)
    #expect(try Data(contentsOf: file) == ciphertext)
  }

  @Test("delete-all removes a day that will not decrypt")
  func deleteAllRemovesAnUnreadableDay() async throws {
    let (directory, file) = try unreadableDayOnDisk(at: Date())
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    _ = try await store.deleteAll()
    #expect(FileManager.default.fileExists(atPath: file.path) == false)
  }

  @Test("retention leaves a day it cannot decrypt alone, however old")
  func retentionSparesAnUnreadableDay() async throws {
    let old = Date().addingTimeInterval(-30 * 86_400)
    let (directory, file) = try unreadableDayOnDisk(at: old)
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    _ = try await store.deleteOlderThan(Date().addingTimeInterval(-7 * 86_400))
    #expect(
      FileManager.default.fileExists(atPath: file.path),
      "a transient keychain failure destroyed history nobody asked to delete")
  }

  @Test("retention leaves a day it cannot decrypt alone while it is inside the window")
  func retentionKeepsARecentUnreadableDay() async throws {
    let (directory, file) = try unreadableDayOnDisk(at: Date())
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    _ = try await store.deleteOlderThan(Date().addingTimeInterval(-7 * 86_400))
    #expect(FileManager.default.fileExists(atPath: file.path))
  }

  @Test("deleting one day removes it even when it will not decrypt")
  func deleteDayRemovesAnUnreadableDay() async throws {
    let moment = Date()
    let (directory, file) = try unreadableDayOnDisk(at: moment)
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    let count = try await store.deleteDay(DayFileHistoryStore.dayFormatter.string(from: moment))
    #expect(count == 0)
    #expect(FileManager.default.fileExists(atPath: file.path) == false)
  }

  @Test("a directory that will not list is not read as an empty history")
  func unlistableDirectoryIsNotReadAsEmpty() async throws {
    let moment = Date()
    let (directory, file) = try unreadableDayOnDisk(at: moment)
    let plaintext = try JSONEncoder().encode([DictationRecord]())
    try plaintext.write(to: file)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o300],
      ofItemAtPath: directory.path)
    #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) == nil)

    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    let id = await store.createDraft(
      session: 1, startedAt: moment,
      durationMilliseconds: 900, targetBundleID: nil)
    #expect(id == nil)
    #expect(try Data(contentsOf: file) == plaintext)
  }

  private func unreadableDayOnDisk(at moment: Date) throws -> (directory: URL, file: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    let day = DayFileHistoryStore.dayFormatter.string(from: moment)
    let file = directory.appendingPathComponent("\(day).history")
    try Data("not this cipher's plaintext".utf8).write(to: file)
    return (directory, file)
  }
}

@Suite("A write that fails must not leave the screen disagreeing with the disk")
struct HistoryWriteFailureTests {
  private func unwritableStore() throws -> DayFileHistoryStore {
    let blocker = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    try Data().write(to: blocker)
    return DayFileHistoryStore(
      directory: blocker.appendingPathComponent("History"),
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
  }

  @Test("a draft the store could not write is not left in the history")
  func draftIsRolledBack() async throws {
    let store = try unwritableStore()
    let id = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 1_000, targetBundleID: nil)
    #expect(id == nil)
    #expect(await store.days().isEmpty)
    #expect(await store.fetch(limit: 10).isEmpty)
  }

  @Test("a day whose file will not delete stays visible")
  func failedDayDeletionKeepsTheDay() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    _ = await store.createDraft(
      session: 1, startedAt: Date(),
      durationMilliseconds: 1_000, targetBundleID: nil)
    let day = try #require(await store.days().first).key
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500],
      ofItemAtPath: directory.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path)
    }

    await #expect(throws: HistoryStoreError.self) { try await store.deleteDay(day) }
    #expect(await store.days().count == 1)
  }
}

@Suite("Deletion must not report success it did not achieve")
struct DeletionHonestyTests {
  private func unlistableStore() throws -> (DayFileHistoryStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    let day = DayFileHistoryStore.dayFormatter.string(from: Date())
    let file = directory.appendingPathComponent("\(day).history")
    try JSONEncoder().encode([DictationRecord]()).write(to: file)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o300],
      ofItemAtPath: directory.path)
    return (
      DayFileHistoryStore(
        directory: directory,
        cipher: PassthroughCipher(),
        isRecordingEnabled: { true }), directory
    )
  }

  private func restore(_ directory: URL) {
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
  }

  @Test("delete-all over an unlistable directory fails instead of reporting success")
  func deleteAllRefusesWhenItCannotSee() async throws {
    let (store, directory) = try unlistableStore()
    defer { restore(directory) }
    await #expect(throws: HistoryStoreError.self) { try await store.deleteAll() }
  }

  @Test("deleting one day over an unlistable directory fails too")
  func deleteDayRefusesWhenItCannotSee() async throws {
    let (store, directory) = try unlistableStore()
    defer { restore(directory) }
    let day = DayFileHistoryStore.dayFormatter.string(from: Date())
    await #expect(throws: HistoryStoreError.self) { try await store.deleteDay(day) }
  }

  @Test("retention over an unlistable directory fails instead of reporting success")
  func retentionRefusesWhenItCannotSee() async throws {
    let (store, directory) = try unlistableStore()
    defer { restore(directory) }
    await #expect(throws: HistoryStoreError.self) {
      try await store.deleteOlderThan(Date())
    }
  }
}

@Suite("A failed write leaves memory as it was")
struct WriteFailureRollbackTests {
  private func readOnly<T>(_ directory: URL, _ body: () async throws -> T) async throws -> T {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500],
      ofItemAtPath: directory.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path)
    }
    return try await body()
  }

  private func loadedStore(records: Int = 1, at date: Date = Date())
    async throws -> (DayFileHistoryStore, URL, [UUID])
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID())")
    let store = DayFileHistoryStore(
      directory: directory,
      cipher: PassthroughCipher(),
      isRecordingEnabled: { true })
    var ids: [UUID] = []
    for index in 0..<records {
      let id = await store.createDraft(
        session: index, startedAt: date,
        durationMilliseconds: 1_000,
        targetBundleID: nil)
      ids.append(try #require(id))
    }
    return (store, directory, ids)
  }

  @Test("a state that would not save is not shown as saved")
  func mutationRollsBack() async throws {
    let (store, directory, ids) = try await loadedStore()
    try await readOnly(directory) {
      await store.setState(ids[0], .sent, reason: nil)
    }
    let day = try #require(await store.days().first).key
    #expect(await store.records(on: day).first?.state == .recorded)
  }

  @Test("a record whose deletion would not save stays visible")
  func deletionRollsBack() async throws {
    let (store, directory, ids) = try await loadedStore(records: 2)
    let deleted = try await readOnly(directory) { await store.delete(ids[0]) }
    #expect(deleted == false)
    let day = try #require(await store.days().first).key
    #expect(await store.records(on: day).count == 2)
  }

  @Test("the last record of a day stays when its file will not delete")
  func deletingTheLastRecordRollsBack() async throws {
    let (store, directory, ids) = try await loadedStore()
    let deleted = try await readOnly(directory) { await store.delete(ids[0]) }
    #expect(deleted == false)
    #expect(await store.days().count == 1)
  }

  @Test("a draft that would not save is not counted")
  func draftRollsBack() async throws {
    let (store, directory, _) = try await loadedStore()
    let created = try await readOnly(directory) {
      await store.createDraft(
        session: 9, startedAt: Date(),
        durationMilliseconds: 1_000, targetBundleID: nil)
    }
    #expect(created == nil)
    let day = try #require(await store.days().first).key
    #expect(await store.records(on: day).count == 1)
  }

  @Test("a boundary day that would not save keeps every record")
  func retentionBoundaryRollsBack() async throws {
    let old = Date(timeIntervalSince1970: 1_755_000_000)
    let (store, directory, _) = try await loadedStore(records: 2, at: old)
    try await readOnly(directory) {
      await #expect(throws: HistoryStoreError.self) {
        try await store.deleteOlderThan(old.addingTimeInterval(1))
      }
    }
    let day = try #require(await store.days().first).key
    #expect(await store.records(on: day).count == 2)
  }
}
