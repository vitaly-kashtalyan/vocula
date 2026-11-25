import Foundation
import Synchronization
import Testing
import VoculaKit

@testable import Vocula

private final class DiarizerStub: URLProtocol {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var hangs = false
  private static let seen = Mutex(0)
  nonisolated(unsafe) static var requested = Latch()

  static var requests: Int { seen.withLock { $0 } }

  static func reset() {
    seen.withLock { $0 = 0 }
    status = 200
    hangs = false
    requested = Latch()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.seen.withLock { $0 += 1 }
    Self.requested.open()
    if Self.hangs { return }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": "0"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@MainActor
@Suite("The meetings' own fetch of the speaker model", .serialized, .timeLimit(.minutes(1)))
struct MeetingDiarizerFetcherTests {
  private let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("diarizer-fetch-\(UUID().uuidString)", isDirectory: true)

  private func fetcher(secondCopy: Bool) throws -> MeetingDiarizerFetcher {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    DiarizerStub.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DiarizerStub.self]
    let store = ModelStore(
      directory: root, fileSystem: SystemModelFileSystem(),
      manifest: [ModelManifest.descriptor(for: .speakerDiarizer)])
    return MeetingDiarizerFetcher(
      store: store, configuration: configuration, isSecondCopy: secondCopy)
  }

  @Test func itLooksAtTheDiarizerOnly() {
    #expect(MeetingDiarizerFetcher().store.descriptors.map(\.id) == [.speakerDiarizer])
  }

  @Test func aSecondCopyFetchesNothing() async throws {
    let fetcher = try fetcher(secondCopy: true)
    var ready = false
    fetcher.fetch(log: nil) { ready = true }
    await fetcher.running?.value
    #expect(DiarizerStub.requests == 0)
    #expect(!ready)
  }

  @Test func twoFetchesMakeOneRequest() async throws {
    let fetcher = try fetcher(secondCopy: false)
    DiarizerStub.hangs = true
    fetcher.fetch(log: nil) {}
    fetcher.fetch(log: nil) {}
    await DiarizerStub.requested.wait()
    fetcher.fetch(log: nil) {}
    #expect(DiarizerStub.requests == 1)
    #expect(fetcher.running != nil)
  }

  @Test func aFailedFetchIsDiagnosed() async throws {
    let fetcher = try fetcher(secondCopy: false)
    DiarizerStub.status = 500
    let log = DiagnosticLog(fileURL: root.appendingPathComponent("diagnostics.json"))
    var ready = false
    fetcher.fetch(log: log) { ready = true }
    await fetcher.running?.value
    #expect(!ready)
    let lines = log.recent(20).filter { $0.kind == "model.download" }.map(\.detail)
    #expect(!lines.isEmpty)
    #expect(lines.allSatisfy { $0.contains("model=speakerDiarizer") })
  }
}
