import Foundation

public enum GestureAdmission: Equatable, Sendable {
  case admit
  case refuse(session: Int)
  case swallow
}

public struct BlockedGestures: Sendable, Equatable {
  private var blocked: Int?

  public init() {}

  public mutating func admits(
    _ signal: DictationSignal,
    isAllowed: () -> Bool
  ) -> GestureAdmission {
    switch signal {
    case .start(let session):
      guard !isAllowed() else {
        blocked = nil
        return .admit
      }
      blocked = session
      return .refuse(session: session)
    case .stop(let session, _), .cancel(let session, _):
      guard session == blocked else { return .admit }
      blocked = nil
      return .swallow
    }
  }
}
