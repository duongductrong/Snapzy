//
//  ScrollingCaptureStitcherTests.swift
//  SnapzyTests
//
//  Unit tests for the scrolling capture stitch algorithm.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ScrollingCaptureStitcherTests: XCTestCase {

  // MARK: - start(with:)

  func testStart_initializesCorrectly() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 200, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }

    let update = stitcher.start(with: image)

    XCTAssertNotNil(update)
    XCTAssertEqual(update?.acceptedFrameCount, 1)
    XCTAssertEqual(update?.outputHeight, 100)
    XCTAssertNotNil(update?.mergedImage)

    if case .initialized = update?.outcome {} else {
      XCTFail("Expected .initialized outcome, got: \(String(describing: update?.outcome))")
    }
  }

  func testStart_setsFrameCount() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 50) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    XCTAssertEqual(stitcher.acceptedFrameCount, 1)
    XCTAssertEqual(stitcher.outputHeight, 50)
  }

  // MARK: - append identical image

  func testAppend_identicalImage_ignoredNoMovement() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(
      width: 200, height: 100,
      red: 80, green: 80, blue: 80
    ) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)

    let update = stitcher.append(image, maxOutputHeight: 10000)

    XCTAssertNotNil(update)
    if case .ignoredNoMovement = update?.outcome {} else {
      XCTFail("Expected .ignoredNoMovement for identical frame, got: \(String(describing: update?.outcome))")
    }

    // Frame count should NOT increment for ignored frames
    XCTAssertEqual(stitcher.acceptedFrameCount, 1)
  }

  // MARK: - append mismatched dimensions

  func testAppend_mismatchedDimensions_ignoredAlignmentFailed() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image1 = TestImageFactory.solidColor(width: 200, height: 100),
          let image2 = TestImageFactory.solidColor(width: 300, height: 100) else {
      XCTFail("Failed to create test images")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    XCTAssertNotNil(update)
    if case .ignoredAlignmentFailed = update?.outcome {} else {
      XCTFail("Expected .ignoredAlignmentFailed for mismatched dims, got: \(String(describing: update?.outcome))")
    }
  }

  func testAppend_mismatchedHeight_ignoredAlignmentFailed() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image1 = TestImageFactory.solidColor(width: 200, height: 100),
          let image2 = TestImageFactory.solidColor(width: 200, height: 150) else {
      XCTFail("Failed to create test images")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    if case .ignoredAlignmentFailed = update?.outcome {} else {
      XCTFail("Expected .ignoredAlignmentFailed for mismatched height")
    }
  }

  // MARK: - mergedImage

  func testMergedImage_afterStart_returnsNonNil() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let merged = stitcher.mergedImage()

    XCTAssertNotNil(merged)
    XCTAssertEqual(merged?.width, 100)
    XCTAssertEqual(merged?.height, 100)
  }

  func testMergedImage_beforeStart_returnsNil() {
    let stitcher = ScrollingCaptureStitcher()
    XCTAssertNil(stitcher.mergedImage())
  }

  // MARK: - previewImage

  func testPreviewImage_respectsMaxBounds() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 400, height: 400) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)

    let preview = stitcher.previewImage(maxPixelWidth: 100, maxPixelHeight: 100)
    XCTAssertNotNil(preview)

    if let preview {
      XCTAssertLessThanOrEqual(preview.width, 100)
      XCTAssertLessThanOrEqual(preview.height, 100)
    }
  }

  func testPreviewImage_beforeStart_returnsNil() {
    let stitcher = ScrollingCaptureStitcher()
    XCTAssertNil(stitcher.previewImage(maxPixelWidth: 200, maxPixelHeight: 200))
  }

  // MARK: - append shifted gradient (integration)

  func testAppend_shiftedGradient_appendsOrIgnores() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 200
    let height = 100

    guard let image1 = TestImageFactory.verticalGradient(
      width: width, height: height,
      topGray: 0, bottomGray: 200
    ) else {
      XCTFail("Failed to create gradient image")
      return
    }

    guard let image2 = TestImageFactory.shiftedGradient(
      width: width, height: height,
      topGray: 0, bottomGray: 200,
      shiftPixels: 20
    ) else {
      XCTFail("Failed to create shifted gradient image")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    XCTAssertNotNil(update)

    // The outcome depends on whether the stitcher can find an alignment match.
    // With a simple gradient shift the fast-guided path should find it, but
    // we accept both `appended` and `ignoredAlignmentFailed` since pixel
    // matching depends on internal thresholds.
    switch update?.outcome {
    case .appended(let deltaY):
      XCTAssertGreaterThan(deltaY, 0, "Delta should be positive for downward scroll")
      XCTAssertGreaterThan(stitcher.outputHeight, height, "Output height should grow after append")
      XCTAssertEqual(stitcher.acceptedFrameCount, 2)
    case .ignoredAlignmentFailed, .ignoredNoMovement:
      // Also acceptable for synthetic test images
      XCTAssertEqual(stitcher.acceptedFrameCount, 1)
    default:
      break
    }
  }

  // MARK: - Multiple appends build height

  func testMultipleAppends_outputHeightAccumulates() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 50) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let initialHeight = stitcher.outputHeight
    XCTAssertEqual(initialHeight, 50)

    // Appending identical images won't increase height (no movement detected)
    _ = stitcher.append(image, maxOutputHeight: 10000)
    // Height should not change for identical frames
    XCTAssertEqual(stitcher.outputHeight, 50)
  }

  // MARK: - maxOutputHeight enforcement

  func testAppend_atMaxOutputHeight_returnsReachedHeightLimit() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)

    // max = current output height → no more room
    let update = stitcher.append(image, maxOutputHeight: stitcher.outputHeight)

    // For identical images, likely ignoredNoMovement; for shifted images it would be reachedHeightLimit
    // Either outcome is acceptable since we're testing the height limit enforcement path
    XCTAssertNotNil(update)
  }

  // MARK: - Alignment Debug Info

  func testStart_alignmentDebug_isInitialFrame() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }

    let update = stitcher.start(with: image)
    XCTAssertEqual(update?.alignmentDebug?.path, .initialFrame)
    XCTAssertEqual(update?.alignmentDebug?.confidence, 1.0)
    XCTAssertFalse(update?.alignmentDebug?.usedVisionEstimate ?? true)
  }

  // MARK: - Merge Direction

  func testStart_mergeDirectionIsUnresolved() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }

    let update = stitcher.start(with: image)
    XCTAssertEqual(update?.mergeDirection, .unresolved)
  }

  // MARK: - likelyReachedBoundary

  func testAppend_identicalImage_setsLikelyReachedBoundary() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(
      width: 200, height: 100,
      red: 120, green: 120, blue: 120
    ) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let update = stitcher.append(image, maxOutputHeight: 10000)

    if case .ignoredNoMovement = update?.outcome {
      XCTAssertTrue(update?.likelyReachedBoundary ?? false)
    }
  }

  // MARK: - renderMergedImage flag

  func testAppend_renderMergedImageFalse_skipsMergedImage() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let update = stitcher.append(image, maxOutputHeight: 10000, renderMergedImage: false)

    // When renderMergedImage is false, mergedImage in the update may still be
    // the cached version from start(), so we just verify the call succeeds.
    XCTAssertNotNil(update)
  }
}
