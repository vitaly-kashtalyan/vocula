import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingMarkdownTests {
  private let label: @Sendable (MeetingSpeaker) -> String = {
    [.me: "Me", .others: "Others"][$0] ?? $0.rawValue
  }
  private let started = ISO8601DateFormatter().date(from: "2026-11-19T09:30:00Z")!

  private func render(
    _ utterances: [MeetingUtterance], duration: TimeInterval = 2832, includeMe: Bool = true
  ) -> String {
    MeetingMarkdown.render(
      MeetingTranscript(model: "m", utterances: utterances), startedAt: started,
      duration: duration, label: label, includeMe: includeMe)
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

  @Test func aNamedExportStartsWithItsTitle() {
    let text = MeetingMarkdown.render(
      MeetingTranscript(
        model: "m",
        utterances: [MeetingUtterance(start: 4.6, end: 6, speaker: .me, text: "Hi.")]),
      title: #"Q3 "plan" \ review"#, startedAt: started, duration: 2832, label: label,
      includeMe: true)
    #expect(
      text == #"""
        ---
        title: "Q3 \"plan\" \\ review"
        date: 2026-11-19T09:30:00Z
        duration: 00:47:12
        speakers: [Me]
        ---

        **Me** [00:00:04]: Hi.

        """#)
  }

  @Test func plainLinesForTheSheet() {
    let transcript = MeetingTranscript(
      model: "m",
      utterances: [
        MeetingUtterance(start: 4.6, end: 6, speaker: .me, text: "Let's start."),
        MeetingUtterance(start: 11, end: 12, speaker: .others, text: "Green."),
      ])
    #expect(
      MeetingMarkdown.lines(transcript, label: label, includeMe: true)
        == ["Me [00:00:04]: Let's start.", "Others [00:00:11]: Green."])
    #expect(
      MeetingMarkdown.lines(transcript, label: label, includeMe: false)
        == ["Others [00:00:11]: Green."])
  }

  @Test func markdownLabelsNumberedSpeakers() {
    let numbered: @Sendable (MeetingSpeaker) -> String = {
      $0.number.map { "Speaker \($0)" } ?? ($0 == .me ? "Me" : "Others")
    }
    let transcript = MeetingTranscript(
      model: "m",
      utterances: [
        MeetingUtterance(start: 1, end: 2, speaker: .me, text: "Ready?"),
        MeetingUtterance(start: 3, end: 4, speaker: .numbered(1), text: "Yes."),
        MeetingUtterance(start: 5, end: 6, speaker: .numbered(2), text: "Go."),
      ])
    let all = MeetingMarkdown.render(
      transcript, startedAt: started, duration: 10, label: numbered, includeMe: true)
    #expect(all.contains("speakers: [Me, Speaker 1, Speaker 2]"))
    #expect(all.contains("**Speaker 2** [00:00:05]: Go."))
    let without = MeetingMarkdown.render(
      transcript, startedAt: started, duration: 10, label: numbered, includeMe: false)
    #expect(without.contains("speakers: [Speaker 1, Speaker 2]"))
    #expect(!without.contains("Ready?"))
    #expect(
      MeetingMarkdown.lines(transcript, label: numbered, includeMe: false)
        == ["Speaker 1 [00:00:03]: Yes.", "Speaker 2 [00:00:05]: Go."])
  }

  @Test func fileNameReplacesSeparators() {
    #expect(MeetingMarkdown.fileName(for: "Q3: plan/review") == "Q3- plan-review.md")
  }

  @Test func fileNameOfSeparatorsOnly() {
    #expect(MeetingMarkdown.fileName(for: "/:/") == "---.md")
  }

  @Test func fileNameCutsAtACharacter() {
    let cyrillic = MeetingMarkdown.fileName(for: String(repeating: "ж", count: 150))
    #expect(cyrillic.hasSuffix(".md"))
    let stem = String(cyrillic.dropLast(3))
    #expect(stem.utf8.count <= 200)
    #expect(stem.allSatisfy { $0 == "ж" })
    let family = "👨‍👩‍👧"
    let emoji = String(
      MeetingMarkdown.fileName(for: String(repeating: family, count: 60)).dropLast(3))
    #expect(emoji.utf8.count <= 200)
    #expect(emoji.allSatisfy { String($0) == family })
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
