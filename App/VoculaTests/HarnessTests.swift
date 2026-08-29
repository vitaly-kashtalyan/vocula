import Testing

@testable import Vocula

@Suite("App test harness")
struct HarnessTests {
  @Test("the app target is linked and reachable from a test")
  func hostIsLinked() {
    #expect(ApplicationSupport.modelsDirectory.lastPathComponent == "Models")
  }
}
