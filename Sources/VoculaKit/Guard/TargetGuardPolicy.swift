import Foundation

public struct InsertApproval: Sendable {
  fileprivate init() {}
}

public enum TargetGuardPolicy {
  public static func mayStart(focusedSubrole: FocusedSubrole) -> Bool {
    focusedSubrole != .secureTextField
  }

  public static func decideInsert(
    snapshot: TargetSnapshot,
    comparison: TargetComparison
  ) -> InsertDecision {
    if comparison.subrole == .secureTextField { return .deny(.secureField) }
    if snapshot.pid != comparison.pid { return .deny(.appChanged) }
    if !comparison.sameWindow { return .deny(.windowChanged) }
    if !comparison.sameElement { return .deny(.elementChanged) }
    if !snapshot.secureInputWasUp && comparison.secureInputIsUp {
      return .deny(.secureInputRaised)
    }
    return .allow
  }

  public static func approveInsert(
    snapshot: TargetSnapshot,
    comparison: TargetComparison
  ) -> InsertApproval? {
    guard case .allow = decideInsert(snapshot: snapshot, comparison: comparison) else {
      return nil
    }
    return InsertApproval()
  }
}
