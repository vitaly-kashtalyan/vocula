import Foundation

public struct CapturedKey: Sendable, Equatable {
  public let keyCode: UInt16?
  public let modifiers: ModifierSet

  public init(keyCode: UInt16?, modifiers: ModifierSet) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

public enum LiveCheckEvent: Sendable, Equatable {
  case press(at: Timestamp)
  case release(at: Timestamp)
  case timeout(at: Timestamp)
}
