import Testing

@testable import VoculaKit

@Suite("Counted copy")
struct CountedCopyTests {
  @Test(
    "the key is the same for every count; only the number differs",
    arguments: [0, 1, 2, 5, 21, 101])
  func keyIsCountIndependent(count: Int) {
    let copy = HistoryCopy.dictations(count: count)
    #expect(copy.key == "history.dictations")
    #expect(copy.count == count)
  }

  @Test("every counted sentence has a key of its own")
  func keysAreDistinct() {
    let keys = [
      HistoryCopy.dictations(count: 1).key,
      HistoryCopy.records(count: 1).key,
      HistoryCopy.retentionDays(count: 1).key,
      HistoryCopy.words(count: 1).key,
      HistoryCopy.willBeDeleted(count: 1).key,
      LicenceCopy.trialDaysLeft(count: 1).key,
      LicenceCopy.dictationsLeftToday(count: 1, of: 10).key,
      LicenceCopy.dictationsLeftNotice(count: 1).key,
      LanguageCopy.enginesLanguages(count: 1).key,
    ]
    #expect(Set(keys).count == keys.count)
    #expect(keys.allSatisfy { !$0.contains(" ") })
  }

  @Test("a second number is an argument, not a second plural")
  func theLimitIsAnArgument() {
    let copy = LicenceCopy.dictationsLeftToday(count: 3, of: 10)
    #expect(copy.count == 3)
    #expect(copy.extra == [10])
  }
}
