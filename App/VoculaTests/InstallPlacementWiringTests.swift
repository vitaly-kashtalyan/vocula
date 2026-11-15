import Foundation
import Testing
import VoculaKit

@testable import Vocula

@Suite("The read-only answer is statfs's, read once at launch")
struct InstallPlacementWiringTests {
  @Test("the sealed system volume reads read-only")
  func theSealedSystemVolumeIsReadOnly() {
    #expect(UpdaterController.volumeIsReadOnly(atPath: "/System/Applications"))
  }

  @Test("the Applications folder reads writable, though it is a firmlink out of the sealed volume")
  func theApplicationsFolderIsWritable() {
    #expect(!UpdaterController.volumeIsReadOnly(atPath: "/Applications"))
  }

  @Test("the temporary folder reads writable")
  func theTemporaryFolderIsWritable() {
    #expect(!UpdaterController.volumeIsReadOnly(atPath: NSTemporaryDirectory()))
  }

  @Test("a path that does not exist is not read-only, as Sparkle answers")
  func aMissingPathIsNotReadOnly() {
    #expect(!UpdaterController.volumeIsReadOnly(atPath: "/nonexistent-\(UUID().uuidString)"))
  }

  @Test("the test host, a DerivedData copy, has no placement problem")
  @MainActor
  func theTestHostHasNoProblem() {
    #expect(UpdaterController().placementProblem == nil)
  }
}
