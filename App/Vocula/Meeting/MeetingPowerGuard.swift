import Foundation
import IOKit
import IOKit.pwr_mgt
import VoculaKit

final class MeetingPowerGuard: @unchecked Sendable {
  private let queue = DispatchQueue(label: "vocula.meeting.power")
  private let onWillSleep: @Sendable () async -> Void
  private var sequence = MeetingPowerSequence()
  private var rootPort: io_connect_t = 0
  private var port: IONotificationPortRef?
  private var notifier: io_object_t = 0
  private var assertion: IOPMAssertionID?
  private var selfRetain: Unmanaged<MeetingPowerGuard>?

  private init(onWillSleep: @escaping @Sendable () async -> Void) {
    self.onWillSleep = onWillSleep
  }

  deinit { close() }

  static func hold(onWillSleep: @escaping @Sendable () async -> Void) -> MeetingPowerHold {
    let power = MeetingPowerGuard(onWillSleep: onWillSleep)
    return power.queue.sync { power.register() }
  }

  func release() {
    queue.async { self.apply(self.sequence.releaseRequested()) }
  }

  private func register() -> MeetingPowerHold {
    let retained = Unmanaged.passRetained(self)
    selfRetain = retained
    var port: IONotificationPortRef?
    var notifier: io_object_t = 0
    let rootPort = IORegisterForSystemPower(
      retained.toOpaque(), &port,
      { refcon, _, message, argument in
        guard let refcon else { return }
        let power = Unmanaged<MeetingPowerGuard>.fromOpaque(refcon).takeUnretainedValue()
        power.apply(power.sequence.received(message, notification: Int(bitPattern: argument)))
      }, &notifier)
    guard rootPort != 0, let port else {
      deregister()
      return .failed(code: 0)
    }
    self.rootPort = rootPort
    self.port = port
    self.notifier = notifier
    IONotificationPortSetDispatchQueue(port, queue)
    var id: IOPMAssertionID = 0
    let status = IOPMAssertionCreateWithName(
      kIOPMAssertPreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn), "vocula.meeting" as CFString, &id)
    guard status == kIOReturnSuccess else {
      deregister()
      return .failed(code: status)
    }
    assertion = id
    return .held(release: { self.release() })
  }

  private func apply(_ steps: [MeetingPowerSequence.Step]) {
    for step in steps {
      switch step {
      case .allow(let notification):
        IOAllowPowerChange(rootPort, notification)
      case .stopMeeting:
        Task {
          await onWillSleep()
          queue.async { self.meetingStopped() }
        }
        queue.asyncAfter(
          deadline: .now() + Double(MeetingPowerSequence.allowWithin.components.seconds)
        ) { self.meetingStopped() }
      case .deregister:
        deregister()
      }
    }
  }

  private func meetingStopped() {
    apply(sequence.meetingStopped())
  }

  private func deregister() {
    close()
    let retained = selfRetain
    selfRetain = nil
    retained?.release()
  }

  private func close() {
    if notifier != 0 { IODeregisterForSystemPower(&notifier) }
    if let port { IONotificationPortDestroy(port) }
    if rootPort != 0 { IOServiceClose(rootPort) }
    if let assertion { IOPMAssertionRelease(assertion) }
    notifier = 0
    port = nil
    rootPort = 0
    assertion = nil
  }
}
