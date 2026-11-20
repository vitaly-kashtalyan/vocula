import Foundation

public struct MeetingSpeaker: RawRepresentable, Codable, Hashable, Sendable {
  public static let me = MeetingSpeaker(rawValue: "me")
  public static let others = MeetingSpeaker(rawValue: "others")

  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct TimedText: Equatable, Sendable {
  public let start: Double
  public let end: Double
  public let text: String

  public init(start: Double, end: Double, text: String) {
    self.start = start
    self.end = end
    self.text = text
  }
}

public struct MeetingUtterance: Codable, Equatable, Sendable {
  public let start: Double
  public let end: Double
  public let speaker: MeetingSpeaker
  public let text: String
  public let dictation: Bool

  public init(start: Double, end: Double, speaker: MeetingSpeaker, text: String, dictation: Bool) {
    self.start = start
    self.end = end
    self.speaker = speaker
    self.text = text
    self.dictation = dictation
  }
}

public struct MeetingTranscript: Codable, Equatable, Sendable {
  public let model: String?
  public let utterances: [MeetingUtterance]

  public init(model: String?, utterances: [MeetingUtterance]) {
    self.model = model
    self.utterances = utterances
  }
}
