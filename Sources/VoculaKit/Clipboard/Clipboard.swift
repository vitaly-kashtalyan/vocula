import Foundation

public struct ClipboardSnapshot: Sendable, Equatable {
  public let items: [[String: Data]]
  public let changeCount: Int
  public let abandoned: Bool

  public static let byteCap = 16 << 20

  public init(items: [[String: Data]], changeCount: Int, abandoned: Bool = false) {
    self.items = items
    self.changeCount = changeCount
    self.abandoned = abandoned
  }
}

public enum ClipboardWriteOutcome: Sendable, Equatable {
  case written(changeCount: Int)
  case failed(afterChangeCount: Int?)
}

public protocol Clipboard: AnyObject, Sendable {
  var changeCount: Int { get }
  func snapshot() -> ClipboardSnapshot
  func write(
    _ text: String, concealed: Bool,
    transient: Bool
  ) -> ClipboardWriteOutcome
  @discardableResult
  func restore(_ snapshot: ClipboardSnapshot) -> Int?
}

public protocol PasteSending: Sendable {
  func sendPaste() -> Bool
}
