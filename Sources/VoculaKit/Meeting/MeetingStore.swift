import Foundation

public enum MeetingStoreError: Error, Equatable, Sendable { case failed(step: String, code: Int) }

struct MeetingWork: Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case recognize, emptyTranscript, removeAudio }

  public let header: MeetingHeader
  public let kind: Kind
}

public actor MeetingStore {
  private let directory: URL
  private let queue = DispatchSerialQueue(label: "vocula.meeting.store", qos: .utility)

  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    queue.asUnownedSerialExecutor()
  }

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
    guard let sealed = try? Data(contentsOf: headerURL(meeting)),
      let plain = try? cipher.open(sealed),
      let header = try? JSONDecoder().decode(MeetingHeader.self, from: plain), header.id == meeting
    else { return nil }
    return header
  }

  func work(cipher: any HistoryCipher) throws -> [MeetingWork] {
    try meetingIDs().compactMap { id -> MeetingWork? in
      guard let header = header(of: id, cipher: cipher), header.state == .recorded else {
        return nil
      }
      switch Self.presence(of: transcriptURL(id)) {
      case .unknown:
        return nil
      case .absent:
        do {
          let names = try MeetingTrack.allCases.flatMap {
            try Self.chunkURLs(of: $0, in: audioDirectory(id))
          }
          guard names.isEmpty else { return MeetingWork(header: header, kind: .recognize) }
          guard try Self.holdsOnlyChunks(audioDirectory(id)) else { return nil }
          return MeetingWork(header: header, kind: .emptyTranscript)
        } catch {
          return MeetingWork(header: header, kind: .recognize)
        }
      case .present:
        break
      }
      guard (try? transcript(of: id, cipher: cipher)) != nil,
        FileManager.default.fileExists(atPath: audioDirectory(id).path)
      else { return nil }
      return MeetingWork(header: header, kind: .removeAudio)
    }
    .sorted { $0.header.startedAt > $1.header.startedAt }
  }

  public func listing(cipher: any HistoryCipher) throws -> [MeetingListing] {
    try meetingIDs().compactMap { id -> MeetingListing? in
      guard FileManager.default.fileExists(atPath: transcriptURL(id).path),
        let header = header(of: id, cipher: cipher)
      else { return nil }
      return MeetingListing(
        id: id, startedAt: header.startedAt,
        duration: max(0, header.end?.timeIntervalSince(header.startedAt) ?? 0),
        hasEnd: header.end != nil, title: header.title, isPinned: header.isPinned,
        isRecordingState: header.state == .recording, hasTranscript: true)
    }
    .sorted { $0.startedAt > $1.startedAt }
  }

  func chunkNames(of meeting: UUID, track: MeetingTrack) throws -> [String] {
    do {
      return try Self.chunkURLs(of: track, in: audioDirectory(meeting)).map(\.lastPathComponent)
    } catch {
      throw MeetingStoreError.failed(step: "read", code: (error as NSError).code)
    }
  }

  func readChunk(
    of meeting: UUID, track: MeetingTrack, name: String, cipher: any HistoryCipher
  ) throws -> MeetingChunk? {
    let sealed: Data
    do {
      sealed = try Data(contentsOf: audioDirectory(meeting).appendingPathComponent(name))
    } catch {
      throw MeetingStoreError.failed(step: "read", code: (error as NSError).code)
    }
    return Self.chunk(from: sealed, of: track, cipher: cipher)
  }

  func writeTranscript(
    _ transcript: MeetingTranscript, of meeting: UUID, cipher: any HistoryCipher
  ) throws {
    let plaintext: Data
    do { plaintext = try JSONEncoder().encode(transcript) } catch {
      throw MeetingStoreError.failed(step: "encode", code: 0)
    }
    let url = transcriptURL(meeting)
    try seal(plaintext, cipher: cipher, to: url)
    guard (try? self.transcript(of: meeting, cipher: cipher)) == transcript else {
      unlink(url.path)
      throw MeetingStoreError.failed(step: "verify", code: 0)
    }
  }

  public func transcript(of meeting: UUID, cipher: any HistoryCipher) throws -> MeetingTranscript {
    let sealed: Data
    do { sealed = try Data(contentsOf: transcriptURL(meeting)) } catch {
      throw MeetingStoreError.failed(step: "read", code: (error as NSError).code)
    }
    guard let plain = try? cipher.open(sealed),
      let transcript = try? JSONDecoder().decode(MeetingTranscript.self, from: plain)
    else { throw MeetingStoreError.failed(step: "open", code: 0) }
    return transcript
  }

  func removeAudio(of meeting: UUID) throws {
    do {
      try FileManager.default.removeItem(at: audioDirectory(meeting))
    } catch CocoaError.fileNoSuchFile {
    } catch {
      throw MeetingStoreError.failed(step: "remove", code: (error as NSError).code)
    }
  }

  private static func holdsOnlyChunks(_ audio: URL) throws -> Bool {
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: audio.path)
    } catch CocoaError.fileReadNoSuchFile {
      return true
    }
    return names.allSatisfy { $0.hasPrefix(".") || $0.hasSuffix(".partial") }
  }

  private enum Presence { case absent, present, unknown }

  private static func presence(of url: URL) -> Presence {
    do {
      _ = try FileManager.default.attributesOfItem(atPath: url.path)
      return .present
    } catch CocoaError.fileReadNoSuchFile {
      return .absent
    } catch {
      return .unknown
    }
  }

  private func meetingIDs() throws -> [UUID] {
    do {
      return try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap(
        UUID.init(uuidString:))
    } catch CocoaError.fileReadNoSuchFile {
      return []
    } catch {
      throw MeetingStoreError.failed(step: "list", code: (error as NSError).code)
    }
  }

  private func recoverInterrupted(cipher: any HistoryCipher) -> Int {
    var recovered = 0
    for id in (try? meetingIDs()) ?? [] {
      guard var header = header(of: id, cipher: cipher),
        header.state == .recording,
        let files = try? MeetingTrack.allCases.map({
          ($0, try Self.chunkURLs(of: $0, in: audioDirectory(id)))
        })
      else { continue }
      let latest = files.compactMap { track, urls in
        urls.reversed().lazy.compactMap { Self.readChunk($0, of: track, cipher: cipher) }.first?
          .runs.map(\.end).max()
      }.max()
      guard latest != nil || files.allSatisfy({ $0.1.isEmpty }) else { continue }
      header.finish(atHost: latest ?? header.anchor, by: .interrupted)
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

  private static func chunkURLs(of track: MeetingTrack, in audio: URL) throws -> [URL] {
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: audio.path)
    } catch CocoaError.fileReadNoSuchFile {
      names = []
    }
    return
      names
      .filter { $0.hasPrefix("\(track.rawValue)-") && $0.hasSuffix(".sealed") }.sorted()
      .map { audio.appendingPathComponent($0) }
  }

  private static func readChunk(_ url: URL, of track: MeetingTrack, cipher: any HistoryCipher)
    -> MeetingChunk?
  {
    guard let sealed = try? Data(contentsOf: url) else { return nil }
    return chunk(from: sealed, of: track, cipher: cipher)
  }

  private static func chunk(from sealed: Data, of track: MeetingTrack, cipher: any HistoryCipher)
    -> MeetingChunk?
  {
    guard let plain = try? cipher.open(sealed), let chunk = try? MeetingChunk(decoding: plain),
      chunk.track == track
    else { return nil }
    return chunk
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

  private func transcriptURL(_ id: UUID) -> URL {
    meetingDirectory(id).appendingPathComponent("transcript.sealed")
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
    if failure == 0, fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 { failure = errno }
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
