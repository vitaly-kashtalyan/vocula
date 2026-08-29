import Foundation
import Testing

@testable import VoculaKit

@Suite("Choosing the language the window is written in")
struct InterfaceLanguagesTests {
  private let shipped = ["en", "de", "ru", "es", "fr", "it", "pt-BR", "uk", "pl"]

  @Test("the list comes from the bundle, not from a list someone maintains")
  func theListIsDerived() {
    let codes = InterfaceLanguages.available(in: shipped).map(\.code)
    #expect(Set(codes) == Set(shipped))
  }

  @Test("Base is not offered")
  func baseIsExcluded() {
    let codes = InterfaceLanguages.available(in: shipped + ["Base"]).map(\.code)
    #expect(!codes.contains("Base"))
    #expect(codes.count == shipped.count)
  }

  @Test("each language is named in ITSELF, whatever the window is in")
  func namesAreEndonyms() {
    for interface in ["en", "de", "ru"] {
      let names = Dictionary(
        uniqueKeysWithValues:
          InterfaceLanguages
          .available(in: shipped, displayIn: Locale(identifier: interface))
          .map { ($0.code, $0.name) })
      #expect(
        names["ru"] == "Русский", "ru read \(names["ru"] ?? "nil") from a \(interface) window")
      #expect(names["pl"] == "Polski")
      #expect(names["de"] == "Deutsch")
    }
  }

  @Test("the list is ordered by what the reader sees")
  func sortedByName() {
    let names = InterfaceLanguages.available(in: shipped).map(\.name)
    #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
  }

  @Test("no override means the system decides")
  func systemIsTheAbsenceOfAnOverride() {
    #expect(
      InterfaceLanguages.selected(stored: nil, available: shipped)
        == InterfaceLanguages.systemCode)
    #expect(InterfaceLanguages.override(for: InterfaceLanguages.systemCode) == nil)
    #expect(InterfaceLanguages.override(for: "de") == ["de"])
  }

  @Test("an override naming a language that is gone falls back to the system")
  func aStrandedOverrideFallsBack() {
    #expect(
      InterfaceLanguages.selected(stored: ["sv"], available: shipped)
        == InterfaceLanguages.systemCode)
    #expect(InterfaceLanguages.selected(stored: ["de"], available: shipped) == "de")
  }
}
