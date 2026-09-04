import Sparkle
import Testing

@testable import Vocula

@Suite("The updater refuses every copy that is not the installed one")
struct UpdaterGuardTests {
  @Test("a second copy never starts the updater")
  func secondCopy() {
    #expect(UpdaterController.mayStart(isSecondCopy: true, argumentsDisableUpdates: false) == false)
  }

  @Test("the explicit argument never starts the updater")
  func argument() {
    #expect(UpdaterController.mayStart(isSecondCopy: false, argumentsDisableUpdates: true) == false)
  }

  @Test("the installed, unflagged copy is the only one that starts it")
  func installed() {
    #expect(UpdaterController.mayStart(isSecondCopy: false, argumentsDisableUpdates: false) == true)
  }

}

@Suite("A found update survives a postponement and not a refusal")
struct FoundUpdateChoiceTests {
  @Test("skipping the version takes the row away")
  func skipClears() {
    #expect(UpdaterController.clearsFoundUpdate(.skip))
  }

  @Test("dismissing the window is a postponement and keeps it")
  func dismissKeeps() {
    #expect(UpdaterController.clearsFoundUpdate(.dismiss) == false)
  }

  @Test("choosing to install keeps it until the new version is running")
  func installKeeps() {
    #expect(UpdaterController.clearsFoundUpdate(.install) == false)
  }
}
