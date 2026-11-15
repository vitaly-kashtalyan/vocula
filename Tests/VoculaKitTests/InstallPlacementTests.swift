import Testing

@testable import VoculaKit

@Suite("Sparkle 2.9.6's update refusal")
struct InstallPlacementTests {
  private static let translocated =
    "/private/var/folders/ab/cd/T/AppTranslocation/0F1E/d/Vocula.app"

  @Test("a translocated copy on its read-only mount is translocated")
  func aTranslocatedCopyIsTranslocated() {
    #expect(
      InstallPlacement.problem(bundlePath: Self.translocated, volumeIsReadOnly: true)
        == .translocated)
  }

  @Test("a copy on a read-only disk image is a read-only volume")
  func aDiskImageIsReadOnly() {
    #expect(
      InstallPlacement.problem(bundlePath: "/Volumes/Vocula/Vocula.app", volumeIsReadOnly: true)
        == .readOnlyVolume)
  }

  @Test("a translocation path on a writable volume is nothing, as Sparkle checks read-only first")
  func aWritableTranslocationPathIsNothing() {
    #expect(
      InstallPlacement.problem(bundlePath: Self.translocated, volumeIsReadOnly: false) == nil)
  }

  @Test("each case is named by the word a launch argument can carry")
  func eachCaseHasALaunchArgumentWord() {
    #expect(InstallPlacement(rawValue: "translocated") == .translocated)
    #expect(InstallPlacement(rawValue: "readOnlyVolume") == .readOnlyVolume)
    #expect(InstallPlacement(rawValue: "diskImage") == nil)
  }

  @Test("the translocation marker is matched case-sensitively, as Sparkle matches it")
  func theMarkerIsCaseSensitive() {
    #expect(
      InstallPlacement.problem(
        bundlePath: "/private/var/folders/ab/cd/T/apptranslocation/0F1E/d/Vocula.app",
        volumeIsReadOnly: true) == .readOnlyVolume)
  }
}
