//
//  VideoEditorWindow.swift
//  ClaudeShot
//
//  Dark mode video editor window configuration
//

import AppKit

/// Custom NSWindow for video editing with dark mode appearance
final class VideoEditorWindow: NSWindow {

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    configure()
  }

  private func configure() {
    applyTheme()
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    minSize = NSSize(width: 400, height: 300)
    isReleasedWhenClosed = false
    center()
  }

  /// Apply current theme from ThemeManager
  func applyTheme() {
    let themeManager = ThemeManager.shared
    appearance = themeManager.nsAppearance

    // Dynamic background based on appearance
    if themeManager.preferredAppearance == .light {
      backgroundColor = NSColor(white: 0.95, alpha: 1)
    } else if themeManager.preferredAppearance == .dark {
      backgroundColor = NSColor(white: 0.12, alpha: 1)
    } else {
      // System: use semantic color
      backgroundColor = NSColor.windowBackgroundColor
    }
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
