//
//  ScrollingCaptureCommitFrameNormalizerTests.swift
//  SnapzyTests
//
//  Regression tests for mixed-density scrolling-capture commit frames.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ScrollingCaptureCommitFrameNormalizerTests: XCTestCase {

  func testNormalize_promotesNativeExternalDisplayFrameToSessionOutputScale() throws {
    let image = try XCTUnwrap(TestImageFactory.scrollingFrame(width: 100, height: 50))

    let normalized = try XCTUnwrap(
      ScrollingCaptureCommitFrameNormalizer.normalize(
        image,
        logicalSize: CGSize(width: 100, height: 50),
        sourceScaleFactor: 1,
        minimumOutputScaleFactor: 2,
        colorSpaceName: nil
      )
    )

    XCTAssertEqual(normalized.width, 200)
    XCTAssertEqual(normalized.height, 100)
  }

  func testNormalize_returnsAlreadyNormalizedFrameWithoutResizing() throws {
    let image = try XCTUnwrap(TestImageFactory.scrollingFrame(width: 200, height: 100))

    let normalized = try XCTUnwrap(
      ScrollingCaptureCommitFrameNormalizer.normalize(
        image,
        logicalSize: CGSize(width: 100, height: 50),
        sourceScaleFactor: 1,
        minimumOutputScaleFactor: 2,
        colorSpaceName: nil
      )
    )

    XCTAssertTrue((normalized as AnyObject) === (image as AnyObject))
  }
}
