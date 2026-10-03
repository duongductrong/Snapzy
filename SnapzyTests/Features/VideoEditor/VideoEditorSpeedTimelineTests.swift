//
//  VideoEditorSpeedTimelineTests.swift
//  SnapzyTests
//
//  Regression tests for speed-track popover anchoring.
//

@testable import Snapzy
import XCTest

final class VideoEditorSpeedTimelineTests: XCTestCase {
  func testPopoverAnchorLayout_centersOnSegmentVisualPosition() {
    let layout = TimelineSegmentPopoverAnchorLayout(
      leading: 220,
      segmentWidth: 180,
      trackWidth: 500
    )

    XCTAssertEqual(layout.contentFrame.minX, 220, accuracy: 0.001)
    XCTAssertEqual(layout.contentFrame.width, 180, accuracy: 0.001)
    XCTAssertEqual(layout.contentFrame.midX, 310, accuracy: 0.001)
  }

  func testPopoverAnchorLayout_clampsSegmentInsideTrack() {
    let layout = TimelineSegmentPopoverAnchorLayout(
      leading: 480,
      segmentWidth: 180,
      trackWidth: 500
    )

    XCTAssertEqual(layout.contentFrame.minX, 320, accuracy: 0.001)
    XCTAssertEqual(layout.contentFrame.maxX, 500, accuracy: 0.001)
  }
}
