//
//  CaptureSubjectOverlayWindow.swift
//  Snapzy
//
//  Non-activating per-screen Capture Subject overlay panel.
//

import AppKit

final class CaptureSubjectOverlayWindow: NSPanel, CaptureSubjectOverlayWindowProviding {
  weak var eventDelegate: CaptureSubjectOverlayWindowDelegate?

  let targetScreen: NSScreen
  let overlayView: CaptureSubjectOverlayView

  init(screen: NSScreen) {
    targetScreen = screen
    overlayView = CaptureSubjectOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .screenSaver
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
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

  var displayID: CGDirectDisplayID? { targetScreen.displayID }
  var currentPreviewRect: CGRect? { overlayView.currentPreviewRect }
  var currentDragRect: CGRect? { overlayView.currentDragRect }
  var isCameraHovered: Bool { overlayView.isCameraHovered }

  func updatePreview(_ preview: CaptureSubjectSnappedPreview?) {
    overlayView.updatePreview(preview)
  }

  func updateDragRect(_ rect: CGRect?) {
    overlayView.updateDragRect(rect)
  }

  func updateBounds(_ screenFrame: CGRect) {
    overlayView.updateBounds(screenFrame)
  }

  func setPointer(_ point: CGPoint?) {
    overlayView.setPointer(point)
  }

  override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
    self.minSize = frameRect.size
    self.maxSize = frameRect.size
    super.setFrame(frameRect, display: displayFlag)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

extension CaptureSubjectOverlayWindow: CaptureSubjectOverlayViewDelegate {
  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseMovedAt point: CGPoint) {
    eventDelegate?.captureSubjectOverlayWindow(self, mouseMovedAt: point)
  }

  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseDownAt point: CGPoint) {
    eventDelegate?.captureSubjectOverlayWindow(self, mouseDownAt: point)
  }

  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseDraggedAt point: CGPoint) {
    eventDelegate?.captureSubjectOverlayWindow(self, mouseDraggedAt: point)
  }

  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseUpAt point: CGPoint) {
    eventDelegate?.captureSubjectOverlayWindow(self, mouseUpAt: point)
  }

  func captureSubjectOverlayViewDidCancel(_ view: CaptureSubjectOverlayView) {
    eventDelegate?.captureSubjectOverlayWindowDidCancel(self)
  }

  func captureSubjectOverlayViewDidRequestCapture(_ view: CaptureSubjectOverlayView) {
    eventDelegate?.captureSubjectOverlayWindowDidRequestCapture(self)
  }
}
