enum SingleLine {
  static func collapse(_ text: String) -> String {
    text.split(whereSeparator: { $0.isNewline || $0 == "\t" || $0 == " " })
      .joined(separator: " ")
  }
}
