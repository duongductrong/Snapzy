//
//  ThemeManager.swift
//  Snapzy
//
//  Centralized theme state management for SwiftUI and AppKit
//

import AppKit
import Combine
import SwiftUI

enum WindowSurfacePalette {
  static var lightBase: NSColor {
    var color = NSColor.windowBackgroundColor
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
      color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? NSColor.windowBackgroundColor
    }
    return color
  }

  static var darkBase: NSColor {
    var color = NSColor.windowBackgroundColor
    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
      color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? NSColor.windowBackgroundColor
    }
    return color
  }

  @MainActor
  static func backgroundColor(for appearanceMode: AppearanceMode) -> NSColor {
    NSColor.windowBackgroundColor
  }

  static func backgroundColor(for appearance: NSAppearance) -> NSColor {
    var resolvedColor = NSColor.windowBackgroundColor
    appearance.performAsCurrentDrawingAppearance {
      resolvedColor = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? NSColor.windowBackgroundColor
    }
    return resolvedColor
  }
}

/// Manages app-wide appearance/theme state
@MainActor
final class ThemeManager: ObservableObject {

  static let shared = ThemeManager()

  /// User's preferred appearance mode, persisted to UserDefaults
  @AppStorage(PreferencesKeys.appearanceMode)
  var preferredAppearance: AppearanceMode = .system {
    didSet {
      updateSystemAppearance()
      objectWillChange.send()
    }
  }

  /// Resolved color scheme for SwiftUI's .preferredColorScheme() modifier.
  /// Always returns concrete value (.light or .dark), never nil.
  /// Automatically tracks system appearance changes when in .system mode.
  @Published private(set) var systemAppearance: ColorScheme = .light

  private var appearanceObserver: NSObjectProtocol?
  private var appLaunchObserver: NSObjectProtocol?

  private init() {
    // Listen to system appearance changes
    appearanceObserver = DistributedNotificationCenter.default.addObserver(
      forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateSystemAppearance()
      }
    }

    // Update color scheme after app finishes launching (NSApp will be ready)
    appLaunchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateSystemAppearance()
      }
    }

    // Try to initialize now if NSApp is already available
    updateSystemAppearance()
  }

  deinit {
    if let observer = appearanceObserver {
      DistributedNotificationCenter.default.removeObserver(observer)
    }
    if let observer = appLaunchObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Private

  private func updateSystemAppearance() {
    let newScheme: ColorScheme = switch preferredAppearance {
    case .system: currentSystemColorScheme
    case .light: .light
    case .dark: .dark
    }
    if systemAppearance != newScheme {
      systemAppearance = newScheme
    }
  }

  /// Returns current system color scheme by checking NSApp.effectiveAppearance
  private var currentSystemColorScheme: ColorScheme {
    // Try NSApp first, fall back to NSAppearance.current if not ready
    let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
    return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
  }

  // MARK: - AppKit

  /// NSAppearance for NSWindow.appearance property
  /// Returns nil to follow system appearance
  var nsAppearance: NSAppearance? {
    switch preferredAppearance {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }
}
