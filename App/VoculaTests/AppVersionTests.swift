import Foundation
import Testing

@testable import Vocula

@Suite("App version")
struct AppVersionTests {
  @Test("the version is a real version, not the missing-key dash")
  func versionIsPresent() {
    let version = Bundle.main.shortVersion
    #expect(version != "—", "CFBundleShortVersionString is missing from the bundle")
    #expect(Bundle.main.versionLine == "Vocula \(version)")
    let line = Bundle.main.versionAndBuild
    #expect(line.contains(version))
    #expect(line.contains(Bundle.main.buildNumber))
  }

}
