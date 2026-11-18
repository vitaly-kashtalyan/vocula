import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingStoreTests {
  let s: UInt64 = 1_000_000_000
  let started = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func header(anchor: UInt64 = 1_000_000_000) -> MeetingHeader {
    MeetingHeader(id: UUID(), startedAt: started, anchor: anchor)
  }

  private func chunk(_ track: MeetingTrack, _ sequence: UInt32, at start: UInt64, count: Int)
    -> MeetingChunk
  {
    MeetingChunk(
      track: track, sequence: sequence,
      runs: [MeetingRun(start: start, samples: Array(repeating: 7, count: count))])
  }

  private func sealed(_ chunk: MeetingChunk) -> Data {
    MarkingCipher.mark + chunk.encoded()
  }

  private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? Int) ?? -1
  }

  private func names(_ url: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
  }

  private func files(under root: URL) -> [URL] {
    let walker = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey])
    return (walker?.allObjects as? [URL] ?? []).filter {
      (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
  }

  private func snapshot(_ url: URL) -> [String: Data] {
    var out: [String: Data] = [:]
    for file in files(under: url) { out[file.path] = try? Data(contentsOf: file) }
    return out
  }

  private func started(_ header: MeetingHeader, in root: URL, cipher: MarkingCipher) async throws
    -> MeetingStore
  {
    let store = MeetingStore(directory: root)
    _ = try await store.begin(header, cipher: cipher, recovering: false)
    return store
  }

  @Test func aMeetingIsLaidOutPrivately() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let h = header()
    let store = try await started(h, in: root, cipher: cipher)
    try await store.write(chunk(.mic, 0, at: s, count: 4), of: h.id, cipher: cipher)
    try await store.write(chunk(.system, 0, at: s, count: 4), of: h.id, cipher: cipher)
    let meeting = root.appendingPathComponent(h.id.uuidString)
    let audio = meeting.appendingPathComponent("audio")
    for directory in [root, meeting, audio] { #expect(try permissions(directory) == 0o700) }
    #expect(try names(meeting) == ["audio", "header.sealed"])
    #expect(try names(audio) == ["mic-000000.sealed", "system-000000.sealed"])
    for file in files(under: root) { #expect(try permissions(file) == 0o600) }
  }

  @Test func everyByteWrittenWasSealed() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let h = header()
    let store = try await started(h, in: root, cipher: cipher)
    try await store.write(chunk(.mic, 0, at: s, count: 4), of: h.id, cipher: cipher)
    let found = files(under: root)
    #expect(found.count == 2)
    for file in found { #expect(try Data(contentsOf: file).starts(with: MarkingCipher.mark)) }
  }

  @Test func noPartialIsLeftBehind() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let h = header()
    let store = try await started(h, in: root, cipher: cipher)
    try await store.write(chunk(.mic, 0, at: s, count: 4), of: h.id, cipher: cipher)
    try await store.write(chunk(.mic, 1, at: s, count: 4), of: h.id, cipher: cipher)
    try await store.update(h, cipher: cipher)
    try await store.update(h, cipher: cipher)
    #expect(files(under: root).count == 3)
    #expect(files(under: root).allSatisfy { !$0.lastPathComponent.hasSuffix(".partial") })
  }

  @Test func anUnwritableDirectoryRefusesTheStart() async throws {
    let blocker = meetingTemporaryDirectory().appendingPathComponent("file")
    try Data().write(to: blocker)
    let store = MeetingStore(directory: blocker.appendingPathComponent("meetings"))
    var step: String?
    do { _ = try await store.begin(header(), cipher: MarkingCipher(), recovering: false) } catch let
      MeetingStoreError.failed(failed, _)
    { step = failed }
    #expect(step == "directory")
  }

  @Test func aFailedChunkDoesNotStopLaterOnes() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let h = header()
    let store = try await started(h, in: root, cipher: cipher)
    let audio = root.appendingPathComponent(h.id.uuidString).appendingPathComponent("audio")
    chmod(audio.path, 0o500)
    defer { chmod(audio.path, 0o700) }
    await #expect(throws: MeetingStoreError.self) {
      try await store.write(chunk(.mic, 0, at: s, count: 4), of: h.id, cipher: cipher)
    }
    chmod(audio.path, 0o700)
    try await store.write(chunk(.mic, 1, at: s, count: 4), of: h.id, cipher: cipher)
    #expect(try names(audio) == ["mic-000001.sealed"])
  }

  @Test func aSealFailureNamesItsStep() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let h = header()
    let store = try await started(h, in: root, cipher: cipher)
    cipher.failNext(1)
    await #expect(throws: MeetingStoreError.failed(step: "seal", code: 0)) {
      try await store.write(chunk(.mic, 0, at: s, count: 4), of: h.id, cipher: cipher)
    }
  }

  @Test func aLockedKeychainStatusTravelsAsTheCode() async throws {
    struct Locked: HistoryCipher {
      func seal(_ plaintext: Data) throws -> Data {
        throw HistoryCipherError.keyUnavailable(status: -25308)
      }
      func open(_ ciphertext: Data) throws -> Data { ciphertext }
    }
    let root = meetingTemporaryDirectory()
    let store = MeetingStore(directory: root)
    await #expect(throws: MeetingStoreError.failed(step: "seal", code: -25308)) {
      _ = try await store.begin(header(), cipher: Locked(), recovering: false)
    }
  }

  @Test func theHeaderIsRewrittenInPlace() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    var h = header()
    let store = try await started(h, in: root, cipher: cipher)
    h.dictations = [DictationSpan(start: s, end: 2 * s)]
    try await store.update(h, cipher: cipher)
    #expect(await store.header(of: h.id, cipher: cipher)?.dictations == h.dictations)
    #expect(try names(root.appendingPathComponent(h.id.uuidString)) == ["audio", "header.sealed"])
  }

  @Test func anInterruptedMeetingIsRecovered() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(
      header: old,
      chunks: [
        "audio/mic-000000.sealed": sealed(chunk(.mic, 0, at: s, count: 16_000)),
        "audio/mic-000001.sealed": sealed(chunk(.mic, 1, at: 2 * s, count: 8_000)),
        "audio/system-000000.sealed": sealed(chunk(.system, 0, at: s, count: 32_000)),
        "audio/mic-000002.sealed.partial": Data("x".utf8),
        "header.sealed.partial": Data("x".utf8),
      ], in: root)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: cipher, recovering: true)
    let recovered = await store.header(of: old.id, cipher: cipher)
    #expect(count == 1)
    #expect(recovered?.state == .recorded)
    #expect(recovered?.endedBy == .interrupted)
    #expect(recovered?.end == started.addingTimeInterval(2))
    #expect(files(under: root).allSatisfy { !$0.lastPathComponent.hasSuffix(".partial") })
  }

  @Test func theHighestChunkThatOpensDecides() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(
      header: old,
      chunks: [
        "audio/mic-000000.sealed": sealed(chunk(.mic, 0, at: s, count: 16_000)),
        "audio/mic-000002.sealed": sealed(chunk(.mic, 2, at: 5 * s, count: 16_000)),
        "audio/mic-000003.sealed": Data("garbage".utf8),
      ], in: root)
    let store = MeetingStore(directory: root)
    _ = try await store.begin(header(), cipher: cipher, recovering: true)
    #expect(await store.header(of: old.id, cipher: cipher)?.end == started.addingTimeInterval(5))
  }

  @Test func noChunkMeansTheStartTime() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(header: old, chunks: [:], in: root)
    let store = MeetingStore(directory: root)
    _ = try await store.begin(header(), cipher: cipher, recovering: true)
    #expect(await store.header(of: old.id, cipher: cipher)?.end == started)
  }

  @Test func anUnopenableHeaderIsLeftUntouched() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(
      header: old,
      chunks: [
        "header.sealed": Data("garbage".utf8),
        "audio/mic-000000.sealed.partial": Data("x".utf8),
      ], in: root)
    let before = snapshot(root)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: cipher, recovering: true)
    let after = snapshot(root).filter { $0.key.contains(old.id.uuidString) }
    #expect(count == 0)
    #expect(after == before)
  }

  @Test func chunksThatDoNotOpenLeaveTheMeetingUntouched() async throws {
    let root = meetingTemporaryDirectory()
    let old = header()
    try plant(
      header: old,
      chunks: [
        "audio/mic-000000.sealed": Data("garbage".utf8),
        "audio/system-000000.sealed": Data("garbage".utf8),
        "audio/mic-000001.sealed.partial": Data("x".utf8),
      ], in: root)
    let before = snapshot(root)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: MarkingCipher(), recovering: true)
    #expect(count == 0)
    #expect(snapshot(root).filter { $0.key.contains(old.id.uuidString) } == before)
  }

  @Test func anAudioDirectoryThatDoesNotListLeavesTheMeetingUntouched() async throws {
    let root = meetingTemporaryDirectory()
    let old = header()
    try plant(header: old, chunks: ["header.sealed.partial": Data("x".utf8)], in: root)
    let audio = root.appendingPathComponent(old.id.uuidString).appendingPathComponent("audio")
    try FileManager.default.removeItem(at: audio)
    try Data("not a directory".utf8).write(to: audio)
    let before = snapshot(root)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: MarkingCipher(), recovering: true)
    #expect(count == 0)
    #expect(snapshot(root).filter { $0.key.contains(old.id.uuidString) } == before)
  }

  @Test func aMissingAudioDirectoryMeansTheStartTime() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(header: old, chunks: [:], in: root)
    try FileManager.default.removeItem(
      at: root.appendingPathComponent(old.id.uuidString).appendingPathComponent("audio"))
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: cipher, recovering: true)
    let recovered = await store.header(of: old.id, cipher: cipher)
    #expect(count == 1)
    #expect(recovered?.end == started)
    #expect(recovered?.endedBy == .interrupted)
  }

  @Test func aHeaderInAnotherMeetingsFolderIsNotThatMeeting() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(header: old, chunks: ["header.sealed.partial": Data("x".utf8)], in: root)
    let copyID = UUID()
    let copy = root.appendingPathComponent(copyID.uuidString)
    try FileManager.default.copyItem(
      at: root.appendingPathComponent(old.id.uuidString), to: copy)
    let before = snapshot(copy)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: cipher, recovering: true)
    #expect(count == 1)
    #expect(snapshot(copy) == before)
    #expect(await store.header(of: copyID, cipher: cipher) == nil)
    #expect(await store.header(of: old.id, cipher: cipher)?.state == .recorded)
  }

  @Test func aChunkFiledUnderTheOtherTrackIsIgnored() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(
      header: old,
      chunks: [
        "audio/mic-000000.sealed": sealed(chunk(.mic, 0, at: s, count: 2)),
        "audio/mic-000001.sealed": sealed(chunk(.system, 1, at: s + 4 * 62_500, count: 2)),
      ], in: root)
    let store = MeetingStore(directory: root)
    _ = try await store.begin(header(), cipher: cipher, recovering: true)
    #expect(
      await store.header(of: old.id, cipher: cipher)?.end == started.addingTimeInterval(0.000125))
    #expect(await store.timeline(of: old.id, track: .mic, cipher: cipher) == [7, 7])
  }

  @Test func aChunkWithoutRunsFallsBackToTheOneBefore() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(
      header: old,
      chunks: [
        "audio/mic-000000.sealed": sealed(chunk(.mic, 0, at: s, count: 16_000)),
        "audio/mic-000001.sealed": sealed(MeetingChunk(track: .mic, sequence: 1, runs: [])),
      ], in: root)
    let store = MeetingStore(directory: root)
    _ = try await store.begin(header(), cipher: cipher, recovering: true)
    #expect(await store.header(of: old.id, cipher: cipher)?.end == started.addingTimeInterval(1))
  }

  @Test func aRecordedMeetingIsLeftUntouched() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    var old = header()
    old.finish(atHost: old.anchor, by: .stopped)
    try plant(header: old, chunks: [:], in: root)
    let before = snapshot(root)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: cipher, recovering: true)
    #expect(count == 0)
    #expect(snapshot(root).filter { $0.key.contains(old.id.uuidString) } == before)
  }

  @Test func recoveryRunsOnlyWhenAsked() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    let old = header()
    try plant(header: old, chunks: [:], in: root)
    let store = MeetingStore(directory: root)
    let count = try await store.begin(header(), cipher: cipher, recovering: false)
    #expect(count == 0)
    #expect(await store.header(of: old.id, cipher: cipher)?.state == .recording)
  }

  @Test func anUnopenableChunkIsAGapInTheTimeline() async throws {
    let root = meetingTemporaryDirectory()
    let cipher = MarkingCipher()
    var h = header()
    h.finish(atHost: 2 * s, by: .stopped)
    try plant(
      header: h,
      chunks: [
        "audio/mic-000000.sealed": sealed(chunk(.mic, 0, at: s, count: 2)),
        "audio/mic-000001.sealed": Data("garbage".utf8),
        "audio/mic-000002.sealed": sealed(chunk(.mic, 2, at: s + 4 * 62_500, count: 2)),
      ], in: root)
    let store = MeetingStore(directory: root)
    #expect(
      await store.timeline(of: h.id, track: .mic, cipher: cipher) == [7, 7, 0, 0, 7, 7])
  }

  @Test func aMeetingWithoutAnEndHasNoTimeline() async throws {
    let root = meetingTemporaryDirectory()
    let h = header()
    try plant(
      header: h, chunks: ["audio/mic-000000.sealed": sealed(chunk(.mic, 0, at: s, count: 4))],
      in: root)
    let store = MeetingStore(directory: root)
    #expect(await store.timeline(of: h.id, track: .mic, cipher: MarkingCipher()) == [])
  }
}
