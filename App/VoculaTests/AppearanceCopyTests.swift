import Foundation
import Testing

@testable import VoculaKit

@Suite("Appearance tiles say what they have always said")
struct AppearanceCopyTests {
  private func titles(in identifier: String? = nil) -> [String] {
    AppearancePreference.allCases.map { preference in
      var resource = preference.title
      if let identifier { resource.locale = Locale(identifier: identifier) }
      return String(localized: resource)
    }
  }

  @Test("the three tiles keep their English")
  func englishTitles() {
    #expect(titles(in: "en") == ["Match System", "Light", "Dark"])
  }

  @Test("and they resolve through the KIT's catalog, not their own fallback")
  func aTranslatedTitleProvesTheBundle() {
    let german = titles(in: "de")
    let complaint =
      "the German titles came back as the English fallback"
      + " — a kit resource is resolving against Bundle.main"
    #expect(german != titles(in: "en"), "\(complaint)")
    #expect(german == ["Wie System", "Hell", "Dunkel"])
  }
}
