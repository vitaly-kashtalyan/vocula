import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@Suite("Russian plurals resolve per number")
struct RussianPluralTests {
  private static let key = "history.dictations"

  private func render(_ count: Int) throws -> String {
    let path = try #require(
      Bundle.main.path(forResource: "ru", ofType: "lproj"),
      "ru is not seeded in the app bundle")
    let russian = try #require(Bundle(path: path))
    let format = russian.localizedString(forKey: Self.key, value: nil, table: nil)
    try #require(format != Self.key, "the ru catalog has no value for \(Self.key)")
    return String(format: format, locale: Locale(identifier: "ru"), count)
  }

  @Test("one, few and many are three different words")
  func theThreeFormsDiffer() throws {
    #expect(try render(1) == "1 диктовка")
    #expect(try render(2) == "2 диктовки")
    #expect(try render(5) == "5 диктовок")
  }

  @Test("21 and 101 take the singular form, as Russian requires")
  func theBoundaryRows() throws {
    #expect(try render(21) == "21 диктовка")
    #expect(try render(101) == "101 диктовка")
  }

  @Test("English is unaffected by the seed")
  func englishStillReadsAsEnglish() throws {
    let format = try englishFormat(Self.key)
    #expect(String(format: format, locale: Locale(identifier: "en"), 1) == "1 dictation")
    #expect(String(format: format, locale: Locale(identifier: "en"), 2) == "2 dictations")
  }

  private func englishFormat(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: nil, table: nil)
  }

  private func render(_ key: String, _ count: Int) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
    let russian = try #require(Bundle(path: path))
    let format = russian.localizedString(forKey: key, value: nil, table: nil)
    try #require(format != key, "the ru catalog has no value for \(key)")
    return String(format: format, locale: Locale(identifier: "ru"), count)
  }

  @Test("the trial's one-form is a COUNT in Russian, never \"last day\"")
  func trialDaysNeverSaysLastDay() throws {
    #expect(try render("licence.trialDaysLeft", 1) == "Пробный · остался 1 день")
    #expect(try render("licence.trialDaysLeft", 21) == "Пробный · остался 21 день")
    #expect(try render("licence.trialDaysLeft", 3) == "Пробный · осталось 3 дня")
    #expect(try render("licence.trialDaysLeft", 7) == "Пробный · осталось 7 дней")
  }

  @Test("every counted key has four Russian forms that differ where they must")
  func countedKeysTakeFourForms() throws {
    for key in [
      "history.records", "history.retentionDays", "history.words",
      "licence.dictationsLeftNotice",
    ] {
      let one = try render(key, 1)
      let few = try render(key, 3)
      let many = try render(key, 7)
      #expect(one != few, "\(key): one and few are the same")
      #expect(few != many, "\(key): few and many are the same")
      func words(_ text: String) -> String { text.filter { !$0.isNumber } }
      #expect(
        words(try render(key, 21)) == words(one),
        "\(key): 21 did not take the one-form")
    }
  }
}

@Suite("The diagnostic header counts what it shows")
struct DiagnosticsPluralTests {
  private static let english: Bundle = {
    let path = Bundle.main.path(forResource: "en", ofType: "lproj")
    return path.flatMap(Bundle.init(path:)) ?? .main
  }()

  private func header(_ count: Int) -> String {
    CountedText.text(
      DiagnosticsCopy.lastEvents(count: count),
      bundle: Self.english, locale: Locale(identifier: "en"))
  }

  @Test("English distinguishes one from many")
  func englishForms() {
    #expect(header(1) == "Last 1 event")
    #expect(header(30) == "Last 30 events")
  }

  @Test(
    "Russian picks all four categories",
    arguments: [
      (1, "Последнее 1 событие"), (3, "Последние 3 события"),
      (7, "Последние 7 событий"), (21, "Последнее 21 событие"),
    ])
  func russianForms(_ count: Int, _ expected: String) {
    var resource = LocalizedStringResource(
      "diagnostics.lastEvents",
      defaultValue: "Last \(count) events")
    resource.locale = Locale(identifier: "ru")
    #expect(String(localized: resource) == expected)
  }
}
