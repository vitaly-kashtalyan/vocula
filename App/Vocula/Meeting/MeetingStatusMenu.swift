import SwiftUI
import VoculaKit

struct MeetingStatusScene: Scene {
  let meetings: Meetings

  var body: some Scene {
    let shown = meetings.status.statusItemShown
    MenuBarExtra(
      isInserted: Binding(
        get: { shown },
        // Workaround: SwiftUI echoes every programmatic isInserted change through this setter (three times, with the value just built), so only a false while the item is shown is the user removing it.
        set: { if !$0 && shown { meetings.status.statusItemRemoved() } })
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
    Image(systemName: model.symbol)
      .accessibilityLabel(Text(MenuCopy.meetingStatusLabel(recording: model.isRecording)))
  }
}
