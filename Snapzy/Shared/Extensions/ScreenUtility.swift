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
    displayID(of: activeScreen())
  }

  /// The `CGDirectDisplayID` backing a given screen.
  /// Falls back to the main display when the description key is missing.
  static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
      ?? CGMainDisplayID()
  }

  /// The screen backing a `CGDirectDisplayID`, or `nil` if it is no longer connected.
  static func screen(withDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { self.displayID(of: $0) == displayID }
  }

  /// The screen holding most of a region, or `nil` when the region overlaps none of them.
  ///
  /// Used to place a surface back on the display its content came from; the cursor-driven
  /// `activeScreen()` would move it to whichever display the pointer drifted to.
  static func screen(containing rect: CGRect) -> NSScreen? {
    var best: (screen: NSScreen, overlapArea: CGFloat)?
    for screen in NSScreen.screens {
      let overlap = screen.frame.intersection(rect)
      // A disjoint `intersection` returns the null rect, whose infinite components must not
      // reach the area product — test each dimension before multiplying them.
      guard overlap.width > 0, overlap.height > 0 else { continue }
      let area = overlap.width * overlap.height
      if area > (best?.overlapArea ?? 0) {
        best = (screen, area)
      }
    }
    return best?.screen
  }
}
