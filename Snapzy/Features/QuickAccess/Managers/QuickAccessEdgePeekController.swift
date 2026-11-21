//
//  QuickAccessEdgePeekController.swift
//  Snapzy
//
//  Owns one small window per collapsed Quick Access card (#591). Each window
//  is flush with the screen edge and exactly the size of its visible strip, so
//  it never changes the main panel's geometry or click-through behavior.
//

import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating window hosting one peek strip.
final class QuickAccessEdgePeekWindow: NSPanel {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .floating
    isFloatingPanel = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    // Same capture rules as the Quick Access panel (#628, #660).
    CaptureChromeWindowRegistry.configureAppWindow(self)
  }

  /// Receives two-finger scrolls over the peek (#591).
  var onScrollWheel: ((NSEvent) -> Void)?

  override func sendEvent(_ event: NSEvent) {
    if event.type == .scrollWheel, let onScrollWheel {
      onScrollWheel(event)
      return
    }
    super.sendEvent(event)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickAccessEdgePeekController {
  private struct Entry {
    let window: QuickAccessEdgePeekWindow
    let model: QuickAccessEdgePeekModel
  }

  private static let moveDuration: TimeInterval = 0.22
  /// Long enough for the exit spring to settle before the window closes.
  private static let exitDuration: TimeInterval = 0.4

  /// Called when the user clicks a strip to bring its card back.
  var onRestore: ((UUID) -> Void)?

  private var entries: [UUID: Entry] = [:]
  private var restoreSwipes: [UUID: RestoreSwipe] = [:]

  /// One two-finger move over a peek; the first real movement picks the axis.
  private struct RestoreSwipe {
    enum Axis {
      /// Fingers up restores.
      case vertical
      /// Fingers sideways, back out of the edge, restores.
      case horizontal
    }

    var tracker = QuickAccessVerticalSwipeTracker()
    var axis: Axis = .vertical
    var isCandidate = false
  }
  private var order: [UUID] = []
  private var position: QuickAccessPosition = .bottomRight
  private var scale: CGFloat = 1
  private var visibleFrame: CGRect = .zero

  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  // Explicit and nonisolated: see #668.
  nonisolated deinit {}

  /// IDs of the strips on screen, in stack order.
  var collapsedIDs: [UUID] { order }

  func window(for id: UUID) -> NSWindow? { entries[id]?.window }

  /// Brings the strips in line with the current items. Idempotent: call it on
  /// every item, position, scale or display change.
  func sync(
    items: [QuickAccessItem],
    position: QuickAccessPosition,
    scale: CGFloat,
    screen: NSScreen
  ) {
    let collapsed = items.filter(\.isCollapsed)
    let collapsedIDs = Set(collapsed.map(\.id))
    let sideChanged = position.isLeftSide != self.position.isLeftSide

    self.position = position
    self.scale = scale
    visibleFrame = screen.visibleFrame

    for id in Array(entries.keys) where !collapsedIDs.contains(id) {
      remove(id)
    }
    order = collapsed.map(\.id)

    let frames = currentFrames()
    for (index, item) in collapsed.enumerated() {
      let frame = frames[index]
      if let entry = entries[item.id] {
        update(entry.model, with: item)
        place(entry.window, at: frame, animated: !sideChanged)
      } else {
        insert(item, at: frame)
      }
    }
  }

  func closeAll() {
    for id in Array(entries.keys) {
      entries[id]?.window.close()
    }
    entries.removeAll()
    restoreSwipes.removeAll()
    order.removeAll()
  }

  // MARK: - Private

  private func currentFrames() -> [CGRect] {
    QuickAccessEdgePeekLayout.stripFrames(
      count: order.count,
      position: position,
      visibleFrame: visibleFrame,
      scale: scale
    ).map { QuickAccessEdgePeekLayout.windowFrame(forStrip: $0, position: position) }
  }

  private func update(_ model: QuickAccessEdgePeekModel, with item: QuickAccessItem) {
    if model.item != item { model.item = item }
    if model.isLeftSide != position.isLeftSide { model.isLeftSide = position.isLeftSide }
    if model.scale != scale { model.scale = scale }
  }

  private func insert(_ item: QuickAccessItem, at frame: CGRect) {
    let model = QuickAccessEdgePeekModel(item: item, isLeftSide: position.isLeftSide, scale: scale)
    let window = QuickAccessEdgePeekWindow(contentRect: frame)
    let id = item.id
    let view = QuickAccessEdgePeekView(
      model: model,
      onHover: { [weak self] hovering in self?.setHovered(id, hovering: hovering) },
      onRestore: { [weak self] in self?.onRestore?(id) }
    )
    let hostingView = QuickAccessEdgePeekHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: frame.size)
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView
    window.onScrollWheel = { [weak self] event in self?.handleScrollWheel(event, for: id) }
    entries[id] = Entry(window: window, model: model)
    window.orderFrontRegardless()

    // First frame renders the card past the edge; the phase change on the next
    // runloop turn springs it in. The window itself never moves for this.
    Task { @MainActor in
      await Task.yield()
      model.phase = .resting
    }
  }

  private func remove(_ id: UUID) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    restoreSwipes[id] = nil
    let window = entry.window
    window.onScrollWheel = nil

    window.ignoresMouseEvents = true
    entry.model.isHovered = false
    entry.model.phase = .hidden

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(Self.exitDuration * 1_000_000_000))
      window.close()
    }
  }

  /// Moves a window when the column changes (cards added/removed, display or
  /// position change). Size is constant, so this is a cheap translation.
  private func place(_ window: NSWindow, at frame: CGRect, animated: Bool) {
    guard window.frame != frame else { return }
    guard animated, !reduceMotion else {
      window.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.moveDuration
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
      window.animator().setFrame(frame, display: true)
    }
  }

  /// Move two fingers up over a peek, or sideways back out of its edge, to
  /// restore it; the card grows with the fingers and settles back if released
  /// short of the threshold.
  private func handleScrollWheel(_ event: NSEvent, for id: UUID) {
    guard let model = entries[id]?.model else { return }
    var swipe = restoreSwipes[id] ?? RestoreSwipe()
    defer { restoreSwipes[id] = swipe }

    if swipe.tracker.isTracking {
      let lifted = !event.momentumPhase.isEmpty || event.phase.contains(.ended)
      if !lifted,
         let update = swipe.tracker.add(
           fingerDelta: restoreDelta(event, axis: swipe.axis),
           timestamp: event.timestamp
         ) {
        apply(update, to: model, id: id)
      }
      if lifted || event.phase.contains(.cancelled),
         let update = swipe.tracker.finish(cancelled: event.phase.contains(.cancelled)) {
        apply(update, to: model, id: id)
      }
      return
    }

    if event.phase.contains(.began) {
      swipe.isCandidate = event.momentumPhase.isEmpty
    }
    guard swipe.isCandidate, event.momentumPhase.isEmpty,
          event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }

    swipe.isCandidate = false
    if QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
    ) {
      swipe.axis = .vertical
    } else if QuickAccessVerticalSwipeHelpers.isHorizontalDominant(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
    ) {
      swipe.axis = .horizontal
    } else {
      return
    }

    swipe.tracker.begin(timestamp: event.timestamp)
    if let update = swipe.tracker.add(
      fingerDelta: restoreDelta(event, axis: swipe.axis),
      timestamp: event.timestamp
    ) {
      apply(update, to: model, id: id)
    }
  }

  /// Finger movement in the tracker's convention, where negative travel
  /// restores: fingers up, or fingers moving back toward the screen interior.
  private func restoreDelta(_ event: NSEvent, axis: RestoreSwipe.Axis) -> CGFloat {
    switch axis {
    case .vertical:
      return QuickAccessVerticalSwipeHelpers.fingerDeltaY(
        scrollingDeltaY: event.scrollingDeltaY,
        isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
      )
    case .horizontal:
      let fingerDeltaX = QuickAccessVerticalSwipeHelpers.fingerDeltaX(
        scrollingDeltaX: event.scrollingDeltaX,
        isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
      )
      return -QuickAccessVerticalSwipeHelpers.inwardDelta(
        fingerDeltaX: fingerDeltaX,
        isLeftSide: position.isLeftSide
      )
    }
  }

  private func apply(_ update: QuickAccessVerticalSwipeTracker.Update, to model: QuickAccessEdgePeekModel, id: UUID) {
    switch update {
    case let .changed(distance):
      guard !reduceMotion else { return }
      model.restoreSwipeProgress = QuickAccessCollapseSwipePolicy.restoreProgress(distance: distance)
    case let .ended(distance, velocity):
      if QuickAccessCollapseSwipePolicy.shouldRestore(distance: distance, velocity: velocity) {
        onRestore?(id)
      }
      withAnimation(QuickAccessEdgePeekView.motion) {
        model.restoreSwipeProgress = 0
      }
    case .cancelled:
      withAnimation(QuickAccessEdgePeekView.motion) {
        model.restoreSwipeProgress = 0
      }
    }
  }

  private func setHovered(_ id: UUID, hovering: Bool) {
    guard hovering else { return }
    // The revealed card overlaps the Quick Access panel's edge gutter; keep it
    // in front so the panel never swallows clicks meant for it. Hover only
    // previews: restoring needs a click, so brushing the screen edge is safe.
    entries[id]?.window.orderFrontRegardless()
  }
}
