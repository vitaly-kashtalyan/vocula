import Foundation

public enum MeetingMarkdown {
  public static func render(
    _ transcript: MeetingTranscript, startedAt: Date, duration: TimeInterval,
    labels: [MeetingSpeaker: String]
  ) -> String {
    let spoken = transcript.utterances.filter { !$0.dictation }.map {
      (utterance: $0, label: labels[$0.speaker] ?? $0.speaker.rawValue)
    }
    var speakers: [String] = []
    for label in spoken.map(\.label) where !speakers.contains(label) { speakers.append(label) }
    var lines = [
      "---",
      "date: \(startedAt.formatted(.iso8601))",
      "duration: \(clock(duration))",
      "speakers: [\(speakers.joined(separator: ", "))]",
      "---",
    ]
    for (utterance, label) in spoken {
      lines += ["", "**\(label)** [\(clock(utterance.start))]: \(utterance.text)"]
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func clock(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
  }
}
