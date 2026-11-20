import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingStoreTranscriptTests {
  let s: UInt64 = 1_000_000_000

  private struct Twisting: HistoryCipher {
    func seal(_ plaintext: Data) throws -> Data { MarkingCipher.mark + plaintext }
    func open(_ ciphertext: Data) throws -> Data {
      let plain = Data(ciphertext.dropFirst(MarkingCipher.mark.count))
      return Data(
        String(decoding: plain, as: UTF8.self).replacingOccurrences(of: "hi", with: "ho").utf8)
    }
  }

  private func recorded(startedAt seconds: TimeInterval = 800_000_000) -> MeetingHeader {
    var header = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: seconds), anchor: s)
    header.finish(atHost: 3 * s, by: .stopped)
    return header
  }

  private func sealed(_ chunk: MeetingChunk) -> Data { MarkingCipher.mark + chunk.encoded() }

  private func chunk(_ track: MeetingTrack, _ sequence: UInt32 = 0) -> MeetingChunk {
    MeetingChunk(
      track: track, sequence: sequence, runs: [MeetingRun(start: s, samples: [7, 7])])
  }

  private func transcript(_ text: String = "hi") -> MeetingTranscript {
    MeetingTranscript(
      model: "m",
      utterances: [MeetingUtterance(start: 0, end: 1, speaker: .me, text: text, dictation: false)])
  }

  private func meeting(_ id: UUID, in root: URL) -> URL {
    root.appendingPathComponent(id.uuidString, isDirectory: true)
  }

  private func step(of error: any Error) -> String? {
    if case MeetingStoreError.failed(let step, _) = error { return step }
    return nil
  }

  @Test func meetingsRecordedBeforeThisChangeArePending() async throws {
    let root = meetingTemporaryDirectory()
    let older = recorded(startedAt: 800_000_000)
    let newer = recorded(startedAt: 800_000_600)
    for header in [older, newer] {
      try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    }
    let work = try await MeetingStore(directory: root).work(cipher: MarkingCipher())
    #expect(work.map(\.header.id) == [newer.id, older.id])
    #expect(work.map(\.kind) == [.recognize, .recognize])
  }

  @Test func aRecordingMeetingIsNotPending() async throws {
    let root = meetingTemporaryDirectory()
    try plant(
      header: MeetingHeader(id: UUID(), startedAt: Date(), anchor: s),
      chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    #expect(try await MeetingStore(directory: root).work(cipher: MarkingCipher()).isEmpty)
  }

  @Test func aMeetingWithoutChunksGetsAnEmptyTranscript() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: [:], in: root)
    #expect(
      try await MeetingStore(directory: root).work(cipher: MarkingCipher()).map(\.kind)
        == [.emptyTranscript])
  }

  @Test func anAudioFolderWithUnknownFilesIsLeftAlone() async throws {
    let root = meetingTemporaryDirectory()
    let unknown = recorded(startedAt: 800_000_000)
    let finderOnly = recorded(startedAt: 800_000_600)
    try plant(header: unknown, chunks: ["audio/future-000000.bin": Data("?".utf8)], in: root)
    try plant(header: finderOnly, chunks: ["audio/.DS_Store": Data("?".utf8)], in: root)
    let work = try await MeetingStore(directory: root).work(cipher: MarkingCipher())
    #expect(work.map(\.header.id) == [finderOnly.id])
    #expect(work.map(\.kind) == [.emptyTranscript])
  }

  @Test func aTranscriptWithAudioOnlyRemovesAudio() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    let store = MeetingStore(directory: root)
    try await store.writeTranscript(transcript(), of: header.id, cipher: MarkingCipher())
    #expect(try await store.work(cipher: MarkingCipher()).map(\.kind) == [.removeAudio])
    try await store.removeAudio(of: header.id)
    #expect(try await store.work(cipher: MarkingCipher()).isEmpty)
  }

  @Test func anUnreadableTranscriptIsLeftAlone() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    try Data("garbage".utf8).write(
      to: meeting(header.id, in: root).appendingPathComponent("transcript.sealed"))
    #expect(try await MeetingStore(directory: root).work(cipher: MarkingCipher()).isEmpty)
  }

  @Test func anUnreadableHeaderIsLeftAlone() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    try Data("garbage".utf8).write(
      to: meeting(header.id, in: root).appendingPathComponent("header.sealed"))
    #expect(try await MeetingStore(directory: root).work(cipher: MarkingCipher()).isEmpty)
  }

  @Test func aMissingFolderIsNoWork() async throws {
    let root = meetingTemporaryDirectory().appendingPathComponent("absent")
    let store = MeetingStore(directory: root)
    #expect(try await store.work(cipher: MarkingCipher()).isEmpty)
    #expect(try await store.listing(cipher: MarkingCipher()).isEmpty)
  }

  @Test func aFolderThatCannotBeListedFails() async throws {
    let root = meetingTemporaryDirectory()
    chmod(root.path, 0)
    defer { chmod(root.path, 0o700) }
    do {
      _ = try await MeetingStore(directory: root).work(cipher: MarkingCipher())
      Issue.record("listing an unreadable folder succeeded")
    } catch {
      #expect(step(of: error) == "list")
    }
  }

  @Test func chunksAreReadOneByOne() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(
      header: header,
      chunks: [
        "audio/mic-000001.sealed": sealed(chunk(.mic, 1)),
        "audio/mic-000000.sealed": sealed(chunk(.mic, 0)),
        "audio/system-000000.sealed": sealed(chunk(.system)),
      ], in: root)
    let store = MeetingStore(directory: root)
    let names = try await store.chunkNames(of: header.id, track: .mic)
    #expect(names == ["mic-000000.sealed", "mic-000001.sealed"])
    let read = try await store.readChunk(
      of: header.id, track: .mic, name: names[1], cipher: MarkingCipher())
    #expect(read == .chunk(chunk(.mic, 1)))
  }

  @Test func aCorruptChunkReadsAsCorrupt() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": Data("garbage".utf8)], in: root)
    let read = try await MeetingStore(directory: root).readChunk(
      of: header.id, track: .mic, name: "mic-000000.sealed", cipher: MarkingCipher())
    #expect(read == .corrupt)
  }

  @Test func aChunkFiledUnderTheOtherTrackIsCorrupt() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.system))], in: root)
    let read = try await MeetingStore(directory: root).readChunk(
      of: header.id, track: .mic, name: "mic-000000.sealed", cipher: MarkingCipher())
    #expect(read == .corrupt)
  }

  @Test func anUnreadableChunkFileFails() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    let file = meeting(header.id, in: root).appendingPathComponent("audio/mic-000000.sealed")
    chmod(file.path, 0)
    defer { chmod(file.path, 0o600) }
    do {
      _ = try await MeetingStore(directory: root).readChunk(
        of: header.id, track: .mic, name: "mic-000000.sealed", cipher: MarkingCipher())
      Issue.record("reading an unreadable chunk succeeded")
    } catch {
      #expect(step(of: error) == "read")
    }
  }

  @Test func aTranscriptIsWrittenSealedAndVerified() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: [:], in: root)
    let store = MeetingStore(directory: root)
    try await store.writeTranscript(transcript(), of: header.id, cipher: MarkingCipher())
    let file = meeting(header.id, in: root).appendingPathComponent("transcript.sealed")
    #expect(try Data(contentsOf: file).starts(with: MarkingCipher.mark))
    let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
    #expect(mode as? Int == 0o600)
    #expect(try await store.transcript(of: header.id, cipher: MarkingCipher()) == transcript())
  }

  @Test func aLeftoverPartialIsReplaced() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: [:], in: root)
    let directory = meeting(header.id, in: root)
    try Data("left by a crash".utf8).write(
      to: directory.appendingPathComponent("transcript.sealed.partial"))
    let store = MeetingStore(directory: root)
    try await store.writeTranscript(transcript(), of: header.id, cipher: MarkingCipher())
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("transcript.sealed.partial").path))
    #expect(try await store.transcript(of: header.id, cipher: MarkingCipher()) == transcript())
  }

  @Test func aMismatchedReadBackIsRemoved() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: [:], in: root)
    do {
      try await MeetingStore(directory: root).writeTranscript(
        transcript("hi"), of: header.id, cipher: Twisting())
      Issue.record("a transcript that reads back differently was kept")
    } catch {
      #expect(step(of: error) == "verify")
    }
    #expect(
      !FileManager.default.fileExists(
        atPath: meeting(header.id, in: root).appendingPathComponent("transcript.sealed").path))
  }

  @Test func listingShowsTranscribedMeetingsNewestFirst() async throws {
    let root = meetingTemporaryDirectory()
    let older = recorded(startedAt: 800_000_000)
    let newer = recorded(startedAt: 800_000_600)
    let untranscribed = recorded(startedAt: 800_001_200)
    for header in [older, newer, untranscribed] { try plant(header: header, chunks: [:], in: root) }
    let store = MeetingStore(directory: root)
    for header in [older, newer] {
      try await store.writeTranscript(transcript(), of: header.id, cipher: MarkingCipher())
    }
    let listing = try await store.listing(cipher: MarkingCipher())
    #expect(listing.map(\.id) == [newer.id, older.id])
    #expect(listing.first?.startedAt == newer.startedAt)
    #expect(listing.first?.duration == 2)
  }

  @Test func removingAudioLeavesTheTranscript() async throws {
    let root = meetingTemporaryDirectory()
    let header = recorded()
    try plant(header: header, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic))], in: root)
    let store = MeetingStore(directory: root)
    try await store.writeTranscript(transcript(), of: header.id, cipher: MarkingCipher())
    try await store.removeAudio(of: header.id)
    try await store.removeAudio(of: header.id)
    let directory = meeting(header.id, in: root)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio").path))
    #expect(try await store.transcript(of: header.id, cipher: MarkingCipher()) == transcript())
  }

  @Test func theHeaderGivesItsEndAsHostTime() {
    #expect(recorded().endHost == 3 * s)
    #expect(MeetingHeader(id: UUID(), startedAt: Date(), anchor: s).endHost == nil)
  }
}
