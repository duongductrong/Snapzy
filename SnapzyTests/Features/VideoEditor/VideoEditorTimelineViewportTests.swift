//
//  VideoEditorTimelineViewportTests.swift
//  SnapzyTests
//
//  Unit tests for the timeline viewport zoom/scroll math.
//

@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorTimelineViewportTests: XCTestCase {
  private func makeViewport(
    viewportWidth: CGFloat = 1000,
    duration: TimeInterval = 60
  ) -> VideoEditorTimelineViewport {
    let viewport = VideoEditorTimelineViewport()
    viewport.viewportWidth = viewportWidth
    viewport.durationSeconds = duration
    return viewport
  }

  // MARK: - Fit State

  func testInitialState_isFit() {
    let viewport = makeViewport()
    XCTAssertTrue(viewport.isFit)
    XCTAssertEqual(viewport.zoomLevel, 1)
    XCTAssertEqual(viewport.contentWidth, 1000)
    XCTAssertEqual(viewport.scrollOffset, 0)
  }

  // MARK: - Mapping

  func testMapping_roundTripAtFit() {
    let viewport = makeViewport()
    XCTAssertEqual(viewport.x(for: 30), 500, accuracy: 0.001)
    XCTAssertEqual(viewport.time(for: 500), 30, accuracy: 0.001)
  }

  func testMapping_scalesWithZoom() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    XCTAssertEqual(viewport.contentWidth, 2000)
    XCTAssertEqual(viewport.x(for: 30), 1000, accuracy: 0.001)
    XCTAssertEqual(viewport.time(for: 1000), 30, accuracy: 0.001)
  }

  func testMapping_clampsOutsideRange() {
    let viewport = makeViewport()
    XCTAssertEqual(viewport.x(for: -5), 0)
    XCTAssertEqual(viewport.x(for: 120), 1000)
    XCTAssertEqual(viewport.time(for: -10), 0)
    XCTAssertEqual(viewport.time(for: 2000), 60, accuracy: 0.001)
  }

  // MARK: - Zoom Anchoring

  func testZoom_keepsAnchorTimeAtAnchorViewportX() {
    let viewport = makeViewport()
    // Anchor: t=10s currently at viewport x=200 → scroll offset 300.
    viewport.scrollOffset = 300
    let anchorTime = viewport.time(for: 200 + 300)

    viewport.setZoom(2, keepingTimeAtViewportX: anchorTime, anchorViewportX: 200)

    // After zoom, t=10s maps to content x=1000; it should sit at viewport x=200.
    XCTAssertEqual(viewport.x(for: anchorTime) - viewport.scrollOffset, 200, accuracy: 0.01)
  }

  func testZoomIn_usesStepAndClampsAtMax() {
    let viewport = makeViewport(duration: 5)
    for _ in 0 ..< 20 {
      viewport.zoomIn(anchorTime: 0)
    }
    // 5s duration with 1s min visible caps zoom at 5x.
    XCTAssertEqual(viewport.zoomLevel, 5, accuracy: 0.001)
    XCTAssertFalse(viewport.canZoomIn)
  }

  func testZoomOut_clampsAtFit() {
    let viewport = makeViewport()
    viewport.zoomOut(anchorTime: 10)
    XCTAssertTrue(viewport.isFit)
    XCTAssertEqual(viewport.scrollOffset, 0)
  }

  func testFit_resetsZoomAndScroll() {
    let viewport = makeViewport()
    viewport.setZoom(4, keepingTimeAtViewportX: 10, anchorViewportX: 100)
    XCTAssertFalse(viewport.isFit)

    viewport.fit()

    XCTAssertTrue(viewport.isFit)
    XCTAssertEqual(viewport.scrollOffset, 0)
  }

  // MARK: - Scroll Clamping

  func testClampScroll_boundsOffsetToScrollableRange() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    XCTAssertEqual(viewport.contentWidth, 2000)

    viewport.scrollOffset = 5000
    viewport.clampScroll()
    XCTAssertEqual(viewport.scrollOffset, 1000, accuracy: 0.001)

    viewport.scrollOffset = -100
    viewport.clampScroll()
    XCTAssertEqual(viewport.scrollOffset, 0)
  }

  // MARK: - Wheel Zoom

  func testScrollZoomFactor_positiveDeltaZoomsInNegativeZoomsOut() {
    let zoomIn = VideoEditorTimelineViewport.scrollZoomFactor(
      deltaY: 5, hasPreciseScrollingDeltas: true
    ) ?? 0
    let zoomOut = VideoEditorTimelineViewport.scrollZoomFactor(
      deltaY: -5, hasPreciseScrollingDeltas: true
    ) ?? 1
    XCTAssertGreaterThan(zoomIn, 1)
    XCTAssertLessThan(zoomOut, 1)
  }

  func testScrollZoomFactor_rejectsZeroAndNonFiniteDeltas() {
    XCTAssertNil(VideoEditorTimelineViewport.scrollZoomFactor(deltaY: 0, hasPreciseScrollingDeltas: true))
    XCTAssertNil(VideoEditorTimelineViewport.scrollZoomFactor(deltaY: .nan, hasPreciseScrollingDeltas: true))
    XCTAssertNil(VideoEditorTimelineViewport.scrollZoomFactor(deltaY: .infinity, hasPreciseScrollingDeltas: false))
  }

  func testScrollZoomFactor_preciseDeltasAreFinerThanCoarse() {
    let precise = VideoEditorTimelineViewport.scrollZoomFactor(
      deltaY: 10, hasPreciseScrollingDeltas: true
    ) ?? 1
    let coarse = VideoEditorTimelineViewport.scrollZoomFactor(
      deltaY: 10, hasPreciseScrollingDeltas: false
    ) ?? 1
    // A 10-point trackpad delta should zoom far less than a 10-notch wheel spin.
    XCTAssertLessThan(precise, coarse)
  }

  func testWheelZoom_keepsCursorTimeAtCursorX() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    viewport.scrollOffset = 400

    // Cursor at viewport x=300; the time under it must stay put while zooming.
    let cursorX: CGFloat = 300
    let anchorTime = viewport.time(for: viewport.scrollOffset + cursorX)

    for factor in [1.1, 1.2, 0.9] {
      viewport.zoom(by: factor, anchorTime: anchorTime, anchorViewportX: cursorX)
      XCTAssertEqual(
        viewport.x(for: anchorTime) - viewport.scrollOffset,
        cursorX,
        accuracy: 0.01
      )
    }
  }

  // MARK: - Wheel Pan

  func testPan_contentRightScrollsBack_contentDownScrollsForward() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    viewport.scrollOffset = 500

    // Content moving right scrolls back toward the start.
    viewport.pan(byContentDeltaX: 30, contentDeltaY: 0)
    XCTAssertEqual(viewport.scrollOffset, 470, accuracy: 0.001)

    // Content moving down (wheel rolled down) reads as moving forward in time.
    viewport.pan(byContentDeltaX: 0, contentDeltaY: 20)
    XCTAssertEqual(viewport.scrollOffset, 490, accuracy: 0.001)

    // Non-finite deltas are ignored.
    viewport.pan(byContentDeltaX: .nan, contentDeltaY: 0)
    XCTAssertEqual(viewport.scrollOffset, 490, accuracy: 0.001)
  }

  func testPan_clampsToScrollableRange() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)

    viewport.pan(byContentDeltaX: 0, contentDeltaY: 5000)
    XCTAssertEqual(viewport.scrollOffset, 1000, accuracy: 0.001)

    viewport.pan(byContentDeltaX: 0, contentDeltaY: -5000)
    XCTAssertEqual(viewport.scrollOffset, 0, accuracy: 0.001)
  }

  // MARK: - Playhead Follow

  func testTargetScrollToKeepVisible_noScrollWhenVisible() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    viewport.scrollOffset = 500
    // Playhead at content x=1100 sits inside [500+24, 500+1000-24].
    XCTAssertNil(viewport.targetScrollToKeepVisible(contentX: 1100, margin: 24))
  }

  func testTargetScrollToKeepVisible_scrollsWhenBehindAndAhead() {
    let viewport = makeViewport()
    viewport.setZoom(2, keepingTimeAtViewportX: 0, anchorViewportX: 0)
    viewport.scrollOffset = 500

    // Behind the viewport → scroll back so the playhead sits at the margin.
    XCTAssertEqual(
      viewport.targetScrollToKeepVisible(contentX: 100, margin: 24) ?? -1,
      76,
      accuracy: 0.001
    )

    // Ahead of the viewport → scroll forward, clamped to max offset.
    XCTAssertEqual(
      viewport.targetScrollToKeepVisible(contentX: 1900, margin: 24) ?? -1,
      924,
      accuracy: 0.001
    )
  }
}
