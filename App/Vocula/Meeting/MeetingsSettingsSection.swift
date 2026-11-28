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
  @AppStorage(MeetingStatusLabel.showsTimeKey) private var showsTime = true
  @AppStorage(CallWatch.enabledKey) private var offersOnCall = true
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
        ForEach(Array(MeetingListing.ordered(status.meetings).enumerated()), id: \.element.id) {
          position, listing in
          MeetingRow(
            listing: listing, position: position, status: listing.status(busy: status.busy),
            transcribing: status.transcription?.percent(of: listing.id),
            allows: { listing.allows($0, busy: status.busy, passRunning: status.passRunning) },
            perform: { perform($0, on: listing) })
          if meetings.playback.meeting == listing.id {
            MeetingPlayerRow(playback: meetings.playback)
          }
        }
      }
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        if let percent = status.speakerModel { Text(MenuCopy.speakerModelDownloading(percent)) }
        if status.passRunning { Text(MenuCopy.meetingsDeleteWaits) }
        if status.savingRecording { Text(MenuCopy.meetingSavingRecording) }
      }
    }
    .task { meetings.sectionAppeared() }
    .refreshOnActivate { meetings.sectionAppeared() }
    .alert(
      Text(MenuCopy.meetingRenameTitle),
      isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
      presenting: renaming
    ) { listing in
      TextField(
        text: $renameText, prompt: Text(verbatim: MenuCopy.meetingStart(listing.startedAt))
      ) { Text(MenuCopy.meetingRenameField) }
      Button(MenuCopy.meetingRenameSave) { meetings.rename(listing.id, to: renameText) }
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
    Section {
      Toggle(isOn: $offersOnCall) { Text(MenuCopy.meetingsOffersOnCall) }
        .accessibilityIdentifier("meetings.offersOnCall")
      Toggle(isOn: $showsTime) { Text(MenuCopy.meetingsShowTime) }
        .accessibilityIdentifier("meetings.showsTime")
    } footer: {
      Text(MenuCopy.meetingsOffersOnCallFooter)
    }
  }

  private func perform(_ action: MeetingAction, on listing: MeetingListing) {
    switch action {
    case .play:
      meetings.play(listing.id)
    case .saveRecording:
      saveRecording(listing)
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

  private func saveRecording(_ listing: MeetingListing) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.mpeg4Audio]
    panel.nameFieldStringValue = MeetingMarkdown.fileName(
      for: MeetingRow.title(of: listing), pathExtension: "m4a")
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      meetings.saveRecording(listing.id, to: url)
    }
  }

  @ViewBuilder
  private var failureLine: some View {
    switch status.sectionFailure {
    case .notSaved: Text(MenuCopy.meetingNotSaved)
    case .exportNotWritten: Text(MenuCopy.meetingExportFailed)
    case .transcriptUnreadable: Text(MenuCopy.transcriptUnreadable)
    case .recordingUnreadable: Text(MenuCopy.meetingRecordingUnreadable)
    case nil: if status.listUnreadable { Text(MenuCopy.meetingsListFailed) }
    }
  }
}

struct MeetingRow: View {
  let listing: MeetingListing
  let position: Int
  let status: MeetingListingStatus
  let transcribing: Int?
  let allows: (MeetingAction) -> Bool
  let perform: (MeetingAction) -> Void

  static func title(of listing: MeetingListing) -> String {
    listing.title ?? MenuCopy.meetingStart(listing.startedAt)
  }

  var body: some View {
    LabeledContent {
      HStack {
        if listing.hasAudio {
          Image(systemName: "waveform")
            .foregroundStyle(.secondary)
            .help(Text(MenuCopy.meetingHasRecording))
            .accessibilityLabel(Text(MenuCopy.meetingHasRecording))
            .accessibilityIdentifier("meetings.hasRecording.\(position)")
        }
        actions
      }
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

  private var actions: some View {
    Menu {
      Button(MenuCopy.meetingOpen) { perform(.open) }.disabled(!allows(.open))
        .accessibilityIdentifier("meetings.action.open")
      if listing.hasAudio {
        Button(MenuCopy.meetingPlay) { perform(.play) }.disabled(!allows(.play))
          .accessibilityIdentifier("meetings.action.play")
      }
      Button(MenuCopy.meetingRename) { perform(.rename) }.disabled(!allows(.rename))
        .accessibilityIdentifier("meetings.action.rename")
      Button(listing.isPinned ? MenuCopy.meetingUnpin : MenuCopy.meetingPin) { perform(.pin) }
        .disabled(!allows(.pin))
        .accessibilityIdentifier("meetings.action.pin")
      Button(MenuCopy.meetingExport) { perform(.export) }.disabled(!allows(.export))
        .accessibilityIdentifier("meetings.action.export")
      if listing.hasAudio {
        Button(MenuCopy.meetingSaveRecording) { perform(.saveRecording) }
          .disabled(!allows(.saveRecording))
          .accessibilityIdentifier("meetings.action.saveRecording")
      }
      Button(MenuCopy.meetingCopy) { perform(.copy) }.disabled(!allows(.copy))
        .accessibilityIdentifier("meetings.action.copy")
      Divider()
      Button(MenuCopy.meetingDelete, role: .destructive) { perform(.delete) }
        .disabled(!allows(.delete))
        .accessibilityIdentifier("meetings.action.delete")
    } label: {
      Label {
        Text(MenuCopy.meetingActions(for: Self.title(of: listing)))
      } icon: {
        Image(systemName: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(Text(MenuCopy.meetingActions(for: Self.title(of: listing))))
    .accessibilityIdentifier("meetings.menu.\(position)")
  }

  @ViewBuilder
  private var statusText: some View {
    switch status {
    case .transcribed: Text(MenuCopy.meetingStatusTranscribed)
    case .waiting:
      if let transcribing {
        Text(MenuCopy.meetingStatusTranscribing(transcribing))
      } else {
        Text(MenuCopy.meetingStatusWaiting)
      }
    case .recording: Text(MenuCopy.meetingStatusRecording)
    }
  }
}

struct MeetingPlayerRow: View {
  let playback: MeetingPlayback

  var body: some View {
    if playback.phase == .loading {
      LabeledContent {
        ProgressView().controlSize(.small)
      } label: {
        Text(MenuCopy.meetingPlayerLoading)
      }
      .accessibilityIdentifier("meetings.player.loading")
    } else {
      LabeledContent {
        HStack {
          Text(verbatim: MenuCopy.meetingPlaybackTime(playback.position, of: playback.duration))
            .monospacedDigit()
          Slider(
            value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
            in: 0...max(playback.duration, 1)
          ) {
            Text(MenuCopy.meetingPlayerPosition)
          }
          .labelsHidden()
          .accessibilityValue(
            Text(MenuCopy.meetingPlayerPositionValue(playback.position, of: playback.duration))
          )
          .accessibilityIdentifier("meetings.player.position")
          Text(verbatim: MenuCopy.meetingPlaybackTime(playback.duration, of: playback.duration))
            .monospacedDigit()
        }
      } label: {
        HStack {
          Button {
            playback.pauseOrResume()
          } label: {
            Label {
              Text(paused ? MenuCopy.meetingPlayerResume : MenuCopy.meetingPlayerPause)
            } icon: {
              Image(systemName: paused ? "play.fill" : "pause.fill")
            }
          }
          .help(Text(paused ? MenuCopy.meetingPlayerResume : MenuCopy.meetingPlayerPause))
          .accessibilityIdentifier("meetings.player.pause")
          Button {
            playback.stop()
          } label: {
            Label {
              Text(MenuCopy.meetingPlayerStop)
            } icon: {
              Image(systemName: "stop.fill")
            }
          }
          .help(Text(MenuCopy.meetingPlayerStop))
          .accessibilityIdentifier("meetings.player.stop")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
      }
    }
  }

  private var paused: Bool { playback.phase == .paused }
}

struct MeetingTranscriptSheet: View {
  let item: OpenedTranscript
  let export: () -> Void
  @AppStorage(CopyTranscriptMenu.includeMeKey) private var includeMe = true
  @Environment(\.dismiss) private var dismiss

  private var lines: [String] {
    MeetingMarkdown.lines(
      item.transcript, label: MenuCopy.meetingSpeakerLabel, includeMe: includeMe)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(verbatim: MeetingRow.title(of: item.listing)).font(.headline)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 6) {
        Text(verbatim: MenuCopy.meetingStart(item.listing.startedAt))
        Text(verbatim: MenuCopy.meetingLength(item.listing.duration))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      ScrollView {
        Text(verbatim: lines.joined(separator: "\n"))
          .textSelection(.enabled)
          .accessibilityIdentifier("meetings.sheet.text")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Toggle(isOn: $includeMe) { Text(MenuCopy.copyIncludesMe) }
        Spacer()
        Button(MenuCopy.meetingExport) { export() }
        Button(MenuCopy.meetingSheetClose) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("meetings.sheet.close")
      }
    }
    .padding()
    .frame(minWidth: 520, minHeight: 420)
  }
}
