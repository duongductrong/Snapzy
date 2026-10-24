//
//  CaptureChromeWindowRegistry.swift
//  Snapzy
//
//  Tracks Snapzy's capture chrome windows so captures can exclude them by window ID
//

import AppKit

/// Single source of truth for Snapzy's capture chrome: the overlays, HUDs and recording
/// controls that sit on screen while a capture or recording is in progress.
///
/// Chrome stays visible to screen recorders (Snapzy's own and third-party ones, like
/// CleanShot X), so it cannot rely on `sharingType = .none` to stay out of Snapzy's
/// screenshots. Every capture path instead excludes `windowIDs(roles:)` explicitly.
@MainActor
final class CaptureChromeWindowRegistry {
  nonisolated enum Role: CaseIterable {
    /// Selection overlays, HUDs and countdowns. Shown in Snapzy's own recordings.
    case captureOverlay
    /// Recording toolbar and region overlay. Never shown in Snapzy's own recordings.
    case recordingControls
    /// Quick Access and toasts. Follow the "Include Snapzy in screenshots/recordings" prefs.
    case appWindow
  }

  static let shared = CaptureChromeWindowRegistry()

  private struct Entry {
    weak var window: NSWindow?
    let role: Role
  }

  private var entries: [ObjectIdentifier: Entry] = [:]

  /// Fired after a window is registered or unregistered.
  var onChange: (() -> Void)?

  init() {}

  // Explicit and nonisolated: the synthesized main-actor deinit hops through the
  // back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  deinit {}

  /// Marks `window` as capture chrome: visible to screen recorders, excluded from
  /// Snapzy's screenshots by window ID.
  static func configure(_ window: NSWindow, role: Role) {
    window.sharingType = .readOnly
    shared.register(window, role: role)
  }

  /// Marks `window` as a Snapzy app window (Quick Access, toasts). Recorders see it only
  /// when "Include Snapzy in screenshots" or "Include Snapzy in recordings" is on; Snapzy's
  /// screenshots exclude it by window ID unless the screenshot pref is on.
  static func configureAppWindow(_ window: NSWindow) {
    let defaults = UserDefaults.standard
    window.sharingType = appWindowSharingType(
      includeInScreenshots: defaults.bool(forKey: PreferencesKeys.screenshotIncludeOwnApp),
      includeInRecordings: defaults.bool(forKey: PreferencesKeys.recordingIncludeOwnApp)
    )
    shared.register(window, role: .appWindow)
  }

  nonisolated static func appWindowSharingType(
    includeInScreenshots: Bool,
    includeInRecordings: Bool
  ) -> NSWindow.SharingType {
    includeInScreenshots || includeInRecordings ? .readOnly : .none
  }

  func register(_ window: NSWindow, role: Role) {
    let key = ObjectIdentifier(window)
    if let entry = entries[key], entry.window === window, entry.role == role { return }
    entries[key] = Entry(window: window, role: role)
    onChange?()
  }

  func unregister(_ window: NSWindow) {
    guard entries.removeValue(forKey: ObjectIdentifier(window)) != nil else { return }
    onChange?()
  }

  func windowIDs(roles: Set<Role> = Set(Role.allCases), visibleOnly: Bool = false) -> Set<CGWindowID> {
    entries = entries.filter { $0.value.window != nil }
    return Set(entries.values.compactMap { entry -> CGWindowID? in
      guard roles.contains(entry.role), let window = entry.window, window.windowNumber > 0 else {
        return nil
      }
      guard !visibleOnly || window.isVisible else { return nil }
      return CGWindowID(window.windowNumber)
    })
  }

  /// Windows Snapzy's screenshots must leave out. App windows are kept only when
  /// "Include Snapzy in screenshots" is on.
  func screenshotExcludedWindowIDs(visibleOnly: Bool = false) -> Set<CGWindowID> {
    let includeOwnApp = UserDefaults.standard.bool(forKey: PreferencesKeys.screenshotIncludeOwnApp)
    return windowIDs(
      roles: includeOwnApp ? [.captureOverlay, .recordingControls] : Set(Role.allCases),
      visibleOnly: visibleOnly
    )
  }
}
