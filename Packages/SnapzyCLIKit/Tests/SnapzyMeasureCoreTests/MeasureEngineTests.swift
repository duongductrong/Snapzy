//
//  MeasureEngineTests.swift
//  SnapzyMeasureCoreTests
//
//  Screen Ruler pixel math: edge spans, box snapping, units and text.
//

import CoreGraphics
import XCTest
@testable import SnapzyMeasureCore

final class MeasureEngineTests: XCTestCase {

  /// White 100×60 canvas with a black 1px-bordered box at x 20…59, y 10…39 (inclusive).
  private func boxedRaster() throws -> MeasureRaster {
    let image = MeasureTestImages.image(width: 100, height: 60, colorSpace: MeasureTestImages.sRGB) { x, y in
      let onBorder = (x == 20 || x == 59) && (10...39).contains(y)
        || (y == 10 || y == 39) && (20...59).contains(x)
      return onBorder ? (0, 0, 0) : (255, 255, 255)
    }
    return try XCTUnwrap(MeasureRaster(image: image))
  }

  // MARK: - Spans

  func testSpan_insideBoxMeasuresInnerGap() throws {
    let raster = try boxedRaster()
    let span = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 30, y: 20), axis: .both, tolerance: 8)
    XCTAssertEqual(span.left, 21)
    XCTAssertEqual(span.right, 58)
    XCTAssertEqual(span.top, 11)
    XCTAssertEqual(span.bottom, 38)
    XCTAssertEqual(span.width, 38)
    XCTAssertEqual(span.height, 28)
  }

  func testSpan_outsideBoxMeasuresGapToEdges() throws {
    let raster = try boxedRaster()
    // Left of the box on the same row: from x 0 up to the border at x 20.
    let span = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 5, y: 20), axis: .both, tolerance: 8)
    XCTAssertEqual(span.left, 0)
    XCTAssertEqual(span.right, 19)
    XCTAssertEqual(span.width, 20)
    // Column x 5 never meets the box: full height.
    XCTAssertEqual(span.height, 60)
  }

  func testSpan_axisLockSkipsOtherAxis() throws {
    let raster = try boxedRaster()
    let horizontal = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 30, y: 20), axis: .horizontal, tolerance: 8)
    XCTAssertEqual(horizontal.width, 38)
    XCTAssertNil(horizontal.height)
    let vertical = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 30, y: 20), axis: .vertical, tolerance: 8)
    XCTAssertNil(vertical.width)
    XCTAssertEqual(vertical.height, 28)
  }

  func testSpan_toleranceAbsorbsNearColors() throws {
    // Columns 0…9 are 200, 10…19 are 205: same color at tolerance 8, an edge at tolerance 2.
    let image = MeasureTestImages.image(width: 20, height: 4, colorSpace: MeasureTestImages.sRGB) { x, _ in
      x < 10 ? (200, 200, 200) : (205, 205, 205)
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    XCTAssertEqual(MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 2, y: 1), axis: .horizontal, tolerance: 8).width, 20)
    XCTAssertEqual(MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 2, y: 1), axis: .horizontal, tolerance: 2).width, 10)
  }

  func testSpan_clampsOriginToRaster() throws {
    let raster = try boxedRaster()
    let span = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: -5, y: 500), axis: .both, tolerance: 8)
    XCTAssertEqual(span.origin, MeasurePixel(x: 0, y: 59))
  }

  func testSpan_findsLowContrastEdgeOnFlatBackground() throws {
    // Dark mode: a Δ4 chip on a flat panel.
    let image = MeasureTestImages.image(width: 60, height: 20, colorSpace: MeasureTestImages.sRGB) { x, _ in
      (20..<40).contains(x) ? (42, 42, 42) : (38, 38, 38)
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    let span = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 30, y: 10), axis: .horizontal, tolerance: MeasureEdgeScanner.defaultTolerance)
    XCTAssertEqual(span.left, 20)
    XCTAssertEqual(span.right, 39)
  }

  func testSpan_walksThroughShadowRampToTheCardEdge() throws {
    // Background 236, a 20 px shadow ramp darkening by 3 per pixel, then a white card at x 60.
    let image = MeasureTestImages.image(width: 100, height: 4, colorSpace: MeasureTestImages.sRGB) { x, _ in
      if x >= 60 { return (255, 255, 255) }
      let value = UInt8(x < 40 ? 236 : 236 - (x - 40) * 3)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    let span = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 10, y: 1), axis: .horizontal, tolerance: MeasureEdgeScanner.defaultTolerance)
    XCTAssertEqual(span.left, 0)
    XCTAssertEqual(span.right, 59, "The gap runs to the card, not to where the shadow starts")
  }

  func testSpan_ignoresSlowGradient() throws {
    // A window background darkening by one level every 4 rows: no edge anywhere.
    let image = MeasureTestImages.image(width: 4, height: 200, colorSpace: MeasureTestImages.sRGB) { _, y in
      let value = UInt8(246 - y / 4)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    let span = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 1, y: 100), axis: .vertical, tolerance: MeasureEdgeScanner.defaultTolerance)
    XCTAssertEqual(span.height, 200)
  }

  func testSpan_countsMostlyCoveredAntiAliasedPixel() throws {
    // A dark rect on white from x 20.25 to 39.75: pixels 20 and 39 are 75% covered.
    let image = MeasureTestImages.image(width: 60, height: 4, colorSpace: MeasureTestImages.sRGB) { x, _ in
      switch x {
      case 20, 39: return (64, 64, 64)
      case 21..<39: return (0, 0, 0)
      default: return (255, 255, 255)
      }
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    let inside = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 30, y: 1), axis: .horizontal, tolerance: MeasureEdgeScanner.defaultTolerance)
    XCTAssertEqual(inside.width, 20, "19.5 px of rect: both mostly covered pixels count")
    let gap = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 5, y: 1), axis: .horizontal, tolerance: MeasureEdgeScanner.defaultTolerance)
    XCTAssertEqual(gap.right, 19)
  }

  func testSpan_ignoresMaterialNoise() throws {
    var state: UInt64 = 42
    let image = MeasureTestImages.image(width: 300, height: 40, colorSpace: MeasureTestImages.sRGB) { x, _ in
      state = state &* 6364136223846793005 &+ 1442695040888963407
      let noise = Int((state >> 33) % 11) - 5
      let base = (100..<200).contains(x) ? 255 : 236
      let value = UInt8(clamping: base + noise)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    let gap = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 50, y: 20), axis: .horizontal, tolerance: MeasureEdgeScanner.defaultTolerance)
    XCTAssertEqual(gap.left, 0)
    XCTAssertEqual(gap.right, 99)
  }

  // MARK: - Box snapping

  func testSnap_tightensOverGradientBackground() throws {
    let image = MeasureTestImages.image(width: 120, height: 120, colorSpace: MeasureTestImages.sRGB) { x, y in
      if (40..<80).contains(x), (30..<70).contains(y) { return (52, 120, 246) }
      let value = UInt8(246 - y / 4)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    let snapped = MeasureEdgeScanner.snap(
      MeasurePixelRect(minX: 5, minY: 5, maxX: 110, maxY: 110),
      in: raster,
      tolerance: MeasureEdgeScanner.defaultTolerance
    )
    XCTAssertEqual(snapped, MeasurePixelRect(minX: 40, minY: 30, maxX: 79, maxY: 69))
  }

  func testSnap_tightensToDrawnShape() throws {
    let raster = try boxedRaster()
    let snapped = MeasureEdgeScanner.snap(
      MeasurePixelRect(minX: 5, minY: 2, maxX: 80, maxY: 55),
      in: raster,
      tolerance: 8
    )
    XCTAssertEqual(snapped, MeasurePixelRect(minX: 20, minY: 10, maxX: 59, maxY: 39))
  }

  func testSnap_keepsRectOverUniformArea() throws {
    let raster = try boxedRaster()
    let rect = MeasurePixelRect(minX: 70, minY: 45, maxX: 90, maxY: 55)
    XCTAssertEqual(MeasureEdgeScanner.snap(rect, in: raster, tolerance: 8), rect)
  }

  func testPixelRect_normalizesCorners() {
    let rect = MeasurePixelRect(corner: MeasurePixel(x: 10, y: 40), MeasurePixel(x: 3, y: 5))
    XCTAssertEqual(rect, MeasurePixelRect(minX: 3, minY: 5, maxX: 10, maxY: 40))
    XCTAssertEqual(rect.width, 8)
    XCTAssertEqual(rect.height, 36)
  }

  // MARK: - Formatting

  func testFormatter_pointsAndPixels() {
    XCTAssertEqual(MeasureFormatter.value(pixels: 240, scale: 2, unit: .points), "120")
    XCTAssertEqual(MeasureFormatter.value(pixels: 241, scale: 2, unit: .points), "120.5")
    XCTAssertEqual(MeasureFormatter.value(pixels: 241, scale: 2, unit: .pixels), "241")
    XCTAssertEqual(MeasureFormatter.value(pixels: 37, scale: 1, unit: .points), "37")
  }

  func testFormatter_labelAndCopyText() {
    let box = PixelMeasurement.box(MeasurePixelRect(minX: 0, minY: 0, maxX: 239, maxY: 95))
    XCTAssertEqual(MeasureFormatter.label(for: box, scale: 2, unit: .points), "120 × 48")
    XCTAssertEqual(MeasureFormatter.copyText(for: box, scale: 2, unit: .pixels), "240 × 96 px")

    let horizontal = PixelMeasurement.span(
      MeasureSpan(origin: MeasurePixel(x: 0, y: 0), axis: .horizontal, left: 0, right: 99, top: 0, bottom: 0)
    )
    XCTAssertEqual(MeasureFormatter.copyText(for: horizontal, scale: 2, unit: .points), "50 pt")
  }

  // MARK: - Performance

  func testSpan_fiveKRasterIsFast() throws {
    let width = 5120
    let height = 2880
    let provider = try XCTUnwrap(CGDataProvider(data: Data(repeating: 240, count: width * height * 4) as CFData))
    let image = try XCTUnwrap(CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: MeasureTestImages.sRGB,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ))
    let raster = try XCTUnwrap(MeasureRaster(image: image))
    measure {
      _ = MeasureEdgeScanner.span(in: raster, from: MeasurePixel(x: 2560, y: 1440), axis: .both, tolerance: 8)
    }
  }
}
