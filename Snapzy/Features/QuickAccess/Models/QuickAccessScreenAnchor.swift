//
//  QuickAccessScreenAnchor.swift
//  Snapzy
//
//  Tracks which display the quick access panel is pinned to so multi-monitor
//  captures keep the panel on the screen the user is capturing on (#467).
//

import AppKit

/// Remembers the display a floating panel was placed on.
///
/// The panel is positioned once when it appears, so every later reposition
/// (corner preference, resize, slide-out) must resolve against the *same*
/// screen — re-reading the cursor there would teleport a visible panel as soon
/// as the user moved the mouse to another display. Only a new capture re-anchors
/// it, via `anchor(to:)`.
struct QuickAccessScreenAnchor {

  private(set) var displayID: CGDirectDisplayID?

  /// Pin to `screen`. Returns `true` only when this changes the anchored display.
  @discardableResult
  mutating func anchor(to screen: NSScreen) -> Bool {
    let newDisplayID = ScreenUtility.displayID(of: screen)
    guard newDisplayID != displayID else { return false }
    displayID = newDisplayID
    return true
  }

  /// Pin to the screen the cursor is on. Returns `true` when the display changed.
  @discardableResult
  mutating func anchorToActiveScreen() -> Bool {
    anchor(to: ScreenUtility.activeScreen())
  }

  /// Screen to position against: the anchored display while it is still
  /// connected, otherwise the active screen (display unplugged or never set).
  var screen: NSScreen {
    guard let displayID, let screen = ScreenUtility.screen(withDisplayID: displayID) else {
      return ScreenUtility.activeScreen()
    }
    return screen
  }
}
