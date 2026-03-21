//
//  ScreenUtility.swift
//  Snapzy
//
//  Utility for detecting the active screen (screen under cursor)
//  in dual/multi-monitor setups
//

import AppKit

/// Provides helpers for multi-monitor screen detection.
/// `NSScreen.main` returns the screen containing the key window, but since
/// Snapzy is a menu-bar app with no regular focused windows it always
/// returns the primary screen.  These helpers detect the **screen the user
/// is actually interacting with** by using `NSEvent.mouseLocation`.
enum ScreenUtility {

  /// The screen the mouse cursor is currently on.
  /// Falls back to `NSScreen.main` → `NSScreen.screens.first!`.
  static func activeScreen() -> NSScreen {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
      ?? NSScreen.main
      ?? NSScreen.screens.first!
  }

  /// The `CGDirectDisplayID` of the screen the mouse cursor is currently on.
  static func activeDisplayID() -> CGDirectDisplayID {
    let screen = activeScreen()
    return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
      ?? CGMainDisplayID()
  }
}
