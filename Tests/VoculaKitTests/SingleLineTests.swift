import Testing

@testable import VoculaKit

@Suite("SingleLine")
struct SingleLineTests {
  @Test(
    "every line separator and tab becomes one space",
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
      ("a  b", "a b"),
      ("  a \n\n\t b  ", "a b"),
      ("\n\n", ""),
      ("", ""),
      ("rm -rf /\n:q!\nsafe", "rm -rf / :q! safe"),
    ])
  func runsCollapse(input: String, expected: String) {
    #expect(SingleLine.collapse(input) == expected)
  }

  @Test(
    "spaces outside the three classes are left alone",
    arguments: [
      "Bonjour\u{00A0}!",
      "Bonjour\u{202F}!",
      "\u{3000}a",
      "你好世界",
      "one two",
    ])
  func otherSpacesSurvive(input: String) {
    #expect(SingleLine.collapse(input) == input)
  }

  @Test("a CRLF is one grapheme and yields one space, not two")
  func crlfIsOneGrapheme() {
    #expect(SingleLine.collapse("a\r\nb").count == 3)
  }
}
