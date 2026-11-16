import Foundation
import Testing
import VoculaKit

private let environment = ProcessInfo.processInfo.environment

@Suite struct ModelMirrorTests {
  @Test(
    "the mirror matches every pin",
    .enabled(
      if: environment["VOCULA_RELEASES"] != nil || environment["GITHUB_ACTIONS"] != nil,
      "VOCULA_RELEASES is not set; it names a directory holding models-v1.json and latest.json from the GitHub API"
    ))
  func mirrorMatchesEveryPin() throws {
    let path = try #require(
      environment["VOCULA_RELEASES"],
      "on GitHub Actions the release documents must be fetched before swift test")
    try recordViolations(in: URL(fileURLWithPath: path))
  }

  @Test("the check catches each kind of fault")
  func catchesEachKindOfFault() throws {
    #expect(pins.count == ModelManifest.current.count + retired.count)
    try #require(ModelManifest.current.count >= 4 && !retired.isEmpty)
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    func asset(_ pin: Pin) -> [String: Any] {
      [
        "browser_download_url": pin.url.absoluteString, "size": pin.byteSize,
        "digest": "sha256:" + pin.sha256,
      ]
    }
    func write(_ assets: [[String: Any]], latestTag: String) throws {
      try JSONSerialization.data(withJSONObject: ["tag_name": "models-v1", "assets": assets])
        .write(to: directory.appendingPathComponent("models-v1.json"))
      try JSONSerialization.data(withJSONObject: ["tag_name": latestTag, "assets": [Any]()])
        .write(to: directory.appendingPathComponent("latest.json"))
    }

    try write(pins.map(asset), latestTag: "v9.9.9")
    #expect(try check(directory: directory) == [])

    var assets = pins.map(asset)
    let lastRetired = pins.count - 1
    assets[lastRetired]["size"] = pins[lastRetired].byteSize + 1
    assets[2]["digest"] = "sha256:" + String(repeating: "0", count: 64)
    assets[3]["digest"] = NSNull()
    let firstName = pins[0].url.lastPathComponent
    var moved = assets.removeFirst()
    moved["browser_download_url"] =
      "https://github.com/someone-else/vocula/releases/download/models-v1/" + firstName
    assets.append(moved)
    try write(assets, latestTag: "models-v1")

    let leadingNames = try check(directory: directory).map {
      $0.components(separatedBy: ": ")[0]
    }
    #expect(
      leadingNames
        == [0, 2, 3, lastRetired].map { pins[$0].url.lastPathComponent }
        + [firstName, "latest release"])
    withKnownIssue("planted in a temporary copy, not the live release") {
      try recordViolations(in: directory)
    }
  }

  @Test("a document that is not a release fails the check rather than passing it")
  func aDocumentThatIsNotAReleaseFails() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(#"{"tag_name":"models-v1","assets":[]}"#.utf8)
      .write(to: directory.appendingPathComponent("models-v1.json"))
    try Data(#"{"message":"Not Found"}"#.utf8)
      .write(to: directory.appendingPathComponent("latest.json"))
    #expect(throws: (any Error).self) { try check(directory: directory) }
  }
}

private struct Pin {
  let url: URL
  let sha256: String
  let byteSize: Int64
}

private let retired = [
  Pin(
    url: URL(
      string:
        "https://github.com/vitaly-kashtalyan/vocula/releases/download/models-v1/parakeet-tdt-0.6b-v3.zip"
    )!,
    sha256: "cba75876b0448f11f7db77ce1acb5f2f0619588fe7b4df77bf4b4ec7859be23c",
    byteSize: 466_638_996)
]

private let pins =
  ModelManifest.current.map { Pin(url: $0.remoteURL, sha256: $0.sha256, byteSize: $0.byteSize) }
  + retired

private struct Release: Decodable {
  let tagName: String
  let assets: [Asset]
}

private struct Asset: Decodable {
  let browserDownloadUrl: URL
  let size: Int64
  let digest: String?
}

private func check(directory: URL) throws -> [String] {
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  func release(_ file: String) throws -> Release {
    try decoder.decode(
      Release.self, from: Data(contentsOf: directory.appendingPathComponent(file)))
  }
  let mirror = try release("models-v1.json")
  let latest = try release("latest.json")
  var found: [String] = []
  for pin in pins {
    let name = pin.url.lastPathComponent
    guard let asset = mirror.assets.first(where: { $0.browserDownloadUrl == pin.url }) else {
      found.append("\(name): no asset at \(pin.url.absoluteString)")
      continue
    }
    if asset.size != pin.byteSize {
      found.append("\(name): \(asset.size) bytes, pinned \(pin.byteSize)")
    }
    switch asset.digest {
    case nil: found.append("\(name): GitHub reports no digest")
    case "sha256:" + pin.sha256: break
    case let digest?: found.append("\(name): digest \(digest), pinned sha256:\(pin.sha256)")
    }
  }
  let pinned = Set(pins.map(\.url))
  for asset in mirror.assets where !pinned.contains(asset.browserDownloadUrl) {
    found.append(
      "\(asset.browserDownloadUrl.lastPathComponent): not pinned — name it in ModelManifest, or in retired in Tests/VoculaKitTests/ModelMirrorTests.swift"
    )
  }
  if latest.tagName == "models-v1" {
    found.append(
      "latest release: is models-v1, so releases/latest/download/appcast.xml and Vocula.dmg resolve into it"
    )
  }
  return found
}

private func recordViolations(in directory: URL) throws {
  for message in try check(directory: directory) {
    Issue.record(Comment(rawValue: message))
  }
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
