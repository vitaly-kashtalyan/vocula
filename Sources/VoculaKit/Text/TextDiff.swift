import Foundation

public enum TextDiff {
  public enum Segment: Equatable, Sendable {
    case same(String)
    case removed(String)
    case added(String)
  }

  public static func words(from old: String, to new: String) -> [Segment] {
    let before = old.split(whereSeparator: \.isWhitespace).map(String.init)
    let after = new.split(whereSeparator: \.isWhitespace).map(String.init)
    var removals: [Int: String] = [:]
    var insertions: [Int: String] = [:]
    for change in after.difference(from: before) {
      switch change {
      case .remove(let offset, let word, _): removals[offset] = word
      case .insert(let offset, let word, _): insertions[offset] = word
      }
    }

    var pieces: [Segment] = []
    var i = 0
    var j = 0
    while i < before.count || j < after.count {
      if let removed = removals[i] {
        pieces.append(.removed(removed))
        i += 1
      } else if let added = insertions[j] {
        pieces.append(.added(added))
        j += 1
      } else if i < before.count, j < after.count {
        pieces.append(.same(before[i]))
        i += 1
        j += 1
      } else {
        break
      }
    }
    return joined(pieces)
  }

  private static func joined(_ pieces: [Segment]) -> [Segment] {
    pieces.reduce(into: []) { result, piece in
      switch (result.last, piece) {
      case (.same(let a), .same(let b)): result[result.count - 1] = .same(a + " " + b)
      case (.removed(let a), .removed(let b)): result[result.count - 1] = .removed(a + " " + b)
      case (.added(let a), .added(let b)): result[result.count - 1] = .added(a + " " + b)
      default: result.append(piece)
      }
    }
  }
}
