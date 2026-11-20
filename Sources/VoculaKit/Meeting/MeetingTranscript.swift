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
    self.end = max(start, end)
    self.text = text
  }
}

public struct MeetingUtterance: Codable, Equatable, Sendable {
  public let start: Double
  public let end: Double
  public let speaker: MeetingSpeaker
  public let text: String
  public let dictation: Bool

  private enum CodingKeys: String, CodingKey { case start, end, speaker, text, dictation }

  public init(start: Double, end: Double, speaker: MeetingSpeaker, text: String, dictation: Bool) {
    self.start = start
    self.end = max(start, end)
    self.speaker = speaker
    self.text = text
    self.dictation = dictation
  }

  public init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      start: try fields.decode(Double.self, forKey: .start),
      end: try fields.decode(Double.self, forKey: .end),
      speaker: try fields.decode(MeetingSpeaker.self, forKey: .speaker),
      text: try fields.decode(String.self, forKey: .text),
      dictation: try fields.decode(Bool.self, forKey: .dictation))
  }
}

public struct MeetingTranscript: Codable, Equatable, Sendable {
  public static let empty = MeetingTranscript(model: nil, utterances: [])

  public let model: String?
  public let utterances: [MeetingUtterance]

  public static func recognized(by model: ModelID, utterances: [MeetingUtterance])
    -> MeetingTranscript
  {
    MeetingTranscript(model: model.rawValue, utterances: utterances)
  }

  private enum CodingKeys: String, CodingKey { case model, utterances }

  init(model: String?, utterances: [MeetingUtterance]) {
    self.model = model
    self.utterances = utterances.enumerated().sorted {
      ($0.element.start, $0.offset) < ($1.element.start, $1.offset)
    }.map(\.element)
  }

  public init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    let model = try fields.decodeIfPresent(String.self, forKey: .model)
    let utterances = try fields.decode([MeetingUtterance].self, forKey: .utterances)
    guard model != nil || utterances.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .utterances, in: fields, debugDescription: "utterances without a model")
    }
    self.init(model: model, utterances: utterances)
  }
}
