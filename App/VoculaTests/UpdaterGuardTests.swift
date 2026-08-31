import Foundation
import Testing

@testable import Vocula

@Suite("The updater refuses every copy that is not the installed one")
struct UpdaterGuardTests {
  @Test("a second copy never starts the updater")
  func secondCopy() {
    #expect(UpdaterController.mayStart(isSecondCopy: true, argumentsDisableUpdates: false) == false)
  }

  @Test("the explicit argument never starts the updater")
  func argument() {
    #expect(UpdaterController.mayStart(isSecondCopy: false, argumentsDisableUpdates: true) == false)
  }

  @Test("the installed, unflagged copy is the only one that starts it")
  func installed() {
    #expect(UpdaterController.mayStart(isSecondCopy: false, argumentsDisableUpdates: false) == true)
  }

  @Test("the second-copy flag is read FIRST, in the shape LoginItemGuardTests uses")
  func secondCopyIsReadFirst() throws {
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vocula/Updates/UpdaterController.swift"), encoding: .utf8)
    let declaration = try #require(source.range(of: "func mayStart"))
    let body = source[declaration.upperBound...]
    let second = try #require(body.range(of: "isSecondCopy"))
    let argument = body.range(of: "argumentsDisableUpdates")
    #expect(argument == nil || second.lowerBound < argument!.lowerBound)
  }
}
