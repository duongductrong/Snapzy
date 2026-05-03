//
//  CaptureOverlayShortcutSettings.swift
//  Snapzy
//
//  Shared persistence for shortcuts used by screenshot and recording application modes.
//

import AppKit
import Carbon.HIToolbox
import Foundation

struct CaptureOverlayShortcut: Equatable, Codable {
  let keyCode: UInt32
  let modifiers: UInt32

  var isIndependent: Bool {
    modifiers != 0
  }

  var independentShortcutConfig: ShortcutConfig? {
    guard isIndependent else { return nil }
    return ShortcutConfig(keyCode: keyCode, modifiers: modifiers)
  }

  var displayParts: [String] {
    if let independentShortcutConfig {
      return independentShortcutConfig.displayParts
    }
    return [ShortcutConfig.keyCodeToDisplayString(keyCode)]
  }

  var displayString: String {
    displayParts.joined(separator: " ")
  }

  init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  init?(from event: NSEvent) {
    guard event.type == .keyDown, event.keyCode != UInt16(kVK_Escape) else { return nil }

    let keyCode = UInt32(event.keyCode)
    let modifiers = Self.carbonModifiers(from: event)

    if modifiers == 0 {
      guard Self.isAllowedSingleKey(event) else { return nil }
    } else {
      guard ShortcutConfig(from: event) != nil else { return nil }
    }

    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  func matches(_ event: NSEvent) -> Bool {
    guard !event.modifierFlags.contains(.function) else { return false }
    guard UInt32(event.keyCode) == keyCode else { return false }
    return Self.carbonModifiers(from: event) == modifiers
  }

  static func inlineDisplay(parts: [String]) -> String {
    guard let last = parts.last else { return "" }
    let modifiers = parts.dropLast().joined()
    return modifiers.isEmpty ? last : "\(modifiers)\(last)"
  }

  private static func carbonModifiers(from event: NSEvent) -> UInt32 {
    var carbonModifiers: UInt32 = 0
    if event.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
    if event.modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
    if event.modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
    if event.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
    return carbonModifiers
  }

  private static func isAllowedSingleKey(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection([.command, .control, .option, .shift, .function]).isEmpty else {
      return false
    }
    guard let character = event.charactersIgnoringModifiers?.lowercased().first else {
      return false
    }
    return character.isLetter || character.isNumber || character == " "
  }
}

enum CaptureOverlayShortcutKind: Hashable {
  case applicationCapture
  case applicationRecording

  var displayName: String {
    switch self {
    case .applicationCapture:
      return L10n.PreferencesShortcuts.applicationCaptureTitle
    case .applicationRecording:
      return L10n.PreferencesShortcuts.applicationRecordingTitle
    }
  }
}

enum CaptureOverlayShortcutSettings {
  /// Test hook: override to inject isolated UserDefaults in unit tests.
  static var defaults: UserDefaults = .standard

  static let defaultApplicationCaptureShortcut = CaptureOverlayShortcut(
    keyCode: UInt32(kVK_ANSI_A),
    modifiers: 0
  )
  static let defaultRecordingApplicationCaptureShortcut = CaptureOverlayShortcut(
    keyCode: UInt32(kVK_ANSI_A),
    modifiers: 0
  )

  static var applicationCaptureShortcut: CaptureOverlayShortcut {
    shortcut(
      forKey: PreferencesKeys.areaApplicationCaptureShortcut,
      defaultValue: defaultApplicationCaptureShortcut
    )
  }

  static var applicationCaptureShortcutDisplay: String {
    applicationCaptureShortcut.displayString
  }

  static var applicationCaptureIndependentShortcut: ShortcutConfig? {
    applicationCaptureShortcut.independentShortcutConfig
  }

  static var recordingApplicationCaptureShortcut: CaptureOverlayShortcut {
    shortcut(
      forKey: PreferencesKeys.recordingApplicationCaptureShortcut,
      defaultValue: defaultRecordingApplicationCaptureShortcut
    )
  }

  static var recordingApplicationCaptureShortcutDisplay: String {
    recordingApplicationCaptureShortcut.displayString
  }

  static var recordingApplicationCaptureIndependentShortcut: ShortcutConfig? {
    recordingApplicationCaptureShortcut.independentShortcutConfig
  }

  static func effectiveApplicationCaptureDisplay(parentShortcut: ShortcutConfig) -> String {
    effectiveDisplay(shortcut: applicationCaptureShortcut, parentShortcut: parentShortcut)
  }

  static func effectiveRecordingApplicationCaptureDisplay(parentShortcut: ShortcutConfig) -> String {
    effectiveDisplay(shortcut: recordingApplicationCaptureShortcut, parentShortcut: parentShortcut)
  }

  static func setApplicationCaptureShortcut(_ shortcut: CaptureOverlayShortcut) {
    setShortcut(shortcut, forKey: PreferencesKeys.areaApplicationCaptureShortcut)
  }

  static func resetApplicationCaptureShortcut() {
    Self.defaults.removeObject(forKey: PreferencesKeys.areaApplicationCaptureShortcut)
  }

  static func setRecordingApplicationCaptureShortcut(_ shortcut: CaptureOverlayShortcut) {
    setShortcut(shortcut, forKey: PreferencesKeys.recordingApplicationCaptureShortcut)
  }

  static func resetRecordingApplicationCaptureShortcut() {
    Self.defaults.removeObject(forKey: PreferencesKeys.recordingApplicationCaptureShortcut)
  }

  static func matchesApplicationCaptureShortcut(_ event: NSEvent) -> Bool {
    applicationCaptureShortcut.matches(event)
  }

  static func matchesRecordingApplicationCaptureShortcut(_ event: NSEvent) -> Bool {
    recordingApplicationCaptureShortcut.matches(event)
  }

  static func shortcut(for kind: CaptureOverlayShortcutKind) -> CaptureOverlayShortcut {
    switch kind {
    case .applicationCapture:
      return applicationCaptureShortcut
    case .applicationRecording:
      return recordingApplicationCaptureShortcut
    }
  }

  private static func shortcut(
    forKey key: String,
    defaultValue: CaptureOverlayShortcut
  ) -> CaptureOverlayShortcut {
    let decoder = JSONDecoder()
    if let data = Self.defaults.data(forKey: key),
       let shortcut = try? decoder.decode(CaptureOverlayShortcut.self, from: data) {
      return shortcut
    }

    return legacyShortcut(forKey: key) ?? defaultValue
  }

  private static func setShortcut(_ shortcut: CaptureOverlayShortcut, forKey key: String) {
    guard let data = try? JSONEncoder().encode(shortcut) else { return }
    Self.defaults.set(data, forKey: key)
  }

  private static func effectiveDisplay(
    shortcut: CaptureOverlayShortcut,
    parentShortcut: ShortcutConfig
  ) -> String {
    if shortcut.isIndependent {
      return CaptureOverlayShortcut.inlineDisplay(parts: shortcut.displayParts)
    }
    let parentDisplay = CaptureOverlayShortcut.inlineDisplay(parts: parentShortcut.displayParts)
    let childDisplay = CaptureOverlayShortcut.inlineDisplay(parts: shortcut.displayParts)
    return "\(parentDisplay) \(childDisplay)"
  }

  private static func legacyShortcut(forKey key: String) -> CaptureOverlayShortcut? {
    guard let character = normalizedLegacyShortcut(from: Self.defaults.string(forKey: key)),
          let keyCode = legacyKeyCode(for: character) else {
      return nil
    }
    return CaptureOverlayShortcut(keyCode: keyCode, modifiers: 0)
  }

  private static func normalizedLegacyShortcut(from rawValue: String?) -> Character? {
    guard let rawValue else { return nil }
    if rawValue == " " { return " " }
    guard let shortcut = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .first,
      shortcut.isLetter || shortcut.isNumber
    else {
      return nil
    }
    return shortcut
  }

  private static func legacyKeyCode(for character: Character) -> UInt32? {
    switch character {
    case "a": return UInt32(kVK_ANSI_A)
    case "b": return UInt32(kVK_ANSI_B)
    case "c": return UInt32(kVK_ANSI_C)
    case "d": return UInt32(kVK_ANSI_D)
    case "e": return UInt32(kVK_ANSI_E)
    case "f": return UInt32(kVK_ANSI_F)
    case "g": return UInt32(kVK_ANSI_G)
    case "h": return UInt32(kVK_ANSI_H)
    case "i": return UInt32(kVK_ANSI_I)
    case "j": return UInt32(kVK_ANSI_J)
    case "k": return UInt32(kVK_ANSI_K)
    case "l": return UInt32(kVK_ANSI_L)
    case "m": return UInt32(kVK_ANSI_M)
    case "n": return UInt32(kVK_ANSI_N)
    case "o": return UInt32(kVK_ANSI_O)
    case "p": return UInt32(kVK_ANSI_P)
    case "q": return UInt32(kVK_ANSI_Q)
    case "r": return UInt32(kVK_ANSI_R)
    case "s": return UInt32(kVK_ANSI_S)
    case "t": return UInt32(kVK_ANSI_T)
    case "u": return UInt32(kVK_ANSI_U)
    case "v": return UInt32(kVK_ANSI_V)
    case "w": return UInt32(kVK_ANSI_W)
    case "x": return UInt32(kVK_ANSI_X)
    case "y": return UInt32(kVK_ANSI_Y)
    case "z": return UInt32(kVK_ANSI_Z)
    case " ": return UInt32(kVK_Space)
    default: return nil
    }
  }
}
