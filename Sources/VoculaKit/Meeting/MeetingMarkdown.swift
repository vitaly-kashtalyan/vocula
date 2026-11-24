import Foundation

public enum MeetingMarkdown {
  public static func render(
    _ transcript: MeetingTranscript, title: String? = nil, startedAt: Date,
    duration: TimeInterval, label: (MeetingSpeaker) -> String, includeMe: Bool
  ) -> String {
    let spoken = labelled(transcript, label: label, includeMe: includeMe)
    var speakers: [String] = []
    for name in spoken.map(\.label) where !speakers.contains(name) { speakers.append(name) }
    var lines = ["---"]
    if let title {
      let escaped = title.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      lines.append("title: \"\(escaped)\"")
    }
    lines += [
      "date: \(startedAt.formatted(.iso8601))",
      "duration: \(clock(duration))",
      "speakers: [\(speakers.joined(separator: ", "))]",
      "---",
    ]
    for (utterance, name) in spoken {
      lines += ["", "**\(name)** [\(clock(utterance.start))]: \(utterance.text)"]
    }
    return lines.joined(separator: "\n") + "\n"
  }

  public static func lines(
    _ transcript: MeetingTranscript, label: (MeetingSpeaker) -> String, includeMe: Bool
  ) -> [String] {
    labelled(transcript, label: label, includeMe: includeMe).map {
      "\($0.label) [\(clock($0.utterance.start))]: \($0.utterance.text)"
    }
  }

  public static func fileName(for title: String) -> String {
    var stem = ""
    for character in title {
      let next = character == "/" || character == ":" ? "-" : String(character)
      guard stem.utf8.count + next.utf8.count <= 200 else { break }
      stem += next
    }
    return stem + ".md"
  }

  private static func labelled(
    _ transcript: MeetingTranscript, label: (MeetingSpeaker) -> String, includeMe: Bool
  ) -> [(utterance: MeetingUtterance, label: String)] {
    transcript.utterances.filter { includeMe || $0.speaker != .me }.map {
      (utterance: $0, label: label($0.speaker))
    }
  }

  private static func clock(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
  }
}
