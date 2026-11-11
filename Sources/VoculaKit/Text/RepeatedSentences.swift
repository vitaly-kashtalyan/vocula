import Foundation

public enum RepeatedSentences {
  static let shortestWorthComparing = 3

  public static func collapse(_ text: String) -> String {
    let pieces = sentences(in: text)
    var dropped: [Int] = []
    var kept = pieces.count - 1
    for index in pieces.indices.dropLast().reversed() {
      if isRestarted(text[pieces[index]], by: text[pieces[kept]]) {
        dropped.insert(index, at: 0)
      } else {
        kept = index
      }
    }
    guard !dropped.isEmpty else { return text }
    var result = ""
    var cursor = text.startIndex
    for index in dropped {
      result += text[cursor..<pieces[index].lowerBound]
      cursor = pieces[index + 1].lowerBound
    }
    return result + text[cursor...]
  }

  private static func isRestarted(_ earlier: Substring, by later: Substring) -> Bool {
    guard RefinementPolicy.asks(earlier) == RefinementPolicy.asks(later) else { return false }
    let before = Negations.tokens(in: String(earlier))
    let after = Negations.tokens(in: String(later))
    guard before.count >= shortestWorthComparing, after.starts(with: before) else { return false }
    return !after.dropFirst(before.count).contains(where: Negations.isNegation)
  }

  private static func sentences(in text: String) -> [Range<String.Index>] {
    var pieces: [Range<String.Index>] = []
    var start: String.Index?
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      let next = text.index(after: index)
      if start == nil, !character.isWhitespace { start = index }
      if let open = start, ".!?".contains(character),
        next == text.endIndex || text[next].isWhitespace
      {
        pieces.append(open..<next)
        start = nil
      }
      index = next
    }
    if let open = start { pieces.append(open..<text.endIndex) }
    return pieces
  }
}
