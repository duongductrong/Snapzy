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
  static let annotateTogglePin = Notification.Name("annotateTogglePin")
  static let annotateDragStarted = Notification.Name("annotateDragStarted")
  static let annotateDragEnded = Notification.Name("annotateDragEnded")
  static let annotateZoomIn = Notification.Name("annotateZoomIn")
  static let annotateZoomOut = Notification.Name("annotateZoomOut")
  static let annotateZoomReset = Notification.Name("annotateZoomReset")
  static let annotateScrollZoom = Notification.Name("annotateScrollZoom")
  static let annotateMagnifyZoom = Notification.Name("annotateMagnifyZoom")
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

    // Cmd+S - Save (Done action) — standard macOS
    if event.keyCode == 1 && flags == .command {
      NotificationCenter.default.post(name: .annotateSave, object: self)
      return true
    }

    // Cmd+Shift+S - Save As — standard macOS
    if event.keyCode == 1 && flags == [.command, .shift] {
      NotificationCenter.default.post(name: .annotateSaveAs, object: self)
      return true
    }

    // Copy & Close — configurable (default: ⌘⇧C)
    if AnnotateShortcutManager.shared.matchesCopyAndClose(event) {
      NotificationCenter.default.post(name: .annotateCopyAndClose, object: self)
      return true
    }

    // Toggle Pin — configurable (default: ⌃⌘P)
    if AnnotateShortcutManager.shared.matchesTogglePin(event) {
      NotificationCenter.default.post(name: .annotateTogglePin, object: self)
      return true
    }

    // Cmd+= or Cmd++ — zoom in
    if event.keyCode == 24 && flags == .command {
      NotificationCenter.default.post(name: .annotateZoomIn, object: self)
      return true
    }

    // Cmd+- — zoom out
    if event.keyCode == 27 && flags == .command {
      NotificationCenter.default.post(name: .annotateZoomOut, object: self)
      return true
    }

    // Cmd+0 — zoom to 100%
    if event.keyCode == 29 && flags == .command {
      NotificationCenter.default.post(name: .annotateZoomReset, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  // MARK: - Scroll Wheel & Magnification Zoom

  /// Intercept scroll wheel (Cmd+scroll) and trackpad magnify events
  /// at the window level, before AppKit dispatches them to subviews.
  /// This guarantees capture regardless of which view is under the cursor.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .scrollWheel where event.modifierFlags.contains(.command):
      // Cmd + scroll wheel → zoom
      let delta = event.scrollingDeltaY
      guard delta != 0 else { break }
      NotificationCenter.default.post(
        name: .annotateScrollZoom,
        object: self,
        userInfo: ["delta": delta]
      )
      return  // Consume event — don't forward to subviews

    case .magnify:
      // Trackpad pinch → zoom
      let magnification = event.magnification
      NotificationCenter.default.post(
        name: .annotateMagnifyZoom,
        object: self,
        userInfo: ["magnification": magnification]
      )
      return  // Consume event

    default:
      break
    }
    super.sendEvent(event)
  }
}
