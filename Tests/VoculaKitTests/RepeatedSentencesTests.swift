import Testing

@testable import VoculaKit

@Suite("Repeated sentences")
struct RepeatedSentencesTests {
  @Test(
    "a spoken restart is dropped and the fuller version is the one kept",
    arguments: [
      ("Я хочу сказать. Я хочу сказать, что завтра релиз.", "Я хочу сказать, что завтра релиз."),
      ("Send it to Anna. Send it to Anna and Boris.", "Send it to Anna and Boris."),
    ])
  func keepsTheFullerVersion(text: String, collapsed: String) {
    #expect(RepeatedSentences.collapse(text) == collapsed)
  }

  @Test(
    "a sentence the next one does not start with survives, though its words recur",
    arguments: [
      "Мне нужен этот отчёт. Мне нужно понять, нужен ли этот отчёт вообще.",
      "This is a good idea. My manager also thinks this is a good idea.",
      "Где-то дешевле молоко, я не уверен. Где-то, может быть, дешевле молоко, я не уверен.",
    ])
  func scatteredWordsAreNotARestart(_ text: String) {
    #expect(RepeatedSentences.collapse(text) == text)
  }

  @Test(
    "a restart that adds a negation is a different thought and both survive",
    arguments: [
      "Это работает на маке. Это работает на маке не всегда.",
      "Это можно делать дома. Это можно делать дома, но нельзя на работе.",
    ])
  func negationIsNotARepeat(_ both: String) {
    #expect(RepeatedSentences.collapse(both) == both)
  }

  @Test("two different thoughts are left alone")
  func differentThoughtsSurvive() {
    let text = "Я поставил сервер в стойку. У него внешний диск работает."
    #expect(RepeatedSentences.collapse(text) == text)
  }

  @Test("a sentence too short to compare is never dropped")
  func shortSentencesSurvive() {
    #expect(RepeatedSentences.collapse("Да. Да. Да.") == "Да. Да. Да.")
  }

  @Test(
    "a sentence said, broken off and said again collapses to one",
    arguments: [
      (
        "I will push the branch today. I will push. I will push the branch today.",
        "I will push the branch today."
      ),
      (
        "Сервер не отвечает три часа. Сервер не отвечает. Сервер не отвечает три часа, проверь.",
        "Сервер не отвечает три часа, проверь."
      ),
    ])
  func brokenOffBetweenTwoSayings(text: String, collapsed: String) {
    #expect(RepeatedSentences.collapse(text) == collapsed)
  }

  @Test("emphasis long enough to compare collapses to one sentence")
  func longEmphasisCollapses() {
    #expect(RepeatedSentences.collapse("I love you. I love you. I love you.") == "I love you.")
  }

  @Test("text with nothing to collapse comes back identical")
  func untouchedIsIdentical() {
    let text = "Одно предложение без всяких повторов."
    #expect(RepeatedSentences.collapse(text) == text)
  }

  @Test("a restatement in different casing is still one")
  func casingDoesNotHideARestatement() {
    #expect(
      RepeatedSentences.collapse("I think it works. I THINK it works fine.")
        == "I THINK it works fine.")
  }

  @Test("a decimal is not a sentence boundary, and what was kept is not reflowed")
  func decimalSurvives() {
    #expect(
      RepeatedSentences.collapse(
        "Обнови до 3.5. Это работает у меня на маке. Это работает у меня на маке, проверил.")
        == "Обнови до 3.5. Это работает у меня на маке, проверил.")
  }

  @Test("only the dropped sentence is removed; the spacing around the rest is untouched")
  func spacingIsKept() {
    #expect(
      RepeatedSentences.collapse("Wait!  It works on my Mac.  It works on my Mac, I checked.")
        == "Wait!  It works on my Mac, I checked.")
  }

  @Test(
    "a reordering is a correction, not a restatement",
    arguments: [
      "Move the meeting from Monday to Tuesday. Move the meeting from Tuesday to Monday.",
      "Купи 2 молока и 3 хлеба. Купи 3 молока и 2 хлеба.",
    ])
  func reorderingSurvives(_ text: String) {
    #expect(RepeatedSentences.collapse(text) == text)
  }

  @Test("a shorter sentence after a fuller one may be a correction, so both stay")
  func laterNarrowingSurvives() {
    let text = "Купи молоко, хлеб и сыр. Купи молоко и хлеб."
    #expect(RepeatedSentences.collapse(text) == text)
  }

  @Test(
    "a question is not a restatement of a statement",
    arguments: [
      "Он придёт завтра. Он придёт завтра?",
      "Он придёт завтра? Он придёт завтра.",
      "Он придёт завтра. Он придёт завтра？",
    ])
  func questionSurvives(_ text: String) {
    #expect(RepeatedSentences.collapse(text) == text)
  }

  @Test(
    "a contracted negation added by a restart is a denial",
    arguments: [
      "I agree with the plan. I agree with the plan, but I can't sign it.",
      "I agree with the plan. I agree with the plan, but I can’t sign it.",
      "I agree with the plan. I agree with the plan, but cannot sign it.",
    ])
  func contractedNegationSurvives(_ text: String) {
    #expect(RepeatedSentences.collapse(text) == text)
  }
}
