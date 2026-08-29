import Foundation

public struct InputMeterRequest: Equatable, Sendable {
  public var opensOnDemandOnly: Bool
  public var appIsActive: Bool
  public var userAskedToListen: Bool

  public init(opensOnDemandOnly: Bool, appIsActive: Bool, userAskedToListen: Bool) {
    self.opensOnDemandOnly = opensOnDemandOnly
    self.appIsActive = appIsActive
    self.userAskedToListen = userAskedToListen
  }
}

public enum InputMeterPolicy {
  public static func shouldListen(_ request: InputMeterRequest) -> Bool {
    guard request.appIsActive else { return false }
    return request.userAskedToListen || !request.opensOnDemandOnly
  }
}
