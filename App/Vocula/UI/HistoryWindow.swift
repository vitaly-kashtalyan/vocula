import AppKit
import SwiftUI
import VoculaKit

struct HistorySummary: Equatable {
  let savedTyping: String
  let characters: String
  let averageWords: String
  let dictations: String
}

@MainActor
final class HistoryWindowModel: ObservableObject {
  @Published private(set) var days: [HistoryDay] = []
  @Published private(set) var grid: HistoryGrid = .empty
  @Published private(set) var dayByKey: [String: HistoryDay] = [:]
  @Published private(set) var selectedDay: String?
  @Published private(set) var records: [DictationRecord] = []
  @Published var notice: String?
  @Published var errorNotice: String?

  private let store: HistoryStoring

  init(store: HistoryStoring) { self.store = store }

  var day: HistoryDay? { days.first { $0.key == selectedDay } }

  var averageWordsThisYear: Int? {
    HistoryDay.averageWordsPerDay(days, withinDays: HistoryRetention.days)
  }

  func select(_ day: String?) async {
    selectedDay = day
    guard let day else {
      records = []
      return
    }
    records = await store.records(on: day)
  }

  func deleteAll() async {
    do {
      _ = try await store.deleteAll()
      errorNotice = nil
    } catch {
      errorNotice = String(localized: HistoryScreenCopy.deleteAllFailed)
    }
    await reload()
  }

  func deleteDay() async {
    guard let selectedDay else { return }
    do {
      _ = try await store.deleteDay(selectedDay)
      errorNotice = nil
    } catch {
      errorNotice = String(localized: HistoryScreenCopy.deleteDayFailed)
    }
    await reload()
  }

  func reload() async {
    days = await store.days()
    dayByKey = Dictionary(days.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    grid = HistoryGrid.build(days: days)
    await select(HistoryDay.resolve(selected: selectedDay, in: days))
  }

  func delete(_ record: DictationRecord) async {
    let removed = await store.delete(record.id)
    await reload()
    errorNotice =
      removed
      ? nil
      : String(
        localized: "history.deleteFailed",
        defaultValue: "That record could not be deleted.",
        comment: "Shown when removing one dictation did not reach the disk.")
  }
}

struct HistoryView: View {
  @ObservedObject var model: HistoryWindowModel
  @State private var copied: UUID?
  @State private var confirmingAll = false
  @State private var confirmingDay = false

  var body: some View {
    if model.notice != nil || model.errorNotice != nil {
      Section {
        if let notice = model.notice {
          Text(verbatim: notice).foregroundStyle(.secondary)
        }
        if let errorNotice = model.errorNotice {
          Label {
            Text(verbatim: errorNotice)
          } icon: {
            Image(systemName: "exclamationmark.octagon.fill")
          }
          .foregroundStyle(.red)
        }
      }
    }
    if !model.days.isEmpty { overview }
    Section {
      if model.days.isEmpty {
        Text(HistoryScreenCopy.empty).foregroundStyle(.secondary)
          .accessibilityIdentifier("history.empty")
      }
      ForEach(model.records, id: \.id) { record in
        row(record)
      }
    } header: {
      if let day = model.day {
        HStack {
          Text(
            verbatim: day.title() + " · "
              + CountedText.text(HistoryCopy.dictations(count: day.count)))
          Spacer()
          Menu {
            Button(HistoryScreenCopy.deleteDayItem, role: .destructive) {
              confirmingDay = true
            }
            .accessibilityIdentifier("history.deleteDay")
            Divider()
            Button(HistoryScreenCopy.deleteAllItem, role: .destructive) {
              confirmingAll = true
            }
            .accessibilityIdentifier("history.deleteAll")
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .help(Text(HistoryScreenCopy.deleteMenuHelp))
          .accessibilityIdentifier("history.deleteMenu")
        }
        .confirmationDialog(
          Text(HistoryScreenCopy.confirmDeleteDay(day.title())),
          isPresented: $confirmingDay,
          titleVisibility: .visible
        ) {
          Button(CommonCopy.delete, role: .destructive) {
            Task { await model.deleteDay() }
          }
          Button(CommonCopy.cancel, role: .cancel) {}
        } message: {
          Text(verbatim: CountedText.text(HistoryCopy.willBeDeleted(count: day.count)))
        }
        .confirmationDialog(
          Text(HistoryScreenCopy.deleteAllTitle),
          isPresented: $confirmingAll,
          titleVisibility: .visible
        ) {
          Button(HistoryScreenCopy.deleteAllButton, role: .destructive) {
            Task { await model.deleteAll() }
          }
          Button(CommonCopy.cancel, role: .cancel) {}
        } message: {
          Text(HistoryScreenCopy.deleteAllMessage)
        }
      }
    }
  }

  private var overview: some View {
    Section {
      HistoryHeatmap(
        grid: model.grid,
        dayByKey: model.dayByKey,
        selected: model.selectedDay
      ) { day in
        Task { await model.select(day) }
      }
    }
  }

  @ViewBuilder
  private func row(_ record: DictationRecord) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(verbatim: record.createdAt.formatted(date: .omitted, time: .shortened))
          .font(.caption).foregroundStyle(.secondary)
        Text(verbatim: record.language ?? "—").font(.caption)
        Text(record.state.title).font(.caption)
          .foregroundStyle(colour(for: record.state))
        Spacer()
        if let text = record.finalText, !text.isEmpty {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = record.id
          } label: {
            Image(systemName: copied == record.id ? "checkmark" : "doc.on.doc")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(Text(HistoryScreenCopy.copyAccessibility(time(record))))
          .help(Text(HistoryScreenCopy.copyHelp))
        }
        Button {
          Task { await model.delete(record) }
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(HistoryScreenCopy.deleteAccessibility(time(record))))
        .help(Text(HistoryScreenCopy.deleteHelp))
      }
      if let final = record.finalText {
        Text(verbatim: final)
      } else if let reason = record.reason {
        Text(verbatim: RefusalCopy.text(forRawReason: reason, historyIsRecording: true) ?? reason)
          .italic().foregroundStyle(.secondary)
      } else if record.state == .noSpeech, let metrics = record.metrics {
        Text(verbatim: Self.metricsReadout(metrics))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  static func metricsReadout(_ metrics: SpeechMetrics) -> String {
    let frame = metrics.maxFrameProbability.map { String(format: "%.2f", $0) } ?? "—"
    let peak = metrics.peakLevel.map { String(format: "%.3f", $0) } ?? "—"
    return String(
      localized: HistoryScreenCopy.noSpeechReadout(metrics.segmentCount, frame, peak))
  }

  private func time(_ record: DictationRecord) -> String {
    record.createdAt.formatted(date: .omitted, time: .shortened)
  }

  private func colour(for state: SessionState) -> Color {
    switch state {
    case .sent: return .green
    case .rejected, .failed: return Theme.warning
    default: return .secondary
    }
  }
}

enum HistoryMapGeometry {
  static let cell: CGFloat = 10
  static let radius: CGFloat = 2.8
  static let gap: CGFloat = 2
  static let gutter: CGFloat = 30
  static let columns: CGFloat = 53

  static let width = gutter + columns * (cell + gap)
}

struct HistoryHeatmap: View {
  let grid: HistoryGrid
  let dayByKey: [String: HistoryDay]
  let selected: String?
  let select: (String) -> Void

  private let calendar = Calendar.current

  private var cell: CGFloat { HistoryMapGeometry.cell }
  private var radius: CGFloat { HistoryMapGeometry.radius }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      monthRow
      HStack(alignment: .top, spacing: HistoryMapGeometry.gap) {
        weekdayColumn
        ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, column in
          VStack(spacing: HistoryMapGeometry.gap) {
            ForEach(Array(column.enumerated()), id: \.offset) { _, item in
              cellView(item)
            }
          }
        }
      }
      legend
    }
    .frame(minWidth: HistoryMapGeometry.width, maxWidth: .infinity, alignment: .leading)
  }

  private var monthRow: some View {
    HStack(alignment: .bottom, spacing: HistoryMapGeometry.gap) {
      Color.clear.frame(width: HistoryMapGeometry.gutter, height: 11)
      ForEach(grid.columns.indices, id: \.self) { column in
        Text(verbatim: grid.months.first { $0.column == column }?.title ?? "")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
          .fixedSize()
          .frame(width: cell, alignment: .leading)
      }
    }
    .accessibilityHidden(true)
  }

  private var weekdayColumn: some View {
    VStack(spacing: HistoryMapGeometry.gap) {
      ForEach(0..<7, id: \.self) { row in
        Text(verbatim: weekday(row))
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
          .frame(width: HistoryMapGeometry.gutter - 5, height: cell, alignment: .trailing)
      }
    }
    .accessibilityHidden(true)
  }

  private func weekday(_ row: Int) -> String {
    guard !row.isMultiple(of: 2), grid.weekdays.indices.contains(row) else { return "" }
    return grid.weekdays[row]
  }

  @ViewBuilder
  private func cellView(_ item: HistoryGrid.Cell) -> some View {
    if let key = item.key {
      let day = dayByKey[key]
      Button {
        select(key)
      } label: {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(Color.secondary.opacity(0.12))
          .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .fill(Theme.accentText.opacity(Theme.heatAlpha(item.level)))
          }
          .frame(width: cell, height: cell)
          .overlay { if key == selected { ring } }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(Text(verbatim: label(key, day)))
      .accessibilityIdentifier("history.day.\(key)")
      .accessibilityLabel(Text(verbatim: label(key, day)))
      .accessibilityAddTraits(key == selected ? .isSelected : [])
      .accessibilityHidden(day == nil)
    } else {
      Color.clear.frame(width: cell, height: cell)
    }
  }

  private var ring: some View {
    RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
      .stroke(Theme.accentText, lineWidth: 1.5)
      .padding(-2)
  }

  private var legend: some View {
    HStack(spacing: 5) {
      Text(verbatim: summary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 12)
      Text(HistoryScreenCopy.heatMapLess).font(.caption2).foregroundStyle(.secondary)
      ForEach(0...HistoryGrid.levels, id: \.self) { level in
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
          .fill(Color.secondary.opacity(0.12))
          .overlay {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
              .fill(Theme.accentText.opacity(Theme.heatAlpha(level)))
          }
          .frame(width: 10, height: 10)
      }
      Text(HistoryScreenCopy.heatMapMore).font(.caption2).foregroundStyle(.secondary)
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.leading, HistoryMapGeometry.gutter + HistoryMapGeometry.gap)
    .accessibilityHidden(true)
  }

  private var summary: String {
    guard let selected else { return "" }
    return label(selected, dayByKey[selected])
  }

  private func label(_ key: String, _ day: HistoryDay?) -> String {
    let title = (day ?? HistoryDay(key: key, count: 0, words: 0)).title()
    guard let day, day.count > 0 else {
      return String(localized: HistoryScreenCopy.dayWithNothing(title))
    }
    return title + " · " + CountedText.text(HistoryCopy.dictations(count: day.count))
      + " · " + CountedText.text(HistoryCopy.words(count: day.words))
  }
}
