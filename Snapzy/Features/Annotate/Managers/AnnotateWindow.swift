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
  static let annotateCloudUpload = Notification.Name("annotateCloudUpload")
  static let annotateAutoRedactSensitiveData = Notification.Name("annotateAutoRedactSensitiveData")
  static let annotatePasteImage = Notification.Name("annotatePasteImage")
  static let annotateAddImage = Notification.Name("annotateAddImage")
  static let annotateTogglePin = Notification.Name("annotateTogglePin")
  static let annotateDragStarted = Notification.Name("annotateDragStarted")
  static let annotateDragEnded = Notification.Name("annotateDragEnded")
  static let annotateZoomIn = Notification.Name("annotateZoomIn")
  static let annotateZoomOut = Notification.Name("annotateZoomOut")
  static let annotateZoomReset = Notification.Name("annotateZoomReset")
  static let annotateScrollZoom = Notification.Name("annotateScrollZoom")
  static let annotateMagnifyZoom = Notification.Name("annotateMagnifyZoom")
  static let annotateSpaceDown = Notification.Name("annotateSpaceDown")
  static let annotateSpaceUp = Notification.Name("annotateSpaceUp")
  static let annotatePanDrag = Notification.Name("annotatePanDrag")
  static let annotatePanScroll = Notification.Name("annotatePanScroll")
}

/// Custom NSWindow for annotation editing with dark mode appearance
class AnnotateWindow: NSWindow {
  weak var interactionState: AnnotateState?
  var onEscape: (() -> Bool)?
  private static let activeEditorLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
  private var restingLevel: NSWindow.Level = .normal

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
    level = restingLevel

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
    backgroundColor = WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  func setRestingLevel(_ newLevel: NSWindow.Level) {
    restingLevel = newLevel
    syncLevelWithFocusState()
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

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    layoutTrafficLights()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    // Own Annotate undo/redo at the window boundary so Cmd+Z never falls
    // through to stale AppKit text-system undo actions from inline editing.
    if event.keyCode == 6 && flags == .command {
      interactionState?.undo()
      return true
    }

    if event.keyCode == 6 && flags == [.command, .shift] {
      interactionState?.redo()
      return true
    }

    // Cmd+S while actively editing crop confirms the crop first.
    if event.keyCode == 1 && flags == .command && interactionState?.isCropInteractionActive == true && !isTextInputActive {
      interactionState?.confirmCropInteraction()
      return true
    }

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

    // Toggle Sidebar — configurable (default: ⌘B)
    if AnnotateShortcutManager.shared.matchesToggleSidebar(event) {
      guard !isTextInputActive, let interactionState else {
        return super.performKeyEquivalent(with: event)
      }
      interactionState.toggleSidebarVisibility()
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

    // Cloud Upload — configurable (default: ⌘U)
    if AnnotateShortcutManager.shared.matchesCloudUpload(event) {
      NotificationCenter.default.post(name: .annotateCloudUpload, object: self)
      return true
    }

    // Auto Redact Sensitive Data — configurable (default: unset)
    if AnnotateShortcutManager.shared.matchesAutoRedactSensitiveData(event) {
      if isTextInputActive {
        return super.performKeyEquivalent(with: event)
      }
      NotificationCenter.default.post(name: .annotateAutoRedactSensitiveData, object: self)
      return true
    }

    // Cmd+V - Paste image into current annotate canvas.
    if event.keyCode == 9 && flags == .command {
      // Allow normal text paste while editing text annotations.
      if isTextInputActive {
        return super.performKeyEquivalent(with: event)
      }
      NotificationCenter.default.post(name: .annotatePasteImage, object: self)
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

    // Cmd+0 — zoom to fit
    if event.keyCode == 29 && flags == .command {
      NotificationCenter.default.post(name: .annotateZoomReset, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  @objc func undo(_ sender: Any?) {
    interactionState?.undo()
  }

  @objc func redo(_ sender: Any?) {
    interactionState?.redo()
  }

  override func close() {
    // Restore cursor if the window is closed during a space-hold pan gesture
    // (e.g., user presses ⌘W while Space is held). The keyUp event that would
    // normally restore the arrow cursor never fires after window closure.
    if isSpaceHeld {
      isSpaceHeld = false
      NSCursor.arrow.set()
    }
    super.close()
  }

  // MARK: - Scroll Wheel, Magnification Zoom & Pan

  /// Track whether Space key is currently held for pan mode
  private var isSpaceHeld = false

  /// Whether the current first responder is a text input (TextEditor, NSTextView, etc.)
  private var isTextInputActive: Bool {
    guard let responder = firstResponder else { return false }
    return responder is NSTextView || responder is NSTextField
  }

  private func viewUnderCursor(for event: NSEvent) -> NSView? {
    guard let contentView else { return nil }
    let point = contentView.convert(event.locationInWindow, from: nil)
    return contentView.hitTest(point)
  }

  private func isCursorOverScrollableView(for event: NSEvent) -> Bool {
    var currentView = viewUnderCursor(for: event)
    while let view = currentView {
      if view is NSScrollView || view is NSScroller {
        return true
      }
      currentView = view.superview
    }
    return false
  }

  private func shouldPanForScrollEvent(_ event: NSEvent) -> Bool {
    guard !event.modifierFlags.contains(.command),
          !isTextInputActive,
          interactionState?.canPanInteractively == true,
          !isCursorOverScrollableView(for: event) else { return false }
    return event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
  }

  private func gesturePanDelta(for event: NSEvent) -> CGSize {
    // Direct manipulation UX: finger gesture direction should match image movement.
    // `state.pan(by:)` eventually feeds `.offset(...)` on the canvas, so using the
    // raw scroll deltas here keeps touchpad pan feeling like "grab and move".
    CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
  }

  /// Intercept scroll wheel (Cmd+scroll), trackpad magnify, Space key,
  /// and mouse drag events at the window level for zoom & pan.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .keyDown where event.keyCode == 53:
      if isTextInputActive { break }
      if interactionState?.isCropInteractionActive == true {
        interactionState?.cancelCrop()
        return
      }
      if onEscape?() == true { return }

    case .keyDown where event.keyCode == 36 || event.keyCode == 76:
      guard !isTextInputActive, interactionState?.isCropInteractionActive == true else { break }
      interactionState?.confirmCropInteraction()
      return

    case .scrollWheel where event.modifierFlags.contains(.command):
      // Cmd + scroll wheel → zoom
      let delta = event.scrollingDeltaY
      guard delta != 0 else { break }
      NotificationCenter.default.post(
        name: .annotateScrollZoom,
        object: self,
        userInfo: ["delta": delta]
      )
      return  // Consume event

    case .scrollWheel where shouldPanForScrollEvent(event):
      let delta = gesturePanDelta(for: event)
      NotificationCenter.default.post(
        name: .annotatePanScroll,
        object: self,
        userInfo: [
          "deltaX": delta.width,
          "deltaY": delta.height
        ]
      )
      return

    case .magnify:
      // Trackpad pinch → zoom
      let magnification = event.magnification
      NotificationCenter.default.post(
        name: .annotateMagnifyZoom,
        object: self,
        userInfo: ["magnification": magnification]
      )
      return  // Consume event

    case .keyDown where event.keyCode == 49:
      // If a text input is focused, let Space pass through for typing
      if isTextInputActive { break }
      // Space key down — consume ALL (including repeats) to prevent system beep
      if !event.isARepeat, interactionState?.canPanInteractively == true {
        isSpaceHeld = true
        NSCursor.openHand.set()
        NotificationCenter.default.post(name: .annotateSpaceDown, object: self)
      }
      return  // Always consume to silence beep

    case .keyUp where event.keyCode == 49:
      // If a text input is focused, let Space pass through
      if isTextInputActive { break }
      // Space key up → deactivate pan mode
      let wasSpaceHeld = isSpaceHeld
      isSpaceHeld = false
      if wasSpaceHeld {
        NSCursor.arrow.set()
        NotificationCenter.default.post(name: .annotateSpaceUp, object: self)
      }
      return

    case .leftMouseDragged where isSpaceHeld || (interactionState?.isCanvasPanningMode == true && !isTextInputActive):
      // Mouse drag while the hand tool is active → pan.
      NSCursor.closedHand.set()
      let dx = event.deltaX
      let dy = event.deltaY
      NotificationCenter.default.post(
        name: .annotatePanDrag,
        object: self,
        userInfo: ["deltaX": dx, "deltaY": dy]
      )
      return  // Consume — don't forward to drawing canvas

    case .leftMouseDown where isSpaceHeld || (interactionState?.isCanvasPanningMode == true && !isTextInputActive):
      // Consume mouse-down during pan to prevent drawing.
      return

    case .leftMouseUp where isSpaceHeld || interactionState?.isCanvasPanningMode == true:
      // Consume mouse-up during pan, restore the appropriate hand cursor.
      if interactionState?.isCanvasPanningMode == true {
        NSCursor.openHand.set()
      } else {
        NSCursor.arrow.set()
      }
      return

    default:
      break
    }
    super.sendEvent(event)
  }
}