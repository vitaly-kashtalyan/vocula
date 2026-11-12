import Foundation

public enum RefinementSwitch {
  public enum Footer: Equatable, Sendable {
    case explanation, explanationOffersDownload, pastesAsRecognised
  }

  public enum Action: Equatable, Sendable {
    case startDownload, cancelDownload
  }

  public enum Download: Equatable, Sendable {
    case idle, thisModel, otherModel
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

  public static func toggled(on: Bool, model: ModelStatus, download: Download) -> Action? {
    if on { return model != .ready && download == .idle ? .startDownload : nil }
    return download == .thisModel ? .cancelDownload : nil
  }
}
