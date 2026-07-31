//
//  CropContentAnalyzerTests.swift
//  SnapzyTests
//
//  Tests for the pure image edge analysis engine: border detection on
//  synthetic rasters (native + downscaled), Y-flip into bottom-left image
//  points, retina point mapping, and auto-crop tightening rules.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class CropContentAnalyzerTests: XCTestCase {
  // 800x600 px, white bg, dark rect pixels x:[200,600) y(top-down):[150,450).
  // In bottom-left image points the content rect is (200, 150, 400, 300).
  private static let imageWidth = 800
  private static let imageHeight = 600
  private static let darkRect = CGRect(x: 200, y: 150, width: 400, height: 300)  // top-left px
  private static let pointSize = CGSize(width: imageWidth, height: imageHeight)

  private func makeImage(
    rects: [(rect: CGRect, gray: UInt8)]? = nil,
    background: UInt8 = 255,
    width: Int? = nil,
    height: Int? = nil
  ) throws -> CGImage {
    try XCTUnwrap(TestImageFactory.solidWithRects(
      width: width ?? Self.imageWidth, height: height ?? Self.imageHeight,
      backgroundGray: background, rects: rects ?? [(Self.darkRect, 32)]
    ))
  }

  private func makeProfile(
    _ image: CGImage,
    pointSize: CGSize? = nil,
    maxAnalysisDimension: Int = 1024
  ) throws -> CropEdgeProfile {
    try XCTUnwrap(CropContentAnalyzer.edgeProfile(
      for: image, imagePointSize: pointSize ?? Self.pointSize,
      maxAnalysisDimension: maxAnalysisDimension
    ))
  }

  private func assertEdges(
    _ actual: [CGFloat], _ expected: [CGFloat], accuracy: CGFloat,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual.count, expected.count, "edge count mismatch", file: file, line: line)
    for (actualEdge, expectedEdge) in zip(actual, expected) {
      XCTAssertEqual(actualEdge, expectedEdge, accuracy: accuracy, file: file, line: line)
    }
  }

  // MARK: - edgeProfile

  func testFindsFourContentBordersAtNativeScale() throws {
    let profile = try makeProfile(makeImage())

    // Content borders plus the always-present image-bounds edges.
    assertEdges(profile.verticalEdges, [0, 200, 600, 800], accuracy: 2)
    assertEdges(profile.horizontalEdges, [0, 150, 450, 600], accuracy: 2)
    // Bounds edges carry strength 0; content borders are strong (mean
    // per-pixel gradient 669 * covered fraction).
    XCTAssertEqual(profile.verticalStrengths[0], 0)
    XCTAssertEqual(profile.verticalStrengths[3], 0)
    XCTAssertGreaterThan(profile.verticalStrengths[1], 200)
    XCTAssertGreaterThan(profile.horizontalStrengths[2], 200)
  }

  func testHorizontalEdgesAreFlippedToBottomLeftOrigin() throws {
    // 100x100 image, dark rect at top-down pixel rows [10, 30), cols [10, 60).
    let image = try makeImage(
      rects: [(CGRect(x: 10, y: 10, width: 50, height: 20), 32)],
      width: 100, height: 100
    )
    let profile = try makeProfile(image, pointSize: CGSize(width: 100, height: 100))

    // Top-down rows 10 / 30 become bottom-left points 90 / 70, ascending.
    assertEdges(profile.horizontalEdges, [0, 70, 90, 100], accuracy: 2)
    assertEdges(profile.verticalEdges, [0, 10, 60, 100], accuracy: 2)
  }

  func testUniformImageYieldsOnlyImageBoundsEdges() throws {
    let image = try XCTUnwrap(TestImageFactory.solidColor(
      width: Self.imageWidth, height: Self.imageHeight
    ))
    let profile = try makeProfile(image)

    assertEdges(profile.verticalEdges, [0, 800], accuracy: 0.01)
    assertEdges(profile.horizontalEdges, [0, 600], accuracy: 0.01)
    XCTAssertEqual(profile.verticalStrengths, [0, 0])

    // No candidates strictly inside a rough rect -> no tightening.
    XCTAssertNil(CropContentAnalyzer.contentBounds(
      in: CGRect(x: 100, y: 100, width: 600, height: 400), profile: profile
    ))
  }

  func testRetinaPointMappingHalvesEdgePositions() throws {
    let profile = try makeProfile(makeImage(), pointSize: CGSize(width: 400, height: 300))

    assertEdges(profile.verticalEdges, [0, 100, 300, 400], accuracy: 1)
    assertEdges(profile.horizontalEdges, [0, 75, 225, 300], accuracy: 1)
  }

  func testDownscaledAnalysisKeepsBorderPositions() throws {
    // 800x600 analyzed at 400x300; tolerance doubles with the 2x scale.
    let profile = try makeProfile(makeImage(), maxAnalysisDimension: 400)

    assertEdges(profile.verticalEdges, [0, 200, 600, 800], accuracy: 4)
    assertEdges(profile.horizontalEdges, [0, 150, 450, 600], accuracy: 4)
  }

  // MARK: - contentBounds

  func testContentBoundsTightensRoughRectToContent() throws {
    let profile = try makeProfile(makeImage())
    // Rough rect 40-60 pt outside the dark rect on all sides.
    let tightened = try XCTUnwrap(CropContentAnalyzer.contentBounds(
      in: CGRect(x: 160, y: 110, width: 480, height: 380), profile: profile
    ))
    XCTAssertEqual(tightened.minX, 200, accuracy: 2)
    XCTAssertEqual(tightened.minY, 150, accuracy: 2)
    XCTAssertEqual(tightened.maxX, 600, accuracy: 2)
    XCTAssertEqual(tightened.maxY, 450, accuracy: 2)
  }

  func testContentBoundsNilWhenShrinkNotMeaningful() throws {
    let profile = try makeProfile(makeImage())
    // Only 2 pt outside the content: ~2.3% area reduction, below the 5% floor.
    XCTAssertNil(CropContentAnalyzer.contentBounds(
      in: CGRect(x: 198, y: 148, width: 404, height: 304), profile: profile
    ))
  }

  func testContentBoundsNilWhenContentBelowMinContentSize() throws {
    // 10x10 dark rect at pixels x:[400,410) top-down y:[300,310)
    // -> points x [400,410], y [290,300].
    let image = try makeImage(rects: [(CGRect(x: 400, y: 300, width: 10, height: 10), 32)])
    let profile = try makeProfile(image)

    XCTAssertNil(CropContentAnalyzer.contentBounds(
      in: CGRect(x: 394, y: 284, width: 30, height: 30), profile: profile
    ))
  }

  /// Nested boxes: light-gray outer (192) at pixels (100,100)-(700,500),
  /// dark inner (32) at (200,150)-(600,450). Both borders are detected, but
  /// per side the strongest gradient wins — the dark inner border (mean
  /// strength ~240) beats the lighter outer one (~126) — so auto-crop
  /// tightens to the inner box.
  func testNestedRectsStrongestEdgeWins() throws {
    let image = try makeImage(rects: [
      (CGRect(x: 100, y: 100, width: 600, height: 400), 192),
      (CGRect(x: 200, y: 150, width: 400, height: 300), 32)
    ])
    let profile = try makeProfile(image)

    assertEdges(profile.verticalEdges, [0, 100, 200, 600, 700, 800], accuracy: 2)
    let tightened = try XCTUnwrap(CropContentAnalyzer.contentBounds(
      in: CGRect(x: 60, y: 60, width: 680, height: 480), profile: profile
    ))
    XCTAssertEqual(tightened.minX, 200, accuracy: 2)
    XCTAssertEqual(tightened.minY, 150, accuracy: 2)
    XCTAssertEqual(tightened.maxX, 600, accuracy: 2)
    XCTAssertEqual(tightened.maxY, 450, accuracy: 2)
  }
}
