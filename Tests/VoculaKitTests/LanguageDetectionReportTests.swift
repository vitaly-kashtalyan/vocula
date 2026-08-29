import Testing

@testable import VoculaKit

@Suite("Language detection is logged when it was unsure, and never names a language")
struct LanguageDetectionReportTests {
  @Test("a landslide says nothing")
  func aClearWinnerIsNotWorthALine() {
    #expect(
      LanguageDetectionReport.line(chosen: "en", scores: ["en": 0.97, "ru": 0.02, "pl": 0.01])
        == nil)
  }

  @Test("a winner just over the floor, with the selection holding the mass, says nothing")
  func confidenceIsNotClosenessAndViceVersa() {
    #expect(
      LanguageDetectionReport.line(chosen: "en", scores: ["en": 0.6, "ru": 0.39]) == nil,
      "0.6 is above the floor, the gap is 0.21, and the selection holds 99%")
  }

  @Test("a lost detector is reported however far ahead the winner is")
  func aLostDetectorIsReported() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "ru", scores: ["ru": 0.29, "pl": 0.10, "en": 0.01]))
    #expect(line == "langs=3 pct=29 nextPct=10 selPct=40 gap=190")
  }

  @Test("a coin flip between two confident scores is reported, and the gap shows it")
  func aCloseCallAtHighConfidenceIsReported() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "en", scores: ["en": 0.5005, "ru": 0.4995]))
    #expect(line == "langs=2 pct=50 nextPct=50 selPct=100 gap=1")
  }

  @Test("a detector that heard none of the selected languages is reported")
  func aSelectionThatHoldsNoMassIsReported() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "pl", scores: ["pl": 0.55, "en": 0.03]))
    #expect(line == "langs=2 pct=55 nextPct=3 selPct=58 gap=520")
  }

  @Test("a chosen language that lost is not reported as a tie")
  func aNegativeGapKeepsItsSign() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "en", scores: ["en": 0.1, "ru": 0.8]))
    #expect(line.contains("gap=-700"))
  }

  @Test("a NaN score is a sentinel, never a crash")
  func nanIsAnswered() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "en", scores: ["en": .nan, "ru": 0.2]))
    #expect(line.contains("pct=\(LanguageDetectionReport.notANumber)"))
  }

  @Test("the peak level rides along when the caller has one")
  func thePeakIsCarried() throws {
    let line = try #require(
      LanguageDetectionReport.line(
        chosen: "ru", scores: ["ru": 0.29, "pl": 0.10], peak: 0.123))
    #expect(line.hasSuffix("pk=123"))
  }

  @Test("no language code ever reaches the line")
  func theLineNamesNoLanguage() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "pl", scores: ["pl": 0.41, "ru": 0.34]))
    for code in ["pl", "ru", "en", "lang=", "next="] {
      #expect(!line.contains(code), "\(line) names \(code)")
    }
  }

  @Test("the detail the controller emits survives the log's own redaction")
  func theDetailReachesTheLog() throws {
    let detail = try #require(
      LanguageDetectionReport.detail(
        session: 5, chosen: "pl", scores: ["pl": 0.41, "ru": 0.34, "en": 0.19],
        peak: 0.4))
    #expect(
      DiagnosticLog.redact(detail) == detail,
      "the log dropped a field: every key must be in DiagnosticLog.allowedKeys")
  }

  @Test("an exact tie is a close call, and the percentages are the chosen one's")
  func anExactTieIsReported() throws {
    let line = try #require(
      LanguageDetectionReport.line(chosen: "ru", scores: ["pl": 0.40, "ru": 0.40]))
    #expect(line == "langs=2 pct=40 nextPct=40 selPct=80 gap=0")
  }

  @Test("a chosen language whisper never scored is not invented as a zero")
  func anUnscoredChoiceIsNotReported() {
    #expect(LanguageDetectionReport.line(chosen: "xx", scores: ["yy": 0.9]) == nil)
  }

  @Test("one language is never a close call, however low it scores")
  func aSingleLanguageIsNotACloseCall() {
    #expect(LanguageDetectionReport.line(chosen: "en", scores: ["en": 0.20]) == nil)
    #expect(LanguageDetectionReport.line(chosen: "en", scores: [:]) == nil)
  }
}
