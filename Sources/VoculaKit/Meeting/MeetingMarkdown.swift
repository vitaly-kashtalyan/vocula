import Foundation

public enum MeetingMarkdown {
  public static func render(
    _ transcript: MeetingTranscript, startedAt: Date, duration: TimeInterval,
    labels: [MeetingSpeaker: String]
  ) -> String {
    let spoken = transcript.utterances.filter { !$0.dictation }
    var speakers: [String] = []
    for utterance in spoken {
      let label = labels[utterance.speaker] ?? utterance.speaker.rawValue
      if !speakers.contains(label) { speakers.append(label) }
    }
    let date = ISO8601DateFormatter.string(
      from: startedAt, timeZone: TimeZone(identifier: "UTC")!, formatOptions: .withInternetDateTime)
    var lines = [
      "---",
      "date: \(date)",
      "duration: \(clock(duration))",
      "speakers: [\(speakers.joined(separator: ", "))]",
      "---",
    ]
    for utterance in spoken {
      let label = labels[utterance.speaker] ?? utterance.speaker.rawValue
      lines += ["", "**\(label)** [\(clock(utterance.start))]: \(utterance.text)"]
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func clock(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
  }
}
