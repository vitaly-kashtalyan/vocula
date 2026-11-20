import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingMarkdownTests {
  private let labels: [MeetingSpeaker: String] = [.me: "Me", .others: "Others"]
  private let started = ISO8601DateFormatter().date(from: "2026-11-19T09:30:00Z")!

  private func render(
    _ utterances: [MeetingUtterance], duration: TimeInterval = 2832, includeMe: Bool = true
  ) -> String {
    MeetingMarkdown.render(
      MeetingTranscript(model: "m", utterances: utterances), startedAt: started,
      duration: duration, labels: labels, includeMe: includeMe)
  }

  @Test func rendersTheExportFormat() {
    let text = render([
      MeetingUtterance(
        start: 4.6, end: 6, speaker: .me, text: "Let's start with the release."),
      MeetingUtterance(
        start: 11, end: 12, speaker: .others, text: "The build is green."),
    ])
    #expect(
      text == """
        ---
        date: 2026-11-19T09:30:00Z
        duration: 00:47:12
        speakers: [Me, Others]
        ---

        **Me** [00:00:04]: Let's start with the release.

        **Others** [00:00:11]: The build is green.

        """)
  }

  @Test func myLinesCanBeLeftOut() {
    let lines = [
      MeetingUtterance(start: 1, end: 2, speaker: .me, text: "mine"),
      MeetingUtterance(start: 3, end: 4, speaker: .others, text: "spoken"),
    ]
    let without = render(lines, includeMe: false)
    #expect(!without.contains("mine"))
    #expect(without.contains("speakers: [Others]"))
    #expect(render(lines).contains("**Me** [00:00:01]: mine"))
  }

  @Test func anEmptyTranscriptHasOnlyTheHeader() {
    #expect(
      render([], duration: 5) == """
        ---
        date: 2026-11-19T09:30:00Z
        duration: 00:00:05
        speakers: []
        ---

        """)
  }

  @Test func durationOverAnHour() {
    #expect(render([], duration: 3725).contains("duration: 01:02:05"))
  }

  @Test func anUnknownSpeakerShowsItsId() {
    let text = render([
      MeetingUtterance(
        start: 1, end: 2, speaker: MeetingSpeaker(rawValue: "speaker-2"), text: "hi")
    ])
    #expect(text.contains("**speaker-2** [00:00:01]: hi"))
  }
}
