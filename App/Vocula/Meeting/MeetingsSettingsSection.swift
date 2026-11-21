import SwiftUI
import VoculaKit

struct MeetingsSettingsSection: View {
  let meetings: Meetings

  private var status: MeetingStatusModel { meetings.status }

  var body: some View {
    Section {
      failureLine
      switch status.sectionContent {
      case .reading:
        Text(MenuCopy.meetingsReading)
      case .empty:
        Text(MenuCopy.meetingsEmpty).accessibilityIdentifier("meetings.empty")
      case .lineAlone:
        EmptyView()
      case .list:
        ForEach(MeetingListing.ordered(status.meetings)) { listing in
          MeetingRow(listing: listing, status: listing.status(busy: status.busy))
        }
      }
    } footer: {
      if status.passRunning { Text(MenuCopy.meetingsDeleteWaits) }
    }
    .task { meetings.sectionAppeared() }
    .refreshOnActivate { meetings.sectionAppeared() }
  }

  @ViewBuilder
  private var failureLine: some View {
    switch status.sectionFailure {
    case .notSaved: Text(MenuCopy.meetingNotSaved)
    case .exportNotWritten: Text(MenuCopy.meetingExportFailed)
    case .transcriptUnreadable: Text(MenuCopy.transcriptUnreadable)
    case nil: if status.listUnreadable { Text(MenuCopy.meetingsListFailed) }
    }
  }
}

struct MeetingRow: View {
  let listing: MeetingListing
  let status: MeetingListingStatus

  static func title(of listing: MeetingListing) -> String {
    listing.title ?? MenuCopy.meetingStart(listing.startedAt)
  }

  var body: some View {
    LabeledContent {
      EmptyView()
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(verbatim: Self.title(of: listing))
          if listing.isPinned {
            Image(systemName: "pin.fill")
              .accessibilityLabel(Text(MenuCopy.meetingPinned))
          }
        }
        HStack(spacing: 6) {
          if listing.title != nil { Text(verbatim: MenuCopy.meetingStart(listing.startedAt)) }
          if listing.hasEnd { Text(verbatim: MenuCopy.meetingLength(listing.duration)) }
          statusText
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder
  private var statusText: some View {
    switch status {
    case .transcribed: Text(MenuCopy.meetingStatusTranscribed)
    case .waiting: Text(MenuCopy.meetingStatusWaiting)
    case .recording: Text(MenuCopy.meetingStatusRecording)
    }
  }
}
