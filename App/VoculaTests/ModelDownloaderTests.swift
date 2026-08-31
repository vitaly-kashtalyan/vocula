import CryptoKit
import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

private final class StubProtocol: URLProtocol {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var body = Data()
  nonisolated(unsafe) static var delay: TimeInterval = 0
  nonisolated(unsafe) static var failure: NSError?
  nonisolated(unsafe) static var hangs = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if Self.delay > 0 { Thread.sleep(forTimeInterval: Self.delay) }
    if let failure = Self.failure {
      client?.urlProtocol(self, didFailWithError: failure)
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": "\(Self.body.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    // A transfer that never finishes: the only way a cancellation can be the
    // thing that ends the task rather than racing its completion.
    if Self.hangs { return }
    if !Self.body.isEmpty { client?.urlProtocol(self, didLoad: Self.body) }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func digest(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private let payload = Data((0..<64_000).map { UInt8($0 % 251) })

private func fields(_ detail: String) -> Set<String> {
  Set(detail.split(separator: " ").map(String.init))
}

private func descriptor(sha256: String, byteSize: Int64) -> ModelDescriptor {
  ModelDescriptor(
    id: .largeV3Turbo, family: .whisper, fileName: "test-model.bin",
    remoteURL: URL(string: "https://test.invalid/model.bin")!,
    sha256: sha256, byteSize: byteSize,
    version: "test", licence: "test", displayName: "Test model")
}

@MainActor
@Suite("Model downloader", .serialized)
struct ModelDownloaderTests {
  private func makeDownloader(pinned: ModelDescriptor) -> (ModelDownloader, ModelStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ModelStore(
      directory: directory, fileSystem: SystemModelFileSystem(),
      manifest: [pinned])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let downloader = ModelDownloader(
      store: store, requiredModels: { [.largeV3Turbo] },
      configuration: configuration)
    return (downloader, store, directory)
  }

  @Test("a download that matches its pin lands in the models directory, ready")
  func successfulDownloadInstalls() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    try await downloader.download(.largeV3Turbo)

    let destination = store.url(for: .largeV3Turbo)
    #expect(FileManager.default.fileExists(atPath: destination.path))
    #expect(try Data(contentsOf: destination) == payload)
    #expect(store.status(of: .largeV3Turbo) == .ready)
    #expect(downloader.fraction[.largeV3Turbo] == 1)
  }

  @Test("the installed file is owner-only")
  func installedFileIsOwnerOnly() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    try await downloader.download(.largeV3Turbo)

    let attributes = try FileManager.default
      .attributesOfItem(atPath: store.url(for: .largeV3Turbo).path)
    #expect(attributes[.posixPermissions] as? NSNumber == 0o600)
  }

  @Test("a TLS refusal reaches the diagnostic log with its own status code")
  func tlsFailureIsDiagnosed() async throws {
    StubProtocol.status = 200
    StubProtocol.body = Data()
    StubProtocol.failure = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
      userInfo: ["_kCFStreamErrorCodeKey": -9836])
    defer { StubProtocol.failure = nil }
    let (downloader, _, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }
    var lines: [(String, String)] = []
    downloader.diagnose = { lines.append(($0, $1)) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }

    #expect(lines.count == 1)
    let (kind, detail) = try #require(lines.first)
    #expect(kind == "model.download")
    #expect(
      fields(detail) == [
        "outcome=failed", "model=largeV3Turbo", "pct=0",
        "domain=\(NSURLErrorDomain)", "code=-1200", "tls=-9836",
      ])
    #expect(
      DiagnosticLog.redact(detail) == detail,
      "a field the allow-list does not know reaches the file as <dropped>")
  }

  @Test("an HTTP status is diagnosed as itself, with no TLS status invented")
  func httpFailureIsDiagnosed() async throws {
    StubProtocol.status = 404
    StubProtocol.body = Data("<html>not found</html>".utf8)
    let (downloader, _, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }
    var lines: [(String, String)] = []
    downloader.diagnose = { lines.append(($0, $1)) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }

    let detail = try #require(lines.first?.1)
    let seen = fields(detail)
    #expect(seen.contains("outcome=failed"))
    #expect(seen.contains("domain=http"))
    #expect(seen.contains("code=404"))
    #expect(!seen.contains { $0.hasPrefix("tls=") })
    #expect(DiagnosticLog.redact(detail) == detail)
  }

  @Test("a transport failure carrying no TLS status omits the field")
  func transportFailureWithoutTLSStatus() async throws {
    StubProtocol.failure = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [:])
    defer { StubProtocol.failure = nil }
    let (downloader, _, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }
    var lines: [(String, String)] = []
    downloader.diagnose = { lines.append(($0, $1)) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }

    let seen = fields(try #require(lines.first?.1))
    #expect(seen.contains("code=\(NSURLErrorTimedOut)"))
    #expect(!seen.contains { $0.hasPrefix("tls=") })
  }

  @Test("a checksum mismatch is its own outcome, not a transport failure")
  func checksumMismatchIsDiagnosed() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    let (downloader, _, directory) = makeDownloader(
      pinned: descriptor(
        sha256: digest(Data("something else".utf8)),
        byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }
    var lines: [(String, String)] = []
    downloader.diagnose = { lines.append(($0, $1)) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }

    let detail = try #require(lines.first?.1)
    let seen = fields(detail)
    #expect(seen.contains("outcome=checksum"))
    #expect(!seen.contains { $0.hasPrefix("domain=") })
    #expect(DiagnosticLog.redact(detail) == detail)
  }

  @Test("a cancelled download is not written to the log")
  func cancellationIsNotDiagnosed() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    StubProtocol.hangs = true
    defer { StubProtocol.hangs = false }
    let (downloader, _, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }
    var lines: [(String, String)] = []
    downloader.diagnose = { lines.append(($0, $1)) }

    let transfer = Task { try await downloader.download(.largeV3Turbo) }
    var yields = 0
    while downloader.isDownloading == false, yields < 10_000 {
      await Task.yield()
      yields += 1
    }
    #expect(downloader.isDownloading, "the transfer never started")
    // `isDownloading` is raised before the task exists, and `cancel()` is a
    // silent no-op until it does, so the ask has to be repeated.
    var attempts = 0
    while downloader.isDownloading, attempts < 10_000 {
      downloader.cancel()
      await Task.yield()
      attempts += 1
    }

    await #expect(throws: CancellationError.self) { try await transfer.value }
    #expect(lines.isEmpty, "cancelling is routine, and the log records the anomaly")
  }

  @Test("a refusal for want of disk space says so, rather than saying nothing")
  func noSpaceIsDiagnosed() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    let (downloader, _, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: .max))
    defer { try? FileManager.default.removeItem(at: directory) }
    var lines: [(String, String)] = []
    downloader.diagnose = { lines.append(($0, $1)) }

    await downloader.downloadOne(.largeV3Turbo)

    let detail = try #require(lines.first?.1)
    #expect(fields(detail).contains("outcome=noSpace"))
    #expect(DiagnosticLog.redact(detail) == detail)
    #expect(downloader.lastError != nil)
  }

  @Test("an HTTP error is a transport failure, and nothing is installed")
  func httpErrorInstallsNothing() async throws {
    StubProtocol.status = 404
    StubProtocol.body = Data("<html>not found</html>".utf8)
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }
    #expect(FileManager.default.fileExists(atPath: store.url(for: .largeV3Turbo).path) == false)
    #expect(store.status(of: .largeV3Turbo) == .missing)
  }

  @Test("a body that does not match the pin is deleted, not left behind")
  func checksumMismatchDeletesTheFile() async throws {
    StubProtocol.status = 200
    StubProtocol.body = Data(payload.reversed())
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }
    #expect(FileManager.default.fileExists(atPath: store.url(for: .largeV3Turbo).path) == false)
  }

  @Test("a truncated body is removed too")
  func truncatedBodyIsRemoved() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload.prefix(1000)
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }
    #expect(FileManager.default.fileExists(atPath: store.url(for: .largeV3Turbo).path) == false)
  }

  @Test("a failed download leaves no state that blocks the next one")
  func aFailureDoesNotStrandTheDownloader() async throws {
    StubProtocol.status = 500
    StubProtocol.body = Data()
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: ModelDownloadError.self) {
      try await downloader.download(.largeV3Turbo)
    }
    #expect(downloader.isDownloading == false)

    StubProtocol.status = 200
    StubProtocol.body = payload
    try await downloader.download(.largeV3Turbo)
    #expect(store.status(of: .largeV3Turbo) == .ready)
  }

  @Test("a second download request while one is in flight is refused, not a crash")
  func aSecondRequestWhileDownloadingIsRefused() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    StubProtocol.delay = 0.5
    defer { StubProtocol.delay = 0 }
    let (downloader, store, directory) = makeDownloader(
      pinned: descriptor(sha256: digest(payload), byteSize: Int64(payload.count)))
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = Task { try await downloader.download(.largeV3Turbo) }
    var yields = 0
    while downloader.isDownloading == false, yields < 10_000 {
      await Task.yield()
      yields += 1
    }
    #expect(downloader.isDownloading, "the first transfer never started")

    try await downloader.download(.largeV3Turbo)

    try await first.value
    #expect(store.status(of: .largeV3Turbo) == .ready)
    #expect(try Data(contentsOf: store.url(for: .largeV3Turbo)) == payload)
  }
}

@MainActor
@Suite("Resume data survives the process, and a dead one does not strand it", .serialized)
struct ResumeDataTests {
  private func makeDownloader() -> (ModelDownloader, ModelStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ModelStore(
      directory: directory, fileSystem: SystemModelFileSystem(),
      manifest: [descriptor(sha256: digest(payload), byteSize: Int64(payload.count))])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return (
      ModelDownloader(
        store: store, requiredModels: { [.largeV3Turbo] },
        configuration: configuration), store, directory
    )
  }

  private func resumeURL(in directory: URL) -> URL {
    directory.appendingPathComponent("\(ModelID.largeV3Turbo.rawValue).resume")
  }

  @Test("a download that finishes leaves no resume file behind")
  func successLeavesNothing() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    let (downloader, store, directory) = makeDownloader()
    defer { try? FileManager.default.removeItem(at: directory) }

    try await downloader.download(.largeV3Turbo)
    #expect(store.status(of: .largeV3Turbo) == .ready)
    #expect(FileManager.default.fileExists(atPath: resumeURL(in: directory).path) == false)
  }

  @Test("resume data pointing at a file that is gone does not block the download")
  func staleResumeDataStartsOver() async throws {
    StubProtocol.status = 200
    StubProtocol.body = payload
    let (downloader, store, directory) = makeDownloader()
    defer { try? FileManager.default.removeItem(at: directory) }

    let stale: [String: Any] = [
      "NSURLSessionResumeInfoVersion": 2,
      "NSURLSessionResumeCurrentRequest":
        Data(base64Encoded: "YnBsaXN0MDA=") ?? Data(),
      "NSURLSessionResumeInfoTempFileName": "CFNetworkDownload_gone.tmp",
      "NSURLSessionResumeInfoLocalPath":
        NSTemporaryDirectory() + "CFNetworkDownload_gone.tmp",
      "NSURLSessionDownloadURL": "https://test.invalid/model.bin",
      "NSURLSessionResumeBytesReceived": 1024,
    ]
    let blob = try PropertyListSerialization.data(
      fromPropertyList: stale,
      format: .binary, options: 0)
    try blob.write(to: resumeURL(in: directory))

    try await downloader.download(.largeV3Turbo)
    #expect(store.status(of: .largeV3Turbo) == .ready)
    #expect(FileManager.default.fileExists(atPath: resumeURL(in: directory).path) == false)
  }
}
