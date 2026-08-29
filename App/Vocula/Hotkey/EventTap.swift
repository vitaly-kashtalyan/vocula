@preconcurrency import AppKit
import VoculaKit

final class EventTap {
  typealias Handler = @MainActor (CGEventType, CGEvent) -> CGEvent?

  private var port: CFMachPort?
  private var source: CFRunLoopSource?
  private let options: CGEventTapOptions
  private let mask: CGEventMask
  private let handler: Handler
  private let onDisabled: @MainActor () -> Void

  init(
    options: CGEventTapOptions, handler: @escaping Handler,
    onDisabled: @escaping @MainActor () -> Void
  ) {
    self.options = options
    self.handler = handler
    self.onDisabled = onDisabled
    self.mask = CGEventMask(
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue))
  }

  @discardableResult
  func install() -> Bool {
    guard !VoculaAppDelegate.isSecondCopy else { return false }
    guard port == nil else { return true }
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      let refconBits = UInt(bitPattern: refcon)
      return MainActor.assumeIsolated { () -> Unmanaged<CGEvent>? in
        let tap = Unmanaged<EventTap>
          .fromOpaque(UnsafeMutableRawPointer(bitPattern: refconBits)!)
          .takeUnretainedValue()
        // Only the timeout: macOS reports tapDisabledByUserInput when we disable the tap ourselves.
        if type == .tapDisabledByTimeout {
          tap.onDisabled()
          return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
          return Unmanaged.passUnretained(event)
        }
        guard let passed = tap.handler(type, event) else { return nil }
        return Unmanaged.passUnretained(passed)
      }
    }
    port = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: options,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque())
    guard let port else { return false }
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: false)
    return true
  }

  func setEnabled(_ enabled: Bool) {
    guard let port else { return }
    CGEvent.tapEnable(tap: port, enable: enabled)
  }

  @discardableResult
  func reArm() -> Bool {
    guard let port else { return false }
    CGEvent.tapEnable(tap: port, enable: true)
    return CGEvent.tapIsEnabled(tap: port)
  }

  func uninstall() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let port { CFMachPortInvalidate(port) }
    source = nil
    port = nil
  }

  deinit { uninstall() }
}
