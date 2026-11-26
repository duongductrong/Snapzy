//
//  VideoEditorTimelineSnapperTests.swift
//  SnapzyTests
//

@testable import Snapzy
import XCTest

final class VideoEditorTimelineSnapperTests: XCTestCase {
  func testSnap_locksOntoNearestTargetWithinPixelThreshold() {
    let candidates: [VideoEditorTimelineSnapper.SnapTarget] = [
      .init(time: 2.0, kind: .clipBoundary),
      .init(time: 5.0, kind: .playhead),
      .init(time: 8.0, kind: .zoomEdge),
    ]

    // At 100 px/sec with 7 px threshold -> 0.07s snap radius.
    let snapped = VideoEditorTimelineSnapper.snap(
      time: 4.95,
      candidates: candidates,
      pixelsPerSecond: 100
    )
    XCTAssertEqual(snapped.time, 5.0, accuracy: 0.0001)
    XCTAssertEqual(snapped.target, .init(time: 5.0, kind: .playhead))

    let unsnapped = VideoEditorTimelineSnapper.snap(
      time: 4.80,
      candidates: candidates,
      pixelsPerSecond: 100
    )
    XCTAssertEqual(unsnapped.time, 4.80, accuracy: 0.0001)
    XCTAssertNil(unsnapped.target)
  }

  func testSnap_breaksTiesByTargetPriority() {
    let candidates: [VideoEditorTimelineSnapper.SnapTarget] = [
      .init(time: 3.0, kind: .zoomEdge),
      .init(time: 3.0, kind: .playhead),
      .init(time: 3.0, kind: .clipBoundary),
    ]

    let result = VideoEditorTimelineSnapper.snap(
      time: 3.01,
      candidates: candidates,
      pixelsPerSecond: 100
    )
    XCTAssertEqual(result.target?.kind, .playhead)
  }

  func testSnapRange_snapsEitherLeadingOrTrailingEdgeAndRespectsBypass() {
    let candidates: [VideoEditorTimelineSnapper.SnapTarget] = [
      .init(time: 2.0, kind: .clipBoundary),
      .init(time: 6.0, kind: .playhead),
    ]

    // Trailing edge at 5.96 is within 0.07s of 6.0 -> shifts start to 4.0.
    let trailingSnap = VideoEditorTimelineSnapper.snapRange(
      start: 3.96,
      duration: 2.0,
      candidates: candidates,
      pixelsPerSecond: 100
    )
    XCTAssertEqual(trailingSnap.start, 4.0, accuracy: 0.0001)
    XCTAssertEqual(trailingSnap.target?.kind, .playhead)

    // Holding Option (isDisabled = true) bypasses snapping completely.
    let bypassed = VideoEditorTimelineSnapper.snapRange(
      start: 3.96,
      duration: 2.0,
      candidates: candidates,
      pixelsPerSecond: 100,
      isDisabled: true
    )
    XCTAssertEqual(bypassed.start, 3.96, accuracy: 0.0001)
    XCTAssertNil(bypassed.target)
  }

  @MainActor
  func testSnapGuideState_updatesAndClearsCleanly() {
    let guide = VideoEditorTimelineSnapGuideState()
    XCTAssertNil(guide.activeTime)

    let target = VideoEditorTimelineSnapper.SnapTarget(time: 4.5, kind: .clipBoundary)
    guide.update(target, emitHaptic: false)
    XCTAssertEqual(guide.activeTarget, target)
    XCTAssertEqual(guide.activeTime, 4.5)

    guide.clear()
    XCTAssertNil(guide.activeTarget)
    XCTAssertNil(guide.activeTime)
  }
}
