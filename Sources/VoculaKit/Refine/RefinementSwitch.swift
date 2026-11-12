import Foundation

public enum RefinementSwitch {
  public enum Footer: Equatable, Sendable {
    case explanation, explanationOffersDownload, pastesAsRecognised
  }

  public enum Action: Equatable, Sendable {
    case startDownload, cancelDownload
  }

  public static func isActive(intent: Bool, model: ModelStatus) -> Bool {
    intent && model == .ready
  }

  public static func isWanted(_ id: ModelID, intent: Bool) -> Bool {
    id != .qwenRefine2B || intent
  }

  public static func footer(intent: Bool, model: ModelStatus) -> Footer {
    if model == .ready { return .explanation }
    return intent ? .pastesAsRecognised : .explanationOffersDownload
  }

  public static func showsLoad(intent: Bool, model: ModelStatus, downloadingThis: Bool) -> Bool {
    intent && model != .ready && !downloadingThis
  }

  public static func toggled(
    on: Bool, model: ModelStatus?, downloadingThis: Bool, busy: Bool
  ) -> Action? {
    if on { return model != .ready && !busy ? .startDownload : nil }
    return downloadingThis ? .cancelDownload : nil
  }
}
