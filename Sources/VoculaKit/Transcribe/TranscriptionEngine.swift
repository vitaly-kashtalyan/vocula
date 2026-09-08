import Foundation

public struct Transcription: Equatable, Sendable {
  public let text: String
  // Optional because an engine may not know: Parakeet identifies the language
  // inside its own pass and reports nothing back, so naming one would be a guess
  // that reaches the History screen as if it were a measurement.
  public let language: String?
  public let firstTokenProbability: Float?
  public let languageScores: [String: Float]

  public init(
    text: String, language: String?,
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
  func warmUp() async

  func transcribe(
    _ samples: [Float], languages: LanguageSelection,
    deadline: Duration
  ) async throws -> Transcription
}

extension Transcribing {
  public func warmUp() async {}
}
