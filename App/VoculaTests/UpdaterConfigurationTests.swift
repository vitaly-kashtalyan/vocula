import Foundation
import Testing

@testable import Vocula

@Suite("The updater's configuration is pinned, not incidental")
struct UpdaterConfigurationTests {
  private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

  @Test("the feed URL is this literal")
  func feedURL() {
    #expect(
      info["SUFeedURL"] as? String
        == "https://github.com/vitaly-kashtalyan/vocula/releases/latest/download/appcast.xml")
  }

  @Test("the public key is a real Ed25519 key")
  func publicKey() {
    let key = info["SUPublicEDKey"] as? String
    #expect(key?.count == 44)
    #expect(Data(base64Encoded: key ?? "")?.count == 32)
  }

  @Test("automatic checks ship ON")
  func automaticChecks() {
    #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
  }

  @Test("the silent-install checkbox Sparkle would otherwise offer is refused")
  func noSilentInstallOffer() {
    #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
  }

  @Test("the signature is checked before the archive is unpacked, and the feed is signed")
  func signedBeforeUnpacked() {
    #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    #expect(info["SURequireSignedFeed"] as? Bool == true)
  }

  @Test("automatic download, profiling and the interval are all ABSENT")
  func absentKeys() {
    #expect(info["SUAutomaticallyUpdate"] == nil)
    #expect(info["SUEnableSystemProfiling"] == nil)
    #expect(info["SUScheduledCheckInterval"] == nil)
  }
}
