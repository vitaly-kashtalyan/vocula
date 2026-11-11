import Foundation

public enum RefinePrompt {
  public static func rendered(_ transcript: String) -> String {
    let fenced =
      transcript
      .replacingOccurrences(of: "</transcript>", with: "< /transcript>", options: .caseInsensitive)
      .replacingOccurrences(of: "<transcript>", with: "< transcript>", options: .caseInsensitive)
    return """
      Rewrite this dictated transcript as tight written prose. Keep every
      distinct claim, question and request, and the speaker's tone. Return only the text.

      OUTPUT
      Return only the rewritten text. No preamble, no explanation, no markdown, no
      quotation marks, no commentary.

      <transcript>
      \(fenced)
      </transcript>

      """
  }
}
