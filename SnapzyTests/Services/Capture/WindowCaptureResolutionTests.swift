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
