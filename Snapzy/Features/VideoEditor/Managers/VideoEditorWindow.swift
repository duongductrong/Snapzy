//
//  VideoEditorWindow.swift
//  Snapzy
//
//  Dark mode video editor window configuration
//

import AppKit
import Combine

// MARK: - Notifications

extension Notification.Name {
  static let videoEditorCloudUpload = Notification.Name("videoEditorCloudUpload")
}

/// Custom NSWindow for video editing with dark mode appearance
class VideoEditorWindow: NSWindow {
  private static let activeEditorLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
  private var restingLevel: NSWindow.Level = .normal
  private var themeObserver: AnyCancellable?

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    configure()
  }
  
  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    
    layoutTrafficLights()
  }

  private func configure() {
    applyTheme()
    setupThemeObserver()

    // Enable full-size content view
    styleMask.insert(.fullSizeContentView)

    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    minSize = NSSize(width: 400, height: 300)
    isReleasedWhenClosed = false
    center()

    // Explicit normal level for proper Cmd+Tab behavior
    level = restingLevel

    // Register as managed window for normal Cmd+` cycling
    collectionBehavior = [.managed, .participatesInCycle]

    applyCornerRadius()
  }

  private func setupThemeObserver() {
    themeObserver = ThemeManager.shared.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.applyTheme()
      }
  }

  func applyActiveEditorLevel() {
    level = Self.activeEditorLevel
  }

  func restoreRestingLevel() {
    level = restingLevel
  }

  func syncLevelWithFocusState() {
    level = (isKeyWindow || isMainWindow) ? Self.activeEditorLevel : restingLevel
  }

  /// Apply current theme from ThemeManager
  func applyTheme() {
    let themeManager = ThemeManager.shared
    appearance = themeManager.nsAppearance
    backgroundColor = WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
