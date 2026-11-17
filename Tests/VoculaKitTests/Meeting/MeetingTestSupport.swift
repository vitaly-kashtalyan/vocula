import Foundation

@testable import VoculaKit

final class MarkingCipher: HistoryCipher, @unchecked Sendable {
  static let mark = Data("SEALED".utf8)
  struct NotSealed: Error {}
  struct Refused: Error {}

  private let lock = NSLock()
  private var failures = 0

  init() {}

  func failNext(_ seals: Int) {
    lock.withLock { failures = seals }
  }

  func seal(_ plaintext: Data) throws -> Data {
    let fail = lock.withLock {
      defer { failures = max(0, failures - 1) }
      return failures > 0
    }
    if fail { throw Refused() }
    return Self.mark + plaintext
  }

  func open(_ ciphertext: Data) throws -> Data {
    guard ciphertext.starts(with: Self.mark) else { throw NotSealed() }
    return ciphertext.dropFirst(Self.mark.count)
  }
}

func meetingTemporaryDirectory() -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("vocula-meeting-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func plant(header: MeetingHeader, chunks: [String: Data], in root: URL) throws {
  let directory = root.appendingPathComponent(header.id.uuidString, isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory.appendingPathComponent("audio"), withIntermediateDirectories: true)
  let sealed = MarkingCipher.mark + (try JSONEncoder().encode(header))
  try sealed.write(to: directory.appendingPathComponent("header.sealed"))
  for (path, bytes) in chunks {
    try bytes.write(to: directory.appendingPathComponent(path))
  }
}
