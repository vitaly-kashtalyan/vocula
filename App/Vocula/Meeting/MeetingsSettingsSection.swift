import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoculaKit

struct OpenedTranscript: Identifiable {
  let listing: MeetingListing
  let transcript: MeetingTranscript

  var id: UUID { listing.id }
}

struct MeetingsSettingsSection: View {
  let meetings: Meetings
  @AppStorage(CopyTranscriptMenu.includeMeKey) private var includeMe = true
  @State private var renaming: MeetingListing?
  @State private var renameText = ""
  @State private var deleting: MeetingListing?
  @State private var opened: OpenedTranscript?

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
          MeetingRow(
            listing: listing, status: listing.status(busy: status.busy),
            allows: { listing.allows($0, busy: status.busy, passRunning: status.passRunning) },
            perform: { perform($0, on: listing) })
        }
      }
    } footer: {
      if status.passRunning { Text(MenuCopy.meetingsDeleteWaits) }
    }
    .task { meetings.sectionAppeared() }
    .refreshOnActivate { meetings.sectionAppeared() }
    .alert(
      Text(MenuCopy.meetingRenameTitle),
      isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    ) {
      TextField(
        text: $renameText,
        prompt: Text(verbatim: renaming.map { MenuCopy.meetingStart($0.startedAt) } ?? "")
      ) { Text(MenuCopy.meetingRenameField) }
      Button(MenuCopy.meetingRenameSave) {
        if let listing = renaming { meetings.rename(listing.id, to: renameText) }
      }
      Button(CommonCopy.cancel, role: .cancel) {}
    }
    .confirmationDialog(
      Text(MenuCopy.meetingDeleteTitle),
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      presenting: deleting
    ) { listing in
      Button(CommonCopy.delete, role: .destructive) { meetings.delete(listing.id) }
      Button(CommonCopy.cancel, role: .cancel) {}
    } message: { _ in
      Text(MenuCopy.meetingDeleteMessage)
    }
    .sheet(item: $opened) { item in
      MeetingTranscriptSheet(item: item, export: { export(item.listing) })
    }
  }

  private func perform(_ action: MeetingAction, on listing: MeetingListing) {
    switch action {
    case .open:
      Task {
        if let transcript = await meetings.open(listing.id) {
          opened = OpenedTranscript(listing: listing, transcript: transcript)
        }
      }
    case .rename:
      renameText = listing.title ?? ""
      renaming = listing
    case .pin:
      meetings.setPinned(listing.id, !listing.isPinned)
    case .export:
      export(listing)
    case .copy:
      meetings.copyFromSection(listing.id, includeMe: includeMe)
    case .delete:
      deleting = listing
    }
  }

  private func export(_ listing: MeetingListing) {
    Task {
      guard let data = await meetings.exportData(listing.id, includeMe: includeMe) else { return }
      let panel = NSSavePanel()
      panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
      panel.nameFieldStringValue = MeetingMarkdown.fileName(for: MeetingRow.title(of: listing))
      panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        meetings.write(data, to: url)
      }
    }
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
  let allows: (MeetingAction) -> Bool
  let perform: (MeetingAction) -> Void

  static func title(of listing: MeetingListing) -> String {
    listing.title ?? MenuCopy.meetingStart(listing.startedAt)
  }

  var body: some View {
    LabeledContent {
      Menu {
        ForEach([MeetingAction.open, .rename, .pin, .export, .copy], id: \.self) { item($0) }
        Divider()
        Button(role: .destructive) {
          perform(.delete)
        } label: {
          label(for: .delete)
        }
        .disabled(!allows(.delete))
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel(Text(MenuCopy.meetingActions(for: Self.title(of: listing))))
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

  private func item(_ action: MeetingAction) -> some View {
    Button {
      perform(action)
    } label: {
      label(for: action)
    }.disabled(!allows(action))
  }

  @ViewBuilder
  private func label(for action: MeetingAction) -> some View {
    switch action {
    case .open: Text(MenuCopy.meetingOpen)
    case .rename: Text(MenuCopy.meetingRename)
    case .pin: Text(listing.isPinned ? MenuCopy.meetingUnpin : MenuCopy.meetingPin)
    case .export: Text(MenuCopy.meetingExport)
    case .copy: Text(MenuCopy.meetingCopy)
    case .delete: Text(MenuCopy.meetingDelete)
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

struct MeetingTranscriptSheet: View {
  let item: OpenedTranscript
  let export: () -> Void
  @AppStorage(CopyTranscriptMenu.includeMeKey) private var includeMe = true
  @Environment(\.dismiss) private var dismiss

  private var lines: [String] {
    MeetingMarkdown.lines(
      item.transcript,
      labels: [
        .me: String(localized: MenuCopy.meetingSpeakerMe),
        .others: String(localized: MenuCopy.meetingSpeakerOthers),
      ], includeMe: includeMe)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(verbatim: MeetingRow.title(of: item.listing)).font(.headline)
      HStack(spacing: 6) {
        Text(verbatim: MenuCopy.meetingStart(item.listing.startedAt))
        Text(verbatim: MenuCopy.meetingLength(item.listing.duration))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      ScrollView {
        Text(verbatim: lines.joined(separator: "\n"))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Toggle(isOn: $includeMe) { Text(MenuCopy.copyIncludesMe) }
        Spacer()
        Button(MenuCopy.meetingExport) { export() }
        Button(MenuCopy.meetingSheetClose) { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding()
    .frame(minWidth: 520, minHeight: 420)
  }
}
