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
/// past a small movement threshold does the decider step in. It first asks
/// the window server to run the drag (`performDrag(with:)`), which keeps
/// cross-display moves, Spaces and menu-bar constraints native. If the frame
/// still stays put, the manual path takes ownership for the rest of the
/// gesture. If the system moves the frame before the manual path owns it,
/// the gesture is ceded back so exactly one mode owns it.
struct PinWindowDragDecider: Equatable {
  enum Mode: Equatable {
    case idle
    case tracking(startScreenPoint: NSPoint, grabOffset: NSPoint, initialFrameOrigin: NSPoint)
    case systemDragRequested(requestTimestamp: TimeInterval, grabOffset: NSPoint, frameOrigin: NSPoint)
    case manual(grabOffset: NSPoint)
    case native
  }

  enum Action: Equatable {
    /// Let AppKit handle the event untouched.
    case forward
    /// Hand the gesture to the window server via `performDrag(with:)`.
    case beginSystemDrag
    /// Move the window to this screen origin and consume the event.
    case move(to: NSPoint)
  }

  static let movementThreshold: CGFloat = 4

  /// How long the frame may stay put after the system-drag request before
  /// the manual path takes over. Dragged events are coalesced, so distance
  /// alone would fall back before the window server reports the first move
  /// of a drag it accepted, and the two would fight over the frame.
  static let systemDragFallbackDelay: TimeInterval = 0.1

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

  /// Whether this window moves the frame itself (or may start to), so its
  /// event handling must stay attached to the gesture. A drag the window
  /// server owns follows the cursor on its own and may never send a mouse-up.
  var isWindowDriven: Bool {
    switch mode {
    case .tracking, .manual:
      return true
    case .idle, .systemDragRequested, .native:
      return false
    }
  }

  /// Whether the decider took the gesture away from the click path, so the
  /// trailing mouse-up must not reach the content underneath.
  var ownsGesture: Bool {
    switch mode {
    case .systemDragRequested, .manual:
      return true
    case .idle, .tracking, .native:
      return false
    }
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

  /// Evaluates a drag update and returns what the window should do with it.
  /// `timestamp` is the event's system-uptime timestamp.
  mutating func dragged(
    screenPoint: NSPoint,
    currentFrameOrigin: NSPoint,
    timestamp: TimeInterval
  ) -> Action {
    switch mode {
    case .idle, .native:
      return .forward
    case let .tracking(start, offset, initialOrigin):
      // The system moved the frame: native background dragging owns this
      // gesture.
      guard !frameMoved(currentFrameOrigin, from: initialOrigin) else {
        mode = .native
        return .forward
      }
      guard distance(from: start, to: screenPoint) >= Self.movementThreshold else {
        return .forward
      }
      mode = .systemDragRequested(
        requestTimestamp: timestamp,
        grabOffset: offset,
        frameOrigin: currentFrameOrigin
      )
      return .beginSystemDrag
    case let .systemDragRequested(requestTimestamp, offset, origin):
      // The frame moved: the window server accepted the drag.
      guard !frameMoved(currentFrameOrigin, from: origin) else {
        mode = .native
        return .forward
      }
      guard timestamp - requestTimestamp >= Self.systemDragFallbackDelay else {
        return .forward
      }
      return applyingManualMove(screenPoint: screenPoint, grabOffset: offset)
    case let .manual(offset):
      // Once manual, keep ownership until mouse-up. Native dragging already
      // had its chance while tracking; a frame the system adjusted mid-drag
      // (crossing displays, backing-scale changes) must not strand the
      // gesture with nobody moving the window.
      return applyingManualMove(screenPoint: screenPoint, grabOffset: offset)
    }
  }

  /// Ends the gesture: mouse-up, cancellation, or the left button found
  /// released mid-gesture.
  mutating func end() {
    mode = .idle
  }

  private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
    hypot(end.x - start.x, end.y - start.y)
  }

  private func frameMoved(_ origin: NSPoint, from reference: NSPoint) -> Bool {
    abs(origin.x - reference.x) > Self.systemMoveTolerance
      || abs(origin.y - reference.y) > Self.systemMoveTolerance
  }

  private mutating func applyingManualMove(screenPoint: NSPoint, grabOffset: NSPoint) -> Action {
    mode = .manual(grabOffset: grabOffset)
    return .move(to: NSPoint(x: screenPoint.x - grabOffset.x, y: screenPoint.y - grabOffset.y))
  }
}

@MainActor
final class QuickAccessPinWindow: NSPanel {
  private static let pinnedWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)

  var onEscapeRequested: (() -> Void)?

  private weak var pinState: QuickAccessPinWindowState?
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?

  // Native-first background drag ownership: the manual path in
  // `PinWindowDragDecider` only takes over when the native path does not
  // move the frame.
  private var backgroundDrag = PinWindowDragDecider()
  // `performDrag(with:)` expects the gesture's original mouse-down.
  private var backgroundDragMouseDown: NSEvent?

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
    case .magnify:
      if !routeMagnifyToImageScrollView(event) {
        super.sendEvent(event)
      }
    case .scrollWheel:
      super.sendEvent(event)
    case .leftMouseDown:
      beginBackgroundDragIfEligible(with: event)
      super.sendEvent(event)
    case .leftMouseDragged where continueBackgroundDrag(with: event):
      return
    case .leftMouseUp:
      // The decider consumed the gesture: swallow the mouse-up so the click
      // underneath does not fire (same behavior as a native window drag).
      let ownedGesture = backgroundDrag.ownsGesture
      backgroundDrag.end()
      backgroundDragMouseDown = nil
      if ownedGesture {
        return
      }
      super.sendEvent(event)
    default:
      super.sendEvent(event)
    }
  }

  override func resignKey() {
    // Key status can move mid-gesture (the hover path keying another window,
    // or the system reassigning displays). Keep a live drag alive; the
    // pressed-button check in `continueBackgroundDrag` ends it once released.
    if !isBackgroundDragInProgress {
      backgroundDrag.end()
    }
    super.resignKey()
  }

  @discardableResult
  private func routeMagnifyToImageScrollView(_ event: NSEvent) -> Bool {
    guard let contentView, let pinState, !pinState.isLocked else { return false }
    let hitView = contentView.hitTest(event.locationInWindow)
    var responder: NSResponder? = hitView
    while let current = responder {
      if let scrollView = current as? QuickAccessPinImageScrollView {
        scrollView.magnify(with: event)
        return true
      }
      responder = current.nextResponder
    }
    return false
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
    updateMousePassthrough(at: NSEvent.mouseLocation)
  }

  func updateMousePassthrough(at mouseLocation: NSPoint) {
    guard let pinState else {
      ignoresMouseEvents = false
      return
    }

    let isInside = frame.contains(mouseLocation)
    pinState.isMouseInside = isInside

    guard pinState.isLocked else {
      ignoresMouseEvents = false
      // The local monitor runs before the window moves for this event, so the
      // cursor can briefly sit outside the frame. Handing key status away then
      // would interrupt the drag.
      guard !isBackgroundDragInProgress else { return }
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
    // AppKit may key the panel from a hit-tested view only when that view opts
    // in. The existing pointer-hover path can also key this nonactivating pin
    // directly, without activating the Snapzy application.
    becomesKeyOnlyIfNeeded = true
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
    backgroundDragMouseDown = nil
    guard let pinState, !pinState.isLocked else { return }
    guard !isOverInteractiveControl(event) else { return }

    backgroundDragMouseDown = event
    backgroundDrag.begin(
      startScreenPoint: NSEvent.mouseLocation,
      grabOffset: event.locationInWindow,
      initialFrameOrigin: frame.origin
    )
  }

  private var isBackgroundDragInProgress: Bool {
    backgroundDrag.isWindowDriven && NSEvent.pressedMouseButtons & 0x1 != 0
  }

  private func continueBackgroundDrag(with event: NSEvent) -> Bool {
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
    let action = backgroundDrag.dragged(
      screenPoint: NSEvent.mouseLocation,
      currentFrameOrigin: frame.origin,
      timestamp: event.timestamp
    )
    logDragTransition("dragged", from: modeBefore, to: backgroundDrag.mode, context: [
      "frame": "\(frameBefore)",
      "action": "\(action)",
    ])

    switch action {
    case .forward:
      // While tracking we deliberately forward events untouched so AppKit
      // keeps its chance to own the gesture.
      return false
    case .beginSystemDrag:
      // Returns right away; the window server drives the drag if it accepts.
      performDrag(with: backgroundDragMouseDown ?? event)
      return true
    case let .move(target):
      setFrameOrigin(target)
      return true
    }
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

}
