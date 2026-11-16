import Foundation
import Testing
import VoculaKit

@Suite struct ModelMirrorTests {
  @Test("the check catches each kind of fault")
  func catchesEachKindOfFault() throws {
    #expect(pins.count == ModelManifest.current.count + retired.count)
    try #require(pins.count >= 4)
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
    assets[1]["size"] = pins[1].byteSize + 1
    assets[2]["digest"] = "sha256:" + String(repeating: "0", count: 64)
    assets[3]["digest"] = NSNull()
    assets.removeFirst()
    let firstName = pins[0].url.lastPathComponent
    assets.append([
      "browser_download_url":
        "https://github.com/someone-else/vocula/releases/download/models-v1/" + firstName,
      "size": pins[0].byteSize, "digest": "sha256:" + pins[0].sha256,
    ])
    try write(assets, latestTag: "models-v1")

    let leadingNames = try check(directory: directory).map {
      $0.components(separatedBy: ": ")[0]
    }
    #expect(
      leadingNames
        == pins.prefix(4).map(\.url.lastPathComponent) + [firstName, "latest release"])
  }

  @Test("a document that is not a release fails the check rather than passing it")
  func aDocumentThatIsNotAReleaseFails() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(throws: (any Error).self) { try check(directory: directory) }
    try Data(#"{"message":"Not Found"}"#.utf8)
      .write(to: directory.appendingPathComponent("models-v1.json"))
    try Data(#"{"tag_name":"v9.9.9","assets":[]}"#.utf8)
      .write(to: directory.appendingPathComponent("latest.json"))
    #expect(throws: (any Error).self) { try check(directory: directory) }
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

private func violations(pins: [Pin], mirror: Release, latest: Release) -> [String] {
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

private func check(directory: URL) throws -> [String] {
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  func release(_ file: String) throws -> Release {
    try decoder.decode(
      Release.self, from: Data(contentsOf: directory.appendingPathComponent(file)))
  }
  return violations(
    pins: pins, mirror: try release("models-v1.json"), latest: try release("latest.json"))
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
