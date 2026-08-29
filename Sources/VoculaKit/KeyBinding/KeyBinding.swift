import Foundation

public enum BindingClass: String, Codable, Sendable, CaseIterable {
  case singleModifier
  case modifierPair
  case comboWithKey
  case functionKey
}

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let leftCommand = ModifierSet(rawValue: 1 << 0)
  public static let rightCommand = ModifierSet(rawValue: 1 << 1)
  public static let leftOption = ModifierSet(rawValue: 1 << 2)
  public static let rightOption = ModifierSet(rawValue: 1 << 3)
  public static let leftControl = ModifierSet(rawValue: 1 << 4)
  public static let rightControl = ModifierSet(rawValue: 1 << 5)
  public static let leftShift = ModifierSet(rawValue: 1 << 6)
  public static let rightShift = ModifierSet(rawValue: 1 << 7)
  public static let function = ModifierSet(rawValue: 1 << 8)

  public var carbonMask: UInt32 {
    var mask: UInt32 = 0
    if !isDisjoint(with: [.leftShift, .rightShift]) { mask |= 1 << 17 }
    if !isDisjoint(with: [.leftControl, .rightControl]) { mask |= 1 << 18 }
    if !isDisjoint(with: [.leftOption, .rightOption]) { mask |= 1 << 19 }
    if !isDisjoint(with: [.leftCommand, .rightCommand]) { mask |= 1 << 20 }
    return mask
  }
}

public struct KeyBinding: Codable, Hashable, Sendable {
  public var klass: BindingClass
  public var keyCode: UInt16?
  public var modifiers: ModifierSet

  public init(klass: BindingClass, keyCode: UInt16?, modifiers: ModifierSet) {
    self.klass = klass
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public var absorbsOwnEvent: Bool {
    klass == .comboWithKey || klass == .functionKey
  }

  public var isBareModifier: Bool {
    klass == .singleModifier || klass == .modifierPair
  }

  public static let fn = KeyBinding(klass: .singleModifier, keyCode: nil, modifiers: [.function])
  public static let rightCommand = KeyBinding(
    klass: .singleModifier, keyCode: nil,
    modifiers: [.rightCommand])
  public static let rightControl = KeyBinding(
    klass: .singleModifier, keyCode: nil,
    modifiers: [.rightControl])
  public static let rightOption = KeyBinding(
    klass: .singleModifier, keyCode: nil,
    modifiers: [.rightOption])

  public static let languageCycle = KeyBinding(
    klass: .comboWithKey, keyCode: 0x25,
    modifiers: [.leftControl, .leftShift])
}
