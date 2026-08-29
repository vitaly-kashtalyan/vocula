import AppKit
import ApplicationServices
import Carbon.HIToolbox
import VoculaKit

actor AXTargetProbe: TargetProbing {
  private struct Pins {
    let window: AXUIElement?
    let element: AXUIElement?
  }
  private var pins: [UUID: Pins] = [:]

  private func applyTimeout(
    _ element: AXUIElement,
    until deadline: ContinuousClock.Instant
  ) -> Bool {
    guard let seconds = QueryBudget.secondsRemaining(until: deadline, now: ContinuousClock.now)
    else { return false }
    AXUIElementSetMessagingTimeout(element, seconds)
    return true
  }

  private func currentTarget(
    until deadline: ContinuousClock.Instant
  ) async -> (pid: Int32, element: AXUIElement?, window: AXUIElement?) {
    let pid = await MainActor.run {
      NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }
    let system = AXUIElementCreateSystemWide()
    let element = applyTimeout(system, until: deadline) ? focusedElement(system) : nil
    let currentWindow = element.flatMap { window(of: $0, until: deadline) }
    return (pid, element, currentWindow)
  }

  func snapshot(budget: Duration) async -> (TargetSnapshot, FocusedSubrole) {
    let deadline = ContinuousClock.now + budget
    let (pid, element, window) = await currentTarget(until: deadline)
    let snapshot = TargetSnapshot(
      pid: pid,
      secureInputWasUp: IsSecureEventInputEnabled())
    pins[snapshot.token] = Pins(window: window, element: element)
    return (snapshot, subrole(of: element, until: deadline))
  }

  func compare(_ snapshot: TargetSnapshot, budget: Duration) async -> TargetComparison {
    let deadline = ContinuousClock.now + budget
    let pinned = pins[snapshot.token]
    let (pid, element, window) = await currentTarget(until: deadline)

    func same(_ pinned: AXUIElement?, _ now: AXUIElement?) -> Bool {
      IdentityComparison.same(pinned: pinned, now: now) { CFEqual($0, $1) }
    }

    return TargetComparison(
      pid: pid,
      sameWindow: same(pinned?.window, window),
      sameElement: same(pinned?.element, element),
      subrole: subrole(of: element, until: deadline),
      secureInputIsUp: IsSecureEventInputEnabled())
  }

  func release(_ snapshot: TargetSnapshot) async {
    pins.removeValue(forKey: snapshot.token)
  }

  private func subrole(
    of element: AXUIElement?,
    until deadline: ContinuousClock.Instant
  ) -> FocusedSubrole {
    guard let element else { return .unknown }
    guard applyTimeout(element, until: deadline) else { return .unknown }
    return SubroleAnswer.from(
      subrole: string(element, kAXSubroleAttribute as String),
      secureSubroleIdentifier: kAXSecureTextFieldSubrole as String)
  }

  private func focusedElement(_ system: AXUIElement) -> AXUIElement? {
    var focused: AnyObject?
    guard
      AXUIElementCopyAttributeValue(
        system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let value = focused,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private func window(
    of element: AXUIElement,
    until deadline: ContinuousClock.Instant
  ) -> AXUIElement? {
    guard applyTimeout(element, until: deadline) else { return nil }
    var window: AnyObject?
    guard
      AXUIElementCopyAttributeValue(
        element, kAXWindowAttribute as CFString, &window) == .success,
      let value = window,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value as? String
  }
}
