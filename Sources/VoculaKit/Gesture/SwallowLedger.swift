import Foundation

public struct SwallowLedger: Sendable {
  public enum Owner: Hashable, Sendable {
    case normal
    case liveCheck
  }

  private struct Claim: Hashable {
    let keyCode: UInt16
    let owner: Owner
  }

  private var claimedBindingKeys: Set<Claim> = []
  private var escapeClaim: Bool?

  public init() {}

  public mutating func claimBindingDown(_ keyCode: UInt16, owner: Owner = .normal) {
    claimedBindingKeys.insert(Claim(keyCode: keyCode, owner: owner))
  }

  public func ownsBindingUp(_ keyCode: UInt16, owner: Owner = .normal) -> Bool {
    claimedBindingKeys.contains(Claim(keyCode: keyCode, owner: owner))
  }

  @discardableResult
  public mutating func releaseBindingUp(_ keyCode: UInt16, owner: Owner = .normal) -> Bool {
    claimedBindingKeys.remove(Claim(keyCode: keyCode, owner: owner)) != nil
  }

  public mutating func noteEscapeDown(swallowed: Bool) {
    guard escapeClaim == nil else { return }
    escapeClaim = swallowed
  }

  public mutating func consumeEscapeUp() -> Bool {
    defer { escapeClaim = nil }
    return escapeClaim ?? false
  }

  public var awaitsRelease: Bool {
    !claimedBindingKeys.isEmpty || escapeClaim == true
  }

  public mutating func reset() {
    claimedBindingKeys.removeAll()
    escapeClaim = nil
  }
}
