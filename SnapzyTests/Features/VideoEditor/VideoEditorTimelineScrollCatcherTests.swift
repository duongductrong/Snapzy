//
//  VideoEditorTimelineScrollCatcherTests.swift
//  SnapzyTests
//
//  Regression tests for timeline scroll-event routing.
//

import AppKit
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorTimelineScrollCatcherTests: XCTestCase {
  func testZeroDeltaScrollEventIsPassedThroughInsteadOfConsumed() {
    let (view, viewport) = makeCatcher()
    defer {
      view.cleanup()
    }
    let event = MockScrollWheelEvent(
      location: NSPoint(x: 80, y: 20),
      deltaX: 0,
      deltaY: 0,
      modifierFlags: []
    )

    XCTAssertNil(view.window)
    XCTAssertNil(event.window)
    XCTAssertEqual(event.scrollingDeltaX, 0)
    XCTAssertEqual(event.scrollingDeltaY, 0)
    XCTAssertTrue(view.bounds.contains(event.locationInWindow))
    withExtendedLifetime(viewport) {
      XCTAssertFalse(view.handleScroll(event))
      XCTAssertEqual(viewport.zoomLevel, 1)
      XCTAssertEqual(viewport.scrollOffset, 0)
    }
  }

  func testNonzeroScrollEventIsHandledAndPansTimeline() {
    let (view, viewport) = makeCatcher()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    defer { view.cleanup() }

    let event = MockScrollWheelEvent(
      location: NSPoint(x: 80, y: 20),
      deltaX: 0,
      deltaY: 10,
      modifierFlags: []
    )

    withExtendedLifetime(viewport) {
      XCTAssertTrue(view.handleScroll(event))
      XCTAssertEqual(viewport.scrollOffset, 180, accuracy: 0.001)
    }
  }

  func testCommandScrollEventIsHandledAndZoomsTimeline() {
    let (view, viewport) = makeCatcher()
    defer { view.cleanup() }

    let event = MockScrollWheelEvent(
      location: NSPoint(x: 80, y: 20),
      deltaX: 0,
      deltaY: 2,
      modifierFlags: [.command]
    )

    withExtendedLifetime(viewport) {
      XCTAssertTrue(view.handleScroll(event))
      XCTAssertGreaterThan(viewport.zoomLevel, 1)
    }
  }

  func testCommandScrollAtZoomCapIsPassedThrough() {
    let (view, viewport) = makeCatcher()
    viewport.setZoom(
      VideoEditorTimelineViewport.maxZoom,
      keepingTimeAtViewportX: 0,
      anchorViewportX: 0
    )
    defer { view.cleanup() }

    let event = MockScrollWheelEvent(
      location: NSPoint(x: 80, y: 20),
      deltaX: 0,
      deltaY: 10,
      modifierFlags: [.command]
    )

    withExtendedLifetime(viewport) {
      XCTAssertFalse(view.handleScroll(event))
      XCTAssertEqual(viewport.zoomLevel, VideoEditorTimelineViewport.maxZoom)
    }
  }

  func testScrollEventAtFitIsPassedThroughWhenTimelineCannotPan() {
    let (view, viewport) = makeCatcher()
    defer { view.cleanup() }

    let event = MockScrollWheelEvent(
      location: NSPoint(x: 80, y: 20),
      deltaX: 0,
      deltaY: 10,
      modifierFlags: []
    )

    withExtendedLifetime(viewport) {
      XCTAssertFalse(view.handleScroll(event))
      XCTAssertEqual(viewport.scrollOffset, 0)
    }
  }

  private func makeCatcher() -> (TimelineScrollEventCatcherView, VideoEditorTimelineViewport) {
    let viewport = VideoEditorTimelineViewport()
    viewport.viewportWidth = 200
    viewport.durationSeconds = 20

    let view = TimelineScrollEventCatcherView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    view.viewport = viewport
    return (view, viewport)
  }
}

private final class MockScrollWheelEvent: NSEvent {
  private let eventLocation: NSPoint
  private let eventDeltaX: CGFloat
  private let eventDeltaY: CGFloat
  private let eventModifierFlags: NSEvent.ModifierFlags

  init(
    location: NSPoint,
    deltaX: CGFloat,
    deltaY: CGFloat,
    modifierFlags: NSEvent.ModifierFlags
  ) {
    eventLocation = location
    eventDeltaX = deltaX
    eventDeltaY = deltaY
    eventModifierFlags = modifierFlags
    super.init()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var type: NSEvent.EventType { .scrollWheel }
  override var locationInWindow: NSPoint { eventLocation }
  override var scrollingDeltaX: CGFloat { eventDeltaX }
  override var scrollingDeltaY: CGFloat { eventDeltaY }
  override var modifierFlags: NSEvent.ModifierFlags { eventModifierFlags }
  override var hasPreciseScrollingDeltas: Bool { false }
  override var momentumPhase: NSEvent.Phase { [] }
}
