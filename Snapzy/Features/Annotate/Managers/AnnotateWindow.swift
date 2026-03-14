//
//  AnnotateWindow.swift
//  Snapzy
//
//  Dark mode annotation window with proper styling
//

import AppKit

// MARK: - Notifications

extension Notification.Name {
  static let annotateSave = Notification.Name("annotateSave")
  static let annotateSaveAs = Notification.Name("annotateSaveAs")
  static let annotateCopyAndClose = Notification.Name("annotateCopyAndClose")
  static let annotateDragStarted = Notification.Name("annotateDragStarted")
  static let annotateDragEnded = Notification.Name("annotateDragEnded")
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

    // Explicit normal level for proper Cmd+Tab behavior
    level = .normal

    // Register as managed window for normal Cmd+` cycling
    collectionBehavior = [.managed, .participatesInCycle]

    // Increase window corner radius
    configureCornerRadius()
  }

  /// Configure custom corner radius for the window
  private func configureCornerRadius() {
    applyCornerRadius()
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
    layoutTrafficLights()
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

    // Cmd+Shift+C - Copy to clipboard and close
    if event.keyCode == 8 && flags == [.command, .shift] {
      NotificationCenter.default.post(name: .annotateCopyAndClose, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }
}
