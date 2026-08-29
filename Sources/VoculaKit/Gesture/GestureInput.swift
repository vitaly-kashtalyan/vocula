import Foundation

public typealias Timestamp = Duration

public enum GestureInput: Sendable, Equatable {
  case bindingDown(Timestamp)
  case bindingUp(Timestamp)
  case foreignKey(Timestamp)
  case escape(Timestamp)
  case tick(Timestamp)
}
