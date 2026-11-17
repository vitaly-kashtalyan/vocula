import Testing

@testable import VoculaKit

@Suite("Accessibility watch")
struct AccessibilityWatchTests {
  @Test("a grant after a revocation restarts even while a rebuilt monitor exists")
  func aGrantAfterARevocationRestartsWithAMonitor() {
    var watch = AccessibilityWatch(trusted: true)
    #expect(watch.observe(trusted: false, monitorExists: true) == .tearDown)
    #expect(watch.observe(trusted: true, monitorExists: true) == .restart)
  }

  @Test("a monitor that reappears while revoked is torn down again")
  func aMonitorThatReappearsWhileRevokedIsTornDownAgain() {
    var watch = AccessibilityWatch(trusted: true)
    #expect(watch.observe(trusted: false, monitorExists: true) == .tearDown)
    #expect(watch.observe(trusted: false, monitorExists: false) == nil)
    #expect(watch.observe(trusted: false, monitorExists: true) == .tearDown)
  }

  @Test("a revocation seen without a monitor still restarts on the grant")
  func aRevocationWithoutAMonitorStillRestartsOnTheGrant() {
    var watch = AccessibilityWatch(trusted: true)
    #expect(watch.observe(trusted: false, monitorExists: false) == nil)
    #expect(watch.observe(trusted: true, monitorExists: false) == .restart)
  }

  @Test("a launch without Accessibility is left to onboarding until a grant is read")
  func aLaunchWithoutAccessibilityIsNotArmed() {
    var watch = AccessibilityWatch(trusted: false)
    #expect(watch.observe(trusted: false, monitorExists: true) == nil)
    #expect(watch.observe(trusted: true, monitorExists: true) == nil)
    #expect(watch.observe(trusted: false, monitorExists: true) == .tearDown)
  }

  @Test("steady readings yield nothing")
  func steadyReadingsYieldNothing() {
    var watch = AccessibilityWatch(trusted: true)
    for _ in 0..<3 {
      #expect(watch.observe(trusted: true, monitorExists: true) == nil)
    }
    _ = watch.observe(trusted: false, monitorExists: true)
    for _ in 0..<3 {
      #expect(watch.observe(trusted: false, monitorExists: false) == nil)
    }
  }

  @Test("a second revocation after a restart tears down again")
  func aSecondRevocationAfterARestartTearsDownAgain() {
    var watch = AccessibilityWatch(trusted: true)
    _ = watch.observe(trusted: false, monitorExists: true)
    _ = watch.observe(trusted: true, monitorExists: false)
    #expect(watch.observe(trusted: true, monitorExists: true) == nil)
    #expect(watch.observe(trusted: false, monitorExists: true) == .tearDown)
  }
}
