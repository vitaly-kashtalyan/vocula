import Testing

@testable import VoculaKit

private let base = TargetSnapshot(pid: 501, secureInputWasUp: false)

private func unchanged(
  pid: Int32 = 501,
  sameWindow: Bool = true,
  sameElement: Bool = true,
  subrole: FocusedSubrole = .other("AXTextField"),
  secureInputIsUp: Bool = false
) -> TargetComparison {
  TargetComparison(
    pid: pid, sameWindow: sameWindow, sameElement: sameElement,
    subrole: subrole, secureInputIsUp: secureInputIsUp)
}

@Suite("TargetGuard")
struct TargetGuardTests {
  @Test("a secure field blocks the start")
  func secureFieldBlocksStart() {
    #expect(TargetGuardPolicy.mayStart(focusedSubrole: .secureTextField) == false)
  }

  @Test("an unknown or silent Accessibility answer does NOT block the start")
  func unknownDoesNotBlockStart() {
    #expect(TargetGuardPolicy.mayStart(focusedSubrole: .unknown))
    #expect(TargetGuardPolicy.mayStart(focusedSubrole: .other("AXTextArea")))
  }

  @Test("the same target with nothing changed allows the insert")
  func sameTargetAllows() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base,
        comparison: unchanged()) == .allow)
  }

  @Test("a different app denies")
  func appChangedDenies() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base, comparison: unchanged(pid: 999)) == .deny(.appChanged))
  }

  @Test("a different window of the same app denies")
  func windowChangedDenies() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base, comparison: unchanged(sameWindow: false))
        == .deny(.windowChanged))
  }

  @Test("a different field of the same form denies")
  func elementChangedDenies() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base, comparison: unchanged(sameElement: false))
        == .deny(.elementChanged))
  }

  @Test("focus that moved into a secure field inside the same app denies")
  func secureFieldInsideSameAppDenies() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base, comparison: unchanged(subrole: .secureTextField))
        == .deny(.secureField))
  }

  @Test("secure input that went up during transcription denies")
  func secureInputRaisedDenies() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base, comparison: unchanged(secureInputIsUp: true))
        == .deny(.secureInputRaised))
  }

  @Test("a permanently raised flag does NOT deny — that would refuse every insert")
  func permanentlyRaisedFlagAllows() {
    let snapshot = TargetSnapshot(pid: 501, secureInputWasUp: true)
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: snapshot, comparison: unchanged(secureInputIsUp: true)) == .allow)
  }

  @Test("a flag that went down during transcription does not deny either")
  func loweredFlagAllows() {
    let snapshot = TargetSnapshot(pid: 501, secureInputWasUp: true)
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: snapshot, comparison: unchanged(secureInputIsUp: false)) == .allow)
  }

  @Test("an unknown subrole at insert time does not deny")
  func unknownAtInsertAllows() {
    #expect(
      TargetGuardPolicy.decideInsert(
        snapshot: base, comparison: unchanged(subrole: .unknown)) == .allow)
  }
}
