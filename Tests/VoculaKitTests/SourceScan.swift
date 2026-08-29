import Foundation

enum SourceScan {
  static func logicalLines(_ source: String) -> [String] {
    let physical = source.components(separatedBy: "\n")
    var out = [String](repeating: "", count: physical.count)
    var index = 0
    while index < physical.count {
      var joined = physical[index]
      var depth = openDepth(joined)
      var last = index
      while depth > 0, last + 1 < physical.count {
        last += 1
        let next = physical[last].trimmingCharacters(in: .whitespaces)
        joined += (joined.hasSuffix("(") ? "" : " ") + next
        depth += openDepth(physical[last])
      }
      out[index] = joined
      index = last + 1
    }
    return out
  }

  private static func openDepth(_ line: String) -> Int {
    var depth = 0
    var inString = false
    var escaped = false
    for character in line {
      if escaped {
        escaped = false
        continue
      }
      switch character {
      case "\\" where inString: escaped = true
      case "\"": inString.toggle()
      case "(" where !inString: depth += 1
      case ")" where !inString: depth -= 1
      default: break
      }
    }
    return depth
  }
}
