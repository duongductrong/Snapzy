//
//  DesktopIconManager.swift
//  Snapzy
//
//  Provides Finder and widget app references for ScreenCaptureKit-based exclusion.
//  Instead of killing/restarting processes (slow, ~3-5s), we exclude apps from
//  SCContentFilter at capture time. Open Finder windows stay visible via
//  exceptingWindows. Wallpaper is preserved because it's rendered by
//  Dock/WallpaperAgent, not Finder.
//

import Foundation
import ScreenCaptureKit

@MainActor
final class DesktopIconManager {
  static let shared = DesktopIconManager()

  /// Bundle IDs for widget-related processes on macOS 14+
  private static let widgetBundleIDs: Set<String> = [
    "com.apple.notificationcenterui",
    "com.apple.widgetkit.simulator",
    "com.apple.widgetkitextensionhost",
  ]

  private init() {}

  /// Whether the user has enabled desktop icon hiding in preferences
  var isIconHidingEnabled: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.hideDesktopIcons)
  }

  /// Whether the user has enabled desktop widget hiding in preferences
  var isWidgetHidingEnabled: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.hideDesktopWidgets)
  }

  /// Get Finder as SCRunningApplication for exclusion from capture filters.
  func getFinderApps(from content: SCShareableContent) -> [SCRunningApplication] {
    content.applications.filter { $0.bundleIdentifier == "com.apple.finder" }
  }

  /// Get only Finder's desktop/icon windows for window-based exclusion.
  func getDesktopIconWindows(from content: SCShareableContent) -> [SCWindow] {
    content.windows.filter { window in
      window.owningApplication?.bundleIdentifier == "com.apple.finder"
        && window.windowLayer > 0
        && window.isOnScreen
    }
  }

  /// Get widget-related apps for exclusion from capture filters.
  func getWidgetApps(from content: SCShareableContent) -> [SCRunningApplication] {
    content.applications.filter { Self.widgetBundleIDs.contains($0.bundleIdentifier) }
  }

  /// Get on-screen widget windows for window-based exclusion.
  func getWidgetWindows(from content: SCShareableContent) -> [SCWindow] {
    content.windows.filter { window in
      Self.widgetBundleIDs.contains(window.owningApplication?.bundleIdentifier ?? "")
        && window.isOnScreen
    }
  }

  /// Get visible Finder windows (non-desktop) to keep in capture via exceptingWindows.
  /// Desktop icon windows have windowLayer > 0; regular Finder windows have windowLayer == 0.
  func getVisibleFinderWindows(from content: SCShareableContent) -> [SCWindow] {
    content.windows.filter { window in
      window.owningApplication?.bundleIdentifier == "com.apple.finder"
        && window.windowLayer == 0
        && window.isOnScreen
    }
  }
}
