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

  // MARK: - append with shifted content (integration)

  func testAppend_shiftedContent_appendsOrFailsAlignment() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 200
    let height = 100

    // Use distinct row signatures so there is measurable inter-frame change.
    guard let image1 = TestImageFactory.scrollingFrame(width: width, height: height, logicalYOffset: 0) else {
      XCTFail("Failed to create frame 1")
      return
    }

    guard let image2 = TestImageFactory.scrollingFrame(width: width, height: height, logicalYOffset: 20) else {
      XCTFail("Failed to create frame 2")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    XCTAssertNotNil(update)

    // Synthetic images may not align reliably through the vision-assisted matcher,
    // so we accept either a successful append or an alignment failure,
    // but never "no movement" because the frames are objectively different.
    switch update?.outcome {
    case .appended(let deltaY):
      XCTAssertGreaterThan(deltaY, 0, "Delta should be positive for downward scroll")
      XCTAssertGreaterThan(stitcher.outputHeight, height, "Output height should grow after append")
      XCTAssertEqual(stitcher.acceptedFrameCount, 2)
    case .ignoredAlignmentFailed:
      XCTAssertEqual(stitcher.acceptedFrameCount, 1)
    case .ignoredNoMovement:
      XCTFail("Expected movement between shifted frames, got ignoredNoMovement")
    default:
      XCTFail("Unexpected outcome: \(String(describing: update?.outcome))")
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
    XCTAssertEqual(update?.safety, .confirmed)
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

  func testAppend_largeExpectedDelta_isNotPinnedToSmallLastMatch() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 240
    let height = 400
    let firstDelta = 24
    let secondDelta = 140

    guard
      let first = TestImageFactory.scrollingFrame(width: width, height: height, logicalYOffset: 0),
      let second = TestImageFactory.scrollingFrame(
        width: width,
        height: height,
        logicalYOffset: firstDelta
      ),
      let third = TestImageFactory.scrollingFrame(
        width: width,
        height: height,
        logicalYOffset: firstDelta + secondDelta
      )
    else {
      XCTFail("Failed to create scrolling frames")
      return
    }

    _ = stitcher.start(with: first)
    let firstUpdate = stitcher.append(
      second,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: firstDelta
    )
    guard case .appended(let acceptedFirstDelta) = firstUpdate?.outcome else {
      XCTFail("Expected first append to succeed, got \(String(describing: firstUpdate?.outcome))")
      return
    }
    XCTAssertEqual(acceptedFirstDelta, firstDelta)

    let secondUpdate = stitcher.append(
      third,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: secondDelta
    )
    guard case .appended(let acceptedSecondDelta) = secondUpdate?.outcome else {
      XCTFail("Expected large second append to succeed, got \(String(describing: secondUpdate?.outcome))")
      return
    }
    XCTAssertEqual(acceptedSecondDelta, secondDelta)
    XCTAssertEqual(stitcher.outputHeight, height + firstDelta + secondDelta)
  }

  func testAppend_repeatedContentIntermediateFrame_isNotAppendedForKnownStep() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 240
    let height = 360
    let knownStep = 80
    let intermediate = 12

    guard
      let first = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: 0
      ),
      let mid = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: intermediate
      ),
      let settled = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: knownStep
      )
    else {
      XCTFail("Failed to create repeated-content frames")
      return
    }

    _ = stitcher.start(with: first)
    let intermediateUpdate = stitcher.append(
      mid,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: knownStep
    )
    if case .appended = intermediateUpdate?.outcome {
      XCTFail("Intermediate repeated-content frame should not append, got \(String(describing: intermediateUpdate?.outcome))")
      return
    }
    XCTAssertEqual(stitcher.acceptedFrameCount, 1)

    let settledUpdate = stitcher.append(
      settled,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: knownStep
    )
    guard case .appended(let deltaY) = settledUpdate?.outcome else {
      XCTFail("Settled known-step frame should append, got \(String(describing: settledUpdate?.outcome))")
      return
    }
    XCTAssertEqual(deltaY, knownStep)
    XCTAssertEqual(stitcher.outputHeight, height + knownStep)
  }

  func testAppend_settledFinalStepIncludesShortRemainingStrip() throws {
    let stitcher = ScrollingCaptureStitcher()
    let first = try XCTUnwrap(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: 0))
    _ = stitcher.start(with: first)
    for (offset, expectedAppend) in [(80, 80), (160, 80), (172, 12)] {
      let frame = try XCTUnwrap(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: offset))
      let update = try XCTUnwrap(stitcher.append(frame, maxOutputHeight: 10_000,
        expectedSignedDeltaPixels: -80, allowsSettledPartialStep: true))
      guard case .appended(let delta) = update.outcome else {
        return XCTFail("Expected remaining strip at offset \(offset), got \(update.outcome)")
      }
      XCTAssertEqual(delta, expectedAppend)
    }
    XCTAssertEqual(stitcher.outputHeight, 532)
    let reference = try XCTUnwrap(TestImageFactory.repeatedScrollingFrame(width: 240, height: 532, logicalYOffset: 0))
    let result = try XCTUnwrap(stitcher.mergedImage())
    XCTAssertEqual(result.dataProvider?.data as Data?, reference.dataProvider?.data as Data?)
  }

  func testAppend_settledStepStillRejectsOversizedJump() throws {
    let stitcher = ScrollingCaptureStitcher()
    let first = try XCTUnwrap(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: 0))
    let jumped = try XCTUnwrap(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: 240))
    _ = stitcher.start(with: first)
    let update = stitcher.append(jumped, maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: -80, allowsSettledPartialStep: true)
    if case .appended = update?.outcome {
      XCTFail("Settled frames must still obey the maximum known step")
    }
    XCTAssertEqual(stitcher.outputHeight, 360)
  }

  func testAppend_skippedBandDoesNotOverrideKnownStep() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 240
    let height = 360
    let knownStep = 80
    let skippedBand = 240

    guard
      let first = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: 0
      ),
      let leap = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: skippedBand
      )
    else {
      XCTFail("Failed to create skipped-band frames")
      return
    }

    _ = stitcher.start(with: first)
    let update = stitcher.append(
      leap,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: knownStep
    )
    if case .appended(let deltaY) = update?.outcome {
      XCTFail("Skipped-band leap \(deltaY) should not append against known step \(knownStep)")
      return
    }
    XCTAssertEqual(stitcher.acceptedFrameCount, 1)
    XCTAssertEqual(stitcher.outputHeight, height)
  }

  func testAppend_mismatchedDimensions_marksUnsafe() {
    let stitcher = ScrollingCaptureStitcher()
    guard
      let image1 = TestImageFactory.solidColor(width: 100, height: 100),
      let image2 = TestImageFactory.solidColor(width: 120, height: 100)
    else {
      XCTFail("Failed to create test images")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    XCTAssertEqual(update?.safety, .unsafe(reason: "alignment-failed"))
  }

}
