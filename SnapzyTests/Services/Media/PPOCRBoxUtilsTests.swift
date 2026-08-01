//
//  PPOCRBoxUtilsTests.swift
//  SnapzyTests
//
//  Synthetic binary-map coverage for DB box post-processing geometry.
//

import XCTest
@testable import Snapzy

final class PPOCRBoxUtilsTests: XCTestCase {

  /// Builds a probability map with solid high-probability blobs at the given
  /// rects (x, y, width, height), zeros elsewhere.
  private func probabilityMap(
    width: Int, height: Int, blobs: [(x: Int, y: Int, w: Int, h: Int)], peak: Float = 0.9
  ) -> [Float] {
    var map = [Float](repeating: 0, count: width * height)
    for blob in blobs {
      for y in blob.y..<(blob.y + blob.h) {
        for x in blob.x..<(blob.x + blob.w) {
          map[y * width + x] = peak
        }
      }
    }
    return map
  }

  // MARK: - connectedComponents

  func testTwoSeparatedBlobsYieldTwoComponents() {
    let map = probabilityMap(width: 40, height: 20, blobs: [(2, 2, 10, 4), (25, 12, 10, 4)])
    let binary = map.map { $0 > 0.2 }
    let components = PPOCRBoxUtils.connectedComponents(
      binary: binary, probability: map, width: 40, height: 20, minPixelCount: 3
    )
    XCTAssertEqual(components.count, 2)
    for component in components {
      XCTAssertEqual(component.meanProbability, 0.9, accuracy: 0.001)
    }
  }

  func testDiagonallyTouchingPixelsFormOneComponent() {
    var map = [Float](repeating: 0, count: 4 * 4)
    map[0 * 4 + 0] = 0.9  // (0,0)
    map[1 * 4 + 1] = 0.9  // (1,1) — 8-connected to (0,0)
    let binary = map.map { $0 > 0.2 }
    let components = PPOCRBoxUtils.connectedComponents(
      binary: binary, probability: map, width: 4, height: 4, minPixelCount: 1
    )
    XCTAssertEqual(components.count, 1)
    XCTAssertEqual(components.first?.pixelCount, 2)
  }

  func testSpecksBelowMinPixelCountAreFiltered() {
    let map = probabilityMap(width: 20, height: 10, blobs: [(1, 1, 1, 1), (10, 1, 8, 4)])
    let binary = map.map { $0 > 0.2 }
    let components = PPOCRBoxUtils.connectedComponents(
      binary: binary, probability: map, width: 20, height: 10, minPixelCount: 3
    )
    XCTAssertEqual(components.count, 1)
    XCTAssertEqual(components.first?.minX, 10)
  }

  /// Only the ring of a blob is retained. A solid 6×5 rectangle has a 4×3
  /// interior that the hull does not need and must not carry.
  func testBoundaryPointsExcludeInteriorPixels() {
    let map = probabilityMap(width: 20, height: 20, blobs: [(4, 4, 6, 5)])
    let binary = map.map { $0 > 0.2 }
    let components = PPOCRBoxUtils.connectedComponents(
      binary: binary, probability: map, width: 20, height: 20, minPixelCount: 3
    )
    XCTAssertEqual(components.first?.pixelCount, 30)
    XCTAssertEqual(components.first?.boundaryPoints.count, 30 - 4 * 3)
  }

  // MARK: - minAreaRect

  func testMinAreaRectFitsAxisAlignedPointsWithZeroAngle() {
    let points = [
      CGPoint(x: 10, y: 4), CGPoint(x: 30, y: 4),
      CGPoint(x: 30, y: 14), CGPoint(x: 10, y: 14),
    ]
    let fitted = PPOCRBoxUtils.minAreaRect(points)
    XCTAssertEqual(fitted?.size.width ?? 0, 20, accuracy: 0.001)
    XCTAssertEqual(fitted?.size.height ?? 0, 10, accuracy: 0.001)
    XCTAssertEqual(fitted?.center.x ?? 0, 20, accuracy: 0.001)
    XCTAssertEqual(fitted?.center.y ?? 0, 9, accuracy: 0.001)
    XCTAssertEqual(fitted?.angle ?? 1, 0, accuracy: 0.001)
    XCTAssertEqual(fitted?.isAxisAligned, true)
  }

  /// A 30° line must come back as a 30° box, not as its much larger
  /// axis-aligned bounding box — this is the whole point of the mini-box fit.
  func testMinAreaRectRecoversRotationOfATiltedLine() {
    let angle = CGFloat.pi / 6
    let source = PPOCRRotatedRect(
      center: CGPoint(x: 100, y: 60), size: CGSize(width: 80, height: 12), angle: angle
    )
    let fitted = PPOCRBoxUtils.minAreaRect(source.corners)
    XCTAssertEqual(fitted?.angle ?? 0, angle, accuracy: 0.001)
    XCTAssertEqual(fitted?.size.width ?? 0, 80, accuracy: 0.001)
    XCTAssertEqual(fitted?.size.height ?? 0, 12, accuracy: 0.001)
    XCTAssertEqual(fitted?.center.x ?? 0, 100, accuracy: 0.001)
    XCTAssertEqual(fitted?.center.y ?? 0, 60, accuracy: 0.001)
    // The axis-aligned bounds would have been far bigger.
    XCTAssertGreaterThan(source.boundingRect.height, 40)
  }

  /// The long axis always becomes the width, so a horizontal line never comes
  /// back rotated 90° depending on which hull edge won the fit.
  func testMinAreaRectPutsTheLongAxisOnWidth() {
    let source = PPOCRRotatedRect(
      center: CGPoint(x: 50, y: 50), size: CGSize(width: 10, height: 60), angle: 0
    )
    let fitted = PPOCRBoxUtils.minAreaRect(source.corners)
    XCTAssertEqual(fitted?.size.width ?? 0, 60, accuracy: 0.001)
    XCTAssertEqual(fitted?.size.height ?? 0, 10, accuracy: 0.001)
    XCTAssertEqual(abs(fitted?.angle ?? 0), .pi / 2, accuracy: 0.001)
  }

  // MARK: - unclipped

  func testUnclipExpandsBoxByAreaRatioOverPerimeter() {
    let rect = PPOCRRotatedRect(
      center: CGPoint(x: 20, y: 15), size: CGSize(width: 20, height: 10), angle: 0
    )
    // distance = 20*10*1.5 / (2*(20+10)) = 300/60 = 5
    let expanded = PPOCRBoxUtils.unclipped(rect, ratio: 1.5)
    XCTAssertEqual(expanded.size.width, 30, accuracy: 0.001)
    XCTAssertEqual(expanded.size.height, 20, accuracy: 0.001)
    XCTAssertEqual(expanded.center, rect.center)
    XCTAssertEqual(expanded.angle, 0, accuracy: 0.001)
  }

  /// A rotated box grows perpendicular to its own baseline, so its
  /// axis-aligned bounds grow in both dimensions.
  func testUnclipExpandsAlongTheBoxAxesNotTheImageAxes() {
    let rect = PPOCRRotatedRect(
      center: CGPoint(x: 100, y: 100), size: CGSize(width: 40, height: 10), angle: .pi / 4
    )
    let expanded = PPOCRBoxUtils.unclipped(rect, ratio: 1.4)
    XCTAssertEqual(expanded.angle, rect.angle, accuracy: 0.001)
    XCTAssertGreaterThan(expanded.size.width, rect.size.width)
    XCTAssertGreaterThan(expanded.size.height, rect.size.height)
    XCTAssertEqual(
      expanded.size.width - rect.size.width,
      expanded.size.height - rect.size.height,
      accuracy: 0.001
    )
  }

  // MARK: - readingOrder

  func testReadingOrderSortsTopToBottomThenLeftToRight() {
    func box(_ x: CGFloat, _ y: CGFloat) -> PPOCRTextBox {
      PPOCRTextBox(rect: CGRect(x: x, y: y, width: 10, height: 5), score: 0.9)
    }
    // Same visual row (y within 10px) but out of x order, plus a lower row.
    let ordered = PPOCRBoxUtils.readingOrder([box(50, 12), box(10, 10), box(10, 40)])
    XCTAssertEqual(ordered.map { $0.rect.minX }, [10, 50, 10])
    XCTAssertEqual(ordered.map { $0.rect.minY }, [10, 12, 40])
  }

  // MARK: - Detector postprocess (integration of the pieces)

  func testPostprocessProducesClippedScaledOrderedBoxes() {
    // 20×20 det map upscaled to a 200×200 original image (10× scale). Blobs
    // are 5 map px tall so their fitted mini-box clears the min_size floor.
    let map = probabilityMap(width: 20, height: 20, blobs: [(3, 1, 6, 5), (10, 10, 8, 5)])
    let boxes = PPOCRDetector.postprocess(
      probabilities: map, mapWidth: 20, mapHeight: 20, originalWidth: 200, originalHeight: 200
    )
    XCTAssertEqual(boxes.count, 2)
    // First blob is higher in the image → first in reading order.
    XCTAssertLessThan(boxes[0].rect.minY, boxes[1].rect.minY)
    // Unclip expands beyond the raw blob (6×5 map px → 60×50 image px).
    XCTAssertGreaterThan(boxes[0].rect.width, 60)
    // Solid rectangular blobs fit upright, so the cheap crop path applies.
    XCTAssertTrue(boxes.allSatisfy(\.rotated.isAxisAligned))
    // Boxes stay inside image bounds after unclip + scale.
    for box in boxes {
      XCTAssertGreaterThanOrEqual(box.rect.minX, 0)
      XCTAssertGreaterThanOrEqual(box.rect.minY, 0)
      XCTAssertLessThanOrEqual(box.rect.maxX, 200)
      XCTAssertLessThanOrEqual(box.rect.maxY, 200)
    }
  }

  func testPostprocessDropsMiniBoxesUnderMinSize() {
    // 2 map px tall once fitted to pixel centres — below PaddleOCR's min_size
    // of 3, so the hairline is discarded rather than sent to the recognizer.
    let map = probabilityMap(width: 20, height: 20, blobs: [(3, 5, 12, 3)])
    let boxes = PPOCRDetector.postprocess(
      probabilities: map, mapWidth: 20, mapHeight: 20, originalWidth: 200, originalHeight: 200
    )
    XCTAssertTrue(boxes.isEmpty)
  }

  func testPostprocessFiltersLowScoreComponents() {
    // Blob with mean probability below box_thresh (0.4) must be dropped.
    let map = probabilityMap(width: 20, height: 10, blobs: [(1, 1, 6, 3)], peak: 0.3)
    let boxes = PPOCRDetector.postprocess(
      probabilities: map, mapWidth: 20, mapHeight: 10, originalWidth: 200, originalHeight: 100
    )
    XCTAssertTrue(boxes.isEmpty)
  }
}
