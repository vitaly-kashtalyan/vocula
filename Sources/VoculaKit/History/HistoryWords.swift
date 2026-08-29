import Foundation

public enum HistoryWords {
  public static func count(in text: String?) -> Int {
    guard let text else { return 0 }
    return text.split(whereSeparator: \.isWhitespace).count
  }

  public static func characters(in text: String?) -> Int {
    text?.count ?? 0
  }
}
