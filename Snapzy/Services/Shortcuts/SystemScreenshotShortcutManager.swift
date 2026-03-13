//
//  SystemScreenshotShortcutManager.swift
//  Snapzy
//
//  Detects macOS system screenshot shortcut conflicts and guides user to disable them
//

import AppKit
import Foundation

/// Manages detection and resolution of conflicts between Snapzy shortcuts
/// and macOS built-in screenshot shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5).
///
/// Requires entitlement:
///   com.apple.security.temporary-exception.shared-preference.read-only
///   → com.apple.symbolichotkeys
@MainActor
final class SystemScreenshotShortcutManager {

  static let shared = SystemScreenshotShortcutManager()

  // MARK: - Symbolic Hotkey IDs

  /// macOS symbolic hotkey IDs for screenshot shortcuts
  /// Reference: ~/Library/Preferences/com.apple.symbolichotkeys.plist
  private enum SystemHotkeyID: Int, CaseIterable {
    case saveAreaToFile = 28        // ⌘⇧4 — Save picture of selected area as file
    case copyAreaToClipboard = 29   // ⌃⌘⇧4 — Copy picture of selected area to clipboard
    case saveScreenToFile = 30      // ⌘⇧3 — Save picture of screen as file
    case copyScreenToClipboard = 31 // ⌃⌘⇧3 — Copy picture of screen to clipboard
    case screenshotOptions = 184    // ⌘⇧5 — Screenshot and recording options
  }

  // MARK: - UserDefaults Keys

  private let promptSeenKey = "systemShortcutsDisablePromptSeen"

  // MARK: - Public API

  /// Whether the user has already been prompted to disable system shortcuts
  var hasSeenDisablePrompt: Bool {
    get { UserDefaults.standard.bool(forKey: promptSeenKey) }
    set { UserDefaults.standard.set(newValue, forKey: promptSeenKey) }
  }

  /// Check if any macOS system screenshot shortcuts are still enabled
  /// that would conflict with Snapzy's default shortcuts.
  ///
  /// Reads `com.apple.symbolichotkeys` via UserDefaults(suiteName:),
  /// which requires the shared-preference.read-only entitlement in sandbox.
  func hasConflictingSystemShortcuts() -> Bool {
    guard let hotkeys = readHotkeys() else {
      // Can't read — assume NO conflicts (don't nag user if we can't verify)
      DiagnosticLogger.shared.log(
        .warning, .action,
        "Cannot read com.apple.symbolichotkeys — assuming no conflicts"
      )
      return false
    }

    // Check only the IDs that directly conflict with Snapzy defaults (⌘⇧3, ⌘⇧4, ⌘⇧5)
    let conflictingIDs: [SystemHotkeyID] = [
      .saveScreenToFile,     // ⌘⇧3 conflicts with Snapzy fullscreen
      .saveAreaToFile,       // ⌘⇧4 conflicts with Snapzy area capture
      .screenshotOptions,    // ⌘⇧5 conflicts with Snapzy recording
    ]

    for hotkeyID in conflictingIDs {
      if isHotkeyEnabled(id: hotkeyID.rawValue, in: hotkeys) {
        DiagnosticLogger.shared.log(
          .info, .action,
          "System screenshot hotkey \(hotkeyID.rawValue) is enabled — conflict detected"
        )
        return true
      }
    }

    DiagnosticLogger.shared.log(
      .info, .action,
      "No conflicting system screenshot shortcuts detected"
    )
    return false
  }

  /// Open System Settings to the Keyboard Shortcuts → Screenshots pane
  func openSystemScreenshotSettings() {
    // Mark prompt as seen
    hasSeenDisablePrompt = true

    // Deep link to Keyboard Settings — Screenshots section
    // Works on macOS 13+ (Ventura and later)
    let urls = [
      "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Screenshots",
      "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
    ]

    for urlString in urls {
      if let url = URL(string: urlString) {
        NSWorkspace.shared.open(url)
        DiagnosticLogger.shared.log(
          .info, .action,
          "Opened System Settings: \(urlString)"
        )
        return
      }
    }

    // Fallback: open general Keyboard settings
    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Private

  /// Read the AppleSymbolicHotKeys dictionary from the system preferences domain.
  private func readHotkeys() -> [String: Any]? {
    // Method 1: UserDefaults(suiteName:) — works with shared-preference entitlement
    if let prefs = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
      let hotkeys = prefs.dictionary(forKey: "AppleSymbolicHotKeys")
    {
      DiagnosticLogger.shared.log(
        .info, .action,
        "Read \(hotkeys.count) symbolic hotkeys via UserDefaults"
      )
      return hotkeys
    }

    // Method 2: CFPreferences API — lower level, may work where UserDefaults doesn't
    if let value = CFPreferencesCopyAppValue(
      "AppleSymbolicHotKeys" as CFString,
      "com.apple.symbolichotkeys" as CFString
    ) {
      if let hotkeys = value as? [String: Any] {
        DiagnosticLogger.shared.log(
          .info, .action,
          "Read \(hotkeys.count) symbolic hotkeys via CFPreferences"
        )
        return hotkeys
      }
    }

    DiagnosticLogger.shared.log(
      .warning, .action,
      "All methods failed to read com.apple.symbolichotkeys"
    )
    return nil
  }

  /// Check if a specific symbolic hotkey is enabled
  private func isHotkeyEnabled(id: Int, in hotkeys: [String: Any]) -> Bool {
    guard let entry = hotkeys[String(id)] as? [String: Any] else {
      // Entry missing — shortcut may not exist on this macOS version
      return false
    }

    // The "enabled" key — try Bool first, then NSNumber
    if let enabled = entry["enabled"] as? Bool {
      return enabled
    }
    if let enabled = entry["enabled"] as? NSNumber {
      return enabled.boolValue
    }

    // If no "enabled" key, assume enabled by default (macOS default behavior)
    return true
  }

  private init() {}
}
