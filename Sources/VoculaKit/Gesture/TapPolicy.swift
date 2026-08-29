import Foundation

public struct AbsorbSet: Equatable, Sendable {
  public var primaryBinding: Bool
  public var languageCycle: Bool
  public var escape: Bool
}

public enum TapPolicy {
  public static func absorbedKeys(config: GestureConfig, isRecording: Bool) -> AbsorbSet {
    AbsorbSet(
      primaryBinding: config.primary.absorbsOwnEvent,
      languageCycle: config.languageCycle?.absorbsOwnEvent ?? false,
      escape: isRecording)
  }

  public static func needsActiveTap(config: GestureConfig, isRecording: Bool) -> Bool {
    let set = absorbedKeys(config: config, isRecording: isRecording)
    return set.primaryBinding || set.languageCycle || set.escape
  }
}

public enum SyntheticEventSignature {
  public static let value: Int64 = 0x564F_4355_4C41
}

public enum SelfEventFilter {
  public static func isOurs(userData: Int64) -> Bool {
    userData == SyntheticEventSignature.value
  }
}

public enum ReArmDecision: Equatable, Sendable {
  case reArm(attempt: Int)
  case reArmAndWarn(attempt: Int)
}

public struct ReArmCounter: Sendable {
  public var window: Duration = .seconds(300)
  private var attempts: [Timestamp] = []

  public init() {}

  public mutating func disabled(at instant: Timestamp) -> ReArmDecision {
    attempts.removeAll { instant - $0 > window }
    attempts.append(instant)
    return attempts.count >= 3
      ? .reArmAndWarn(attempt: attempts.count)
      : .reArm(attempt: attempts.count)
  }
}
