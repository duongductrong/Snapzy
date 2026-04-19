//
//  CaptureOverlayShortcutSettings.swift
//  Snapzy
//
//  Shared persistence for local shortcuts used inside the capture overlay session.
//

import AppKit
import Foundation

enum CaptureOverlayShortcutSettings {
  static let defaultApplicationCaptureShortcut: Character = "a"

  static var applicationCaptureShortcut: Character {
    normalizedShortcut(from: UserDefaults.standard.string(forKey: PreferencesKeys.areaApplicationCaptureShortcut))
      ?? defaultApplicationCaptureShortcut
  }

  static var applicationCaptureShortcutDisplay: String {
    String(applicationCaptureShortcut).uppercased()
  }

  static func setApplicationCaptureShortcut(_ shortcut: Character) {
    guard let normalized = normalizedShortcut(from: String(shortcut)) else { return }
    UserDefaults.standard.set(String(normalized), forKey: PreferencesKeys.areaApplicationCaptureShortcut)
  }

  static func resetApplicationCaptureShortcut() {
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.areaApplicationCaptureShortcut)
  }

  static func matchesApplicationCaptureShortcut(_ event: NSEvent) -> Bool {
    guard let typedCharacter = normalizedShortcut(
      from: event.charactersIgnoringModifiers?.lowercased()
    ) else {
      return false
    }
    return typedCharacter == applicationCaptureShortcut
  }

  private static func normalizedShortcut(from rawValue: String?) -> Character? {
    guard let rawValue else { return nil }
    guard let shortcut = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .first,
      shortcut.isLetter
    else {
      return nil
    }
    return shortcut
  }
}
