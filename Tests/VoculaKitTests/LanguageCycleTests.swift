import Testing

@testable import VoculaKit

@Suite("Language cycling")
struct LanguageCycleTests {
  private let ruEn = LanguageSelection(codes: ["ru", "en"], autoDetect: true)

  @Test("auto-detect cycles to the first language, and the set survives")
  func autoToFirst() {
    let next = ruEn.cycled()
    #expect(next.autoDetect == false)
    #expect(next.pinned == "ru")
    #expect(next.codes == ["ru", "en"])
  }

  @Test("the first language cycles to the second")
  func firstToSecond() {
    let next = ruEn.cycled().cycled()
    #expect(next.pinned == "en")
    #expect(next.autoDetect == false)
  }

  @Test("the last language cycles back to auto-detect")
  func lastToAuto() {
    #expect(ruEn.cycled().cycled().cycled() == ruEn)
  }

  @Test("three languages take four steps to come back round")
  func threeLanguages() {
    let start = LanguageSelection(codes: ["ru", "en", "de"], autoDetect: true)
    let steps = (1...4).reduce(into: [start]) { acc, _ in acc.append(acc.last!.cycled()) }
    #expect(steps.map(\.pinned) == ["ru", "ru", "en", "de", "ru"])
    #expect(steps.map(\.autoDetect) == [true, false, false, false, true])
  }

  @Test("a single language cycles between itself and auto-detect")
  func oneLanguage() {
    let one = LanguageSelection(codes: ["ru"], autoDetect: true)
    #expect(one.cycled().autoDetect == false)
    #expect(one.cycled().cycled() == one)
  }

  @Test("the pinned language is what the policy chooses")
  func policyFollowsThePin() {
    let pinned = LanguageSelection(codes: ["ru", "en"], autoDetect: false, pinned: "en")
    #expect(
      LanguagePolicy.choose(
        probabilities: ["ru": 0.9, "en": 0.1],
        selection: pinned) == "en")
  }

  @Test("a pin outside the set falls back to the first language")
  func pinOutsideTheSet() {
    #expect(
      LanguageSelection(
        codes: ["ru", "en"], autoDetect: false,
        pinned: "de"
      ).pinned == "ru")
  }

  @Test("removing a language takes it out of the set in either mode")
  func removing() {
    let auto = LanguageSelection(codes: ["ru", "en"], autoDetect: true)
    #expect(auto.removing("ru").codes == ["en"])
    let pinned = LanguageSelection(codes: ["ru", "en"], autoDetect: false, pinned: "en")
    #expect(pinned.removing("ru").codes == ["en"])
    #expect(pinned.removing("ru").pinned == "en")
  }

  @Test("removing the pinned language moves the pin to what is left")
  func removingThePin() {
    let pinned = LanguageSelection(codes: ["ru", "en"], autoDetect: false, pinned: "en")
    #expect(pinned.removing("en").pinned == "ru")
  }

  @Test("the last language cannot be removed")
  func removingTheLast() {
    let one = LanguageSelection(codes: ["ru"], autoDetect: true)
    #expect(one.removing("ru") == one)
  }

  @Test("auto-detect leaves no pin to read back")
  func autoDetectHasNoPin() {
    #expect(
      LanguageSelection(
        codes: ["ru", "en"], autoDetect: true,
        pinned: "en"
      ).pinned == "ru")
  }
}
