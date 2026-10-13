//
//  AnnotateSelectionChromeMetricsTests.swift
//  SnapzyTests
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateSelectionChromeMetricsTests: XCTestCase {
  func testUnitFitAtUnitZoomPreservesExistingChromeMeasurements() {
    let metrics = AnnotateSelectionChromeMetrics(fitScale: 1, zoomScale: 1)

    XCTAssertEqual(
      metrics.imageLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize),
      8,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      metrics.canvasLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize),
      8,
      accuracy: 0.0001
    )
  }

  func testTallCaptureAtFitKeepsVisibleAndHitHandlesAtEightScreenPoints() {
    let fitScale: CGFloat = 0.05
    let metrics = AnnotateSelectionChromeMetrics(fitScale: fitScale, zoomScale: 1)

    XCTAssertEqual(
      metrics.imageLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize),
      160,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      metrics.canvasLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize),
      8,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      metrics.imageLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize) * fitScale,
      8,
      accuracy: 0.0001
    )
  }

  func testTallCaptureAtMaximumZoomKeepsSelectionChromeInScreenSpace() {
    let fitScale: CGFloat = 0.05
    let zoomScale: CGFloat = 16
    let metrics = AnnotateSelectionChromeMetrics(fitScale: fitScale, zoomScale: zoomScale)

    XCTAssertEqual(
      metrics.imageLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize),
      10,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      metrics.canvasLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize),
      0.5,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      metrics.imageLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize) * fitScale * zoomScale,
      8,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      metrics.canvasLength(forScreenPoints: AnnotateSelectionChromeMetrics.handleSize) * zoomScale,
      8,
      accuracy: 0.0001
    )
  }

  func testInvalidScalesRemainFinite() {
    let metrics = AnnotateSelectionChromeMetrics(fitScale: 0, zoomScale: 0)

    XCTAssertTrue(metrics.imageLength(forScreenPoints: 1).isFinite)
    XCTAssertTrue(metrics.canvasLength(forScreenPoints: 1).isFinite)
  }
}
