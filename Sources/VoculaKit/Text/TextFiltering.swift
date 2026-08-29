import Foundation

public struct FilterResult: Equatable, Sendable {
  public let text: String
  public let wasDroppedAsHallucination: Bool

  public init(text: String, wasDroppedAsHallucination: Bool) {
    self.text = text
    self.wasDroppedAsHallucination = wasDroppedAsHallucination
  }
}

public protocol TextFiltering: Sendable {
  func evaluate(_ text: String, language: String?) -> FilterResult
}

extension TextFiltering {
  public func filter(_ text: String, language: String? = nil) -> String {
    evaluate(text, language: language).text
  }
}

public struct PassthroughFilter: TextFiltering {
  public init() {}
  public func evaluate(_ text: String, language: String?) -> FilterResult {
    FilterResult(text: text, wasDroppedAsHallucination: false)
  }
}
