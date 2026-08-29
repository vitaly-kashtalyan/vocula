import Foundation
import Testing

@testable import VoculaKit

@Suite("Settings", .serialized)
struct AppSettingsTests {
  private func fresh(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test("defaults are history on, a year, and English alone")
  func defaults() {
    let settings = AppSettings(defaults: fresh("test.settings.defaults"))
    #expect(settings.historyEnabled == true)
    #expect(HistoryRetention.days == 365)
    #expect(settings.languages == .default)
    #expect(settings.languages.codes == ["en"])
    #expect(settings.languages.needsDetection == false)
    #expect(settings.hasCompletedOnboarding == false)
  }

  @Test("a language the user chose outlives the default changing under them")
  func aStoredSelectionWins() {
    let defaults = fresh("test.settings.storedLanguages")
    AppSettings(defaults: defaults).languages =
      LanguageSelection(codes: ["ru", "de"], autoDetect: true)
    #expect(AppSettings(defaults: defaults).languages.codes == ["ru", "de"])
  }

  @Test("the pinned language is stored beside the set")
  func pinnedLanguageRoundTrips() {
    let settings = AppSettings(defaults: fresh("test.settings.pinned"))
    settings.languages = LanguageSelection(
      codes: ["ru", "en"], autoDetect: false,
      pinned: "en")
    #expect(settings.languages.pinned == "en")
    #expect(settings.languages.codes == ["ru", "en"])
    #expect(settings.languages.autoDetect == false)
  }

  @Test("the storage keys and fallbacks are a fixed contract")
  func publishedStorageContract() {
    #expect(AppSettings.historyEnabledKey == "history.enabled")
    #expect(AppSettings.historyEnabledDefault == true)
    let defaults = fresh("test.settings.keys")
    defaults.set(false, forKey: "history.enabled")
    let settings = AppSettings(defaults: defaults)
    #expect(settings.historyEnabled == false)
  }

  @Test("completing onboarding is written through to the defaults store")
  func onboardingCompletionPersists() {
    let defaults = fresh("test.settings.onboarding")
    AppSettings(defaults: defaults).hasCompletedOnboarding = true
    #expect(defaults.bool(forKey: "onboarding.completed") == true)
    #expect(AppSettings(defaults: defaults).hasCompletedOnboarding == true)
  }

  @Test("a session pause masks history without changing the persistent setting")
  func sessionOnlyPause() {
    let defaults = fresh("test.settings.pause")
    let settings = AppSettings(defaults: defaults)
    defer { settings.sessionOnlyPause = false }
    settings.historyEnabled = true
    settings.sessionOnlyPause = true
    #expect(settings.isRecordingHistory == false)
    #expect(settings.historyEnabled == true)
  }

  @Test("the pause is never written to the defaults suite")
  func pauseIsNotPersisted() {
    let defaults = fresh("test.settings.pause.persistence")
    let settings = AppSettings(defaults: defaults)
    defer { settings.sessionOnlyPause = false }
    settings.sessionOnlyPause = true
    #expect(defaults.dictionaryRepresentation().keys.contains { $0.contains("Pause") } == false)
    #expect(AppSettings(defaults: defaults).sessionOnlyPause == true)
  }

  @Test("turning history off permanently survives a restart")
  func permanentOff() {
    let defaults = fresh("test.settings.off")
    let settings = AppSettings(defaults: defaults)
    settings.historyEnabled = false
    #expect(AppSettings(defaults: defaults).isRecordingHistory == false)
  }

  @Test("the microphone priority list round-trips through storage")
  func microphonePriorityRoundTrips() {
    let settings = AppSettings(defaults: fresh("test.settings.microphonePriority"))
    #expect(settings.microphonePriority.devices.isEmpty)
    #expect(settings.microphonePriorityMigrated == false)

    let list = MicrophonePriorityList(devices: [
      RankedInputDevice(uid: "built-in", name: "MacBook Pro Microphone"),
      RankedInputDevice(uid: "usb-1", name: "USB Interface"),
    ])
    settings.microphonePriority = list
    settings.microphonePriorityMigrated = true

    #expect(settings.microphonePriority == list)
    #expect(settings.microphonePriorityMigrated == true)
  }
}
