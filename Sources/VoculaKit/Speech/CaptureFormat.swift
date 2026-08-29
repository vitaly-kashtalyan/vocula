import Foundation

public struct CaptureFormat: Equatable, Sendable {
  public let rate: Double
  public let channels: Int

  public init(rate: Double, channels: Int) {
    self.rate = rate
    self.channels = channels
  }

  public static func client(hardwareRate: Double, hardwareChannels: Int) -> CaptureFormat? {
    guard hardwareRate > 0, hardwareChannels > 0 else { return nil }
    return CaptureFormat(rate: hardwareRate, channels: hardwareChannels)
  }
}
