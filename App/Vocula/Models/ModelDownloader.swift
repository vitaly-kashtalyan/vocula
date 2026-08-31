import Foundation
import VoculaKit

enum ModelDownloadError: LocalizedError {
  case notEnoughSpace(SpaceVerdict)
  case capacityUnavailable
  case checksumMismatch(displayName: String)
  case transport(Error)

  var errorDescription: String? {
    switch self {
    case .notEnoughSpace(let verdict):
      return String(
        localized: "models.download.notStarted",
        defaultValue: "Download not started: \(verdict.humanReadable).",
        comment: "The argument is a sentence about free disk space, already localized.")
    case .capacityUnavailable:
      return String(
        localized: "models.download.capacityUnknown",
        defaultValue: "Download not started: free disk space could not be determined. Try again.",
        comment: "Shown when macOS will not report how much room is left.")
    case .checksumMismatch(let displayName):
      return String(
        localized: "models.download.checksumMismatch",
        defaultValue:
          "The file for “\(displayName)” did not match its checksum. It has been deleted; try again.",
        comment: "The argument is a model's display name. Keep the typographic quotes.")
    case .transport(let error):
      return String(
        localized: "models.downloadFailed",
        defaultValue: "Download failed: \(error.localizedDescription)",
        comment: "The argument is the system's own error message, already localized by macOS.")
    }
  }
}

@MainActor
final class ModelDownloader: NSObject, ObservableObject {
  @Published private(set) var fraction: [ModelID: Double] = [:]
  @Published private(set) var lastError: String?
  @Published private(set) var isDownloading = false

  let store: ModelStore
  var diagnose: ((String, String) -> Void)?
  private let requiredModels: @Sendable () -> [ModelID]
  private var task: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<URL, Error>?
  private var current: ModelID?
  private var session: URLSession!

  init(
    store: ModelStore, requiredModels: @escaping @Sendable () -> [ModelID],
    configuration: URLSessionConfiguration = .default
  ) {
    self.store = store
    self.requiredModels = requiredModels
    super.init()
    self.session = URLSession(
      configuration: configuration, delegate: self,
      delegateQueue: nil)
  }

  private func resumeURL(for id: ModelID) -> URL {
    store.directory.appendingPathComponent("\(id.rawValue).resume")
  }

  private func storedResumeData(for id: ModelID) -> Data? {
    try? Data(contentsOf: resumeURL(for: id))
  }

  private func keep(resumeData: Data, for id: ModelID) {
    try? resumeData.write(to: resumeURL(for: id), options: .atomic)
  }

  private func discardResumeData(for id: ModelID) {
    try? FileManager.default.removeItem(at: resumeURL(for: id))
  }

  private func spaceRefusal(for ids: [ModelID]) async -> String? {
    let store = self.store
    let verdict = await Task.detached(priority: .utility) {
      store.spaceVerdict(for: ids)
    }.value
    switch verdict {
    case .enough:
      return nil
    case .short(let byBytes):
      diagnose?(
        "model.download", ["outcome=noSpace", "bytes=\(byBytes)"].joined(separator: " "))
      return ModelDownloadError.notEnoughSpace(verdict).errorDescription
    case .unknown:
      diagnose?("model.download", "outcome=noCapacity")
      return ModelDownloadError.capacityUnavailable.errorDescription
    }
  }

  func downloadMissing() async {
    lastError = nil
    await refreshStatuses()
    let ids = requiredModels()
    if let refusal = await spaceRefusal(for: ids) {
      lastError = refusal
      return
    }
    for id in ids where statuses[id] != .ready {
      do { try await download(id) } catch is CancellationError {
        await refreshStatuses()
        return
      } catch {
        lastError = error.localizedDescription
        await refreshStatuses()
        return
      }
    }
    await refreshStatuses()
    lastError = nil
  }

  func downloadOne(_ id: ModelID) async {
    lastError = nil
    await refreshStatuses()
    guard statuses[id] != .ready else { return }
    if let refusal = await spaceRefusal(for: [id]) {
      lastError = refusal
      return
    }
    do { try await download(id) } catch is CancellationError {
      await refreshStatuses()
      return
    } catch {
      lastError = error.localizedDescription
      await refreshStatuses()
      return
    }
    await refreshStatuses()
    lastError = nil
  }

  func download(_ id: ModelID) async throws {
    do {
      try await perform(id)
    } catch {
      if !(error is CancellationError) {
        diagnose?("model.download", failureDetail(error, for: id))
      }
      throw error
    }
  }

  private func failureDetail(_ error: Error, for id: ModelID) -> String {
    var outcome = "failed"
    var cause: [String] = []
    switch error as? ModelDownloadError {
    case .checksumMismatch:
      outcome = "checksum"
    case .transport(let underlying):
      let transport = underlying as NSError
      cause = ["domain=\(transport.domain)", "code=\(transport.code)"]
      // CFNetwork keeps the handshake's own OSStatus only here; every value of
      // it collapses into the same `localizedDescription`.
      if let status = transport.userInfo["_kCFStreamErrorCodeKey"] as? Int, status != 0 {
        cause.append("tls=\(status)")
      }
    case .notEnoughSpace, .capacityUnavailable, .none:
      break
    }
    let percent = Int((fraction[id] ?? 0) * 100)
    return (["outcome=\(outcome)", "model=\(id.rawValue)", "pct=\(percent)"] + cause)
      .joined(separator: " ")
  }

  private func perform(_ id: ModelID) async throws {
    guard !isDownloading else { return }
    let store = self.store
    isDownloading = true
    defer {
      isDownloading = false
      if current == id {
        current = nil
        task = nil
        continuation = nil
      }
    }
    let model = store.descriptor(for: id)
    let destination = store.url(for: id)
    let resumeData = storedResumeData(for: id)
    await Task.detached(priority: .utility) {
      try? FileManager.default.removeItem(at: destination)
    }.value

    current = id
    fraction[id] = 0
    let temporary: URL
    do {
      temporary = try await startTask(model, resumingWith: resumeData)
    } catch is ModelDownloadError where resumeData != nil {
      discardResumeData(for: id)
      temporary = try await startTask(model, resumingWith: nil)
    }
    discardResumeData(for: id)
    defer {
      Task.detached(priority: .utility) {
        try? FileManager.default.removeItem(at: temporary)
      }
    }
    try await Task.detached(priority: .utility) {
      try FileManager.default.moveItem(at: temporary, to: destination)
    }.value
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: destination.path)

    let verified = await Task.detached(priority: .utility) {
      store.status(of: id) == .ready
    }.value
    guard verified else {
      try? FileManager.default.removeItem(at: destination)
      throw ModelDownloadError.checksumMismatch(displayName: model.displayName)
    }
    fraction[id] = 1
    current = nil
    task = nil
  }

  private func startTask(
    _ model: ModelDescriptor,
    resumingWith resumeData: Data?
  ) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let task =
        resumeData.map { session.downloadTask(withResumeData: $0) }
        ?? session.downloadTask(with: model.remoteURL)
      self.task = task
      task.resume()
    }
  }

  func cancel() {
    guard let task else { return }
    let id = current
    task.cancel(byProducingResumeData: { data in
      Task { @MainActor in
        if let id, let data { self.keep(resumeData: data, for: id) }
        self.continuation?.resume(throwing: CancellationError())
        self.continuation = nil
        self.current = nil
        self.task = nil
      }
    })
  }

  func shutdown() { session.invalidateAndCancel() }

  @Published private(set) var statuses: [ModelID: ModelStatus] = [:]

  var allReady: Bool {
    let ids = requiredModels()
    return !ids.isEmpty && ids.allSatisfy { statuses[$0] == .ready }
  }

  func refreshStatuses() async {
    let store = self.store
    let computed = await Task.detached(priority: .utility) {
      var result: [ModelID: ModelStatus] = [:]
      for model in store.descriptors { result[model.id] = store.status(of: model.id) }
      return result
    }.value
    statuses = computed
  }
}

extension ModelDownloader: URLSessionDownloadDelegate {
  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    if let response = downloadTask.response as? HTTPURLResponse,
      !(200..<300).contains(response.statusCode)
    {
      Task { @MainActor in
        self.continuation?.resume(
          throwing: ModelDownloadError.transport(
            NSError(
              domain: "http", code: response.statusCode,
              userInfo: [
                NSLocalizedDescriptionKey:
                  String(
                    localized: "models.download.httpStatus",
                    defaultValue: "the server answered \(response.statusCode)",
                    comment:
                      "Reason inside a download failure; the argument is an HTTP status code. Lower case: it is joined into a longer sentence."
                  )
              ])))
        self.continuation = nil
      }
      return
    }
    let staged = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    do {
      try FileManager.default.moveItem(at: location, to: staged)
      Task { @MainActor in
        self.continuation?.resume(returning: staged)
        self.continuation = nil
      }
    } catch {
      Task { @MainActor in
        self.continuation?.resume(throwing: ModelDownloadError.transport(error))
        self.continuation = nil
      }
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    Task { @MainActor in
      guard let id = self.current else { return }
      guard Int(value * 100) != Int((self.fraction[id] ?? -1) * 100) else { return }
      self.fraction[id] = value
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    if (error as NSError).code == NSURLErrorCancelled { return }
    let data =
      (error as NSError)
      .userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    Task { @MainActor in
      if let id = self.current, let data { self.keep(resumeData: data, for: id) }
      self.continuation?.resume(throwing: ModelDownloadError.transport(error))
      self.continuation = nil
    }
  }
}
