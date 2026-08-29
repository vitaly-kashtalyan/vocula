import Foundation

public struct GestureConfig: Sendable, Equatable {
  public var primary: KeyBinding
  public var languageCycle: KeyBinding?
  public var timings: Timings

  public init(
    primary: KeyBinding = .fn,
    languageCycle: KeyBinding? = nil,
    timings: Timings = .default
  ) {
    self.primary = primary
    self.languageCycle = languageCycle
    self.timings = timings
  }

  var collisionRuleApplies: Bool {
    primary.isBareModifier
  }
}

public struct GestureStateMachine: Sendable {
  private enum State: Equatable {
    case idle
    case holding(session: Int, pressedAt: Timestamp)
    case spentHoldKeyDown
  }

  public var config: GestureConfig
  private var state: State = .idle
  private var lastSession = 0

  public init(config: GestureConfig) { self.config = config }

  public mutating func handle(_ input: GestureInput) -> GestureOutput {
    switch input {
    case .bindingDown(let at): return down(at)
    case .bindingUp(let at): return up(at)
    case .foreignKey(let at): return foreignKey(at)
    case .escape(let at): return escape(at)
    case .tick(let at): return tick(at)
    }
  }

  private mutating func down(_ at: Timestamp) -> GestureOutput {
    switch state {
    case .idle, .spentHoldKeyDown:
      lastSession += 1
      state = .holding(session: lastSession, pressedAt: at)
      return GestureOutput(
        signals: [.start(session: lastSession)],
        nextDeadline: at + config.timings.maxRecording)
    case .holding:
      return GestureOutput(nextDeadline: currentDeadline())
    }
  }

  private mutating func up(_ at: Timestamp) -> GestureOutput {
    switch state {
    case .holding(let session, let pressedAt):
      state = .idle
      let signal: DictationSignal =
        at - pressedAt < config.timings.minRecording
        ? .cancel(session: session, reason: .tooShort)
        : .stop(session: session, reason: .releasedHold)
      return GestureOutput(signals: [signal], nextDeadline: nil)
    case .idle, .spentHoldKeyDown:
      state = .idle
      return GestureOutput(nextDeadline: nil)
    }
  }

  private mutating func tick(_ at: Timestamp) -> GestureOutput {
    switch state {
    case .holding(let session, let pressedAt):
      guard at - pressedAt >= config.timings.maxRecording else {
        return GestureOutput(nextDeadline: currentDeadline())
      }
      state = .spentHoldKeyDown
      return GestureOutput(signals: [.stop(session: session, reason: .durationLimit)])
    case .idle, .spentHoldKeyDown:
      return GestureOutput(nextDeadline: nil)
    }
  }

  private mutating func foreignKey(_ at: Timestamp) -> GestureOutput {
    guard config.collisionRuleApplies else {
      return GestureOutput(nextDeadline: currentDeadline())
    }
    switch state {
    case .holding(let session, _):
      state = .idle
      return GestureOutput(signals: [.cancel(session: session, reason: .collision)])
    case .idle, .spentHoldKeyDown:
      return GestureOutput(nextDeadline: currentDeadline())
    }
  }

  private mutating func escape(_ at: Timestamp) -> GestureOutput {
    switch state {
    case .holding(let session, _):
      state = .idle
      return GestureOutput(signals: [.cancel(session: session, reason: .escape)])
    case .idle, .spentHoldKeyDown:
      return GestureOutput(nextDeadline: nil)
    }
  }

  public var isHoldingBinding: Bool {
    if case .holding = state { return true }
    return false
  }

  public mutating func abandon() { state = .idle }

  public var isRecording: Bool { isHoldingBinding }

  private func currentDeadline() -> Timestamp? {
    switch state {
    case .idle, .spentHoldKeyDown:
      return nil
    case .holding(_, let pressedAt):
      return pressedAt + config.timings.maxRecording
    }
  }
}
