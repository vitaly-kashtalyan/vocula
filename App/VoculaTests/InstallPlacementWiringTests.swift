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

@Suite("Each case draws its own pair of keys")
struct PlacementCopyTests {
  @Test("a disk image draws the disk-image title and footer")
  func aDiskImageDrawsTheDiskImageKeys() {
    #expect(
      OnboardingScreenCopy.placementTitle(.readOnlyVolume).key
        == "onboarding.placement.diskImage.title")
    #expect(
      OnboardingScreenCopy.placementFooter(.readOnlyVolume).key
        == "onboarding.placement.diskImage.footer")
  }

  @Test("a translocated copy draws its own title and footer")
  func aTranslocatedCopyDrawsItsOwnKeys() {
    #expect(
      OnboardingScreenCopy.placementTitle(.translocated).key
        == "onboarding.placement.translocated.title")
    #expect(
      OnboardingScreenCopy.placementFooter(.translocated).key
        == "onboarding.placement.translocated.footer")
  }
}
