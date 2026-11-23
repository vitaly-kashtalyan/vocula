import Foundation
import VoculaKit

@MainActor
final class MeetingFixture {
  private static let start = Date(timeIntervalSinceReferenceDate: 816_000_000)

  private var meetings = [
    MeetingListing(
      id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, startedAt: start,
      duration: 2832, title: "Weekly sync"),
    MeetingListing(
      id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
      startedAt: start.addingTimeInterval(-86_400), duration: 312, isPinned: true),
    MeetingListing(
      id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
      startedAt: start.addingTimeInterval(3_600), duration: 95, hasTranscript: false),
  ]

  private let transcript = MeetingTranscript(
    model: "fixture",
    utterances: [
      MeetingUtterance(start: 4, end: 6, speaker: .me, text: "Let's start with the release."),
      MeetingUtterance(start: 11, end: 12, speaker: .others, text: "The build is green."),
    ])

  func parts() -> MeetingTranscriptionParts {
    MeetingTranscriptionParts(
      makeTranscriber: { _, _, _ in nil },
      listing: { _ in await .meetings(self.meetings) },
      transcript: { id in await self.read(id) },
      updateHeader: { id, _, change in await self.update(id, change) },
      delete: { id, _ in await self.delete(id) },
      write: { _, _ in .done },
      paste: { _ in },
      fetchDiarizer: { _ in })
  }

  private func read(_ id: UUID) -> MeetingReadResult {
    meetings.contains { $0.id == id && $0.hasTranscript }
      ? .transcript(transcript) : .failed(step: "read", code: 0)
  }

  private func update(_ id: UUID, _ change: (inout MeetingHeader) -> Void) -> MeetingActionResult {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return .refused }
    let old = meetings[index]
    var header = MeetingHeader(id: id, startedAt: old.startedAt, anchor: 0)
    header.title = old.title
    header.pinned = old.isPinned
    change(&header)
    meetings[index] = MeetingListing(
      id: id, startedAt: old.startedAt, duration: old.duration, hasEnd: old.hasEnd,
      title: header.title, isPinned: header.isPinned, isRecordingState: old.isRecordingState,
      hasTranscript: old.hasTranscript)
    return .done
  }

  private func delete(_ id: UUID) -> MeetingActionResult {
    guard let index = meetings.firstIndex(where: { $0.id == id }), !meetings[index].isPinned
    else { return .refused }
    meetings.remove(at: index)
    return .done
  }
}
