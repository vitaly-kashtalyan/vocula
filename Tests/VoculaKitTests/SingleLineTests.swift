import Testing

@testable import VoculaKit

@Suite("SingleLine")
struct SingleLineTests {
  @Test(
    "every line separator becomes one space, and CRLF is one grapheme so it yields one",
    arguments: [
      ("a\nb", "a b"),
      ("a\rb", "a b"),
      ("a\r\nb", "a b"),
      ("a\u{0B}b", "a b"),
      ("a\u{0C}b", "a b"),
      ("a\u{85}b", "a b"),
      ("a\u{2028}b", "a b"),
      ("a\u{2029}b", "a b"),
      ("a\tb", "a b"),
    ])
  func separatorsCollapse(input: String, expected: String) {
    #expect(SingleLine.collapse(input) == expected)
  }

  @Test(
    "runs collapse and edges are trimmed",
    arguments: [
      ("  a \n\n\t b  ", "a b"),
      ("\n\n", ""),
      ("", ""),
    ])
  func runsCollapse(input: String, expected: String) {
    #expect(SingleLine.collapse(input) == expected)
  }

  @Test(
    "a space that is not one of the three separators survives, so French keeps its narrow gap",
    arguments: [
      "Bonjour\u{00A0}!",
      "\u{3000}a",
    ])
  func otherSpacesSurvive(input: String) {
    #expect(SingleLine.collapse(input) == input)
  }
}
