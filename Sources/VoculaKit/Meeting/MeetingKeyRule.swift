import Foundation

public enum MeetingKeyRule {
  public static let itemNotFound: Int32 = -25300
  public static let keyByteCount = 32

  public enum Step: Equatable, Sendable {
    case use
    case mint
    case refuse(code: Int32)
  }

  public static func step(afterLookup status: Int32, keyByteCount: Int?, mayMint: Bool = true)
    -> Step
  {
    if status == 0 {
      return keyByteCount == Self.keyByteCount ? .use : .refuse(code: 0)
    }
    return status == itemNotFound && mayMint ? .mint : .refuse(code: status)
  }
}
