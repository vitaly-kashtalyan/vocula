import Testing

@testable import VoculaKit

@Suite("Refusal dedup")
struct RefusalDedupTests {
  @Test("two different sessions each get an explanation of their own")
  func differentSessionsAreNotConflated() {
    var dedup = RefusalDedup()
    dedup.noted(session: 1)
    #expect(dedup.alreadyExplained(session: 2) == false)
  }

  @Test("an unpaired refused does not block the next refusal's own dedup")
  func unpairedRefusedDoesNotLeakForward() {
    var dedup = RefusalDedup()
    dedup.noted(session: 1)
    dedup.noted(session: 2)
    #expect(dedup.alreadyExplained(session: 2) == true)
    #expect(dedup.alreadyExplained(session: 1) == false)
  }

  @Test("consuming the marker prevents it from matching twice")
  func markerIsConsumedOnce() {
    var dedup = RefusalDedup()
    dedup.noted(session: 1)
    #expect(dedup.alreadyExplained(session: 1) == true)
    #expect(dedup.alreadyExplained(session: 1) == false)
  }
}
