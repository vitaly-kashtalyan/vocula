import AppKit
import Testing

@testable import Vocula

@MainActor
@Suite("Reopening the window after the menu bar icon was dragged out")
struct MenuBarRecoveryTests {
  private func panel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    return panel
  }

  private func window() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

  @Test("the indicator strip is not a window the user can be sent to")
  func theIndicatorStripDoesNotCount() {
    let strip = panel()
    strip.orderFrontRegardless()
    defer { strip.close() }
    #expect(strip.isVisible, "the panel never came on screen, so the check proves nothing")
    #expect(VoculaAppDelegate.hasVisibleWindow([strip]) == false)
  }

  @Test("a settings window the user can already see does count")
  func aRealWindowCounts() {
    let settings = window()
    settings.orderFront(nil)
    defer { settings.close() }
    #expect(settings.isVisible, "the window never came on screen, so the check proves nothing")
    #expect(VoculaAppDelegate.hasVisibleWindow([settings]) == true)
  }

  @Test("a closed window does not count")
  func aClosedWindowDoesNotCount() {
    #expect(VoculaAppDelegate.hasVisibleWindow([window()]) == false)
  }
}

@MainActor
@Suite("A second copy of the app and the login item")
struct LoginItemGuardTests {
  @Test("a test host never registers itself to start at login")
  func aSecondCopyDoesNotRegister() {
    let suite = "app.vocula.mac.loginitemtest"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(
      VoculaAppDelegate.isSecondCopy,
      "this suite only means something in a process that is a second copy")
    LoginItem.registerIfNeverAsked(defaults: defaults)
    #expect(defaults.object(forKey: "autostart.initialRegistrationAttempted") == nil)
  }
}
