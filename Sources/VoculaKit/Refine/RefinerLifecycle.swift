import Foundation

public struct RefinerLifecycle: Sendable {
  public enum Event: Equatable, Sendable {
    case pipelineStarted(isActive: Bool)
    case settingChanged(isActive: Bool)
    case loadFailed(isEnabled: Bool, model: ModelStatus)
    case tornDown
  }

  public enum Action: Equatable, Sendable {
    case prewarm, unload, discard
  }

  private var isEnabled = false
  private var hasRefiner = false

  public init() {}

  public mutating func handle(_ event: Event) -> [Action] {
    switch event {
    case .pipelineStarted(let enabled):
      hasRefiner = true
      isEnabled = enabled
      return enabled ? [.prewarm] : []
    case .settingChanged(let enabled):
      guard enabled != isEnabled else { return [] }
      isEnabled = enabled
      guard hasRefiner else { return [] }
      return enabled ? [.prewarm] : [.unload]
    case .loadFailed(let enabled, let model):
      guard enabled, model == .ready else { return [] }
      return [.discard]
    case .tornDown:
      defer { hasRefiner = false }
      return hasRefiner ? [.unload] : []
    }
  }
}
