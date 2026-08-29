import Foundation
import Testing

@testable import VoculaKit

@Suite("Appearance")
struct AppearancePreferenceTests {
  @Test("the default is the system's own appearance")
  func defaultsToSystem() {
    #expect(AppearancePreference.default == .system)
    #expect(AppearancePreference(stored: nil) == .system)
  }

  @Test("an unknown stored value falls back to the system")
  func unknownFallsBack() {
    #expect(AppearancePreference(stored: "sepia") == .system)
    #expect(AppearancePreference(stored: "") == .system)
  }

  @Test("the three stored values are a fixed contract")
  func rawValues() {
    #expect(AppearancePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
    #expect(AppearancePreference.storageKey == "appearance")
  }

  @Test("every choice has a key a menu can show")
  func titles() {
    let keys = AppearancePreference.allCases.map { "\($0.title)" }
    #expect(Set(keys).count == 3)
    #expect(keys.allSatisfy { !$0.isEmpty })
  }

  @Test("the setting round-trips through storage")
  func roundTrip() {
    let defaults = UserDefaults(suiteName: "test.appearance")!
    defaults.removePersistentDomain(forName: "test.appearance")
    let settings = AppSettings(defaults: defaults)
    #expect(settings.appearance == .system)
    settings.appearance = .dark
    #expect(AppSettings(defaults: defaults).appearance == .dark)
  }
}
