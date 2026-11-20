import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@Suite struct MeetingCopyTests {
  static let lines: [LocalizedStringResource] =
    [
      MenuCopy.recordMeeting, MenuCopy.stopMeeting, MenuCopy.dismissMeetingNotice,
      MenuCopy.meetingStatusLabel(recording: true), MenuCopy.meetingStatusLabel(recording: false),
      MenuCopy.meetingSince(Date(timeIntervalSince1970: 1_000)),
    ]
    + MeetingWarning.allCases.map(MenuCopy.meetingWarning)
    + MeetingNotice.allCases.map(MenuCopy.meetingNotice)
    + [
      MenuCopy.copyTranscript, MenuCopy.meetingSpeakerMe, MenuCopy.meetingSpeakerOthers,
      MenuCopy.meetingTranscribing(40), MenuCopy.transcriptUnreadable,
      MenuCopy.meetingItemLabel(.transcribing),
    ]
    + MenuCopy.meetingTranscription(.finished(transcribed: 1, failed: 1))

  private func text(_ resource: LocalizedStringResource, in identifier: String) -> String {
    var resource = resource
    resource.locale = Locale(identifier: identifier)
    return String(localized: resource)
  }

  @Test func theSystemAudioUsageDescriptionIsLocalized() throws {
    let english = try #require(
      Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
    let german = try #require(
      Bundle.main.path(forResource: "de", ofType: "lproj").flatMap(Bundle.init(path:)))
    let key = "NSAudioCaptureUsageDescription"
    let englishValue = english.localizedString(forKey: key, value: nil, table: "InfoPlist")
    #expect(englishValue == "Vocula records other apps' sound only while you record a meeting.")
    #expect(german.localizedString(forKey: key, value: nil, table: "InfoPlist") != englishValue)
    let localized = Bundle.main.localizedInfoDictionary?[key]
    #expect((localized as? String)?.isEmpty == false)
  }

  @Test(arguments: lines)
  func everyMeetingLineIsTranslated(resource: LocalizedStringResource) {
    let english = text(resource, in: "en")
    #expect(english != resource.key)
    #expect(text(resource, in: "de") != english)
  }
}
