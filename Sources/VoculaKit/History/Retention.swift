import Foundation

public enum HistoryRetention {
  public static let days = 365
}

public struct RetentionSweeper: Sendable {
  private let store: HistoryStoring
  private let days: Int
  private let diagnosticLog: DiagnosticLog?
  private let calendar: Calendar

  public init(
    store: HistoryStoring, days: Int = HistoryRetention.days,
    diagnosticLog: DiagnosticLog? = nil,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) {
    self.store = store
    self.days = days
    self.diagnosticLog = diagnosticLog
    self.calendar = calendar
  }

  @discardableResult
  public func sweep(now: Date = Date()) async -> Int {
    let cutoff =
      calendar.date(byAdding: .day, value: -days, to: now)
      ?? now.addingTimeInterval(-Double(days) * 86_400)
    do {
      return try await store.deleteOlderThan(cutoff)
    } catch {
      diagnosticLog?.record("history.retentionFailed", "")
      return 0
    }
  }
}
