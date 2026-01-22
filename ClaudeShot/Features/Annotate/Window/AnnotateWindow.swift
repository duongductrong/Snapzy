//
//  AnnotateWindow.swift
//  ClaudeShot
//
//  Dark mode annotation window with proper styling
//

import AppKit

// MARK: - Notifications

extension Notification.Name {
  static let annotateSave = Notification.Name("annotateSave")
  static let annotateSaveAs = Notification.Name("annotateSaveAs")
}

/// Custom NSWindow for annotation editing with dark mode appearance
final class AnnotateWindow: NSWindow {

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

    // Enable full-size content view
    styleMask.insert(.fullSizeContentView)

    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    minSize = NSSize(width: 800, height: 600)
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

  override func layoutIfNeeded() {
    super.layoutIfNeeded()

    // Get traffic light buttons
    guard let closeButton = standardWindowButton(.closeButton),
          let miniaturizeButton = standardWindowButton(.miniaturizeButton),
          let zoomButton = standardWindowButton(.zoomButton),
          let contentView = contentView else {
      return
    }

    // Calculate position to center traffic lights with toolbar items
    // Toolbar has: 8px top padding + 28px button height + 8px bottom padding = 44px total
    // Traffic light button height is typically 16px
    let toolbarGap: CGFloat = 4
    let toolbarTopPadding: CGFloat = 0
    let toolbarItemHeight: CGFloat = 28
    let trafficLightHeight = closeButton.frame.height

    // Center traffic lights vertically with the 28px toolbar items
    let yPosition = toolbarTopPadding - toolbarGap + (toolbarItemHeight - trafficLightHeight) / 2

    // Position buttons vertically centered with toolbar items
    closeButton.frame.origin.y = yPosition
    miniaturizeButton.frame.origin.y = yPosition
    zoomButton.frame.origin.y = yPosition

    // Keep original horizontal spacing (standard macOS position)
    closeButton.frame.origin.x = 12
    miniaturizeButton.frame.origin.x = closeButton.frame.maxX + 8
    zoomButton.frame.origin.x = miniaturizeButton.frame.maxX + 8
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    // Cmd+S - Save (Done action)
    if event.keyCode == 1 && flags == .command {
      NotificationCenter.default.post(name: .annotateSave, object: self)
      return true
    }

    // Cmd+Shift+S - Save As
    if event.keyCode == 1 && flags == [.command, .shift] {
      NotificationCenter.default.post(name: .annotateSaveAs, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }
}
