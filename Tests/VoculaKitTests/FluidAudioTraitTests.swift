import Foundation
import Testing

@Suite("FluidAudio is built with its diarizer and without its GPL-licensed text-to-speech")
struct FluidAudioTraitTests {
  private static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static func traits(in manifest: String) -> [String]? {
    guard
      let line = manifest.split(separator: "\n").first(where: {
        $0.contains("FluidInference/FluidAudio.git")
      }),
      let list = line.firstMatch(of: /traits: \[([^\]]*)\]/)?.output.1
    else { return nil }
    return list.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(
        in: CharacterSet(charactersIn: "\""))
    }.filter { !$0.isEmpty }
  }

  @Test func theParserSeesWhatWouldShipTheText() {
    let url = #".package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3""#
    #expect(Self.traits(in: url + ")") == nil)
    #expect(Self.traits(in: url + #", traits: ["TTS", "Diarizer"])"#) == ["TTS", "Diarizer"])
    #expect(Self.traits(in: url + ", traits: [])") == [])
    #expect(Self.traits(in: "nothing here") == nil)
  }

  @Test func thePackageAsksForTheDiarizerAlone() throws {
    let manifest = try String(
      contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(Self.traits(in: manifest) == ["Diarizer"])
  }
}
