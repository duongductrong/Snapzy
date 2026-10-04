//
//  SmartElementOverlayWindow.swift
//  Snapzy
//
//  Non-activating per-screen smart-element overlay panel.
//

import AppKit

final class SmartElementOverlayWindow: NSPanel, SmartElementOverlayWindowProviding {
  weak var eventDelegate: SmartElementOverlayWindowDelegate?

  let targetScreen: NSScreen
  let overlayView: SmartElementOverlayView

  init(screen: NSScreen) {
    targetScreen = screen
    overlayView = SmartElementOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .screenSaver
    backgroundColor = NSColor(white: 0, alpha: 0.005)
    isOpaque = false
    hasShadow = false
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    // Smart Element dismisses its overlays before capture; keep them shareable so remote
    // display clients can render the dimming and highlighted target during selection.
    sharingType = .readOnly
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    contentView = overlayView
    overlayView.delegate = self
    
    isMovable = false
    isMovableByWindowBackground = false
    minSize = screen.frame.size
    maxSize = screen.frame.size

    setAccessibilityElement(false)
    setAccessibilityHidden(true)
    setAccessibilityRole(.unknown)
    orderOut(nil)
  }

  var displayID: CGDirectDisplayID? {
    targetScreen.displayID
  }

  var currentHighlightRect: CGRect? {
    overlayView.currentHighlightRect
  }

  func updateHighlight(_ rect: CGRect?) {
    overlayView.updateHighlight(rect)
  }

  func updateBounds(_ screenFrame: CGRect) {
    overlayView.updateBounds(screenFrame)
  }

  override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
    self.minSize = frameRect.size
    self.maxSize = frameRect.size
    super.setFrame(frameRect, display: displayFlag)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

extension SmartElementOverlayWindow: SmartElementOverlayViewDelegate {
  func smartElementOverlayView(_ view: SmartElementOverlayView, mouseMovedAt point: CGPoint) {
    eventDelegate?.smartElementOverlayWindow(self, mouseMovedAt: point)
  }

  func smartElementOverlayView(_ view: SmartElementOverlayView, mouseDownAt point: CGPoint) {
    eventDelegate?.smartElementOverlayWindow(self, mouseDownAt: point)
  }

  func smartElementOverlayViewDidCancel(_ view: SmartElementOverlayView) {
    eventDelegate?.smartElementOverlayWindowDidCancel(self)
  }
}
