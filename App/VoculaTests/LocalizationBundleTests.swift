import Foundation
import Testing

@testable import VoculaKit

@Suite("The app bundle carries a compiled catalog")
struct LocalizationBundleTests {
  @Test("en is a declared localization")
  func englishIsDeclared() {
    #expect(Bundle.main.localizations.contains("en"))
  }

  @Test("the catalog was COMPILED into the bundle, not merely committed")
  func lprojExists() {
    #expect(Bundle.main.path(forResource: "en", ofType: "lproj") != nil)
  }

  @Test("a symbolic key resolves to something other than itself")
  func keysResolve() {
    #expect(String(localized: "history.dictations") != "history.dictations")
  }

  @Test("the kit's own resource bundle was compiled, not merely copied")
  func kitBundleIsLocalized() {
    #expect(Bundle.module.path(forResource: "en", ofType: "lproj") != nil)
  }

  @Test("a kit-owned key resolves through the kit's bundle")
  func kitKeyResolves() {
    #expect(String(localized: "refusal.noSpeech", bundle: .module) != "refusal.noSpeech")
  }

  @Test("the microphone usage description is localizable and localized")
  func microphoneUsageDescriptionIsInTheCatalog() throws {
    let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
    let english = try #require(Bundle(path: path))
    #expect(
      english.localizedString(
        forKey: "NSMicrophoneUsageDescription",
        value: nil, table: "InfoPlist")
        == "Vocula records audio only while you are dictating.")
    let localized = Bundle.main.localizedInfoDictionary?["NSMicrophoneUsageDescription"]
    #expect((localized as? String)?.isEmpty == false)
  }
}
