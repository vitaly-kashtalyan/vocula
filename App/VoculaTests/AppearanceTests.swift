import AppKit
import Testing

@testable import Vocula
@testable import VoculaKit

struct AppearanceTests {
  @Test("matching the system means no override at all")
  func systemIsNil() {
    #expect(AppearancePreference.system.nsAppearance == nil)
  }

  @Test("light and dark are the two named appearances")
  func explicitAppearances() {
    #expect(AppearancePreference.light.nsAppearance?.name == .aqua)
    #expect(AppearancePreference.dark.nsAppearance?.name == .darkAqua)
  }
}
