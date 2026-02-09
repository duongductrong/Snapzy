//
//  RecordingAnnotationToolbarWindow.swift
//  Snapzy
//
//  Floating NSWindow for annotation tools during recording
//  Draggable with auto-snap to corners, auto horizontal/vertical layout
//  Uses manual drag tracking loop for full control over placeholder + snap
//

import AppKit
import Combine
import SwiftUI

// MARK: - First-click content view

/// Accepts first mouse so the toolbar is draggable without needing a focus click first.
private class FirstMouseVisualEffectView: NSVisualEffectView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class RecordingAnnotationToolbarWindow: NSWindow {

  private let annotationState: RecordingAnnotationState
  private var hostingView: NSHostingView<AnyView>?
  private var effectView: NSVisualEffectView?
  private var direction: AnnotationToolbarDirection = .horizontal
  private var enabledCancellable: AnyCancellable?
  private let snapHelper = AnnotationToolbarSnapHelper()

  init(annotationState: RecordingAnnotationState) {
    self.annotationState = annotationState

    super.init(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    rebuildContent()
    positionDefault()
    observeToggle()
  }

  // MARK: - Configuration

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hasShadow = false
    isReleasedWhenClosed = false
    appearance = ThemeManager.shared.nsAppearance
    isMovableByWindowBackground = false
    acceptsMouseMovedEvents = true
  }

  // Force-accept first click without requiring focus — ensures drag works immediately
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown && !isKeyWindow {
      makeKeyAndOrderFront(nil)
    }
    super.sendEvent(event)
  }

  private func observeToggle() {
    enabledCancellable = annotationState.$isAnnotationEnabled
      .receive(on: RunLoop.main)
      .sink { [weak self] enabled in
        if enabled {
          self?.orderFrontRegardless()
        } else {
          self?.orderOut(nil)
        }
      }
  }

  // MARK: - Content

  private func rebuildContent() {
    let view = RecordingAnnotationToolbarView(
      state: annotationState,
      direction: direction
    )

    let themed = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hosting = NSHostingView(rootView: AnyView(themed))
    hosting.translatesAutoresizingMaskIntoConstraints = false

    let effect = FirstMouseVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = ToolbarConstants.toolbarCornerRadius
    effect.layer?.masksToBounds = true

    hosting.layer?.backgroundColor = .clear
    effect.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: effect.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
      hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
    ])

    let fittingSize = hosting.fittingSize
    effect.frame = CGRect(origin: .zero, size: fittingSize)

    contentView = effect
    hostingView = hosting
    effectView = effect
    setContentSize(fittingSize)
  }

  // MARK: - Positioning

  private func positionDefault() {
    guard let screen = NSScreen.main else { return }
    let sf = screen.visibleFrame
    let size = self.frame.size
    let x = sf.midX - size.width / 2
    let y = sf.minY + 60
    setFrameOrigin(CGPoint(x: x, y: y))
  }

  // MARK: - Manual Drag + Snap

  override func mouseDown(with event: NSEvent) {
    // Use screen coordinates — locationInWindow shifts as window moves, causing jitter
    let startMouse = NSEvent.mouseLocation
    let startOrigin = frame.origin

    // Show placeholder at initial snap position
    var lastSnap = currentSnap()
    snapHelper.showPlaceholder(snap: lastSnap, size: sizeForDirection(lastSnap.direction))

    var dragged = false
    while true {
      guard let nextEvent = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

      if nextEvent.type == .leftMouseUp {
        break
      }

      // Move window by screen-space delta
      let currentMouse = NSEvent.mouseLocation
      let newOrigin = CGPoint(
        x: startOrigin.x + (currentMouse.x - startMouse.x),
        y: startOrigin.y + (currentMouse.y - startMouse.y)
      )
      setFrameOrigin(newOrigin)
      dragged = true

      // Update placeholder to match new snap target
      lastSnap = currentSnap()
      snapHelper.updatePlaceholder(snap: lastSnap, size: sizeForDirection(lastSnap.direction))
    }

    snapHelper.hidePlaceholder()

    if dragged {
      snapToPosition(lastSnap)
    }
  }

  // MARK: - Snap

  private func currentSnap() -> AnnotationToolbarSnapResult {
    snapHelper.computeSnap(for: frame, currentDirection: direction) { [self] dir in
      sizeForDirection(dir)
    }
  }

  private func sizeForDirection(_ dir: AnnotationToolbarDirection) -> CGSize {
    if dir == direction { return frame.size }
    return CGSize(width: frame.size.height, height: frame.size.width)
  }

  private func snapToPosition(_ snap: AnnotationToolbarSnapResult) {
    if snap.direction != direction {
      direction = snap.direction
      rebuildContent()
    }

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.25
      ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      self.animator().setFrameOrigin(snap.origin)
    }
  }

  override var canBecomeKey: Bool { true }
}
