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

  init(
    diagnosticLog: @escaping @MainActor () -> DiagnosticLog?,
    status: MeetingStatusModel = MeetingStatusModel(),
    makeDependencies: @escaping MakeDependencies = { Meetings.live(log: $0, recover: $1) },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.diagnosticLog = diagnosticLog
    self.status = status
    self.makeDependencies = makeDependencies
    self.sleep = sleep
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
      let recorder = MeetingRecorder(dependencies)
      self.recorder = recorder
      if let signals { follow(signals) }
      return Task { await recorder.start() }
    }
  }

  func dismiss() { status.dismiss() }

  func apply(_ new: MeetingStatus, of meeting: Int) {
    guard meetingSwitch.isCurrent(meeting), !(new.isRecording && concluded == meeting) else {
      return
    }
    if new.isRecording { meetingSwitch.began(meeting) } else { concluded = meeting }
    status.update(new)
  }

  func pipelineStarted(_ signals: StreamFanout<DictationSignal>) {
    self.signals = signals
    follow(signals)
  }

  func stopForTermination() async {
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
      cipher: { try MeetingKey.cipher() },
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
    }
  }
}
