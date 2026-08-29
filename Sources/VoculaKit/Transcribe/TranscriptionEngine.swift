import Foundation

public struct Transcription: Equatable, Sendable {
  public let text: String
  public let language: String
  public let firstTokenProbability: Float?
  public let languageScores: [String: Float]

  public init(
    text: String, language: String,
    firstTokenProbability: Float? = nil,
    languageScores: [String: Float] = [:]
  ) {
    self.text = text
    self.language = language
    self.firstTokenProbability = firstTokenProbability
    self.languageScores = languageScores
  }
}

public enum TranscriptionError: Error, Equatable {
  case modelNotLoaded
  case timedOut
  case engineFailed(String)
}

public protocol Transcribing: Sendable {
  func transcribe(
    _ samples: [Float], languages: LanguageSelection,
    deadline: Duration
  ) async throws -> Transcription
}
