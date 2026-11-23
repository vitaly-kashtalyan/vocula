import Foundation

public struct SpeakerTurn: Equatable, Sendable {
  public let speaker: String
  public let start: Double
  public let end: Double

  public init(speaker: String, start: Double, end: Double) {
    self.speaker = speaker
    self.start = start
    self.end = end
  }
}
