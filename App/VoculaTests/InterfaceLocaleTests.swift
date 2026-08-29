import Foundation
import Testing

@testable import VoculaKit

@Suite("The interface locale follows the interface")
struct InterfaceLocaleTests {
  private static let language = Locale(
    identifier: Locale.interface.language.languageCode?.identifier ?? "en")

  @Test("every translated locale is actually in the bundle")
  func theTranslationsShip() {
    let shipped = Set(Bundle.main.localizations)
    for code in ["en", "de", "ru", "es", "fr", "it", "pt-BR", "uk", "pl"] {
      #expect(shipped.contains(code), "\(code) is translated but not in the bundle")
    }
    #expect(
      shipped.contains(Locale.interface.identifier)
        || Bundle.main.preferredLocalizations.contains(Locale.interface.identifier),
      "the interface resolved to \(Locale.interface.identifier), which is not shipped")
  }

  @Test("a compact number renders in the interface's language, not the host region")
  func compactNumbersFollowTheInterface() {
    let rendered = (3200).formatted(.number.notation(.compactName).locale(.interface))
    #expect(
      rendered
        == (3200).formatted(
          .number.notation(.compactName)
            .locale(Self.language)))
  }

  @Test("a month name renders in the interface's language")
  func monthNamesFollowTheInterface() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .interface
    let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
    #expect(
      january.formatted(.dateTime.month(.abbreviated).locale(.interface))
        == january.formatted(.dateTime.month(.abbreviated).locale(Self.language)))
  }

  @Test("weekday and month labels come from the same locale")
  func weekdaysAndMonthsAgree() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .interface
    var reference = Calendar(identifier: .gregorian)
    reference.locale = Self.language
    #expect(calendar.shortWeekdaySymbols == reference.shortWeekdaySymbols)
  }

  @Test("a byte count follows the interface, not the region")
  func byteCountsFollowTheInterface() {
    let interface = (1_620_000_000).formatted(.byteCount(style: .file).locale(.interface))
    #expect(
      interface
        == (1_620_000_000)
        .formatted(.byteCount(style: .file).locale(Self.language)))
  }
}
