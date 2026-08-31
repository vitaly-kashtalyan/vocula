import Foundation
import Testing

@testable import Vocula

@MainActor
@Suite("The updater is released when nothing holds it")
struct UpdaterLifetimeTests {
  @Test("an unstarted updater deallocates")
  func unstartedDeallocates() {
    weak var leaked: UpdaterController?
    do {
      let updater = UpdaterController()
      leaked = updater
      #expect(leaked != nil)
    }
    #expect(leaked == nil, "nothing outside this scope should hold it")
  }

  @Test("a diagnose closure capturing its owner weakly does not trap the updater")
  func diagnoseClosureDoesNotRetain() {
    @MainActor final class Owner {
      let updater = UpdaterController()
      init() {
        updater.diagnose = { [weak self] _, _ in _ = self }
      }
    }
    weak var leaked: UpdaterController?
    do {
      let owner = Owner()
      leaked = owner.updater
      owner.updater.diagnose?("update.failed", "outcome=failed")
    }
    #expect(leaked == nil, "the weak capture is what breaks the cycle — see VoculaAppDelegate")
  }

  @Test("a strong capture IS a cycle, which is what the weak one prevents")
  func aStrongCaptureWouldLeak() {
    @MainActor final class Owner {
      let updater = UpdaterController()
      init() {
        updater.diagnose = { [self] _, _ in _ = self }
      }
    }
    weak var leaked: UpdaterController?
    do {
      let owner = Owner()
      leaked = owner.updater
    }
    #expect(
      leaked != nil,
      "if this passes nil the cycle stopped existing and the weak capture above is no longer load-bearing"
    )
  }
}
