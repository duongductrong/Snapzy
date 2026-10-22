//
//  WindowCaptureResolutionTests.swift
//  SnapzyTests
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class WindowCaptureResolutionTests: XCTestCase {
  func testDisplayBackingScaleWinsOverNominalFilterScale() {
    XCTAssertEqual(
      WindowCaptureResolution.scaleFactor(
        displayBackingScaleFactor: 2,
        filterPointPixelScale: 1,
        fallback: 1
      ),
      2
    )
  }

  func testOneXExternalDisplayRemainsNativeWhenBothSourcesAgree() {
    XCTAssertEqual(
      WindowCaptureResolution.scaleFactor(
        displayBackingScaleFactor: 1,
        filterPointPixelScale: 1,
        fallback: 2
      ),
      1
    )
  }

  func testFilterScaleIsUsedWhenDisplayScaleIsUnavailable() {
    XCTAssertEqual(
      WindowCaptureResolution.scaleFactor(
        displayBackingScaleFactor: nil,
        filterPointPixelScale: 1.5,
        fallback: 1
      ),
      1.5
    )
  }

  func testOneXOutputIsRejectedForTwoXTarget() {
    XCTAssertTrue(
      WindowCaptureResolution.isUndersized(
        pixelSize: CGSize(width: 800, height: 450),
        logicalSize: CGSize(width: 800, height: 450),
        expectedScaleFactor: 2
      )
    )
  }

  func testNativeOneXOutputIsAcceptedForOneXTarget() {
    XCTAssertFalse(
      WindowCaptureResolution.isUndersized(
        pixelSize: CGSize(width: 800, height: 450),
        logicalSize: CGSize(width: 800, height: 450),
        expectedScaleFactor: 1
      )
    )
  }

  func testUnshadowedCanvasMatchesWindowPixels() {
    XCTAssertEqual(
      WindowCaptureResolution.canvasPixelSize(
        logicalSize: CGSize(width: 1_800, height: 1_129),
        scaleFactor: 2,
        includesShadow: false
      ),
      CGSize(width: 3_600, height: 2_258)
    )
  }

  // Issue #569: a 1800x1129pt window on a 2x display renders a 3824x2482px
  // shadowed bitmap. A frame-sized canvas shrank it to ~91%.
  func testShadowedCanvasFitsMeasuredRetinaShadow() {
    let canvas = WindowCaptureResolution.canvasPixelSize(
      logicalSize: CGSize(width: 1_800, height: 1_129),
      scaleFactor: 2,
      includesShadow: true
    )
    XCTAssertGreaterThanOrEqual(canvas.width, 3_824)
    XCTAssertGreaterThanOrEqual(canvas.height, 2_482)
  }

  func testShadowedCanvasFitsShadowOnOneXDisplay() {
    // The shadow adds ~112pt per dimension at any display scale.
    let canvas = WindowCaptureResolution.canvasPixelSize(
      logicalSize: CGSize(width: 1_200, height: 798),
      scaleFactor: 1,
      includesShadow: true
    )
    XCTAssertGreaterThanOrEqual(canvas.width, 1_312)
    XCTAssertGreaterThanOrEqual(canvas.height, 910)
  }

  func testShadowPaddingScalesWithDisplay() {
    let canvas = WindowCaptureResolution.canvasPixelSize(
      logicalSize: CGSize(width: 1_000, height: 500),
      scaleFactor: 2,
      includesShadow: true
    )
    let padding = WindowCaptureResolution.shadowCanvasPadding * 2 * 2
    XCTAssertEqual(canvas, CGSize(width: 2_000 + padding, height: 1_000 + padding))
  }

  func testRoundingAndTransparentMarginsDoNotTriggerFallback() {
    XCTAssertFalse(
      WindowCaptureResolution.isUndersized(
        pixelSize: CGSize(width: 1_800, height: 900),
        logicalSize: CGSize(width: 1_000, height: 500),
        expectedScaleFactor: 2
      )
    )
  }

  // Issue #634: measured on a 2x display. A cached 600x400pt frame sized the
  // padded canvas for an 800x620pt window, which came out 0.894x native.
  func testResizedWindowFrameIsStale() {
    XCTAssertTrue(
      WindowCaptureResolution.isFrameStale(
        CGRect(x: 200, y: 200, width: 600, height: 400),
        currentFrame: CGRect(x: 200, y: 200, width: 800, height: 620)
      )
    )
  }

  func testMovedWindowFrameIsStale() {
    // A move can change the display, and with it the capture scale.
    XCTAssertTrue(
      WindowCaptureResolution.isFrameStale(
        CGRect(x: 200, y: 200, width: 800, height: 620),
        currentFrame: CGRect(x: 1_900, y: 200, width: 800, height: 620)
      )
    )
  }

  func testMatchingWindowFrameIsNotStale() {
    XCTAssertFalse(
      WindowCaptureResolution.isFrameStale(
        CGRect(x: 200, y: 200, width: 800, height: 620),
        currentFrame: CGRect(x: 200.5, y: 200, width: 800, height: 620.5)
      )
    )
  }

  func testUnknownLiveFrameKeepsCachedWindow() {
    XCTAssertFalse(
      WindowCaptureResolution.isFrameStale(
        CGRect(x: 200, y: 200, width: 800, height: 620),
        currentFrame: nil
      )
    )
  }

  func testShadowedWindowAtNativeScaleIsAccepted() {
    // 800x620pt window plus shadow, trimmed: 1796x1436px.
    XCTAssertFalse(
      WindowCaptureResolution.isScaledBelowNative(
        pixelSize: CGSize(width: 1_796, height: 1_436),
        logicalSize: CGSize(width: 800, height: 620),
        scaleFactor: 2
      )
    )
  }

  func testShadowedWindowScaledToFitIsRejected() {
    // Issue #634 outputs: 0.847x (v2.0.0, frame-sized canvas) and 0.805x
    // (stale frame). Both pass the 75% undersize rule.
    let cases: [(pixels: CGSize, points: CGSize)] = [
      (CGSize(width: 1_521, height: 1_215), CGSize(width: 800, height: 620)),
      (CGSize(width: 2_091, height: 1_447), CGSize(width: 1_200, height: 800)),
    ]
    for (pixels, points) in cases {
      XCTAssertFalse(
        WindowCaptureResolution.isUndersized(pixelSize: pixels, logicalSize: points, expectedScaleFactor: 2)
      )
      XCTAssertTrue(
        WindowCaptureResolution.isScaledBelowNative(pixelSize: pixels, logicalSize: points, scaleFactor: 2),
        "\(pixels) for \(points)"
      )
    }
  }

  func testShallowShrinkHiddenByShadowIsNotDetected() {
    // 0.894x from a stale frame: the shadow keeps the trimmed image wider
    // than the native window, so only the frame refresh prevents this one.
    XCTAssertFalse(
      WindowCaptureResolution.isScaledBelowNative(
        pixelSize: CGSize(width: 1_611, height: 1_287),
        logicalSize: CGSize(width: 800, height: 620),
        scaleFactor: 2
      )
    )
  }

  func testTransparentMarginOnOneAxisIsNotScaledBelowNative() {
    // Scaling to fit shrinks both axes; a window that is transparent along
    // one edge only trims short on that axis.
    XCTAssertFalse(
      WindowCaptureResolution.isScaledBelowNative(
        pixelSize: CGSize(width: 1_500, height: 1_436),
        logicalSize: CGSize(width: 800, height: 620),
        scaleFactor: 2
      )
    )
  }
}
