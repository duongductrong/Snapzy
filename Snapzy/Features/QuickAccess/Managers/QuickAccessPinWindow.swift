//
//  QuickAccessPinWindow.swift
//  Snapzy
//
//  Borderless pin window with lock-mode mouse passthrough.
//

import AppKit

@MainActor
final class QuickAccessPinWindow: NSPanel {
  private static let pinnedWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
  internal static let scrollZoomSensitivityPrecise: CGFloat = 0.0015
  internal static let scrollZoomSensitivityCoarse: CGFloat = 0.02
  internal static let magnificationZoomSensitivity: CGFloat = 0.2

  var onEscapeRequested: (() -> Void)?
  var onZoomStepRequested: ((CGFloat) -> Void)?

  private weak var pinState: QuickAccessPinWindowState?
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?

  // Manual window dragging (macOS 27+). The system no longer initiates
  // background window drags for SwiftUI hosting views, so pinned windows
  // cannot be repositioned via isMovableByWindowBackground alone. Verified
  // with an interactive repro on macOS 27.0 (build 26A428): plain NSView
  // content still drags fine, NSHostingView content does not.
  private var manualDragOffset: NSPoint?
  private var manualDragStartScreenPoint: NSPoint?
  private var manualDragHasMoved = false

  private static let manualWindowDragEnabled: Bool =
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
  private static let manualWindowDragThreshold: CGFloat = 4

  init(contentRect: NSRect, state: QuickAccessPinWindowState) {
    pinState = state
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configure()
    installMouseMonitors()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    if handleEscapeIfNeeded(event) {
      return
    }

    super.keyDown(with: event)
  }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .scrollWheel where handleScrollZoomIfNeeded(event):
      return
    case .leftMouseDown:
      beginManualWindowDragIfNeeded(with: event)
      super.sendEvent(event)
    case .leftMouseDragged where continueManualWindowDrag():
      return
    case .leftMouseUp:
      endManualWindowDrag()
      super.sendEvent(event)
    default:
      super.sendEvent(event)
    }
  }

  private var isMouseMonitorsSuspended = false

  override func close() {
    if !isMouseMonitorsSuspended {
      removeMouseMonitorsOnly()
    }
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
    isMouseMonitorsSuspended = false
    super.close()
  }

  func updateMousePassthrough() {
    guard let pinState else {
      ignoresMouseEvents = false
      return
    }

    let mouseLocation = NSEvent.mouseLocation
    let isInside = frame.contains(mouseLocation)
    pinState.isMouseInside = isInside

    guard pinState.isLocked else {
      ignoresMouseEvents = false
      if isInside {
        if !isKeyWindow {
          makeKey()
        }
      } else {
        if isKeyWindow {
          if let otherWindow = NSApp.windows.first(where: { $0 != self && $0.canBecomeKey && $0.isVisible }) {
            otherWindow.makeKey()
          }
        }
      }
      return
    }

    ignoresMouseEvents = isInside && !lockButtonScreenRect.contains(mouseLocation)
  }

  private func configure() {
    isFloatingPanel = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
    applyCornerRadius()
    level = Self.pinnedWindowLevel
    becomesKeyOnlyIfNeeded = false
  }

  private var lockButtonScreenRect: NSRect {
    NSRect(x: frame.maxX - 48, y: frame.maxY - 48, width: 48, height: 48)
  }

  private func installMouseMonitors() {
    let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    if localMouseMonitor == nil {
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
        MainActor.assumeIsolated {
          self?.updateMousePassthrough()
        }
        return event
      }
    }

    if globalMouseMonitor == nil {
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
        Task { @MainActor in
          self?.updateMousePassthrough()
        }
      }
    }

    if localKeyMonitor == nil {
      localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        let didHandle = MainActor.assumeIsolated {
          self?.handleEscapeIfNeeded(event) ?? false
        }
        return didHandle ? nil : event
      }
    }

    if globalKeyMonitor == nil {
      globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        Task { @MainActor in
          _ = self?.handleEscapeIfNeeded(event)
        }
      }
    }
  }

  private func removeEventMonitors() {
    removeMouseMonitorsOnly()
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
  }

  private func removeMouseMonitorsOnly() {
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
  }

  func suspendMouseMonitors() {
    guard !isMouseMonitorsSuspended else { return }
    isMouseMonitorsSuspended = true
    removeMouseMonitorsOnly()
  }

  func resumeMouseMonitors() {
    guard isMouseMonitorsSuspended else { return }
    isMouseMonitorsSuspended = false
    installMouseMonitors()
  }

  // MARK: - Manual Window Drag

  private func beginManualWindowDragIfNeeded(with event: NSEvent) {
    guard Self.manualWindowDragEnabled, manualDragOffset == nil else { return }
    guard let pinState, !pinState.isLocked else { return }
    // The bottom drag handle owns its own file-drag session; leave it alone.
    guard !isOverFileDragHandle(event) else { return }

    manualDragOffset = event.locationInWindow
    manualDragStartScreenPoint = NSEvent.mouseLocation
    manualDragHasMoved = false
  }

  private func continueManualWindowDrag() -> Bool {
    guard let offset = manualDragOffset, let startScreenPoint = manualDragStartScreenPoint else {
      return false
    }

    let screenPoint = NSEvent.mouseLocation
    if !manualDragHasMoved {
      let dx = screenPoint.x - startScreenPoint.x
      let dy = screenPoint.y - startScreenPoint.y
      guard sqrt(dx * dx + dy * dy) >= Self.manualWindowDragThreshold else {
        return true
      }
      manualDragHasMoved = true
    }

    setFrameOrigin(NSPoint(x: screenPoint.x - offset.x, y: screenPoint.y - offset.y))
    return true
  }

  private func endManualWindowDrag() {
    manualDragOffset = nil
    manualDragStartScreenPoint = nil
    manualDragHasMoved = false
  }

  private func isOverFileDragHandle(_ event: NSEvent) -> Bool {
    guard let hitView = contentView?.hitTest(event.locationInWindow) else { return false }
    var view: NSView? = hitView
    while let current = view {
      if current is QuickAccessPinDragHandleNSView {
        return true
      }
      view = current.superview
    }
    return false
  }

  private func handleEscapeIfNeeded(_ event: NSEvent) -> Bool {
    guard event.keyCode == 53 else { return false }
    guard let pinState, !pinState.isLocked else { return false }
    guard isKeyWindow || frame.contains(NSEvent.mouseLocation) else { return false }

    onEscapeRequested?()
    return true
  }

  private func handleScrollZoomIfNeeded(_ event: NSEvent) -> Bool {
    guard let step = Self.scrollZoomStep(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
      isLocked: pinState?.isLocked == true
    ), let onZoomStepRequested else { return false }

    onZoomStepRequested(step)
    return true
  }


  @discardableResult
  func requestMagnifyZoom(magnification: CGFloat) -> Bool {
    guard let step = Self.magnifyZoomStep(
      magnification: magnification,
      isLocked: pinState?.isLocked == true
    ), let onZoomStepRequested else { return false }

    onZoomStepRequested(step)
    return true
  }

  static func scrollZoomStep(
    scrollingDeltaX deltaX: CGFloat = 0,
    scrollingDeltaY deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool,
    isLocked: Bool
  ) -> CGFloat? {
    guard !isLocked else { return nil }

    let magnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
    guard magnitude.isFinite, magnitude != 0 else { return nil }

    let sign: CGFloat
    if deltaY != 0 {
      sign = deltaY > 0 ? 1.0 : -1.0
    } else {
      sign = deltaX > 0 ? 1.0 : -1.0
    }

    let combinedDelta = magnitude * sign
    let sensitivity = hasPreciseScrollingDeltas ? scrollZoomSensitivityPrecise : scrollZoomSensitivityCoarse
    return combinedDelta * sensitivity
  }

  static func magnifyZoomStep(magnification: CGFloat, isLocked: Bool) -> CGFloat? {
    guard !isLocked,
          magnification.isFinite,
          magnification != 0 else { return nil }
    return magnification * magnificationZoomSensitivity
  }
}
