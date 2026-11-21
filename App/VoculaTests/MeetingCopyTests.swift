import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@Suite struct MeetingCopyTests {
  static let lines: [LocalizedStringResource] =
    [
      MenuCopy.recordMeeting, MenuCopy.stopMeeting, MenuCopy.dismissMeetingNotice,
      MenuCopy.meetingItemLabel(.recording), MenuCopy.meetingItemLabel(.idle),
      MenuCopy.meetingSince(Date(timeIntervalSince1970: 1_000)),
    ]
    + MeetingWarning.allCases.map(MenuCopy.meetingWarning)
    + MeetingNotice.allCases.map(MenuCopy.meetingNotice)
    + [
      MenuCopy.copyTranscript, MenuCopy.copyIncludesMe, MenuCopy.meetingSpeakerMe,
      MenuCopy.meetingSpeakerOthers,
      MenuCopy.meetingTranscribing(40), MenuCopy.transcriptUnreadable,
      MenuCopy.meetingItemLabel(.transcribing),
    ]
    + MenuCopy.meetingTranscription(.finished(transcribed: 1, failed: 1))
    + [
      MenuCopy.meetingsSection, MenuCopy.meetingsReading, MenuCopy.meetingsEmpty,
      MenuCopy.meetingStatusTranscribed, MenuCopy.meetingStatusWaiting,
      MenuCopy.meetingStatusRecording, MenuCopy.meetingPinned, MenuCopy.meetingOpen,
      MenuCopy.meetingRename, MenuCopy.meetingPin, MenuCopy.meetingUnpin, MenuCopy.meetingExport,
      MenuCopy.meetingCopy, MenuCopy.meetingDelete, MenuCopy.meetingActions(for: "Sync"),
      MenuCopy.meetingRenameTitle, MenuCopy.meetingRenameSave, MenuCopy.meetingRenameField,
      MenuCopy.meetingDeleteTitle, MenuCopy.meetingDeleteMessage, MenuCopy.meetingsDeleteWaits,
      MenuCopy.meetingSheetClose, MenuCopy.meetingsListFailed, MenuCopy.meetingNotSaved,
      MenuCopy.meetingExportFailed,
    ]

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

  @Test func theCopyRowUsesTheNameWhenSet() {
    let started = Date(timeIntervalSince1970: 0)
    let plain = text(MenuCopy.transcriptRow(startedAt: started, duration: 125), in: "en")
    let length = plain.components(separatedBy: " · ").last
    let named = MeetingListing(id: UUID(), startedAt: started, duration: 125, title: "Sync")
    #expect(text(MenuCopy.transcriptRow(for: named), in: "en") == "Sync · " + (length ?? ""))
    let unnamed = MeetingListing(id: UUID(), startedAt: started, duration: 125)
    #expect(text(MenuCopy.transcriptRow(for: unnamed), in: "en") == plain)
  }

  @Test(arguments: lines)
  func everyMeetingLineIsTranslated(resource: LocalizedStringResource) {
    let english = text(resource, in: "en")
    #expect(english != resource.key)
    #expect(text(resource, in: "de") != english)
  }
}
