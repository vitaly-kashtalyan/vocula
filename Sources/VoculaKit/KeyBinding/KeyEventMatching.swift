import Foundation

public struct RawKeyEvent: Equatable, Sendable {
  public enum Kind: Sendable, Equatable { case keyDown, keyUp, flagsChanged }

  public let kind: Kind
  public let keyCode: UInt16
  public let flags: UInt64

  public init(kind: Kind, keyCode: UInt16, flags: UInt64) {
    self.kind = kind
    self.keyCode = keyCode
    self.flags = flags
  }
}

public enum KeyMatching {
  public enum Code {
    public static let rightCommand: UInt16 = 0x36
    public static let command: UInt16 = 0x37
    public static let shift: UInt16 = 0x38
    public static let option: UInt16 = 0x3A
    public static let control: UInt16 = 0x3B
    public static let rightShift: UInt16 = 0x3C
    public static let rightOption: UInt16 = 0x3D
    public static let rightControl: UInt16 = 0x3E
    public static let function: UInt16 = 0x3F
  }

  enum Mask {
    static let shift: UInt64 = 1 << 17
    static let control: UInt64 = 1 << 18
    static let alternate: UInt64 = 1 << 19
    static let command: UInt64 = 1 << 20
    static let secondaryFn: UInt64 = 1 << 23
  }

  enum DeviceFlag {
    static let leftControl: UInt64 = 0x0000_0001
    static let leftShift: UInt64 = 0x0000_0002
    static let rightShift: UInt64 = 0x0000_0004
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftOption: UInt64 = 0x0000_0020
    static let rightOption: UInt64 = 0x0000_0040
    static let rightControl: UInt64 = 0x0000_2000
    static let any: UInt64 = 0x0000_207F
  }

  public static func isDown(_ keyCode: UInt16, in flags: UInt64) -> Bool {
    switch keyCode {
    case Code.function: return flags & Mask.secondaryFn != 0
    case Code.command: return flags & DeviceFlag.leftCommand != 0
    case Code.rightCommand: return flags & DeviceFlag.rightCommand != 0
    case Code.option: return flags & DeviceFlag.leftOption != 0
    case Code.rightOption: return flags & DeviceFlag.rightOption != 0
    case Code.control: return flags & DeviceFlag.leftControl != 0
    case Code.rightControl: return flags & DeviceFlag.rightControl != 0
    case Code.shift: return flags & DeviceFlag.leftShift != 0
    case Code.rightShift: return flags & DeviceFlag.rightShift != 0
    default: return false
    }
  }

  public static func sidedModifiers(in flags: UInt64) -> ModifierSet {
    var set: ModifierSet = []
    if flags & Mask.secondaryFn != 0 { set.insert(.function) }
    for (code, member) in [
      (Code.command, ModifierSet.leftCommand),
      (Code.rightCommand, .rightCommand),
      (Code.option, .leftOption),
      (Code.rightOption, .rightOption),
      (Code.control, .leftControl),
      (Code.rightControl, .rightControl),
      (Code.shift, .leftShift),
      (Code.rightShift, .rightShift),
    ] where isDown(code, in: flags) {
      set.insert(member)
    }
    return set
  }

  public static func modifierKeyCodes(for binding: KeyBinding) -> Set<UInt16> {
    var codes = Set<UInt16>()
    if binding.modifiers.contains(.function) { codes.insert(Code.function) }
    if binding.modifiers.contains(.leftCommand) { codes.insert(Code.command) }
    if binding.modifiers.contains(.rightCommand) { codes.insert(Code.rightCommand) }
    if binding.modifiers.contains(.leftOption) { codes.insert(Code.option) }
    if binding.modifiers.contains(.rightOption) { codes.insert(Code.rightOption) }
    if binding.modifiers.contains(.leftControl) { codes.insert(Code.control) }
    if binding.modifiers.contains(.rightControl) { codes.insert(Code.rightControl) }
    if binding.modifiers.contains(.leftShift) { codes.insert(Code.shift) }
    if binding.modifiers.contains(.rightShift) { codes.insert(Code.rightShift) }
    return codes
  }

  static func coarseMask(_ modifiers: ModifierSet) -> UInt64 {
    var flags: UInt64 = 0
    if !modifiers.isDisjoint(with: [.leftCommand, .rightCommand]) { flags |= Mask.command }
    if !modifiers.isDisjoint(with: [.leftOption, .rightOption]) { flags |= Mask.alternate }
    if !modifiers.isDisjoint(with: [.leftControl, .rightControl]) { flags |= Mask.control }
    if !modifiers.isDisjoint(with: [.leftShift, .rightShift]) { flags |= Mask.shift }
    return flags
  }

  public static func matchesShape(_ binding: KeyBinding, _ event: RawKeyEvent) -> Bool {
    switch binding.klass {
    case .singleModifier:
      guard event.kind == .flagsChanged else { return false }
      return modifierKeyCodes(for: binding).contains(event.keyCode)

    case .modifierPair:
      guard event.kind == .flagsChanged,
        modifierKeyCodes(for: binding).contains(event.keyCode)
      else { return false }
      guard isDown(event.keyCode, in: event.flags) else { return true }
      return pairIsComplete(binding, event)

    case .comboWithKey, .functionKey:
      guard event.kind == .keyDown || event.kind == .keyUp else { return false }
      guard event.keyCode == binding.keyCode else { return false }
      if event.kind == .keyUp {
        return true
      }
      let carried = event.flags & (Mask.command | Mask.alternate | Mask.control | Mask.shift)
      return carried == coarseMask(binding.modifiers)
    }
  }

  static func pairIsComplete(_ binding: KeyBinding, _ event: RawKeyEvent) -> Bool {
    for code in modifierKeyCodes(for: binding) where code != event.keyCode {
      guard isDown(code, in: event.flags) else { return false }
    }
    return isDown(event.keyCode, in: event.flags)
  }

  public static func isPress(_ event: RawKeyEvent) -> Bool {
    event.kind == .flagsChanged
      ? isDown(event.keyCode, in: event.flags)
      : event.kind == .keyDown
  }

  public static func matchesPrimary(config: GestureConfig, event: RawKeyEvent) -> Bool {
    matchesShape(config.primary, event)
  }

  public static func matchesLanguageCycle(
    config: GestureConfig,
    event: RawKeyEvent
  ) -> Bool {
    guard let cycle = config.languageCycle,
      !matchesPrimary(config: config, event: event)
    else { return false }
    return matchesShape(cycle, event)
  }

  public static func pollMask(for binding: KeyBinding) -> UInt64? {
    var mask: UInt64 = coarseMask(binding.modifiers)
    if binding.modifiers.contains(.function) { mask |= Mask.secondaryFn }
    return mask == 0 ? nil : mask
  }

  public static func isBindingHeld(_ binding: KeyBinding, flags: UInt64) -> Bool {
    guard let mask = pollMask(for: binding) else { return false }
    guard flags & mask == mask else { return false }
    guard flags & DeviceFlag.any != 0 else { return true }
    for bit in sidedPollBits(for: binding) where flags & bit == 0 {
      return false
    }
    return true
  }

  static func sidedPollBits(for binding: KeyBinding) -> [UInt64] {
    var bits: [UInt64] = []
    if binding.modifiers.contains(.leftCommand) { bits.append(DeviceFlag.leftCommand) }
    if binding.modifiers.contains(.rightCommand) { bits.append(DeviceFlag.rightCommand) }
    if binding.modifiers.contains(.leftOption) { bits.append(DeviceFlag.leftOption) }
    if binding.modifiers.contains(.rightOption) { bits.append(DeviceFlag.rightOption) }
    if binding.modifiers.contains(.leftControl) { bits.append(DeviceFlag.leftControl) }
    if binding.modifiers.contains(.rightControl) { bits.append(DeviceFlag.rightControl) }
    if binding.modifiers.contains(.leftShift) { bits.append(DeviceFlag.leftShift) }
    if binding.modifiers.contains(.rightShift) { bits.append(DeviceFlag.rightShift) }
    return bits
  }
}
