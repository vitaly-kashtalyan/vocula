import CoreAudio
import Foundation
import VoculaKit

@MainActor
final class Meetings {
  typealias MakeDependencies =
    @MainActor (_ log: DiagnosticLog?, _ recover: Bool) -> MeetingRecorder.Dependencies?

  let status: MeetingStatusModel
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
  private var schedule = MeetingPassSchedule()
  private var listings = MeetingPassSchedule()
  private var stopsInFlight = 0
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
    let delete = parts.delete
    let log = diagnosticLog()
    return Task {
      let result = await delete(id, busy)
      if schedule.deleteEnded() { await startPass() }
      finished(result, action: "delete", failure: .notSaved, log: log)
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
    if started { requestListing() }
  }

  @discardableResult
  func copyTranscript(_ id: UUID, includeMe: Bool) -> Task<Void, Never> {
    let read = parts.transcript
    let log = diagnosticLog()
    return Task {
      guard let listing = status.transcripts.first(where: { $0.id == id }),
        let transcript = await read(id, log)
      else {
        status.transcriptUnreadable()
        return
      }
      let labels: [MeetingSpeaker: String] = [
        .me: String(localized: MenuCopy.meetingSpeakerMe),
        .others: String(localized: MenuCopy.meetingSpeakerOthers),
      ]
      parts.paste(
        MeetingMarkdown.render(
          transcript, startedAt: listing.startedAt, duration: listing.duration, labels: labels,
          includeMe: includeMe))
      status.transcriptCopied()
    }
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
    guard !isSecondCopy else { return nil }
    return MeetingStore(directory: ApplicationSupport.directory.appendingPathComponent("Meetings"))
  }

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

  private func startPass() async {
    guard
      let transcriber = parts.makeTranscriber(
        diagnosticLog(), { [weak self] in await self?.status.update(transcription: $0) })
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
