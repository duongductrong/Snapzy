//
//  ScreenshotLastAreaStore.swift
//  Snapzy
//
//  Persists the last area-screenshot selection for instant repeat capture
//

import AppKit
import Foundation

/// Stores the most recent manual area-screenshot rect (AppKit global screen
/// coordinates, in points) so it can be re-captured without re-selecting.
/// Mirrors the recording area persistence in `RecordingCoordinator`.
@MainActor
enum ScreenshotLastAreaStore {
  /// Save the last area screenshot rect to UserDefaults
  static func save(_ rect: CGRect) {
    let rectDict: [String: CGFloat] = [
      "x": rect.origin.x,
      "y": rect.origin.y,
      "width": rect.width,
      "height": rect.height
    ]
    UserDefaults.standard.set(rectDict, forKey: PreferencesKeys.screenshotLastAreaRect)
  }

  /// Load the last area screenshot rect from UserDefaults.
  /// Returns nil when nothing is stored or the rect is no longer visible on
  /// any connected screen (e.g. an external display was disconnected).
  static func load() -> CGRect? {
    guard let rectDict = UserDefaults.standard.dictionary(forKey: PreferencesKeys.screenshotLastAreaRect),
          let x = rectDict["x"] as? CGFloat,
          let y = rectDict["y"] as? CGFloat,
          let width = rectDict["width"] as? CGFloat,
          let height = rectDict["height"] as? CGFloat else {
      return nil
    }

    let rect = CGRect(x: x, y: y, width: width, height: height)

    // Validate rect is still visible on current screens
    guard isRectVisibleOnScreen(rect) else {
      return nil
    }

    return rect
  }

  /// Check if rect is visible on any connected screen
  private static func isRectVisibleOnScreen(_ rect: CGRect) -> Bool {
    for screen in NSScreen.screens {
      if screen.frame.intersects(rect) {
        return true
      }
    }
    return false
  }
}
