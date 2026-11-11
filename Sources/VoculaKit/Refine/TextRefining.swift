import Foundation

public protocol TextRefining: Sendable {
  var modelID: String { get }
  func refine(_ text: String, deadline: Duration) async throws -> String
}

public enum RefinementError: Error, Equatable {
  case tokenCap
}
