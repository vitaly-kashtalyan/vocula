import Foundation

public enum DeviceFailover {
  public static let maximumPerSession = 2

  public static func next(
    after lost: String,
    priority: MicrophonePriorityList,
    connected: Set<String>,
    alreadyFailedOver: Int
  ) -> RankedInputDevice? {
    guard alreadyFailedOver < maximumPerSession else { return nil }
    return priority.firstAvailable(in: connected.subtracting([lost]))
  }
}
