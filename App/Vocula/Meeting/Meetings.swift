import CoreAudio
import Foundation
import VoculaKit

@MainActor
final class Meetings {
  typealias MakeDependencies =
    @MainActor (_ log: DiagnosticLog?, _ recover: Bool) -> MeetingRecorder.Dependencies?

  let status: MeetingStatusModel
  let playback: MeetingPlayback
  private(set) var stopping: Task<Void, Never>?
  private let diagnosticLog: @MainActor () -> DiagnosticLog?
  private let makeDependencies: MakeDependencies
  private let sleep: @Sendable (Duration) async throws -> Void
  private var meetingSwitch = MeetingSwitch()
  private var concluded: Int?
  private var recorder: MeetingRecorder?
  private var follower: Task<Void, Never>?
  private var signals: StreamFanout<DictationSignal>?
  private let parts: MeetingTranscriptionParts
  private let diarizerState = MeetingDiarizerState()
  private var schedule = MeetingPassSchedule()
  private var listings = MeetingPassSchedule()
  private var stopsInFlight = 0
  private var savesInFlight = 0
  private var loggedNoKey = false
  private var lastListingFailure: MeetingListingOutcome?
  private(set) var pass: Task<Void, Never>? {
    didSet { publishBusy() }
  }
  private(set) var refreshing: Task<Void, Never>?

  init(
    diagnosticLog: @escaping @MainActor () -> DiagnosticLog?,
    status: MeetingStatusModel = MeetingStatusModel(),
    makeDependencies: @escaping MakeDependencies = { Meetings.live(log: $0, recover: $1) },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    transcription: MeetingTranscriptionParts = .live
  ) {
    self.diagnosticLog = diagnosticLog
    self.status = status
    self.makeDependencies = makeDependencies
    self.sleep = sleep
    parts = transcription
    playback = MeetingPlayback(load: transcription.playable, makePlayer: transcription.makePlayer)
  }

  var holdsAMeeting: Bool { recorder != nil || follower != nil }

  @discardableResult
  func toggle() -> Task<Void, Never>? {
    switch meetingSwitch.pressed() {
    case .ignore:
      return nil
    case .stop:
      status.update(MeetingStatus())
      release()
      return stopping
    case .start(let meeting, let recover):
      playback.stop()
      status.update(MeetingStatus())
      guard var dependencies = makeDependencies(diagnosticLog(), recover) else {
        _ = meetingSwitch.ended(meeting)
        return nil
      }
      dependencies.publish = { [weak self] in await self?.apply($0, of: meeting) }
      dependencies.ended = { [weak self] in await self?.ended(meeting) }
      status.clearTranscriptionOutcome()
      let recorder = MeetingRecorder(dependencies)
      self.recorder = recorder
      publishBusy()
      if let signals { follow(signals) }
      return Task { await recorder.start() }
    }
  }

  func dismiss() { status.dismiss() }

  func sectionAppeared() { requestListing() }

  @discardableResult
  func rename(_ id: UUID, to raw: String) -> Task<Void, Never> {
    let title = MeetingHeader.name(from: raw)
    return change(id, action: "rename") { $0.title = title }
  }

  @discardableResult
  func setPinned(_ id: UUID, _ pinned: Bool) -> Task<Void, Never> {
    change(id, action: "pin") { $0.pinned = pinned }
  }

  @discardableResult
  func delete(_ id: UUID) -> Task<Void, Never> {
    let busy = status.busy
    guard
      status.meetings.first(where: { $0.id == id })?
        .allows(.delete, busy: busy, passRunning: pass != nil) == true,
      schedule.deleteBegan()
    else { return Task {} }
    if playback.meeting == id { playback.stop() }
    let delete = parts.delete
    let log = diagnosticLog()
    return Task {
      let result = await delete(id, busy)
      if schedule.deleteEnded() { await startPass() }
      finished(result, action: "delete", failure: .notSaved, log: log)
    }
  }

  @discardableResult
  func play(_ id: UUID) -> Task<Void, Never> {
    guard
      status.meetings.first(where: { $0.id == id })?
        .allows(.play, busy: status.busy, passRunning: pass != nil) == true
    else { return Task {} }
    let log = diagnosticLog()
    return Task {
      switch await playback.play(id) {
      case .started:
        status.actionSucceeded()
      case .superseded:
        break
      case .failed(let step, let code):
        finished(
          .failed(step: step, code: code), action: "play", failure: .recordingUnreadable, log: log)
      }
    }
  }

  @discardableResult
  func saveRecording(_ id: UUID, to url: URL) -> Task<Void, Never> {
    let save = parts.saveRecording
    let log = diagnosticLog()
    savesInFlight += 1
    status.update(savingRecording: true)
    return Task {
      let result = await save(id, url)
      savesInFlight -= 1
      status.update(savingRecording: savesInFlight > 0)
      var failure = MeetingSectionFailure.recordingUnreadable
      if case .failed(step: "write", _) = result { failure = .exportNotWritten }
      finished(result, action: "saveRecording", failure: failure, log: log)
    }
  }

  private func change(
    _ id: UUID, action: String, _ edit: @escaping @Sendable (inout MeetingHeader) -> Void
  ) -> Task<Void, Never> {
    let update = parts.updateHeader
    let busy = status.busy
    let log = diagnosticLog()
    return Task {
      finished(await update(id, busy, edit), action: action, failure: .notSaved, log: log)
    }
  }

  private func finished(
    _ result: MeetingActionResult, action: String, failure: MeetingSectionFailure,
    log: DiagnosticLog?
  ) {
    switch result {
    case .done:
      status.actionSucceeded()
    case .refused:
      break
    case .failed(let step, let code):
      log?.record("meeting.storeFailed", "action=\(action) step=\(step) code=\(code)")
      status.sectionFailed(failure)
    }
    requestListing()
  }

  func apply(_ new: MeetingStatus, of meeting: Int) {
    guard meetingSwitch.isCurrent(meeting), !(new.isRecording && concluded == meeting) else {
      return
    }
    let started = new.isRecording && !status.isRecording
    if new.isRecording { meetingSwitch.began(meeting) } else { concluded = meeting }
    status.update(new)
    guard started else { return }
    requestListing()
    parts.fetchDiarizer(diagnosticLog(), { [weak self] in self?.status.update(speakerModel: $0) }) {
      [weak self] in await self?.diarizerArrived()
    }
  }

  @discardableResult
  func copyTranscript(_ id: UUID, includeMe: Bool) -> Task<Void, Never> {
    let log = diagnosticLog()
    return Task {
      switch await markdown(id, includeMe: includeMe) {
      case .transcript(let text):
        parts.paste(text)
        status.transcriptCopied()
      case .failed(let step, let code):
        log?.record("meeting.transcribeFailed", "step=\(step) code=\(code)")
        status.transcriptUnreadable()
      case .unavailable:
        status.transcriptUnreadable()
      }
    }
  }

  @discardableResult
  func copyFromSection(_ id: UUID, includeMe: Bool) -> Task<Void, Never> {
    let log = diagnosticLog()
    return Task {
      guard let text = forSection(await markdown(id, includeMe: includeMe), action: "copy", log)
      else { return }
      parts.paste(text)
      status.actionSucceeded()
    }
  }

  func open(_ id: UUID) async -> MeetingTranscript? {
    let log = diagnosticLog()
    switch await parts.transcript(id) {
    case .transcript(let transcript):
      status.actionSucceeded()
      return transcript
    case .failed(let step, let code):
      unreadable(action: "open", step: step, code: code, log)
    case .unavailable:
      status.sectionFailed(.transcriptUnreadable)
    }
    return nil
  }

  func exportData(_ id: UUID, includeMe: Bool) async -> Data? {
    let log = diagnosticLog()
    return forSection(await markdown(id, includeMe: includeMe), action: "export", log)
      .map { Data($0.utf8) }
  }

  @discardableResult
  func write(_ data: Data, to url: URL) -> Task<Void, Never> {
    let write = parts.write
    let log = diagnosticLog()
    return Task {
      switch await write(data, url) {
      case .done, .refused:
        status.actionSucceeded()
      case .failed(let step, let code):
        log?.record("meeting.storeFailed", "action=export step=\(step) code=\(code)")
        status.sectionFailed(.exportNotWritten)
      }
    }
  }

  private enum Rendered {
    case transcript(String)
    case failed(step: String, code: Int)
    case unavailable
  }

  private func markdown(_ id: UUID, includeMe: Bool) async -> Rendered {
    guard let listing = status.meetings.first(where: { $0.id == id }) else { return .unavailable }
    switch await parts.transcript(id) {
    case .transcript(let transcript):
      return .transcript(
        MeetingMarkdown.render(
          transcript, title: listing.title, startedAt: listing.startedAt,
          duration: listing.duration, label: MenuCopy.meetingSpeakerLabel, includeMe: includeMe))
    case .failed(let step, let code):
      return .failed(step: step, code: code)
    case .unavailable:
      return .unavailable
    }
  }

  private func forSection(_ rendered: Rendered, action: String, _ log: DiagnosticLog?) -> String? {
    switch rendered {
    case .transcript(let text):
      return text
    case .failed(let step, let code):
      unreadable(action: action, step: step, code: code, log)
    case .unavailable:
      status.sectionFailed(.transcriptUnreadable)
    }
    return nil
  }

  private func unreadable(action: String, step: String, code: Int, _ log: DiagnosticLog?) {
    log?.record("meeting.storeFailed", "action=\(action) step=\(step) code=\(code)")
    status.sectionFailed(.transcriptUnreadable)
  }

  func pipelineStarted(_ signals: StreamFanout<DictationSignal>) {
    self.signals = signals
    follow(signals)
  }

  func stopForTermination() async {
    schedule.terminate()
    pass?.cancel()
    guard recorder != nil || stopping != nil else { return }
    let previous = stopping
    let recorder = recorder
    let work = Task {
      await recorder?.stop(.quit)
      await previous?.value
    }
    _ = await MeetingBound.wait(for: work, atMost: MeetingBound.termination, sleep: sleep)
  }

  nonisolated static func hostNanos() -> UInt64 {
    AudioConvertHostTimeToNanos(AudioGetCurrentHostTime())
  }

  nonisolated static func makeStore(isSecondCopy: Bool = VoculaAppDelegate.isSecondCopy)
    -> MeetingStore?
  {
    isSecondCopy ? nil : sharedStore
  }

  private nonisolated static let sharedStore = MeetingStore(
    directory: ApplicationSupport.directory.appendingPathComponent("Meetings"))

  static func live(log: DiagnosticLog?, recover: Bool) -> MeetingRecorder.Dependencies? {
    guard let store = makeStore() else { return nil }
    return MeetingRecorder.Dependencies(
      store: store,
      cipher: { try MeetingKey.cipher(mayMint: true) },
      makeMicrophone: { MeetingMicrophone(onEnded: $0) },
      makeSystemAudio: { SystemAudioTap() },
      holdPower: { MeetingPowerGuard.hold(onWillSleep: $0) },
      watchDeviceList: { AudioDeviceListMonitor(onChange: $0) },
      now: { hostNanos() },
      sleep: { try await Task.sleep(for: $0) },
      wallClock: { Date() },
      publish: { _ in },
      ended: {},
      log: log,
      recover: recover)
  }

  private func ended(_ meeting: Int) {
    if meetingSwitch.ended(meeting) { release() }
  }

  private func follow(_ signals: StreamFanout<DictationSignal>) {
    guard let recorder else { return }
    follower?.cancel()
    let stream = signals.subscribe()
    follower = Task { await recorder.follow(stream) }
  }

  private func release() {
    let recorder = recorder
    let follower = follower
    let previous = stopping
    self.recorder = nil
    self.follower = nil
    follower?.cancel()
    stopsInFlight += 1
    publishBusy()
    stopping = Task {
      await follower?.value
      await recorder?.stop(.stopped)
      await previous?.value
      self.stopsInFlight -= 1
      self.publishBusy()
      await self.meetingEnded()
    }
  }

  private func meetingEnded() async {
    requestListing()
    if status.notice != .cannotStart,
      schedule.requested()
    {
      await startPass()
    }
  }

  private func diarizerArrived() async {
    if schedule.requested() { await startPass() }
  }

  private func startPass() async {
    guard
      let transcriber = parts.makeTranscriber(
        diagnosticLog(), diarizerState,
        { [weak self] in await self?.status.update(transcription: $0) })
    else {
      await passEnded()
      return
    }
    pass = Task {
      await transcriber.run()
      await self.passEnded()
    }
  }

  private func passEnded() async {
    pass = nil
    requestListing()
    if schedule.passEnded() {
      await startPass()
    }
  }

  private func publishBusy() {
    status.update(busy: recorder != nil || stopsInFlight > 0, passRunning: pass != nil)
  }

  private func requestListing() {
    guard listings.requested() else { return }
    let listing = parts.listing
    let log = diagnosticLog()
    refreshing = Task {
      repeat {
        received(await listing(log), log: log)
      } while listings.passEnded()
    }
  }

  private func received(_ outcome: MeetingListingOutcome, log: DiagnosticLog?) {
    switch outcome {
    case .noKey(holdsMeetings: true) where !loggedNoKey:
      loggedNoKey = true
      log?.record("meeting.transcribeFailed", "step=key code=\(MeetingKeyRule.itemNotFound)")
    case .unreadable(let step, let code) where lastListingFailure != outcome:
      log?.record("meeting.transcribeFailed", "step=\(step) code=\(code)")
    default:
      break
    }
    lastListingFailure = outcome.isUnreadable ? outcome : nil
    status.update(listing: outcome)
  }
}
