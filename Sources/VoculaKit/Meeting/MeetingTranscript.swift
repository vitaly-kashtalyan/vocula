import Foundation

public struct MeetingSpeaker: RawRepresentable, Codable, Hashable, Sendable {
  public static let me = MeetingSpeaker(rawValue: "me")
  public static let others = MeetingSpeaker(rawValue: "others")

  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public struct TimedText: Equatable, Sendable {
  public let start: Double
  public let end: Double
  public let text: String

  public init(start: Double, end: Double, text: String) {
    self.start = start
    self.end = max(start, end)
    self.text = text
  }
}

public struct MeetingUtterance: Codable, Equatable, Sendable {
  public let start: Double
  public let end: Double
  public let speaker: MeetingSpeaker
  public let text: String

  public init(start: Double, end: Double, speaker: MeetingSpeaker, text: String) {
    self.start = start
    self.end = max(start, end)
    self.speaker = speaker
    self.text = text
  }
}

public struct MeetingTranscript: Codable, Equatable, Sendable {
  public static let empty = MeetingTranscript(model: nil, utterances: [])

  public let model: String?
  public let utterances: [MeetingUtterance]
}
