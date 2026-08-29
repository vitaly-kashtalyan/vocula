import Foundation
import Testing

@testable import Vocula

@Suite("Design tokens")
struct DesignTokenTests {
  @Test("every generated file still matches Design/tokens.json")
  func generatedFilesAreCurrent() throws {
    var root = URL(fileURLWithPath: #filePath)
    while root.pathComponents.count > 1,
      !FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Design/tokens.json").path)
    {
      root.deleteLastPathComponent()
    }
    let tokens = root.appendingPathComponent("Design/tokens.json")
    try #require(
      FileManager.default.fileExists(atPath: tokens.path),
      "Design/tokens.json was not found above \(#filePath)")

    let swift = URL(fileURLWithPath: "/usr/bin/env")
    let task = Process()
    task.executableURL = swift
    task.arguments = [
      "swift", root.appendingPathComponent("Tools/GenerateTokens.swift").path,
      "--check",
    ]
    task.currentDirectoryURL = root
    let output = Pipe()
    task.standardOutput = output
    task.standardError = output
    try task.run()
    task.waitUntilExit()
    let said =
      String(
        data: output.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8) ?? ""
    let message =
      "a generated file has drifted from Design/tokens.json. "
      + "Run `swift Tools/GenerateTokens.swift`. \(said)"
    #expect(task.terminationStatus == 0, Comment(rawValue: message))
  }
}
