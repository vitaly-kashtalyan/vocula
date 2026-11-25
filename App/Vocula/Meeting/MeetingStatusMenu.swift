import SwiftUI
import VoculaKit

struct MeetingStatusScene: Scene {
  let meetings: Meetings

  var body: some Scene {
    let shown = meetings.status.statusItemShown
    MenuBarExtra(
      isInserted: Binding(get: { shown }, set: { meetings.status.insertionWritten($0) })
    ) {
      MeetingStatusMenu(meetings: meetings)
    } label: {
      MeetingStatusLabel(model: meetings.status)
    }
  }
}

struct MeetingStatusMenu: View {
  let meetings: Meetings

  var body: some View {
    if meetings.status.isRecording {
      Button(MenuCopy.stopMeeting) { meetings.toggle() }
      if let since = meetings.status.startedAt { Text(MenuCopy.meetingSince(since)) }
    }
    ForEach(meetings.status.warnings, id: \.self) { Text(MenuCopy.meetingWarning($0)) }
    if let notice = meetings.status.notice { Text(MenuCopy.meetingNotice(notice)) }
    if let percent = meetings.status.speakerModel {
      Text(MenuCopy.speakerModelDownloading(percent))
    }
    if let transcription = meetings.status.transcription {
      ForEach(Array(MenuCopy.meetingTranscription(transcription).enumerated()), id: \.offset) {
        Text($0.element)
      }
    }
    if meetings.status.copyFailed { Text(MenuCopy.transcriptUnreadable) }
    if meetings.status.canDismiss {
      Button(MenuCopy.dismissMeetingNotice) { meetings.dismiss() }
    }
  }
}

struct CopyTranscriptMenu: View {
  static let includeMeKey = "meeting.copy.includesMe"

  let meetings: Meetings
  @AppStorage(Self.includeMeKey) private var includeMe = true

  var body: some View {
    if !meetings.status.transcripts.isEmpty {
      Menu(MenuCopy.copyTranscript) {
        Toggle(MenuCopy.copyIncludesMe, isOn: $includeMe)
        Divider()
        ForEach(meetings.status.transcripts) { listing in
          Button(MenuCopy.transcriptRow(for: listing)) {
            meetings.copyTranscript(listing.id, includeMe: includeMe)
          }
        }
      }
    }
  }
}

struct MeetingStatusLabel: View {
  let model: MeetingStatusModel

  var body: some View {
    Group {
      if let elapsed = model.elapsed, let timer = Self.timer(symbol: model.symbol, elapsed: elapsed)
      {
        Image(nsImage: timer)
      } else {
        Image(systemName: model.symbol)
      }
    }
    .accessibilityLabel(Text(MenuCopy.meetingItemLabel(model.label)))
  }

  // Workaround: a MenuBarExtra label draws its Text in the menu bar's proportional font and
  // drops .monospacedDigit(), so the item changed width every second; an image keeps its size.
  // Rendered at 2x because the one image serves the menu bar of every display.
  private static func timer(symbol: String, elapsed: String) -> NSImage? {
    let renderer = ImageRenderer(
      content: HStack(spacing: 4) {
        Image(systemName: symbol)
        Text(verbatim: elapsed).monospacedDigit()
      }
      .font(Font(NSFont.menuBarFont(ofSize: 0))))
    renderer.scale = 2
    let image = renderer.nsImage
    image?.isTemplate = true
    return image
  }
}
