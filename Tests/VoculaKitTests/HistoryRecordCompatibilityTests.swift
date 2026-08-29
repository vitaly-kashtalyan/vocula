import Foundation
import Testing

@testable import VoculaKit

@Suite("A day file must survive the build that wrote it")
struct HistoryRecordCompatibilityTests {
  private let recordWithoutModelID = """
    [{"id":"9E1B0C7E-0000-4000-8000-000000000001","session":1,
      "createdAt":774000000,"updatedAt":774000000,"deviceID":"test-mac",
      "state":"sent","rawText":"hello","finalText":"hello","language":"en",
      "durationMilliseconds":900,"truncated":false}]
    """

  @Test("a day written before the newest field was added still decodes")
  func aFileFromAnEarlierBuildDecodes() throws {
    let records = try JSONDecoder()
      .decode([DictationRecord].self, from: Data(recordWithoutModelID.utf8))
    #expect(records.count == 1)
    #expect(records[0].finalText == "hello")
    #expect(records[0].modelID == nil)
  }

  @Test("a day carrying a field from a later build still decodes")
  func anUnknownExtraKeyIsIgnored() throws {
    var future = try #require(
      try JSONSerialization.jsonObject(
        with: Data(recordWithoutModelID.utf8)) as? [[String: Any]])
    future[0]["somethingAddedLater"] = "a value this build cannot know"
    let data = try JSONSerialization.data(withJSONObject: future)

    let records = try JSONDecoder().decode([DictationRecord].self, from: data)
    #expect(records.count == 1)
  }

  @Test("a missing non-optional field takes the whole day, not the record")
  func aMissingRequiredFieldLosesEveryRecordInTheDay() throws {
    var records = try #require(
      try JSONSerialization.jsonObject(
        with: Data(recordWithoutModelID.utf8)) as? [[String: Any]])
    var healthy = records[0]
    healthy["id"] = "9E1B0C7E-0000-4000-8000-000000000002"
    records[0].removeValue(forKey: "durationMilliseconds")
    records.append(healthy)
    let data = try JSONSerialization.data(withJSONObject: records)

    #expect((try? JSONDecoder().decode([DictationRecord].self, from: data)) == nil)
  }

  @Test("a session state from a later build takes the whole day too")
  func anUnknownSessionStateLosesTheDay() throws {
    var records = try #require(
      try JSONSerialization.jsonObject(
        with: Data(recordWithoutModelID.utf8)) as? [[String: Any]])
    records[0]["state"] = "salvaged"
    let data = try JSONSerialization.data(withJSONObject: records)

    #expect((try? JSONDecoder().decode([DictationRecord].self, from: data)) == nil)
  }
}
