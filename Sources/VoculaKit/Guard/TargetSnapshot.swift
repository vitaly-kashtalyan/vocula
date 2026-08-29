import Foundation

public enum FocusedSubrole: Equatable, Sendable {
  case secureTextField
  case other(String)
  case unknown
}

public struct TargetSnapshot: Equatable, Sendable {
  public let token: UUID
  public let pid: Int32
  public let secureInputWasUp: Bool

  public init(token: UUID = UUID(), pid: Int32, secureInputWasUp: Bool) {
    self.token = token
    self.pid = pid
    self.secureInputWasUp = secureInputWasUp
  }
}

public struct TargetComparison: Equatable, Sendable {
  public let pid: Int32
  public let sameWindow: Bool
  public let sameElement: Bool
  public let subrole: FocusedSubrole
  public let secureInputIsUp: Bool

  public init(
    pid: Int32, sameWindow: Bool, sameElement: Bool,
    subrole: FocusedSubrole, secureInputIsUp: Bool
  ) {
    self.pid = pid
    self.sameWindow = sameWindow
    self.sameElement = sameElement
    self.subrole = subrole
    self.secureInputIsUp = secureInputIsUp
  }
}

public enum InsertDenyReason: String, Equatable, Sendable, CaseIterable {
  case secureField
  case appChanged
  case windowChanged
  case elementChanged
  case secureInputRaised
}

public enum InsertDecision: Equatable, Sendable {
  case allow
  case deny(InsertDenyReason)
}
