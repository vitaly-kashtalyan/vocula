import Foundation

public enum MeetingStoreError: Error, Equatable, Sendable { case failed(step: String, code: Int) }

public actor MeetingStore {
  private static let sampleRate = 16_000

  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public func begin(_ header: MeetingHeader, cipher: any HistoryCipher, recovering: Bool) throws
    -> Int
  {
    let recovered = recovering ? recoverInterrupted(cipher: cipher) : 0
    try makeDirectory(directory)
    try makeDirectory(meetingDirectory(header.id))
    try makeDirectory(audioDirectory(header.id))
    try update(header, cipher: cipher)
    return recovered
  }

  public func write(_ chunk: MeetingChunk, of meeting: UUID, cipher: any HistoryCipher) throws {
    let name = "\(chunk.track.rawValue)-\(String(format: "%06d", chunk.sequence)).sealed"
    try seal(
      chunk.encoded(), cipher: cipher,
      to: audioDirectory(meeting).appendingPathComponent(name))
  }

  public func update(_ header: MeetingHeader, cipher: any HistoryCipher) throws {
    let plaintext: Data
    do { plaintext = try JSONEncoder().encode(header) } catch {
      throw MeetingStoreError.failed(step: "encode", code: 0)
    }
    try seal(
      plaintext, cipher: cipher,
      to: headerURL(header.id))
  }

  public func header(of meeting: UUID, cipher: any HistoryCipher) -> MeetingHeader? {
    Self.readHeader(headerURL(meeting), cipher: cipher)
  }

  public func timeline(of meeting: UUID, track: MeetingTrack, cipher: any HistoryCipher) -> [Int16]
  {
    guard let header = header(of: meeting, cipher: cipher), let end = header.end else { return [] }
    let seconds = max(0, end.timeIntervalSince(header.startedAt)).rounded(.up) + 1
    let limit = Int(min(seconds, 86_400)) * Self.sampleRate
    let chunks = Self.chunkURLs(of: track, in: audioDirectory(meeting)).compactMap {
      Self.readChunk($0, cipher: cipher)
    }
    return MeetingTimeline.samples(chunks, anchor: header.anchor, limit: limit)
  }

  private func recoverInterrupted(cipher: any HistoryCipher) -> Int {
    let manager = FileManager.default
    let children = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
    var recovered = 0
    for child in children {
      guard let id = UUID(uuidString: child),
        var header = Self.readHeader(headerURL(id), cipher: cipher),
        header.state == .recording
      else { continue }
      var latest: UInt64?
      for track in MeetingTrack.allCases {
        let chunk = Self.chunkURLs(of: track, in: audioDirectory(id)).reversed().lazy
          .compactMap { Self.readChunk($0, cipher: cipher) }.first
        if let end = chunk?.runs.map(\.end).max() { latest = max(latest ?? end, end) }
      }
      header.end = latest.map { header.date(atHost: $0) } ?? header.startedAt
      header.state = .recorded
      header.endedBy = .interrupted
      Self.removePartials(in: meetingDirectory(id))
      Self.removePartials(in: audioDirectory(id))
      if (try? update(header, cipher: cipher)) != nil { recovered += 1 }
    }
    return recovered
  }

  private static func removePartials(in directory: URL) {
    let manager = FileManager.default
    for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
    where name.hasSuffix(".partial") {
      try? manager.removeItem(at: directory.appendingPathComponent(name))
    }
  }

  private static func chunkURLs(of track: MeetingTrack, in audio: URL) -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: audio.path)) ?? []
    return names.filter { $0.hasPrefix("\(track.rawValue)-") && $0.hasSuffix(".sealed") }.sorted()
      .map { audio.appendingPathComponent($0) }
  }

  private static func readChunk(_ url: URL, cipher: any HistoryCipher) -> MeetingChunk? {
    guard let sealed = try? Data(contentsOf: url), let plain = try? cipher.open(sealed) else {
      return nil
    }
    return try? MeetingChunk(decoding: plain)
  }

  private static func readHeader(_ url: URL, cipher: any HistoryCipher) -> MeetingHeader? {
    guard let sealed = try? Data(contentsOf: url), let plain = try? cipher.open(sealed) else {
      return nil
    }
    return try? JSONDecoder().decode(MeetingHeader.self, from: plain)
  }

  private func meetingDirectory(_ id: UUID) -> URL {
    directory.appendingPathComponent(id.uuidString, isDirectory: true)
  }

  private func audioDirectory(_ id: UUID) -> URL {
    meetingDirectory(id).appendingPathComponent("audio", isDirectory: true)
  }

  private func headerURL(_ id: UUID) -> URL {
    meetingDirectory(id).appendingPathComponent("header.sealed")
  }

  private func makeDirectory(_ url: URL) throws {
    do {
      try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw MeetingStoreError.failed(step: "directory", code: (error as NSError).code)
    }
    guard chmod(url.path, 0o700) == 0 else {
      throw MeetingStoreError.failed(step: "directory", code: Int(errno))
    }
  }

  private func seal(_ plaintext: Data, cipher: any HistoryCipher, to url: URL) throws {
    let sealed: Data
    do { sealed = try cipher.seal(plaintext) } catch {
      var code = 0
      if case HistoryCipherError.keyUnavailable(let status) = error { code = Int(status) }
      throw MeetingStoreError.failed(step: "seal", code: code)
    }
    let partial = url.appendingPathExtension("partial")
    let descriptor = open(partial.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard descriptor >= 0 else { throw MeetingStoreError.failed(step: "write", code: Int(errno)) }
    var failure: Int32 = fchmod(descriptor, 0o600) == 0 ? 0 : errno
    if failure == 0 {
      sealed.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
          let n = Foundation.write(descriptor, raw.baseAddress! + offset, raw.count - offset)
          if n < 0 {
            if errno == EINTR { continue }
            failure = errno
            return
          }
          offset += n
        }
      }
    }
    if close(descriptor) != 0 && failure == 0 { failure = errno }
    guard failure == 0 else {
      unlink(partial.path)
      throw MeetingStoreError.failed(step: "write", code: Int(failure))
    }
    guard rename(partial.path, url.path) == 0 else {
      let code = Int(errno)
      unlink(partial.path)
      throw MeetingStoreError.failed(step: "rename", code: code)
    }
  }
}
