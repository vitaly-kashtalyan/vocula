import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingStoreManagementTests {
  private let s: UInt64 = 1_000_000_000
  private let cipher = MarkingCipher()

  private struct Refusing: HistoryCipher {
    func seal(_ plaintext: Data) throws -> Data { plaintext }
    func open(_ ciphertext: Data) throws -> Data { throw CocoaError(.coderReadCorrupt) }
  }

  private func meeting(
    in store: MeetingStore, at seconds: TimeInterval, recorded: Bool = true,
    transcript: Bool = false, pinned: Bool = false
  ) async throws -> MeetingHeader {
    var header = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: seconds), anchor: s)
    _ = try await store.begin(header, cipher: cipher, recovering: false)
    if recorded { header.finish(atHost: s * 3, by: .stopped) }
    if pinned { header.pinned = true }
    try await store.update(header, cipher: cipher)
    if transcript {
      try await store.writeTranscript(
        MeetingTranscript(model: "m", utterances: []), of: header.id, cipher: cipher)
    }
    return header
  }

  @Test func listingIncludesUntranscribedAndInterrupted() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let done = try await meeting(in: store, at: 100, transcript: true)
    let waiting = try await meeting(in: store, at: 200, pinned: true)
    let interrupted = try await meeting(in: store, at: 300, recorded: false)
    let byID = Dictionary(
      uniqueKeysWithValues: try await store.listing(cipher: cipher).map { ($0.id, $0) })
    #expect(byID.count == 3)
    #expect(byID[done.id]?.hasTranscript == true)
    #expect(byID[done.id]?.duration == 2)
    #expect(byID[done.id]?.hasEnd == true)
    #expect(byID[done.id]?.startedAt == done.startedAt)
    #expect(byID[waiting.id]?.hasTranscript == false)
    #expect(byID[waiting.id]?.isPinned == true)
    #expect(byID[waiting.id]?.title == nil)
    #expect(byID[interrupted.id]?.isRecordingState == true)
    #expect(byID[interrupted.id]?.hasEnd == false)
  }

  @Test func renameAndPinAreSealedInTheHeader() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100)
    try await store.updateHeader(of: header.id, cipher: cipher, busy: false) {
      $0.title = "Sync"
      $0.pinned = true
    }
    let read = await store.header(of: header.id, cipher: cipher)
    #expect(read?.title == "Sync")
    #expect(read?.isPinned == true)
    #expect(read?.state == .recorded)
  }

  @Test func aRecordingHeaderIsRefusedOnlyWhileBusy() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100, recorded: false)
    await #expect(throws: MeetingStoreError.refused) {
      try await store.updateHeader(of: header.id, cipher: cipher, busy: true) { $0.title = "x" }
    }
    try await store.updateHeader(of: header.id, cipher: cipher, busy: false) { $0.title = "x" }
    #expect(await store.header(of: header.id, cipher: cipher)?.title == "x")
  }

  @Test func deletingAPinnedMeetingIsRefused() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100, pinned: true)
    await #expect(throws: MeetingStoreError.refused) {
      try await store.delete(header.id, cipher: cipher, busy: false)
    }
    #expect(try await store.listing(cipher: cipher).count == 1)
  }

  @Test func deletingWhileItRecordsIsRefused() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100, recorded: false)
    await #expect(throws: MeetingStoreError.refused) {
      try await store.delete(header.id, cipher: cipher, busy: true)
    }
  }

  @Test func deletingAnUnreadableHeaderIsRefused() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100)
    await #expect(throws: MeetingStoreError.refused) {
      try await store.delete(header.id, cipher: Refusing(), busy: false)
    }
  }

  @Test func deleteLeavesOnlyATombstoneNothingLists() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100, transcript: true)
    #expect(store.holdsMeetings())
    try await store.delete(header.id, cipher: cipher, busy: false)
    #expect(try await store.listing(cipher: cipher).isEmpty)
    #expect(try await store.work(cipher: cipher).isEmpty)
    #expect(!store.holdsMeetings())
    let tombstones = store.tombstones()
    #expect(tombstones.map(\.lastPathComponent) == ["\(header.id.uuidString).deleting"])
  }

  @Test func removingATombstoneTwiceIsFine() async throws {
    let store = MeetingStore(directory: meetingTemporaryDirectory())
    let header = try await meeting(in: store, at: 100)
    try await store.delete(header.id, cipher: cipher, busy: false)
    let tombstone = try #require(store.tombstones().first)
    try MeetingStore.removeTombstone(tombstone)
    try MeetingStore.removeTombstone(tombstone)
    #expect(store.tombstones().isEmpty)
  }
}
