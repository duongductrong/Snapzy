//
//  QuickAccessDraggableView.swift
//  Snapzy
//
//  Shared AppKit bridge for Quick Access gestures and History drag-to-app behavior.
//

import AppKit
import SwiftUI

enum QuickAccessCardDragIntent: Equatable {
  case undetermined
  case swipeToDismiss
  case dragToApp
  case reservedForScroll
}

enum QuickAccessDragScrollAxis: Equatable {
  case horizontal
  case vertical
}

struct QuickAccessCardDragPolicy {
  static let directionThreshold: CGFloat = 30
  static let directDragDistanceThreshold: CGFloat = 6
  static let scrollAxisDominanceRatio: CGFloat = 1.35
  static let dismissDistanceThreshold: CGFloat = 80
  static let dismissVelocityThreshold: CGFloat = 300

  static func shouldBeginDirectDrag(
    horizontalTranslation: CGFloat,
    verticalTranslation: CGFloat,
    reservedScrollAxis: QuickAccessDragScrollAxis? = nil
  ) -> Bool {
    guard horizontalTranslation.isFinite, verticalTranslation.isFinite else {
      return false
    }

    let distanceSquared =
      horizontalTranslation * horizontalTranslation + verticalTranslation * verticalTranslation
    guard distanceSquared >= directDragDistanceThreshold * directDragDistanceThreshold else {
      return false
    }

    return !isPrimaryScrollGesture(
      horizontalTranslation: horizontalTranslation,
      verticalTranslation: verticalTranslation,
      reservedScrollAxis: reservedScrollAxis
    )
  }

  static func isPrimaryScrollGesture(
    horizontalTranslation: CGFloat,
    verticalTranslation: CGFloat,
    reservedScrollAxis: QuickAccessDragScrollAxis?
  ) -> Bool {
    guard horizontalTranslation.isFinite,
          verticalTranslation.isFinite,
          let reservedScrollAxis else {
      return false
    }

    let distanceSquared =
      horizontalTranslation * horizontalTranslation + verticalTranslation * verticalTranslation
    guard distanceSquared >= directDragDistanceThreshold * directDragDistanceThreshold else {
      return false
    }

    let scrollTranslation: CGFloat
    let crossAxisTranslation: CGFloat
    switch reservedScrollAxis {
    case .horizontal:
      scrollTranslation = abs(horizontalTranslation)
      crossAxisTranslation = abs(verticalTranslation)
    case .vertical:
      scrollTranslation = abs(verticalTranslation)
      crossAxisTranslation = abs(horizontalTranslation)
    }

    // Let the containing list keep an unambiguous primary-axis drag. A
    // diagonal or cross-axis movement remains eligible for direct export.
    return scrollTranslation > crossAxisTranslation * Self.scrollAxisDominanceRatio
  }

  let dismissDirection: CGFloat

  func intent(forHorizontalTranslation translation: CGFloat) -> QuickAccessCardDragIntent {
    guard abs(translation) > Self.directionThreshold else {
      return .undetermined
    }

    return translation * dismissDirection > 0 ? .swipeToDismiss : .dragToApp
  }

  func shouldDismiss(
    horizontalTranslation translation: CGFloat,
    horizontalVelocity velocity: CGFloat
  ) -> Bool {
    let hasDismissDirection =
      translation * dismissDirection > 0 || velocity * dismissDirection > 0
    guard hasDismissDirection else { return false }

    return abs(translation) > Self.dismissDistanceThreshold || abs(velocity) > Self.dismissVelocityThreshold
  }
}

nonisolated enum QuickAccessTrackpadSwipeHelpers {
  static let minimumHorizontalDelta: CGFloat = 0.5
  static let horizontalDominanceRatio: CGFloat = 1.35
  static let dismissDistanceThreshold: CGFloat = 80
  static let dismissVelocityThreshold: CGFloat = 300

  static func horizontalDelta(
    scrollingDeltaX deltaX: CGFloat,
    scrollingDeltaY deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool,
    sensitivityMultiplier: CGFloat
  ) -> CGFloat? {
    guard hasPreciseScrollingDeltas,
          deltaX.isFinite,
          deltaY.isFinite else {
      return nil
    }

    let horizontalMagnitude = abs(deltaX)
    let verticalMagnitude = abs(deltaY)
    guard horizontalMagnitude >= Self.minimumHorizontalDelta,
          horizontalMagnitude > verticalMagnitude * Self.horizontalDominanceRatio else {
      return nil
    }

    return deltaX * sensitivityMultiplier
  }

  static func shouldDismiss(
    horizontalTranslation translation: CGFloat,
    horizontalVelocity velocity: CGFloat
  ) -> Bool {
    abs(translation) > Self.dismissDistanceThreshold || abs(velocity) > Self.dismissVelocityThreshold
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
  let swipeMode: QuickAccessTrackpadSwipeMode
  let onDragStarted: () -> Void
  let onDragEnded: (Bool) -> Void
  let onSwipeChanged: (CGFloat) -> Void
  let onSwipeEnded: (CGFloat, CGFloat) -> Void
  let swipeSensitivity: CGFloat
  let dragOnly: Bool
  let reservedScrollAxis: QuickAccessDragScrollAxis?
  /// Two-finger vertical move that starts over the card (#591). Off unless a
  /// handler is given; horizontal swipes are unaffected either way.
  var onVerticalSwipe: ((QuickAccessVerticalSwipeTracker.Update) -> Void)? = nil

  func makeNSView(context: Context) -> QuickAccessDragMonitorView {
    QuickAccessDragMonitorView(
      fileURL: fileURL,
      thumbnail: thumbnail,
      dismissDirection: dismissDirection,
      dragDropEnabled: dragDropEnabled,
      twoFingerSwipeToDismissEnabled: twoFingerSwipeToDismissEnabled,
      swipeMode: swipeMode,
      swipeSensitivity: swipeSensitivity,
      onDragStarted: onDragStarted,
      onDragEnded: onDragEnded,
      onSwipeChanged: onSwipeChanged,
      onSwipeEnded: onSwipeEnded,
      dragOnly: dragOnly,
      reservedScrollAxis: reservedScrollAxis,
      onVerticalSwipe: onVerticalSwipe
    )
  }

  func updateNSView(_ nsView: QuickAccessDragMonitorView, context: Context) {
    nsView.fileURL = fileURL
    nsView.thumbnail = thumbnail
    nsView.dismissDirection = dismissDirection
    nsView.dragDropEnabled = dragDropEnabled
    nsView.dragOnly = dragOnly
    nsView.reservedScrollAxis = reservedScrollAxis
    nsView.twoFingerSwipeToDismissEnabled = twoFingerSwipeToDismissEnabled
    nsView.swipeMode = swipeMode
    nsView.swipeSensitivity = swipeSensitivity
    nsView.onDragStarted = onDragStarted
    nsView.onDragEnded = onDragEnded
    nsView.onSwipeChanged = onSwipeChanged
    nsView.onSwipeEnded = onSwipeEnded
    nsView.onVerticalSwipe = onVerticalSwipe
  }
}

final class QuickAccessDragMonitorView: NSView, NSDraggingSource {
  var fileURL: URL
  var thumbnail: NSImage
  var dismissDirection: CGFloat
  var dragDropEnabled: Bool
  var dragOnly: Bool
  var reservedScrollAxis: QuickAccessDragScrollAxis?
  var twoFingerSwipeToDismissEnabled: Bool
  var swipeMode: QuickAccessTrackpadSwipeMode
  var swipeSensitivity: CGFloat
  var onDragStarted: () -> Void
  var onDragEnded: (Bool) -> Void
  var onSwipeChanged: (CGFloat) -> Void
  var onSwipeEnded: (CGFloat, CGFloat) -> Void
  var onVerticalSwipe: ((QuickAccessVerticalSwipeTracker.Update) -> Void)? {
    didSet {
      // Handler dropped mid-move (upload started, action disabled): release the card.
      if onVerticalSwipe == nil { cancelVerticalSwipe(notifying: oldValue) }
    }
  }

  private var isDragging = false
  private var verticalSwipe = QuickAccessVerticalSwipeTracker()
  /// A scroll gesture began over this card and may still become a vertical move.
  private var isVerticalSwipeCandidate = false
  private var eventMonitor: Any?
  private var mouseDownLocation: NSPoint?
  private var mouseDownEvent: NSEvent?
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
    swipeMode: QuickAccessTrackpadSwipeMode,
    swipeSensitivity: CGFloat,
    onDragStarted: @escaping () -> Void,
    onDragEnded: @escaping (Bool) -> Void,
    onSwipeChanged: @escaping (CGFloat) -> Void,
    onSwipeEnded: @escaping (CGFloat, CGFloat) -> Void,
    dragOnly: Bool = false,
    reservedScrollAxis: QuickAccessDragScrollAxis? = nil,
    onVerticalSwipe: ((QuickAccessVerticalSwipeTracker.Update) -> Void)? = nil
  ) {
    self.fileURL = fileURL
    self.thumbnail = thumbnail
    self.dismissDirection = dismissDirection
    self.dragDropEnabled = dragDropEnabled
    self.dragOnly = dragOnly
    self.reservedScrollAxis = reservedScrollAxis
    self.twoFingerSwipeToDismissEnabled = twoFingerSwipeToDismissEnabled
    self.swipeMode = swipeMode
    self.swipeSensitivity = swipeSensitivity
    self.onDragStarted = onDragStarted
    self.onDragEnded = onDragEnded
    self.onSwipeChanged = onSwipeChanged
    self.onSwipeEnded = onSwipeEnded
    self.onVerticalSwipe = onVerticalSwipe

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
    mouseDownEvent = event
    gestureIntent = .undetermined
    latestVelocity = 0
    lastDragSample = (event.timestamp, 0)
  }

  private func continueTracking(_ event: NSEvent) {
    guard let mouseDownLocation, !isDragging else { return }

    let location = convert(event.locationInWindow, from: nil)
    let translation = location.x - mouseDownLocation.x
    let verticalTranslation = location.y - mouseDownLocation.y
    updateVelocity(translation: translation, timestamp: event.timestamp)

    let policy = QuickAccessCardDragPolicy(dismissDirection: dismissDirection)
    if gestureIntent == .undetermined {
      if dragOnly {
        guard dragDropEnabled else {
          return
        }

        if QuickAccessCardDragPolicy.isPrimaryScrollGesture(
          horizontalTranslation: translation,
          verticalTranslation: verticalTranslation,
          reservedScrollAxis: reservedScrollAxis
        ) {
          gestureIntent = .reservedForScroll
          return
        }

        guard QuickAccessCardDragPolicy.shouldBeginDirectDrag(
          horizontalTranslation: translation,
          verticalTranslation: verticalTranslation,
          reservedScrollAxis: reservedScrollAxis
        ) else {
          return
        }

        gestureIntent = .dragToApp
        beginFileDrag()
        return
      }

      gestureIntent = policy.intent(forHorizontalTranslation: translation)

      if gestureIntent == .dragToApp {
        guard dragDropEnabled else { return }
        beginFileDrag()
        return
      }
    }

    guard gestureIntent != .reservedForScroll else { return }

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
    mouseDownEvent = nil
    gestureIntent = .undetermined
    lastDragSample = nil
    latestVelocity = 0
  }

  private func handleScrollWheel(_ event: NSEvent) {
    if handleVerticalSwipe(event) {
      return
    }

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

    guard let rawDeltaX = QuickAccessTrackpadSwipeHelpers.horizontalDelta(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
      sensitivityMultiplier: swipeSensitivity
    ) else {
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
        finishTrackpadSwipe(cancelled: event.phase.contains(.cancelled))
      }
      return
    }

    let deltaX = rawDeltaX * swipeMode.translationMultiplier

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

  // MARK: - Vertical move (collapse to edge, #591)

  /// Claims two-finger vertical moves that begin over this card. Returns true
  /// when the event was consumed; anything else (horizontal swipes, scrolls
  /// that began elsewhere, momentum) falls through to the existing handling.
  private func handleVerticalSwipe(_ event: NSEvent) -> Bool {
    guard let onVerticalSwipe else {
      isVerticalSwipeCandidate = false
      return false
    }

    if verticalSwipe.isTracking {
      let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
      if !event.momentumPhase.isEmpty {
        // Fingers lifted into a fling: the release velocity decides.
        finishVerticalSwipe(cancelled: false)
      } else if !event.modifierFlags.intersection(disallowedModifiers).isEmpty {
        finishVerticalSwipe(cancelled: true)
      } else {
        let delta = QuickAccessVerticalSwipeHelpers.fingerDeltaY(
          scrollingDeltaY: event.scrollingDeltaY,
          isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
        )
        if let update = verticalSwipe.add(fingerDelta: delta, timestamp: event.timestamp) {
          onVerticalSwipe(update)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
          finishVerticalSwipe(cancelled: event.phase.contains(.cancelled))
        }
      }
      return true
    }

    if event.phase.contains(.began) {
      isVerticalSwipeCandidate =
        containsEventLocation(event) && event.momentumPhase.isEmpty && !isDragging
          && mouseDownLocation == nil && !isTrackpadSwipeTracking
          && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    guard isVerticalSwipeCandidate, !isTrackpadSwipeTracking, event.momentumPhase.isEmpty else {
      return false
    }
    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      isVerticalSwipeCandidate = false
      return false
    }
    guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return false }

    // The first real movement picks the axis for the whole gesture.
    isVerticalSwipeCandidate = false
    guard QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
    ) else {
      return false
    }

    verticalSwipe.begin(timestamp: event.timestamp)
    let delta = QuickAccessVerticalSwipeHelpers.fingerDeltaY(
      scrollingDeltaY: event.scrollingDeltaY,
      isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
    )
    if let update = verticalSwipe.add(fingerDelta: delta, timestamp: event.timestamp) {
      onVerticalSwipe(update)
    }
    return true
  }

  private func finishVerticalSwipe(cancelled: Bool) {
    if let update = verticalSwipe.finish(cancelled: cancelled) {
      onVerticalSwipe?(update)
    }
  }

  private func cancelVerticalSwipe(notifying handler: ((QuickAccessVerticalSwipeTracker.Update) -> Void)?) {
    isVerticalSwipeCandidate = false
    if verticalSwipe.finish(cancelled: true) != nil {
      handler?(.cancelled)
    }
  }

  func containsEventLocation(_ event: NSEvent) -> Bool {
    let location = convert(event.locationInWindow, from: nil)
    return bounds.contains(location)
  }

  private func finishTrackpadSwipe(cancelled: Bool) {
    defer { resetTrackpadSwipe() }
    guard isTrackpadSwipeTracking else { return }

    guard !cancelled,
          QuickAccessTrackpadSwipeHelpers.shouldDismiss(
            horizontalTranslation: accumulatedTrackpadSwipeX,
            horizontalVelocity: latestTrackpadSwipeVelocity
          ) else {
      onSwipeEnded(0, 0)
      return
    }

    onSwipeEnded(accumulatedTrackpadSwipeX, latestTrackpadSwipeVelocity)
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

  private func beginFileDrag() {
    guard !isDragging, fileURL.isFileURL, let mouseDownEvent, let mouseDownLocation else { return }

    sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(fileURL)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      sourceAccess?.stop()
      sourceAccess = nil
      resetTracking()
      return
    }

    isDragging = true
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

    dragItem.setDraggingFrame(
      NSRect(
        x: mouseDownLocation.x - imageSize.width / 2,
        y: mouseDownLocation.y - imageSize.height / 2,
        width: imageSize.width,
        height: imageSize.height
      ),
      contents: dragImage
    )

    let session = beginDraggingSession(with: [dragItem], event: mouseDownEvent, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Native file drag started",
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
      "Native file drag ended",
      context: [
        "operation": "\(operation.rawValue)",
        "success": success ? "true" : "false",
      ]
    )
    onDragEnded(success)
  }
}
