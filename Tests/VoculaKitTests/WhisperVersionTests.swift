import Foundation
import Testing
import VoculaKit

@Suite("Every place that names whisper.cpp names the same build")
struct WhisperVersionTests {
  private static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  private static func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  private static func capture(_ pattern: String, in text: String) throws -> String? {
    try Regex(pattern).firstMatch(in: text)?.output[1].substring.map(String.init)
  }

  @Test("the build page, the licence tag, the notice and the credit form one chain")
  func oneChain() throws {
    let package = try Self.read("Package.swift")
    let notice = try Self.read("App/Vocula/Licenses/THIRD-PARTY.txt")

    let build = try #require(
      try Self.capture(#"releases/download/b(\d+)/whisper-b\1-xcframework\.zip"#, in: package),
      "Package.swift links no whisper.cpp build page (b<N>) — the marker moved or the URL predates 1.9.3"
    )
    let checksum = try #require(
      try Self.capture(
        #"whisper-b\d+-xcframework\.zip"\s*,\s*checksum:\s*"([0-9a-f]{64})""#, in: package),
      "Package.swift names no checksum after the whisper.cpp artefact")
    let tag = try #require(
      try Self.capture(#"ggml-org/whisper\.cpp/blob/v([0-9][0-9.]*)/LICENSE"#, in: notice),
      "THIRD-PARTY.txt names no whisper.cpp licence tag")

    let artefact =
      "https://github.com/ggml-org/whisper.cpp/releases/download/b\(build)/whisper-b\(build)-xcframework.zip"
    #expect(
      notice.contains("\(artefact)\n  SHA-256  \(checksum)"),
      "THIRD-PARTY.txt does not name the artefact and digest Package.swift links")
    #expect(
      notice.contains("b\(build), which is the same commit as tag v\(tag)"),
      "the notice does not tie b\(build) to v\(tag)")
    #expect(ModelFamily.whisper.engineCredit.hasPrefix("whisper.cpp v\(tag) "))
  }
}
