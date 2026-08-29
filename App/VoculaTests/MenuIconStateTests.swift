import AppKit
import Testing

@testable import Vocula

@Suite("Menu icon state")
struct MenuIconStateTests {
  private static let all: [MenuIconState] =
    [.idle, .recording, .working, .error("why"), .keyLost("why")]

  @Test(
    "the mark is worn by the two ordinary states and no other",
    arguments: MenuIconStateTests.all)
  func onlyOrdinaryStatesWearTheMark(_ state: MenuIconState) {
    let ordinary = state == .idle || state == .recording
    #expect(
      (state.mark != nil) == ordinary,
      "\(state) disagrees with the mark/symbol split")
  }

  @Test(
    "every state without a mark names a symbol the system can draw",
    arguments: MenuIconStateTests.all)
  func symbolsExist(_ state: MenuIconState) {
    guard state.mark == nil else { return }
    #expect(
      NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil) != nil,
      "“\(state.symbol)” is not an SF Symbol on this system, so the menu bar is empty")
  }
}

@Suite("Recovering the record key after Accessibility comes back")
struct KeyLossRecoveryTests {
  private static let notice = "Accessibility is no longer granted"

  private func next(
    _ current: MenuIconState, granted: Bool, tapInstalled: Bool = true
  ) -> MenuIconState {
    KeyLossRecovery.next(
      current: current, accessibilityGranted: granted,
      revokedNotice: Self.notice, tapInstalled: tapInstalled)
  }

  @Test("granting it again clears the banner the launch put up")
  func grantingRecovers() {
    #expect(next(.keyLost(Self.notice), granted: true) == .idle)
  }

  @Test("a revoked permission raises the banner")
  func revokingRaisesTheBanner() {
    #expect(next(.idle, granted: false) == .keyLost(Self.notice))
  }

  @Test("the banner is not rewritten while it is already up")
  func theBannerDoesNotChurn() {
    #expect(next(.keyLost("something else"), granted: false) == .keyLost("something else"))
  }

  @Test("granting it does not clear an unrelated failure")
  func anUnrelatedErrorSurvives() {
    #expect(next(.error("models are missing"), granted: true) == .error("models are missing"))
  }

  @Test("a permission that came back but a tap that did not is still reported")
  func aDeadTapKeepsTheBanner() {
    #expect(
      next(.keyLost(Self.notice), granted: true, tapInstalled: false) == .keyLost(Self.notice))
  }

  @Test("the tap is only reinstalled when the key is actually lost")
  func theTapIsNotTouchedWhileHealthy() {
    var attempts = 0
    _ = KeyLossRecovery.next(
      current: .idle, accessibilityGranted: true,
      revokedNotice: Self.notice,
      tapInstalled: {
        attempts += 1
        return true
      }())
    #expect(attempts == 0, "an idle app reinstalled its event tap for no reason")
  }
}
