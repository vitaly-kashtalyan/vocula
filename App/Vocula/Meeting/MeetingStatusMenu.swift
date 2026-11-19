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
    if let notice = meetings.status.notice {
      Text(MenuCopy.meetingNotice(notice))
      Button(MenuCopy.dismissMeetingNotice) { meetings.dismiss() }
    }
  }
}

struct MeetingStatusLabel: View {
  let model: MeetingStatusModel

  var body: some View {
    Group {
      if let elapsed = model.elapsed {
        Image(nsImage: Self.timer(symbol: model.symbol, elapsed: elapsed))
      } else {
        Image(systemName: model.symbol)
      }
    }
    .accessibilityLabel(Text(MenuCopy.meetingStatusLabel(recording: model.isRecording)))
  }

  // Workaround: a MenuBarExtra label draws its Text in the menu bar's proportional font and
  // drops .monospacedDigit(), so the item changed width every second; an image keeps its size.
  private static func timer(symbol: String, elapsed: String) -> NSImage {
    let renderer = ImageRenderer(
      content: HStack(spacing: 4) {
        Image(systemName: symbol)
        Text(verbatim: elapsed).monospacedDigit()
      }
      .font(Font(NSFont.menuBarFont(ofSize: 0))))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    let image = renderer.nsImage ?? NSImage()
    image.isTemplate = true
    return image
  }
}
