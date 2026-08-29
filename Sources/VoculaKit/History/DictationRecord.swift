import Foundation

public struct DictationRecord: Equatable, Sendable, Codable {
  public let id: UUID
  public var session: Int
  public var createdAt: Date
  public var updatedAt: Date
  public var owner: String?
  public var state: SessionState
  public var reason: String?
  public var rawText: String?
  public var finalText: String?
  public var language: String?
  public var durationMilliseconds: Int
  public var targetBundleID: String?
  public var metrics: SpeechMetrics?
  public var truncated: Bool
  public var modelID: String?
}
