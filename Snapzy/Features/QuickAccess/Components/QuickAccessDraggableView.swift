//
//  QuickAccessDraggableView.swift
//  Snapzy
//
//  AppKit bridge for Quick Access card swipe and drag-to-app behavior.
//

import AppKit
import SwiftUI

enum QuickAccessCardDragIntent: Equatable {
  case undetermined
  case swipeToDismiss
  case dragToApp
}

struct QuickAccessCardDragPolicy {
  static let directionThreshold: CGFloat = 30
  static let dismissDistanceThreshold: CGFloat = 80
  static let dismissVelocityThreshold: CGFloat = 300

  let leftSwipeBehavior: QuickAccessSwipeBehavior
  let rightSwipeBehavior: QuickAccessSwipeBehavior

  private func behavior(for translation: CGFloat) -> QuickAccessSwipeBehavior {
    translation > 0 ? rightSwipeBehavior : leftSwipeBehavior
  }

  func intent(forHorizontalTranslation translation: CGFloat) -> QuickAccessCardDragIntent {
    guard abs(translation) > Self.directionThreshold else {
      return .undetermined
    }

    switch behavior(for: translation) {
    case .dismiss:
      return .swipeToDismiss
    case .dragToApp:
      return .dragToApp
    case .none:
      return .undetermined
    }
  }

  func shouldDismiss(
    horizontalTranslation translation: CGFloat,
    horizontalVelocity velocity: CGFloat
  ) -> Bool {
    guard behavior(for: translation) == .dismiss else { return false }

    return abs(translation) > Self.dismissDistanceThreshold || abs(velocity) > Self.dismissVelocityThreshold
  }
}

struct QuickAccessTrackpadSwipePolicy {
  static let minimumHorizontalDelta: CGFloat = 0.5
  static let horizontalDominanceRatio: CGFloat = 1.35

  let leftSwipeBehavior: QuickAccessSwipeBehavior
  let rightSwipeBehavior: QuickAccessSwipeBehavior
  let sensitivityMultiplier: CGFloat

  init(
    leftSwipeBehavior: QuickAccessSwipeBehavior,
    rightSwipeBehavior: QuickAccessSwipeBehavior,
    sensitivityMultiplier: CGFloat = 1.0
  ) {
    self.leftSwipeBehavior = leftSwipeBehavior
    self.rightSwipeBehavior = rightSwipeBehavior
    self.sensitivityMultiplier = sensitivityMultiplier
  }

  func horizontalDelta(
    scrollingDeltaX deltaX: CGFloat,
    scrollingDeltaY deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool,
    isDirectionInverted: Bool = false
  ) -> CGFloat? {
    guard hasPreciseScrollingDeltas,
          deltaX.isFinite,
          deltaY.isFinite else {
      return nil
    }

    // Natural scrolling inverts scrollingDeltaX sign, so normalize it
    // so positive always means swipe right regardless of preference.
    let normalizedDeltaX = isDirectionInverted ? -deltaX : deltaX

    let horizontalMagnitude = abs(normalizedDeltaX)
    let verticalMagnitude = abs(deltaY)
    guard horizontalMagnitude >= Self.minimumHorizontalDelta,
          horizontalMagnitude > verticalMagnitude * Self.horizontalDominanceRatio else {
      return nil
    }

    return normalizedDeltaX * sensitivityMultiplier
  }

  func behavior(for deltaX: CGFloat) -> QuickAccessSwipeBehavior {
    deltaX > 0 ? rightSwipeBehavior : leftSwipeBehavior
  }

  func dismissTranslation(accumulatedHorizontalDelta deltaX: CGFloat) -> CGFloat? {
    guard deltaX.isFinite,
          behavior(for: deltaX) == .dismiss else {
      return nil
    }

    return deltaX
  }
}

/// Transparent monitor view that lets SwiftUI keep normal hit testing while
/// AppKit owns the native drag session.
struct QuickAccessDraggableView: NSViewRepresentable {
  let fileURL: URL
  let thumbnail: NSImage
  let dismissDirection: CGFloat
  let dragDropEnabled: Bool
  let twoFingerSwipeToDismissEnabled: Bool
  let leftSwipeBehavior: QuickAccessSwipeBehavior
  let rightSwipeBehavior: QuickAccessSwipeBehavior
  let onDragStarted: () -> Void
  let onDragEnded: (Bool) -> Void
  let onSwipeChanged: (CGFloat) -> Void
  let onSwipeEnded: (CGFloat, CGFloat) -> Void
  let swipeSensitivity: CGFloat

  func makeNSView(context: Context) -> QuickAccessDragMonitorView {
    QuickAccessDragMonitorView(
      fileURL: fileURL,
      thumbnail: thumbnail,
      dismissDirection: dismissDirection,
      dragDropEnabled: dragDropEnabled,
      twoFingerSwipeToDismissEnabled: twoFingerSwipeToDismissEnabled,
      leftSwipeBehavior: leftSwipeBehavior,
      rightSwipeBehavior: rightSwipeBehavior,
      swipeSensitivity: swipeSensitivity,
      onDragStarted: onDragStarted,
      onDragEnded: onDragEnded,
      onSwipeChanged: onSwipeChanged,
      onSwipeEnded: onSwipeEnded
    )
  }

  func updateNSView(_ nsView: QuickAccessDragMonitorView, context: Context) {
    nsView.fileURL = fileURL
    nsView.thumbnail = thumbnail
    nsView.dismissDirection = dismissDirection
    nsView.dragDropEnabled = dragDropEnabled
    nsView.twoFingerSwipeToDismissEnabled = twoFingerSwipeToDismissEnabled
    nsView.leftSwipeBehavior = leftSwipeBehavior
    nsView.rightSwipeBehavior = rightSwipeBehavior
    nsView.swipeSensitivity = swipeSensitivity
    nsView.onDragStarted = onDragStarted
    nsView.onDragEnded = onDragEnded
    nsView.onSwipeChanged = onSwipeChanged
    nsView.onSwipeEnded = onSwipeEnded
  }
}

final class QuickAccessDragMonitorView: NSView, NSDraggingSource {
  var fileURL: URL
  var thumbnail: NSImage
  var dismissDirection: CGFloat
  var dragDropEnabled: Bool
  var twoFingerSwipeToDismissEnabled: Bool
  var leftSwipeBehavior: QuickAccessSwipeBehavior
  var rightSwipeBehavior: QuickAccessSwipeBehavior
  var swipeSensitivity: CGFloat
  var onDragStarted: () -> Void
  var onDragEnded: (Bool) -> Void
  var onSwipeChanged: (CGFloat) -> Void
  var onSwipeEnded: (CGFloat, CGFloat) -> Void

  private var isDragging = false
  private var eventMonitor: Any?
  private var mouseDownLocation: NSPoint?
  private var gestureIntent: QuickAccessCardDragIntent = .undetermined
  private var lastDragSample: (timestamp: TimeInterval, translation: CGFloat)?
  private var latestVelocity: CGFloat = 0
  private var isTrackpadSwipeTracking = false
  private var accumulatedTrackpadSwipeX: CGFloat = 0
  private var lastTrackpadSwipeSample: (timestamp: TimeInterval, translation: CGFloat)?
  private var latestTrackpadSwipeVelocity: CGFloat = 0
  private var sourceAccess: SandboxFileAccessManager.ScopedAccess?

  init(
    fileURL: URL,
    thumbnail: NSImage,
    dismissDirection: CGFloat,
    dragDropEnabled: Bool,
    twoFingerSwipeToDismissEnabled: Bool,
    leftSwipeBehavior: QuickAccessSwipeBehavior,
    rightSwipeBehavior: QuickAccessSwipeBehavior,
    swipeSensitivity: CGFloat,
    onDragStarted: @escaping () -> Void,
    onDragEnded: @escaping (Bool) -> Void,
    onSwipeChanged: @escaping (CGFloat) -> Void,
    onSwipeEnded: @escaping (CGFloat, CGFloat) -> Void
  ) {
    self.fileURL = fileURL
    self.thumbnail = thumbnail
    self.dismissDirection = dismissDirection
    self.dragDropEnabled = dragDropEnabled
    self.twoFingerSwipeToDismissEnabled = twoFingerSwipeToDismissEnabled
    self.leftSwipeBehavior = leftSwipeBehavior
    self.rightSwipeBehavior = rightSwipeBehavior
    self.swipeSensitivity = swipeSensitivity
    self.onDragStarted = onDragStarted
    self.onDragEnded = onDragEnded
    self.onSwipeChanged = onSwipeChanged
    self.onSwipeEnded = onSwipeEnded

    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateEventMonitor()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  deinit {
    removeEventMonitor()
    sourceAccess?.stop()
  }

  // MARK: - Event Monitoring

  private func updateEventMonitor() {
    removeEventMonitor()
    guard window != nil else { return }

    eventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
    ) { [weak self] event in
      self?.handle(event) ?? event
    }
  }

  private func removeEventMonitor() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
  }

  private func handle(_ event: NSEvent) -> NSEvent {
    guard event.window === window else { return event }

    switch event.type {
    case .leftMouseDown:
      beginTrackingIfNeeded(event)
    case .leftMouseDragged:
      continueTracking(event)
    case .leftMouseUp:
      endTracking(event)
    case .scrollWheel:
      handleScrollWheel(event)
    default:
      break
    }

    return event
  }

  private func beginTrackingIfNeeded(_ event: NSEvent) {
    guard !event.modifierFlags.contains(.control) else {
      resetTracking()
      return
    }

    let location = convert(event.locationInWindow, from: nil)
    guard bounds.contains(location) else { return }

    mouseDownLocation = location
    gestureIntent = .undetermined
    latestVelocity = 0
    lastDragSample = (event.timestamp, 0)
  }

  private func continueTracking(_ event: NSEvent) {
    guard let mouseDownLocation, !isDragging else { return }

    let location = convert(event.locationInWindow, from: nil)
    let translation = location.x - mouseDownLocation.x
    updateVelocity(translation: translation, timestamp: event.timestamp)

    let policy = QuickAccessCardDragPolicy(
      leftSwipeBehavior: leftSwipeBehavior,
      rightSwipeBehavior: rightSwipeBehavior
    )
    if gestureIntent == .undetermined {
      gestureIntent = policy.intent(forHorizontalTranslation: translation)

      if gestureIntent == .dragToApp {
        guard dragDropEnabled else { return }
        beginFileDrag(with: event)
        return
      }
    }

    if gestureIntent == .swipeToDismiss {
      onSwipeChanged(translation)
    }
  }

  private func endTracking(_ event: NSEvent) {
    guard let mouseDownLocation else {
      resetTracking()
      return
    }

    if gestureIntent == .swipeToDismiss {
      let location = convert(event.locationInWindow, from: nil)
      let translation = location.x - mouseDownLocation.x
      onSwipeEnded(translation, latestVelocity)
    }

    resetTracking()
  }

  private func resetTracking() {
    mouseDownLocation = nil
    gestureIntent = .undetermined
    lastDragSample = nil
    latestVelocity = 0
  }

  private func handleScrollWheel(_ event: NSEvent) {
    guard containsEventLocation(event) else {
      finishTrackpadSwipe(cancelled: true)
      return
    }

    guard twoFingerSwipeToDismissEnabled,
          !isDragging else {
      finishTrackpadSwipe(cancelled: true)
      return
    }

    guard event.momentumPhase.isEmpty else {
      finishTrackpadSwipe(cancelled: false)
      return
    }

    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
      finishTrackpadSwipe(cancelled: true)
      return
    }

    if event.phase.contains(.began) {
      resetTrackpadSwipe()
    }

    let policy = QuickAccessTrackpadSwipePolicy(
      leftSwipeBehavior: leftSwipeBehavior,
      rightSwipeBehavior: rightSwipeBehavior,
      sensitivityMultiplier: swipeSensitivity
    )
    guard let deltaX = policy.horizontalDelta(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
      isDirectionInverted: event.isDirectionInvertedFromDevice
    ) else {
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
        finishTrackpadSwipe(cancelled: event.phase.contains(.cancelled))
      }
      return
    }

    if !isTrackpadSwipeTracking {
      isTrackpadSwipeTracking = true
      accumulatedTrackpadSwipeX = 0
      latestTrackpadSwipeVelocity = 0
      lastTrackpadSwipeSample = (event.timestamp, 0)
    }

    accumulatedTrackpadSwipeX += deltaX
    updateTrackpadSwipeVelocity(
      translation: accumulatedTrackpadSwipeX,
      timestamp: event.timestamp
    )

    // Report the live translation so the card follows the user's finger
    // direction regardless of whether the swipe is toward the dismiss edge.
    onSwipeChanged(accumulatedTrackpadSwipeX)

    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      finishTrackpadSwipe(cancelled: event.phase.contains(.cancelled))
    }
  }

  func containsEventLocation(_ event: NSEvent) -> Bool {
    let location = convert(event.locationInWindow, from: nil)
    return bounds.contains(location)
  }

  private func finishTrackpadSwipe(cancelled: Bool) {
    defer { resetTrackpadSwipe() }
    guard isTrackpadSwipeTracking else { return }

    let policy = QuickAccessTrackpadSwipePolicy(
      leftSwipeBehavior: leftSwipeBehavior,
      rightSwipeBehavior: rightSwipeBehavior,
      sensitivityMultiplier: swipeSensitivity
    )
    guard !cancelled,
          let translation = policy.dismissTranslation(
            accumulatedHorizontalDelta: accumulatedTrackpadSwipeX
          ) else {
      onSwipeEnded(0, 0)
      return
    }

    onSwipeEnded(translation, latestTrackpadSwipeVelocity)
  }

  private func resetTrackpadSwipe() {
    isTrackpadSwipeTracking = false
    accumulatedTrackpadSwipeX = 0
    lastTrackpadSwipeSample = nil
    latestTrackpadSwipeVelocity = 0
  }

  private func updateVelocity(translation: CGFloat, timestamp: TimeInterval) {
    defer {
      lastDragSample = (timestamp, translation)
    }

    guard let lastDragSample else { return }
    let elapsed = timestamp - lastDragSample.timestamp
    guard elapsed > 0 else { return }

    latestVelocity = (translation - lastDragSample.translation) / CGFloat(elapsed)
  }

  private func updateTrackpadSwipeVelocity(translation: CGFloat, timestamp: TimeInterval) {
    defer {
      lastTrackpadSwipeSample = (timestamp, translation)
    }

    guard let lastTrackpadSwipeSample else { return }
    let elapsed = timestamp - lastTrackpadSwipeSample.timestamp
    guard elapsed > 0 else { return }

    latestTrackpadSwipeVelocity = (translation - lastTrackpadSwipeSample.translation) / CGFloat(elapsed)
  }

  // MARK: - Drag Initiation

  private func beginFileDrag(with event: NSEvent) {
    guard !isDragging else { return }

    isDragging = true
    sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(fileURL)
    onDragStarted()

    let dragItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
    let imageSize = NSSize(width: 120, height: 75)
    let dragImage = NSImage(size: imageSize)
    dragImage.lockFocus()
    thumbnail.draw(
      in: NSRect(origin: .zero, size: imageSize),
      from: .zero,
      operation: .sourceOver,
      fraction: 0.8
    )
    dragImage.unlockFocus()

    let mouseLocation = convert(event.locationInWindow, from: nil)
    dragItem.setDraggingFrame(
      NSRect(
        x: mouseLocation.x - imageSize.width / 2,
        y: mouseLocation.y - imageSize.height / 2,
        width: imageSize.width,
        height: imageSize.height
      ),
      contents: dragImage
    )

    let session = beginDraggingSession(with: [dragItem], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access drag started",
      context: ["fileName": fileURL.lastPathComponent]
    )
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    isDragging = false
    let success = operation != []
    sourceAccess?.stop()
    sourceAccess = nil
    resetTracking()
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access drag ended",
      context: [
        "operation": "\(operation.rawValue)",
        "success": success ? "true" : "false",
      ]
    )
    onDragEnded(success)
  }
}
