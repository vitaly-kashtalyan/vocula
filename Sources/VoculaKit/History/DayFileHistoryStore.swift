import Foundation

public actor DayFileHistoryStore: HistoryStoring {
  private let directory: URL
  private let cipher: HistoryCipher
  private let isRecordingEnabled: @Sendable () -> Bool
  private var diagnosticLog: DiagnosticLog?
  private var recordsByDay: [String: [DictationRecord]] = [:]
  private var unreadableDays: Set<String> = []
  private var directoryUnreadable = false
  private var loaded = false

  public init(
    directory: URL, cipher: HistoryCipher,
    isRecordingEnabled: @escaping @Sendable () -> Bool,
    diagnosticLog: DiagnosticLog? = nil
  ) {
    self.directory = directory
    self.cipher = cipher
    self.isRecordingEnabled = isRecordingEnabled
    self.diagnosticLog = diagnosticLog
  }

  public func attach(diagnosticLog: DiagnosticLog) { self.diagnosticLog = diagnosticLog }

  static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private func dayKey(_ date: Date) -> String { Self.dayFormatter.string(from: date) }
  private func url(forDay day: String) -> URL {
    directory.appendingPathComponent("\(day).history")
  }

  private func loadIfNeeded() {
    guard !loaded else { return }
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    else {
      directoryUnreadable = true
      diagnosticLog?.record("history.readFailed", "")
      return
    }
    directoryUnreadable = false
    loaded = true
    for name in names where name.hasSuffix(".history") {
      let day = String(name.dropLast(".history".count))
      guard let blob = try? Data(contentsOf: url(forDay: day)),
        let json = try? cipher.open(blob),
        let records = try? JSONDecoder().decode([DictationRecord].self, from: json)
      else {
        unreadableDays.insert(day)
        diagnosticLog?.record("history.readFailed", "")
        continue
      }
      recordsByDay[day] = records
    }
  }

  @discardableResult
  private func write(day: String) -> Bool {
    guard !unreadableDays.contains(day), !directoryUnreadable else {
      diagnosticLog?.record("history.writeFailed", "")
      return false
    }
    guard let records = recordsByDay[day] else { return remove(day: day) }
    guard records.isEmpty == false else { return remove(day: day) }
    do {
      let json = try JSONEncoder().encode(records)
      try cipher.seal(json).write(to: url(forDay: day), options: .atomic)
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url(forDay: day).path)
      return true
    } catch {
      diagnosticLog?.record("history.writeFailed", "")
      return false
    }
  }

  private func remove(day: String) -> Bool {
    let path = url(forDay: day)
    if FileManager.default.fileExists(atPath: path.path) {
      do { try FileManager.default.removeItem(at: path) } catch {
        diagnosticLog?.record("history.writeFailed", "")
        return false
      }
    }
    recordsByDay[day] = nil
    unreadableDays.remove(day)
    return true
  }

  private func locate(_ id: UUID) -> (day: String, index: Int)? {
    for (day, records) in recordsByDay {
      if let index = records.firstIndex(where: { $0.id == id }) { return (day, index) }
    }
    return nil
  }

  private func mutate(_ id: UUID, _ change: (inout DictationRecord) -> Void) {
    loadIfNeeded()
    guard let (day, index) = locate(id) else { return }
    let previous = recordsByDay[day]
    change(&recordsByDay[day]![index])
    recordsByDay[day]![index].updatedAt = Date()
    if !write(day: day) { recordsByDay[day] = previous }
  }

  public func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int,
    targetBundleID: String?, modelID: String? = nil
  ) async -> UUID? {
    guard isRecordingEnabled() else { return nil }
    loadIfNeeded()
    let record = DictationRecord(
      id: UUID(), session: session, createdAt: startedAt, updatedAt: startedAt,
      owner: nil, state: .recorded, reason: nil,
      rawText: nil, finalText: nil, language: nil,
      durationMilliseconds: durationMilliseconds, targetBundleID: targetBundleID,
      metrics: nil, truncated: false, modelID: modelID)
    let day = dayKey(startedAt)
    recordsByDay[day, default: []].append(record)
    guard write(day: day) else {
      rollBack(day: day)
      return nil
    }
    return record.id
  }

  public func markTruncated(_ id: UUID) async { mutate(id) { $0.truncated = true } }
  public func attachMetrics(_ id: UUID, _ metrics: SpeechMetrics) async {
    mutate(id) { $0.metrics = metrics }
  }
  public func attachRawText(_ id: UUID, _ text: String, language: String) async {
    mutate(id) {
      $0.rawText = text
      $0.language = language
    }
  }
  public func attachFinalText(_ id: UUID, _ text: String) async {
    mutate(id) { $0.finalText = text }
  }
  public func setState(_ id: UUID, _ state: SessionState, reason: String?) async {
    mutate(id) {
      $0.state = state
      $0.reason = reason
    }
  }

  public func days() async -> [HistoryDay] {
    loadIfNeeded()
    return
      recordsByDay
      .map { day, records in
        let inserted = records.filter { $0.state == .sent }
        return HistoryDay(
          key: day, count: records.count,
          words: records.reduce(0) { $0 + HistoryWords.count(in: $1.finalText) },
          insertedCharacters: inserted.reduce(0) {
            $0 + HistoryWords.characters(in: $1.finalText)
          })
      }
      .sorted { $0.key > $1.key }
  }

  public func records(on day: String) async -> [DictationRecord] {
    loadIfNeeded()
    return (recordsByDay[day] ?? []).sorted { $0.createdAt > $1.createdAt }
  }

  @discardableResult
  public func deleteDay(_ day: String) async throws -> Int {
    loadIfNeeded()
    guard !directoryUnreadable else { throw HistoryStoreError.writeFailed }
    guard recordsByDay[day] != nil || unreadableDays.contains(day) else { return 0 }
    let count = recordsByDay[day]?.count ?? 0
    guard remove(day: day) else { throw HistoryStoreError.writeFailed }
    return count
  }

  public func fetch(limit: Int) async -> [DictationRecord] {
    loadIfNeeded()
    return Array(
      recordsByDay.values.flatMap { $0 }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(limit))
  }

  @discardableResult
  public func delete(_ id: UUID) async -> Bool {
    loadIfNeeded()
    guard let (day, index) = locate(id) else { return false }
    let record = recordsByDay[day]!.remove(at: index)
    guard write(day: day) else {
      recordsByDay[day, default: []].insert(record, at: index)
      return false
    }
    return true
  }

  private func rollBack(day: String) {
    recordsByDay[day]?.removeLast()
    if recordsByDay[day]?.isEmpty == true { recordsByDay[day] = nil }
  }

  @discardableResult
  public func deleteAll() async throws -> Int {
    loadIfNeeded()
    guard !directoryUnreadable else { throw HistoryStoreError.writeFailed }
    var removed = 0
    for day in Set(recordsByDay.keys).union(unreadableDays) {
      removed += recordsByDay[day]?.count ?? 0
      guard remove(day: day) else { throw HistoryStoreError.writeFailed }
    }
    return removed
  }

  @discardableResult
  public func deleteOlderThan(_ date: Date) async throws -> Int {
    loadIfNeeded()
    guard !directoryUnreadable else { throw HistoryStoreError.writeFailed }
    var removed = 0
    for day in recordsByDay.keys where day < dayKey(date) {
      removed += recordsByDay[day]?.count ?? 0
      guard remove(day: day) else { throw HistoryStoreError.writeFailed }
    }
    let boundary = dayKey(date)
    if let records = recordsByDay[boundary] {
      let kept = records.filter { $0.createdAt >= date }
      if kept.count != records.count {
        recordsByDay[boundary] = kept
        guard write(day: boundary) else {
          recordsByDay[boundary] = records
          throw HistoryStoreError.writeFailed
        }
        removed += records.count - kept.count
      }
    }
    return removed
  }

}
