//
//  QuickAccessPinWindow.swift
//  Snapzy
//
//  Borderless pin window with lock-mode mouse passthrough.
//

import AppKit

/// Per-gesture decision logic for pin-window background dragging.
///
/// The policy is native-first: every eligible drag starts as `.tracking`,
/// events keep flowing to AppKit untouched, and only when the frame stays put
/// past a small movement threshold does the manual path take ownership of the
/// gesture. If the system moves the frame at any point (native dragging is
/// available), the gesture is ceded back so exactly one mode owns it.
struct PinWindowDragDecider: Equatable {
  enum Mode: Equatable {
    case idle
    case tracking(startScreenPoint: NSPoint, grabOffset: NSPoint, initialFrameOrigin: NSPoint)
    case manual(grabOffset: NSPoint, appliedFrameOrigin: NSPoint)
    case native
  }

  static let movementThreshold: CGFloat = 4

  /// How far the frame may deviate from the recorded origin before it counts
  /// as "the system moved the window". Live drags can be subject to
  /// point/pixel snapping, so exact equality would false-trigger the
  /// native-first backoff.
  static let systemMoveTolerance: CGFloat = 2

  private(set) var mode: Mode = .idle

  var isManual: Bool {
    if case .manual = mode { return true }
    return false
  }

  /// Starts tracking a new eligible background drag. Always resets first so
  /// stale state can never leak into the next gesture.
  mutating func begin(startScreenPoint: NSPoint, grabOffset: NSPoint, initialFrameOrigin: NSPoint) {
    mode = .tracking(
      startScreenPoint: startScreenPoint,
      grabOffset: grabOffset,
      initialFrameOrigin: initialFrameOrigin
    )
  }

  /// Evaluates a drag update. Returns the screen origin the window should be
  /// moved to when the manual path owns the gesture, otherwise nil so events
  /// keep flowing to AppKit.
  mutating func dragged(screenPoint: NSPoint, currentFrameOrigin: NSPoint) -> NSPoint? {
    switch mode {
    case .idle, .native:
      return nil
    case let .tracking(start, offset, initialOrigin):
      // The system moved the frame: native background dragging owns this
      // gesture.
      guard !frameMoved(currentFrameOrigin, from: initialOrigin) else {
        mode = .native
        return nil
      }
      let dx = screenPoint.x - start.x
      let dy = screenPoint.y - start.y
      guard dx * dx + dy * dy >= Self.movementThreshold * Self.movementThreshold else {
        return nil
      }
      return applyingManualMove(screenPoint: screenPoint, grabOffset: offset)
    case let .manual(offset, applied):
      // Back off if the frame moved without our involvement.
      guard !frameMoved(currentFrameOrigin, from: applied) else {
        mode = .native
        return nil
      }
      return applyingManualMove(screenPoint: screenPoint, grabOffset: offset)
    }
  }

  /// Ends the gesture: mouse-up, cancellation, or the window losing key
  /// status.
  mutating func end() {
    mode = .idle
  }

  private func frameMoved(_ origin: NSPoint, from reference: NSPoint) -> Bool {
    abs(origin.x - reference.x) > Self.systemMoveTolerance
      || abs(origin.y - reference.y) > Self.systemMoveTolerance
  }

  private mutating func applyingManualMove(screenPoint: NSPoint, grabOffset: NSPoint) -> NSPoint {
    let target = NSPoint(x: screenPoint.x - grabOffset.x, y: screenPoint.y - grabOffset.y)
    mode = .manual(grabOffset: grabOffset, appliedFrameOrigin: target)
    return target
  }
}

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

  // Native-first background drag ownership: the manual path in
  // `PinWindowDragDecider` only takes over when the native path does not
  // move the frame.
  private var backgroundDrag = PinWindowDragDecider()

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
      beginBackgroundDragIfEligible(with: event)
      super.sendEvent(event)
    case .leftMouseDragged where continueBackgroundDrag():
      return
    case .leftMouseUp:
      // A manual drag consumed the gesture: swallow the mouse-up so the click
      // underneath does not fire (same behavior as a native window drag).
      let wasManual = backgroundDrag.isManual
      backgroundDrag.end()
      if wasManual {
        return
      }
      super.sendEvent(event)
    default:
      super.sendEvent(event)
    }
  }

  override func resignKey() {
    backgroundDrag.end()
    super.resignKey()
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

  // MARK: - Background Drag Ownership

  private func beginBackgroundDragIfEligible(with event: NSEvent) {
    // A fresh mouse-down always resets first, so stale state from a missed
    // mouse-up or a cancelled gesture can never leak into this one.
    backgroundDrag.end()
    guard let pinState, !pinState.isLocked else { return }
    guard !isOverInteractiveControl(event) else { return }

    backgroundDrag.begin(
      startScreenPoint: NSEvent.mouseLocation,
      grabOffset: event.locationInWindow,
      initialFrameOrigin: frame.origin
    )
  }

  private func continueBackgroundDrag() -> Bool {
    // Missed mouse-up (the window resigned key or the event was lost
    // mid-gesture): the left button is no longer pressed, so the gesture is
    // over.
    guard NSEvent.pressedMouseButtons & 0x1 != 0 else {
      logDragTransition("missedMouseUp", from: backgroundDrag.mode, to: .idle)
      backgroundDrag.end()
      return false
    }

    let modeBefore = backgroundDrag.mode
    let frameBefore = frame.origin
    guard let target = backgroundDrag.dragged(
      screenPoint: NSEvent.mouseLocation,
      currentFrameOrigin: frame.origin
    ) else {
      logDragTransition("dragged", from: modeBefore, to: backgroundDrag.mode, context: [
        "frame": "\(frameBefore)",
      ])
      // While tracking we deliberately forward events untouched so AppKit
      // keeps its chance to own the gesture; only an active manual drag
      // consumes them.
      return backgroundDrag.isManual
    }
    logDragTransition("dragged", from: modeBefore, to: backgroundDrag.mode, context: [
      "frame": "\(frameBefore)",
      "target": "\(target)",
    ])
    setFrameOrigin(target)
    return true
  }

  private func logDragTransition(
    _ event: String,
    from: PinWindowDragDecider.Mode,
    to: PinWindowDragDecider.Mode,
    context: [String: String] = [:]
  ) {
    guard from != to else { return }
    var context = context
    context["event"] = event
    context["from"] = "\(from)"
    context["to"] = "\(to)"
    DiagnosticLogger.shared.log(
      .info,
      .ui,
      "Pin drag ownership changed",
      context: context
    )
  }

  private func isOverInteractiveControl(_ event: NSEvent) -> Bool {
    guard let contentView else { return false }
    // `locationInWindow` is in the window's base (unflipped) coordinate
    // system; the SwiftUI hosting contentView is flipped, so convert before
    // any geometry math or the y axis comes out upside down.
    let windowPoint = event.locationInWindow
    let point = contentView.convert(windowPoint, from: nil)

    // Marker views are realized behind their controls as sibling subviews
    // (SwiftUI `.background`), so ancestor hit-testing never reaches them —
    // test their bounds directly.
    var stack: [NSView] = [contentView]
    while let view = stack.popLast() {
      if let exclusion = view as? PinWindowDragExclusionView {
        let exclusionRect = exclusion.convert(exclusion.bounds, to: contentView)
        if NSPointInRect(point, exclusionRect) {
          return true
        }
      }
      stack.append(contentsOf: view.subviews)
    }

    // The bottom file-drag handle owns its own NSDraggingSession. hitTest
    // expects the point in the receiver's superview coordinate system.
    let superPoint = contentView.superview?.convert(windowPoint, from: nil) ?? windowPoint
    guard let hitView = contentView.hitTest(superPoint) else { return false }
    var current: NSView? = hitView
    while let view = current {
      if view is QuickAccessPinDragHandleNSView || view is PinWindowDragExclusionView {
        return true
      }
      current = view.superview
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
