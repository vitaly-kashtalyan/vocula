import Foundation

public enum SpeechDetectorError: Error, Equatable {
  case modelNotLoaded
  case failed(String)
}

public protocol SpeechDetecting: Sendable {
  func markup(_ samples: [Float]) async throws -> SpeechMarkup
}
