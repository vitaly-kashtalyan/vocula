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
  private var hold: MeetingHoldGate?
  private var holdFollower: Task<Void, Never>?
  private(set) var pass: Task<Void, Never>?
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
      if schedule.recordingStarted() == .cancel { pass?.cancel() }
      if hold == nil { hold = parts.makeHold() }
      let recorder = MeetingRecorder(dependencies)
      self.recorder = recorder
      if let signals {
        follow(signals)
        if holdFollower == nil { listen(signals) }
      }
      return Task { await recorder.start() }
    }
  }

  func dismiss() { status.dismiss() }

  func apply(_ new: MeetingStatus, of meeting: Int) {
    guard meetingSwitch.isCurrent(meeting), !(new.isRecording && concluded == meeting) else {
      return
    }
    let started = new.isRecording && !status.isRecording
    if new.isRecording { meetingSwitch.began(meeting) } else { concluded = meeting }
    status.update(new)
    if started { refreshListing() }
  }

  @discardableResult
  func copyTranscript(_ id: UUID) -> Task<Void, Never> {
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
          transcript, startedAt: listing.startedAt, duration: listing.duration, labels: labels))
      status.transcriptCopied()
    }
  }

  func pipelineStarted(_ signals: StreamFanout<DictationSignal>) {
    self.signals = signals
    follow(signals)
    if hold != nil { listen(signals) }
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
    stopping = Task {
      await follower?.value
      await recorder?.stop(.stopped)
      await previous?.value
      await self.meetingEnded()
    }
  }

  private func meetingEnded() async {
    if status.notice != .cannotStart,
      schedule.requested(recording: recorder != nil) == .start
    {
      await startPass()
    }
    await dropHoldIfIdle()
  }

  private func startPass() async {
    let hold = self.hold ?? parts.makeHold()
    self.hold = hold
    guard
      let transcriber = parts.makeTranscriber(
        diagnosticLog(), hold, { [weak self] in await self?.status.update(transcription: $0) })
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
    refreshListing()
    if schedule.passEnded(recording: recorder != nil) == .start {
      await startPass()
    } else {
      await dropHoldIfIdle()
    }
  }

  private func dropHoldIfIdle() async {
    guard recorder == nil, pass == nil, schedule.isIdle else { return }
    hold = nil
    guard let follower = holdFollower else { return }
    holdFollower = nil
    follower.cancel()
    await follower.value
  }

  private func listen(_ signals: StreamFanout<DictationSignal>) {
    holdFollower?.cancel()
    guard let hold else { return }
    let stream = signals.subscribe()
    holdFollower = Task {
      for await signal in stream { await hold.received(signal) }
      if !Task.isCancelled { await hold.streamEnded() }
    }
  }

  private func refreshListing() {
    let listing = parts.listing
    let log = diagnosticLog()
    refreshing = Task {
      if let found = await listing(log) { status.update(transcripts: found) }
    }
  }
}
