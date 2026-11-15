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

  @Test("the Applications folder is nothing")
  func theApplicationsFolderIsNothing() {
    #expect(
      InstallPlacement.problem(bundlePath: "/Applications/Vocula.app", volumeIsReadOnly: false)
        == nil)
  }

  @Test("a DerivedData build is nothing")
  func aDerivedDataBuildIsNothing() {
    #expect(
      InstallPlacement.problem(
        bundlePath:
          "/Users/x/Library/Developer/Xcode/DerivedData/Vocula-ab/Build/Products/Debug/Vocula.app",
        volumeIsReadOnly: false) == nil)
  }

  @Test("the translocation marker is matched case-sensitively, as Sparkle matches it")
  func theMarkerIsCaseSensitive() {
    #expect(
      InstallPlacement.problem(
        bundlePath: "/private/var/folders/ab/cd/T/apptranslocation/0F1E/d/Vocula.app",
        volumeIsReadOnly: true) == .readOnlyVolume)
  }
}
