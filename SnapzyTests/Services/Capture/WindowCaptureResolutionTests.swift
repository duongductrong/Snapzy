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
}
