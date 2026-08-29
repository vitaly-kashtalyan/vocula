import CryptoKit
import Foundation
import Testing

@testable import Vocula

@Suite("System model file system")
struct SystemModelFileSystemTests {
  private func temporaryFile(_ bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try bytes.write(to: url)
    return url
  }

  @Test("a file larger than the read chunk hashes the same as a one-shot digest")
  func streamedDigestCrossesTheChunkBoundary() throws {
    var bytes = Data(count: 10 * 1024 * 1024)
    for index in stride(from: 0, to: bytes.count, by: 7) {
      bytes[index] = UInt8(index % 251)
    }
    let url = try temporaryFile(bytes)
    defer { try? FileManager.default.removeItem(at: url) }

    let oneShot = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    #expect(try SystemModelFileSystem().sha256(of: url) == oneShot)
  }

  @Test("an empty file hashes to the digest of nothing, and does not hang")
  func emptyFileTerminates() throws {
    let url = try temporaryFile(Data())
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(
      try SystemModelFileSystem().sha256(of: url)
        == SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined())
  }

  @Test("the digest is 64 lowercase hex characters")
  func digestSpelling() throws {
    let url = try temporaryFile(Data([0x00, 0x0f, 0xff]))
    defer { try? FileManager.default.removeItem(at: url) }
    let digest = try SystemModelFileSystem().sha256(of: url)
    #expect(digest.count == 64)
    #expect(digest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }

  @Test("a missing file throws rather than reporting a digest")
  func missingFileThrows() {
    let absent = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    #expect(throws: (any Error).self) {
      try SystemModelFileSystem().sha256(of: absent)
    }
  }

  @Test("size and existence answer for a real file, and for one that is not there")
  func sizeAndExistence() throws {
    let url = try temporaryFile(Data(count: 1234))
    defer { try? FileManager.default.removeItem(at: url) }
    let fileSystem = SystemModelFileSystem()
    #expect(fileSystem.fileExists(at: url) == true)
    #expect(fileSystem.size(of: url) == 1234)

    let absent = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    #expect(fileSystem.fileExists(at: absent) == false)
    #expect(fileSystem.size(of: absent) == nil)
  }

  @Test("the volume reports a capacity")
  func capacityIsAnswerable() {
    let capacity = SystemModelFileSystem()
      .availableCapacity(at: FileManager.default.temporaryDirectory)
    #expect(capacity != nil)
    #expect((capacity ?? 0) > 0)
  }
}
