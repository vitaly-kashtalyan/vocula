import Foundation

public protocol HistoryStoring: SessionRecording {
  func fetch(limit: Int) async -> [DictationRecord]
  func days() async -> [HistoryDay]
  func records(on day: String) async -> [DictationRecord]
  @discardableResult
  func deleteDay(_ day: String) async throws -> Int
  @discardableResult
  func delete(_ id: UUID) async -> Bool
  @discardableResult
  func deleteAll() async throws -> Int
  @discardableResult
  func deleteOlderThan(_ date: Date) async throws -> Int
}

public enum HistoryStoreError: Error, Equatable, Sendable {
  case writeFailed
}
