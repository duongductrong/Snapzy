//
//  QuickAccessPanel.swift
//  Snapzy
//
//  NSPanel subclass for quick access screenshot overlay
//

import AppKit
import Foundation

/// Non-activating floating panel for screenshot previews
@MainActor
final class QuickAccessPanel: NSPanel {
  private var visibleItemCount = 0
  private var overlayScale: CGFloat = 1
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var isMouseInteractionActive = false

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanel()
    installMouseMonitors()
  }

  private var isMonitorsSuspended = false

  override func close() {
    if !isMonitorsSuspended {
      removeMouseMonitors()
    }
    isMonitorsSuspended = false
    super.close()
  }

  func suspendMouseMonitors() {
    guard !isMonitorsSuspended else { return }
    isMonitorsSuspended = true
    removeMouseMonitors()
  }

  func resumeMouseMonitors() {
    guard isMonitorsSuspended else { return }
    isMonitorsSuspended = false
    installMouseMonitors()
  }

  /// Reinstall monitors after a runloop stall. macOS can silently disable the global
  /// event tap when delivery stalls (no re-enable notification reaches the app),
  /// which leaves hover dead until the monitors are recreated. No-op while suspended
  /// (e.g. during an active capture session).
  func reinstallMouseMonitors() {
    guard !isMonitorsSuspended else { return }
    removeMouseMonitors()
    installMouseMonitors()
  }

  func updatePassthroughRegion(itemCount: Int, scale: CGFloat) {
    visibleItemCount = max(0, itemCount)
    overlayScale = max(0.1, scale)
    refreshMousePassthrough()
  }

  func containsInteractivePoint(_ screenPoint: NSPoint) -> Bool {
    guard visibleItemCount > 0 else { return false }

    let activeHeight = Self.interactiveContentHeight(
      itemCount: visibleItemCount,
      scale: overlayScale,
      panelHeight: frame.height
    )
    let interactiveRect = NSRect(
      x: frame.minX,
      y: frame.minY,
      width: frame.width,
      height: activeHeight
    )
    return interactiveRect.contains(screenPoint)
  }

  /// Whether the panel should let mouse events fall through to the window below
  /// while the pointer is at `screenPoint`.
  ///
  /// The window server picks a click's target window the moment the click happens,
  /// using whatever `ignoresMouseEvents` is at that instant. Snapzy can only flip it
  /// after its main thread has handled a mouse-move, so the panel must already
  /// accept clicks *before* the pointer reaches a card. Otherwise a quick first click
  /// falls through to the app behind and the card seems to ignore it (#698).
  ///
  /// The decision therefore depends only on height: pass clicks through only at or
  /// above the top of the card stack (the empty area of the fixed-size panel). Beside
  /// or below the stack the panel accepts clicks. That costs nothing outside the
  /// panel frame (the window cannot receive those clicks anyway), and pointers
  /// arriving from the side or from below meet a card that is already clickable.
  /// Only a pointer moving straight down out of the empty area still needs a flip.
  func shouldPassMouseThrough(at screenPoint: NSPoint) -> Bool {
    guard visibleItemCount > 0 else { return true }

    let cardsTop = frame.minY + Self.interactiveContentHeight(
      itemCount: visibleItemCount,
      scale: overlayScale,
      panelHeight: frame.height
    )
    return screenPoint.y >= cardsTop
  }

  static func interactiveContentHeight(itemCount: Int, scale: CGFloat, panelHeight: CGFloat) -> CGFloat {
    guard itemCount > 0 else { return 0 }

    let itemCount = max(0, itemCount)
    let scale = max(0.1, scale)
    let cardHeight = QuickAccessLayout.scaledCardHeight(scale)
    let spacing = CGFloat(max(0, itemCount - 1)) * QuickAccessLayout.cardSpacing
    let contentHeight = CGFloat(itemCount) * cardHeight + spacing + QuickAccessLayout.containerPadding * 2
    return min(panelHeight, contentHeight)
  }

  private func configurePanel() {
    level = .floating
    isFloatingPanel = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false  // Cards have their own shadows
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
    applyCaptureVisibility()
  }

  // MARK: - Capture Visibility

  /// Keeps the panel out of screenshots unless "Include Snapzy in screenshots" is on (#628),
  /// and out of screen recorders unless either "Include Snapzy" pref is on.
  ///
  /// Own-app exclusion hides Snapzy's normal-level windows, but this floating panel stays
  /// on screen during captures, so captures leave it out by window ID. Applied once per
  /// panel: the controller builds a fresh panel on every `show()`.
  private func applyCaptureVisibility() {
    CaptureChromeWindowRegistry.configureAppWindow(self)
  }

  private func installMouseMonitors() {
    let mask: NSEvent.EventTypeMask = [
      .leftMouseDown,
      .leftMouseUp,
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
    ]

    if localMouseMonitor == nil {
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
        MainActor.assumeIsolated {
          self?.handleLocalMouseEvent(event)
        }
        return event
      }
    }

    if globalMouseMonitor == nil {
      // Global monitor handlers run on the main thread. Handle the event inline:
      // hopping through a Task delays the passthrough flip and widens the window
      // in which a click is routed to the app behind the panel (#698).
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
        MainActor.assumeIsolated {
          self?.handleGlobalMouseEvent(event)
        }
      }
    }
  }

  private func removeMouseMonitors() {
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
  }

  /// - Parameter missedMove: true when a mouse-move just went to some other window.
  private func refreshMousePassthrough(missedMove: Bool = false) {
    if isMouseInteractionActive && NSEvent.pressedMouseButtons & 1 == 0 {
      isMouseInteractionActive = false
    }

    if isMouseInteractionActive {
      ignoresMouseEvents = false
      return
    }

    let wasPassingThrough = ignoresMouseEvents
    ignoresMouseEvents = shouldPassMouseThrough(at: NSEvent.mouseLocation)

    // A move that went elsewhere while the pointer is over this (now clickable)
    // panel was routed before the window server applied our flip. Replay it here.
    if !ignoresMouseEvents && (wasPassingThrough || missedMove) {
      resyncHoverAtPointer()
    }
  }

  /// AppKit updates hover tracking (SwiftUI `.onHover`) only when a mouse-move
  /// reaches the window. Turning `ignoresMouseEvents` off takes effect in the window
  /// server asynchronously, so moves made just before or just after the flip still go
  /// to the window behind. If the pointer then stops on a card, the card never sees
  /// hover, its action buttons never appear, and every click lands on the card body
  /// (#698). Feed the panel one move at the current pointer location so hover is
  /// checked right away. No-op while the pointer is outside the panel.
  private func resyncHoverAtPointer() {
    let screenPoint = NSEvent.mouseLocation
    guard frame.contains(screenPoint),
          let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: convertPoint(fromScreen: screenPoint),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
          ) else { return }
    NSApp.postEvent(event, atStart: false)
  }

  private func handleLocalMouseEvent(_ event: NSEvent) {
    if event.window === self {
      switch event.type {
      case .leftMouseDown:
        isMouseInteractionActive = containsInteractivePoint(NSEvent.mouseLocation)
      case .leftMouseUp:
        isMouseInteractionActive = false
      default:
        break
      }
    }

    refreshMousePassthrough(missedMove: event.type == .mouseMoved && event.window !== self)
  }

  private func handleGlobalMouseEvent(_ event: NSEvent) {
    if event.type == .leftMouseUp {
      isMouseInteractionActive = false
    }

    // Global events always went to another app.
    refreshMousePassthrough(missedMove: event.type == .mouseMoved)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
