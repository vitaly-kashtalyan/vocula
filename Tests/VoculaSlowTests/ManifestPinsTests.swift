import CryptoKit
import Foundation
import Testing
import VoculaKit

private let modelDirectory = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("app.vocula.mac/Models")

private let installed = ModelManifest.current.filter {
  FileManager.default.fileExists(
    atPath: modelDirectory.appendingPathComponent($0.fileName).path)
}

private func sha256(of url: URL) throws -> String {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  var hasher = SHA256()
  while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
    hasher.update(data: chunk)
  }
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

@Suite("Manifest pins", .serialized, .enabled(if: !installed.isEmpty))
struct ManifestPinsTests {
  @Test(
    "each installed model matches the size and digest pinned for it",
    arguments: installed)
  func pinsMatchTheRealFile(model: ModelDescriptor) throws {
    let url = modelDirectory.appendingPathComponent(model.fileName)
    let size = try #require(
      try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
    #expect(size == model.byteSize)
    #expect(try sha256(of: url) == model.sha256)
  }
}

extension ModelDescriptor: CustomTestStringConvertible {
  public var testDescription: String { displayName }
}
