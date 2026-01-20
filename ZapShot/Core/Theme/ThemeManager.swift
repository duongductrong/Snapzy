//
//  ThemeManager.swift
//  ZapShot
//
//  Centralized theme state management for SwiftUI and AppKit
//

import AppKit
import Combine
import SwiftUI

/// Manages app-wide appearance/theme state
@MainActor
final class ThemeManager: ObservableObject {

  static let shared = ThemeManager()

  /// User's preferred appearance mode, persisted to UserDefaults
  @AppStorage(PreferencesKeys.appearanceMode)
  var preferredAppearance: AppearanceMode = .system {
    didSet {
      updateEffectiveColorScheme()
    }
  }

  /// Effective color scheme - always returns concrete value, never nil.
  /// Use this to avoid SwiftUI's async propagation delay when preferredColorScheme(nil) is used.
  @Published private(set) var effectiveColorScheme: ColorScheme = .light

  private var appearanceObserver: NSObjectProtocol?
  private var appLaunchObserver: NSObjectProtocol?

  private init() {
    // Listen to system appearance changes
    appearanceObserver = DistributedNotificationCenter.default.addObserver(
      forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updateEffectiveColorScheme()
      }
    }

    // Update color scheme after app finishes launching (NSApp will be ready)
    appLaunchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updateEffectiveColorScheme()
      }
    }

    // Try to initialize now if NSApp is already available
    updateEffectiveColorScheme()
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

  private func updateEffectiveColorScheme() {
    let newScheme: ColorScheme = switch preferredAppearance {
    case .system: currentSystemColorScheme
    case .light: .light
    case .dark: .dark
    }
    if effectiveColorScheme != newScheme {
      effectiveColorScheme = newScheme
    }
  }

  /// Returns current system color scheme by checking NSApp.effectiveAppearance
  private var currentSystemColorScheme: ColorScheme {
    // Guard against NSApp not being initialized yet (during early app launch)
    guard let app = NSApp else { return .light }
    let appearance = app.effectiveAppearance
    return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
  }

  // MARK: - SwiftUI (Deprecated)

  /// ColorScheme for SwiftUI's .preferredColorScheme() modifier
  /// Returns nil to follow system appearance
  /// - Note: Deprecated - use `effectiveColorScheme` instead to avoid async propagation issues
  var systemAppearance: ColorScheme? {
    switch preferredAppearance {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
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
