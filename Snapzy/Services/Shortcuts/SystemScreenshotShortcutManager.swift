//
//  SystemScreenshotShortcutManager.swift
//  Snapzy
//
//  Detects macOS system screenshot shortcut conflicts and guides user to disable them
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// Manages detection and resolution of conflicts between active Snapzy shortcuts
/// and macOS built-in screenshot shortcuts.
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

    var fallbackShortcut: ShortcutConfig {
      switch self {
      case .saveAreaToFile:
        return .defaultArea
      case .copyAreaToClipboard:
        return ShortcutConfig(
          keyCode: UInt32(kVK_ANSI_4),
          modifiers: UInt32(cmdKey | shiftKey | controlKey)
        )
      case .saveScreenToFile:
        return .defaultFullscreen
      case .copyScreenToClipboard:
        return ShortcutConfig(
          keyCode: UInt32(kVK_ANSI_3),
          modifiers: UInt32(cmdKey | shiftKey | controlKey)
        )
      case .screenshotOptions:
        return .defaultRecording
      }
    }

    var displayName: String {
      switch self {
      case .saveAreaToFile:
        return L10n.SystemShortcuts.macOSCaptureArea
      case .copyAreaToClipboard:
        return L10n.SystemShortcuts.macOSCopyArea
      case .saveScreenToFile:
        return L10n.SystemShortcuts.macOSCaptureFullscreen
      case .copyScreenToClipboard:
        return L10n.SystemShortcuts.macOSCopyFullscreen
      case .screenshotOptions:
        return L10n.SystemShortcuts.macOSScreenshotOptions
      }
    }
  }

  // MARK: - Known system shortcuts (fallback when live pref read is unavailable)

  /// Other well-known macOS system shortcuts (outside the symbolic-hotkeys domain) that
  /// can collide with Snapzy bindings. Used as a fallback so detection still reports the
  /// most common conflicts when `com.apple.symbolichotkeys` cannot be read live.
  ///
  /// "Spotlight" is a proper noun and is intentionally left unlocalized.
  private static let otherKnownSystemConflicts: [(name: String, shortcut: ShortcutConfig)] = [
    ("Spotlight", ShortcutConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))),
  ]

  // MARK: - UserDefaults Keys

  private let promptSeenKey = "systemShortcutsDisablePromptSeen"
  private let startupReminderKey = "systemShortcutsStartupReminderLastShown"

  // MARK: - Public API

  /// Whether the user has already been prompted to disable system shortcuts
  var hasSeenDisablePrompt: Bool {
    get { UserDefaults.standard.bool(forKey: promptSeenKey) }
    set { UserDefaults.standard.set(newValue, forKey: promptSeenKey) }
  }

  /// Check if any enabled macOS screenshot shortcuts conflict with the
  /// currently-enabled Snapzy fullscreen/area/recording shortcuts.
  ///
  /// Reads `com.apple.symbolichotkeys` via UserDefaults(suiteName:),
  /// which requires the shared-preference.read-only entitlement in sandbox.
  func hasConflictingSystemShortcuts() -> Bool {
    if let hotkeys = readHotkeys() {
      for kind in GlobalShortcutKind.allCases where kind.isSystemConflictRelevant {
        guard KeyboardShortcutManager.shared.isShortcutEnabled(for: kind) else { continue }
        guard let snapzyShortcut = KeyboardShortcutManager.shared.shortcut(for: kind) else { continue }

        if !matchingSystemHotkeys(for: kind, shortcut: snapzyShortcut, in: hotkeys).isEmpty
             || !otherKnownConflictNames(for: snapzyShortcut).isEmpty {
          return true
        }
      }
      return false
    }

    // Live pref read unavailable — fall back to known default macOS shortcuts so the most
    // common conflicts (⌘⇧3 / ⌘⇧4 / ⌘⇧5, Spotlight) are still detected instead of silently
    // assumed to be absent. This is the core of issue #500: without this fallback the app
    // reported "no conflict" and never warned the user.
    DiagnosticLogger.shared.log(
      .warning, .action,
      "Cannot read com.apple.symbolichotkeys — falling back to known default system shortcuts"
    )
    return hasKnownDefaultConflict()
  }

  /// High-confidence conflict check: returns `true` only when the live
  /// `com.apple.symbolichotkeys` read succeeds AND finds an enabled system shortcut that
  /// collides with an enabled Snapzy shortcut. Used for the proactive launch notification,
  /// where we deliberately avoid notifying about the uncertain degraded-path fallback
  /// conflicts (those can be false positives when the user has disabled the system binding).
  func hasLiveSystemShortcutConflict() -> Bool {
    guard let hotkeys = readHotkeys() else { return false }
    for kind in GlobalShortcutKind.allCases where kind.isSystemConflictRelevant {
      guard KeyboardShortcutManager.shared.isShortcutEnabled(for: kind) else { continue }
      guard let snapzyShortcut = KeyboardShortcutManager.shared.shortcut(for: kind) else { continue }

      if !matchingSystemHotkeys(for: kind, shortcut: snapzyShortcut, in: hotkeys).isEmpty
           || !otherKnownConflictNames(for: snapzyShortcut).isEmpty {
        return true
      }
    }
    return false
  }

  /// Return human-readable system shortcut names that currently conflict with a proposed Snapzy shortcut.
  func conflictDescriptions(for kind: GlobalShortcutKind, shortcut: ShortcutConfig) -> [String] {
    guard kind.isSystemConflictRelevant else { return [] }

    if let hotkeys = readHotkeys() {
      let names = matchingSystemHotkeys(for: kind, shortcut: shortcut, in: hotkeys)
        .map(\.displayName)
      // Also flag always-on system shortcuts that live outside AppleSymbolicHotKeys
      // (e.g. Spotlight ⌘Space), so coverage is real in the normal path, not just degraded.
      return names + otherKnownConflictNames(for: shortcut)
    }

    // Live pref read unavailable — fall back to known default conflict names so the
    // conflict UI (recorder popover / preferences banner) still warns the user instead
    // of silently reporting "no conflict". See issue #500.
    return knownDefaultConflictNames(for: kind, shortcut: shortcut)
  }

  func hasConflict(for kind: GlobalShortcutKind, shortcut: ShortcutConfig) -> Bool {
    !conflictDescriptions(for: kind, shortcut: shortcut).isEmpty
  }

  /// Posts a native notification at app launch when a *high-confidence* system shortcut
  /// conflict is detected (see `hasLiveSystemShortcutConflict`), so the user is warned
  /// proactively instead of discovering it only after a shortcut silently fails. Uses only
  /// the live, enabled-state-aware detection to avoid nagging users who intentionally
  /// disabled the system bindings. Throttled to at most once every 7 days; the timestamp is
  /// persisted only after a successful delivery so an unauthorized/undelivered notification
  /// never silently suppresses the reminder. Directly addresses the "reminder" request in
  /// issue #500.
  func notifyConflictOnLaunchIfNeeded() {
    guard hasLiveSystemShortcutConflict() else { return }

    let defaults = UserDefaults.standard
    if let lastShown = defaults.object(forKey: startupReminderKey) as? Date,
       Date().timeIntervalSince(lastShown) < 7 * 24 * 60 * 60 {
      return
    }

    Task {
      let posted = await SystemNotificationService.shared.post(
        title: L10n.SystemShortcuts.conflictNotificationTitle,
        body: L10n.SystemShortcuts.conflictNotificationBody
      )
      // Persist only on success — an undelivered notification (e.g. not yet authorized)
      // must not suppress the reminder for 7 days.
      if posted {
        defaults.set(Date(), forKey: startupReminderKey)
      }
      DiagnosticLogger.shared.log(
        posted ? .info : .debug, .action,
        "Startup system-shortcut conflict notification \(posted ? "posted" : "skipped")"
      )
    }
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

  private func shortcutConfig(for id: SystemHotkeyID, in hotkeys: [String: Any]) -> ShortcutConfig? {
    guard let entry = hotkeys[String(id.rawValue)] as? [String: Any] else {
      return id.fallbackShortcut
    }
    return parseShortcutConfig(from: entry) ?? id.fallbackShortcut
  }

  private func parseShortcutConfig(from entry: [String: Any]) -> ShortcutConfig? {
    guard let value = entry["value"] as? [String: Any],
          let parameters = value["parameters"] as? [Any],
          parameters.count >= 3,
          let keyCode = integerValue(parameters[1]),
          let flags = integerValue(parameters[2]) else {
      return nil
    }

    return ShortcutConfig(
      keyCode: UInt32(keyCode),
      modifiers: carbonModifiers(fromSystemFlags: UInt64(flags))
    )
  }

  private func integerValue(_ value: Any) -> Int? {
    switch value {
    case let number as NSNumber:
      return number.intValue
    case let int as Int:
      return int
    case let int32 as Int32:
      return Int(int32)
    case let uint as UInt32:
      return Int(uint)
    case let uint as UInt64:
      return Int(uint)
    default:
      return nil
    }
  }

  private func carbonModifiers(fromSystemFlags flags: UInt64) -> UInt32 {
    var modifiers: UInt32 = 0

    if flags & UInt64(NSEvent.ModifierFlags.command.rawValue) != 0 {
      modifiers |= UInt32(cmdKey)
    }
    if flags & UInt64(NSEvent.ModifierFlags.shift.rawValue) != 0 {
      modifiers |= UInt32(shiftKey)
    }
    if flags & UInt64(NSEvent.ModifierFlags.option.rawValue) != 0 {
      modifiers |= UInt32(optionKey)
    }
    if flags & UInt64(NSEvent.ModifierFlags.control.rawValue) != 0 {
      modifiers |= UInt32(controlKey)
    }

    return modifiers
  }

  private func matchingSystemHotkeys(
    for kind: GlobalShortcutKind,
    shortcut: ShortcutConfig,
    in hotkeys: [String: Any]
  ) -> [SystemHotkeyID] {
    relevantSystemHotkeys(for: kind).filter { hotkeyID in
      guard isHotkeyEnabled(id: hotkeyID.rawValue, in: hotkeys),
            let systemShortcut = shortcutConfig(for: hotkeyID, in: hotkeys) else {
        return false
      }

      let matches = systemShortcut == shortcut
      if matches {
        DiagnosticLogger.shared.log(
          .info, .action,
          "System screenshot hotkey \(hotkeyID.rawValue) matches Snapzy \(kind.rawValue) shortcut"
        )
      }
      return matches
    }
  }

  private func relevantSystemHotkeys(for kind: GlobalShortcutKind) -> [SystemHotkeyID] {
    switch kind {
    case .fullscreen:
      return [.saveScreenToFile, .copyScreenToClipboard]
    case .area:
      return [.saveAreaToFile, .copyAreaToClipboard]
    case .repeatArea:
      return [.copyAreaToClipboard]
    case .recording:
      return [.screenshotOptions]
    default:
      return []
    }
  }

  /// Names of well-known, always-on macOS system shortcuts (e.g. Spotlight ⌘Space) that
  /// live outside `AppleSymbolicHotKeys` and therefore are not part of the live pref read.
  /// Checked in both the live and fallback detection paths so the coverage is real, not
  /// merely a degraded-path safety net.
  private func otherKnownConflictNames(for shortcut: ShortcutConfig) -> [String] {
    Self.otherKnownSystemConflicts.compactMap { known in
      known.shortcut == shortcut ? known.name : nil
    }
  }

  /// Names of known-default system shortcuts that conflict with the given Snapzy shortcut,
  /// used as a fallback when the live `com.apple.symbolichotkeys` read is unavailable.
  /// Covers the default macOS screenshot shortcuts (⌘⇧3 / ⌘⇧4 / ⌘⇧5) and other well-known
  /// system bindings such as Spotlight (⌘Space) defined in `otherKnownSystemConflicts`.
  private func knownDefaultConflictNames(for kind: GlobalShortcutKind, shortcut: ShortcutConfig) -> [String] {
    var names: [String] = []

    for hotkeyID in relevantSystemHotkeys(for: kind) where hotkeyID.fallbackShortcut == shortcut {
      names.append(hotkeyID.displayName)
    }
    names.append(contentsOf: otherKnownConflictNames(for: shortcut))

    return names
  }

  /// Fallback conflict check used when the live `com.apple.symbolichotkeys` read fails.
  /// Iterates the enabled, system-conflict-relevant Snapzy shortcuts and compares them
  /// against the well-known default macOS shortcuts. Prevents the silent "no conflict"
  /// result that motivated issue #500, where the app never warned the user even though a
  /// default macOS binding collided with a Snapzy shortcut.
  private func hasKnownDefaultConflict() -> Bool {
    for kind in GlobalShortcutKind.allCases where kind.isSystemConflictRelevant {
      guard KeyboardShortcutManager.shared.isShortcutEnabled(for: kind) else { continue }
      guard let snapzyShortcut = KeyboardShortcutManager.shared.shortcut(for: kind) else { continue }

      if !knownDefaultConflictNames(for: kind, shortcut: snapzyShortcut).isEmpty {
        return true
      }
    }
    return false
  }

  private init() {}
}
