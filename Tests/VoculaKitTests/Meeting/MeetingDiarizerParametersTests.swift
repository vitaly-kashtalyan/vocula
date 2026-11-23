import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingDiarizerParametersTests {
  private func parameters(_ base64: String) -> Data {
    Data(#"{"tensors":{"psi":{"data_base64":"\#(base64)"}}}"#.utf8)
  }

  private var encoded: String {
    [Float(1.5), Float(-2)].withUnsafeBytes { Data($0) }.base64EncodedString()
  }

  @Test func psiDecodesTheParametersShape() throws {
    #expect(try MeetingDiarizerParameters.psi(from: parameters(encoded)) == [1.5, -2.0])
    let broken = String(encoded.prefix(4)) + #"\n"# + String(encoded.dropFirst(4))
    #expect(try MeetingDiarizerParameters.psi(from: parameters(broken)) == [1.5, -2.0])
  }

  @Test func psiRefusesAnythingElse() {
    #expect(throws: (any Error).self) {
      try MeetingDiarizerParameters.psi(from: Data(#"{"tensors":{}}"#.utf8))
    }
    #expect(throws: (any Error).self) { try MeetingDiarizerParameters.psi(from: parameters("")) }
    #expect(throws: (any Error).self) { try MeetingDiarizerParameters.psi(from: Data("junk".utf8)) }
  }
}
