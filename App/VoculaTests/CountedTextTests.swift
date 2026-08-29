import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@Suite("Counted copy renders through the catalog")
struct CountedTextTests {
  private static let everyKind: [CountedCopy] = [
    HistoryCopy.dictations(count: 2),
    HistoryCopy.records(count: 2),
    HistoryCopy.retentionDays(count: 2),
    HistoryCopy.words(count: 2),
    HistoryCopy.willBeDeleted(count: 2),
    LicenceCopy.trialDaysLeft(count: 2),
    LicenceCopy.dictationsLeftToday(count: 2, of: 10),
    LicenceCopy.dictationsLeftNotice(count: 2),
    LanguageCopy.enginesLanguages(count: 99),
  ]

  @Test(
    "every key the kit can produce is in the catalog",
    arguments: CountedTextTests.everyKind)
  func noKeyIsMissing(copy: CountedCopy) {
    let text = CountedText.text(copy)
    #expect(text != "\(copy.count)", "\(copy.key) has no catalog entry")
    #expect(text.contains("\(copy.count)"))
  }

  private static let english: Bundle = {
    let path = Bundle.main.path(forResource: "en", ofType: "lproj")
    return path.flatMap(Bundle.init(path:)) ?? .main
  }()

  private func inEnglish(_ copy: CountedCopy) -> String {
    CountedText.text(copy, bundle: Self.english, locale: Locale(identifier: "en"))
  }

  @Test("one and many are different sentences")
  func singularAndPluralDiffer() {
    #expect(inEnglish(HistoryCopy.dictations(count: 1)) == "1 dictation")
    #expect(inEnglish(HistoryCopy.dictations(count: 2)) == "2 dictations")
    #expect(inEnglish(LicenceCopy.trialDaysLeft(count: 1)) == "Trial · last day")
    #expect(inEnglish(LicenceCopy.trialDaysLeft(count: 3)) == "Trial · 3 days left")
  }

  @Test("the distinction survives in the interface's own language")
  func theDistinctionIsNotEnglishOnly() {
    #expect(
      CountedText.text(HistoryCopy.dictations(count: 1))
        != CountedText.text(HistoryCopy.dictations(count: 2)))
  }

  @Test("the second number is carried through, not swallowed")
  func bothNumbersRender() {
    let text = CountedText.text(LicenceCopy.dictationsLeftToday(count: 3, of: 10))
    #expect(text.contains("3"))
    #expect(text.contains("10"))
  }

  @Test("German plural forms resolve")
  func germanResolves() throws {
    let path = try #require(
      Bundle.main.path(forResource: "de", ofType: "lproj"),
      "de is not in the app bundle")
    let german = try #require(Bundle(path: path))
    let format = german.localizedString(forKey: "history.records", value: nil, table: nil)
    try #require(format != "history.records", "the de catalog has no history.records")
    let one = String(format: format, locale: Locale(identifier: "de"), 1)
    let many = String(format: format, locale: Locale(identifier: "de"), 5)
    #expect(one == "1 Eintrag")
    #expect(many == "5 Einträge")
  }
}
