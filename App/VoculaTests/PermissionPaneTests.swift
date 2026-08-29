import Foundation
import Testing

@testable import Vocula

@MainActor
@Suite("Permission panes")
struct PermissionPaneTests {
  @Test(
    "every candidate parses as a URL, so none is silently skipped",
    arguments: PermissionState.Pane.allCases)
  func candidatesParse(_ pane: PermissionState.Pane) {
    #expect(!pane.candidates.isEmpty, "a pane with no candidates is a dead button")
    for candidate in pane.candidates {
      #expect(
        URL(string: candidate) != nil,
        "“\(candidate)” will not parse, so open(_:) skips it in silence")
      #expect(
        candidate.hasPrefix("x-apple.systempreferences:"),
        "“\(candidate)” is not a System Settings link")
    }
  }

  @Test(
    "the three privacy panes fall back to the bare privacy root",
    arguments: [PermissionState.Pane.inputMonitoring, .accessibility, .microphone])
  func privacyPanesEndAtTheRoot(_ pane: PermissionState.Pane) {
    #expect(pane.candidates.count > 1, "a chain of one cannot fall back")
    #expect(
      pane.candidates.last
        == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
  }

  @Test(
    "each privacy pane asks for its own anchor first",
    arguments: [
      (PermissionState.Pane.inputMonitoring, "Privacy_ListenEvent"),
      (.accessibility, "Privacy_Accessibility"),
      (.microphone, "Privacy_Microphone"),
    ])
  func privacyPanesLeadWithTheirAnchor(_ pane: PermissionState.Pane, _ anchor: String) {
    #expect(pane.candidates.first?.hasSuffix("?\(anchor)") == true)
  }
}
