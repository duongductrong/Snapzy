//
//  PPOCRDetectorResizeTests.swift
//  SnapzyTests
//
//  Det input resizing: 736 min-side upscale plus the 2560 longer-side cap.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PPOCRDetectorResizeTests: XCTestCase {
  func testSmallImageUpscalesToMinSide() {
    XCTAssertEqual(
      PPOCRDetector.resizedDimensions(width: 100, height: 100),
      CGSize(width: 736, height: 736)
    )
  }

  func testImageWithinLimitsKeepsSize() {
    // Smaller side already >= 736 and longer side <= 2560: only 32-rounding.
    XCTAssertEqual(
      PPOCRDetector.resizedDimensions(width: 1600, height: 736),
      CGSize(width: 1600, height: 736)
    )
  }

  func testRetinaCaptureLongerSideCappedAt2560() {
    XCTAssertEqual(
      PPOCRDetector.resizedDimensions(width: 5120, height: 2880),
      CGSize(width: 2560, height: 1440)
    )
  }

  func testCapTakesPrecedenceOverMinSideUpscale() {
    // 200x3000: the min rule would upscale to 736x11040; the cap wins.
    XCTAssertEqual(
      PPOCRDetector.resizedDimensions(width: 200, height: 3000),
      CGSize(width: 160, height: 2560)
    )
  }

  func testCappedSizesStayMultiplesOf32WithinBounds() {
    for (width, height) in [(5011, 3001), (100, 5000), (3840, 2160), (5120, 5120)] {
      let size = PPOCRDetector.resizedDimensions(width: width, height: height)
      XCTAssertEqual(Int(size.width) % 32, 0, "\(width)x\(height)")
      XCTAssertEqual(Int(size.height) % 32, 0, "\(width)x\(height)")
      XCTAssertLessThanOrEqual(max(size.width, size.height), 2560, "\(width)x\(height)")
      XCTAssertGreaterThanOrEqual(min(size.width, size.height), 32, "\(width)x\(height)")
    }
  }
}
