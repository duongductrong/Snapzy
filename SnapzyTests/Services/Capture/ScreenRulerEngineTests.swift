//
//  ScreenRulerEngineTests.swift
//  SnapzyTests
//
//  Screen Ruler pixel math: edge spans, box snapping, units and text.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ScreenRulerEngineTests: XCTestCase {

  /// White 100×60 canvas with a black 1px-bordered box at x 20…59, y 10…39 (inclusive).
  private func boxedRaster() throws -> ScreenRulerRaster {
    let image = ColorPickerTestImages.image(width: 100, height: 60, colorSpace: ColorPickerTestImages.sRGB) { x, y in
      let onBorder = (x == 20 || x == 59) && (10...39).contains(y)
        || (y == 10 || y == 39) && (20...59).contains(x)
      return onBorder ? (0, 0, 0) : (255, 255, 255)
    }
    return try XCTUnwrap(ScreenRulerRaster(image: image))
  }

  // MARK: - Spans

  func testSpan_insideBoxMeasuresInnerGap() throws {
    let raster = try boxedRaster()
    let span = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 30, y: 20), axis: .both, tolerance: 8)
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
    let span = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 5, y: 20), axis: .both, tolerance: 8)
    XCTAssertEqual(span.left, 0)
    XCTAssertEqual(span.right, 19)
    XCTAssertEqual(span.width, 20)
    // Column x 5 never meets the box: full height.
    XCTAssertEqual(span.height, 60)
  }

  func testSpan_axisLockSkipsOtherAxis() throws {
    let raster = try boxedRaster()
    let horizontal = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 30, y: 20), axis: .horizontal, tolerance: 8)
    XCTAssertEqual(horizontal.width, 38)
    XCTAssertNil(horizontal.height)
    let vertical = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 30, y: 20), axis: .vertical, tolerance: 8)
    XCTAssertNil(vertical.width)
    XCTAssertEqual(vertical.height, 28)
  }

  func testSpan_toleranceAbsorbsNearColors() throws {
    // Columns 0…9 are 200, 10…19 are 205: same color at tolerance 8, an edge at tolerance 2.
    let image = ColorPickerTestImages.image(width: 20, height: 4, colorSpace: ColorPickerTestImages.sRGB) { x, _ in
      x < 10 ? (200, 200, 200) : (205, 205, 205)
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    XCTAssertEqual(ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 2, y: 1), axis: .horizontal, tolerance: 8).width, 20)
    XCTAssertEqual(ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 2, y: 1), axis: .horizontal, tolerance: 2).width, 10)
  }

  func testSpan_clampsOriginToRaster() throws {
    let raster = try boxedRaster()
    let span = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: -5, y: 500), axis: .both, tolerance: 8)
    XCTAssertEqual(span.origin, ColorPickerPixel(x: 0, y: 59))
  }

  func testSpan_findsLowContrastEdgeOnFlatBackground() throws {
    // Dark mode: a Δ4 chip on a flat panel.
    let image = ColorPickerTestImages.image(width: 60, height: 20, colorSpace: ColorPickerTestImages.sRGB) { x, _ in
      (20..<40).contains(x) ? (42, 42, 42) : (38, 38, 38)
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    let span = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 30, y: 10), axis: .horizontal, tolerance: ScreenRulerEdgeScanner.defaultTolerance)
    XCTAssertEqual(span.left, 20)
    XCTAssertEqual(span.right, 39)
  }

  func testSpan_walksThroughShadowRampToTheCardEdge() throws {
    // Background 236, a 20 px shadow ramp darkening by 3 per pixel, then a white card at x 60.
    let image = ColorPickerTestImages.image(width: 100, height: 4, colorSpace: ColorPickerTestImages.sRGB) { x, _ in
      if x >= 60 { return (255, 255, 255) }
      let value = UInt8(x < 40 ? 236 : 236 - (x - 40) * 3)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    let span = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 10, y: 1), axis: .horizontal, tolerance: ScreenRulerEdgeScanner.defaultTolerance)
    XCTAssertEqual(span.left, 0)
    XCTAssertEqual(span.right, 59, "The gap runs to the card, not to where the shadow starts")
  }

  func testSpan_ignoresSlowGradient() throws {
    // A window background darkening by one level every 4 rows: no edge anywhere.
    let image = ColorPickerTestImages.image(width: 4, height: 200, colorSpace: ColorPickerTestImages.sRGB) { _, y in
      let value = UInt8(246 - y / 4)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    let span = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 1, y: 100), axis: .vertical, tolerance: ScreenRulerEdgeScanner.defaultTolerance)
    XCTAssertEqual(span.height, 200)
  }

  func testSpan_countsMostlyCoveredAntiAliasedPixel() throws {
    // A dark rect on white from x 20.25 to 39.75: pixels 20 and 39 are 75% covered.
    let image = ColorPickerTestImages.image(width: 60, height: 4, colorSpace: ColorPickerTestImages.sRGB) { x, _ in
      switch x {
      case 20, 39: return (64, 64, 64)
      case 21..<39: return (0, 0, 0)
      default: return (255, 255, 255)
      }
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    let inside = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 30, y: 1), axis: .horizontal, tolerance: ScreenRulerEdgeScanner.defaultTolerance)
    XCTAssertEqual(inside.width, 20, "19.5 px of rect: both mostly covered pixels count")
    let gap = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 5, y: 1), axis: .horizontal, tolerance: ScreenRulerEdgeScanner.defaultTolerance)
    XCTAssertEqual(gap.right, 19)
  }

  func testSpan_ignoresMaterialNoise() throws {
    var state: UInt64 = 42
    let image = ColorPickerTestImages.image(width: 300, height: 40, colorSpace: ColorPickerTestImages.sRGB) { x, _ in
      state = state &* 6364136223846793005 &+ 1442695040888963407
      let noise = Int((state >> 33) % 11) - 5
      let base = (100..<200).contains(x) ? 255 : 236
      let value = UInt8(clamping: base + noise)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    let gap = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 50, y: 20), axis: .horizontal, tolerance: ScreenRulerEdgeScanner.defaultTolerance)
    XCTAssertEqual(gap.left, 0)
    XCTAssertEqual(gap.right, 99)
  }

  // MARK: - Box snapping

  func testSnap_tightensOverGradientBackground() throws {
    let image = ColorPickerTestImages.image(width: 120, height: 120, colorSpace: ColorPickerTestImages.sRGB) { x, y in
      if (40..<80).contains(x), (30..<70).contains(y) { return (52, 120, 246) }
      let value = UInt8(246 - y / 4)
      return (value, value, value)
    }
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    let snapped = ScreenRulerEdgeScanner.snap(
      ScreenRulerPixelRect(minX: 5, minY: 5, maxX: 110, maxY: 110),
      in: raster,
      tolerance: ScreenRulerEdgeScanner.defaultTolerance
    )
    XCTAssertEqual(snapped, ScreenRulerPixelRect(minX: 40, minY: 30, maxX: 79, maxY: 69))
  }

  func testSnap_tightensToDrawnShape() throws {
    let raster = try boxedRaster()
    let snapped = ScreenRulerEdgeScanner.snap(
      ScreenRulerPixelRect(minX: 5, minY: 2, maxX: 80, maxY: 55),
      in: raster,
      tolerance: 8
    )
    XCTAssertEqual(snapped, ScreenRulerPixelRect(minX: 20, minY: 10, maxX: 59, maxY: 39))
  }

  func testSnap_keepsRectOverUniformArea() throws {
    let raster = try boxedRaster()
    let rect = ScreenRulerPixelRect(minX: 70, minY: 45, maxX: 90, maxY: 55)
    XCTAssertEqual(ScreenRulerEdgeScanner.snap(rect, in: raster, tolerance: 8), rect)
  }

  func testPixelRect_normalizesCorners() {
    let rect = ScreenRulerPixelRect(corner: ColorPickerPixel(x: 10, y: 40), ColorPickerPixel(x: 3, y: 5))
    XCTAssertEqual(rect, ScreenRulerPixelRect(minX: 3, minY: 5, maxX: 10, maxY: 40))
    XCTAssertEqual(rect.width, 8)
    XCTAssertEqual(rect.height, 36)
  }

  // MARK: - Formatting

  func testFormatter_pointsAndPixels() {
    XCTAssertEqual(ScreenRulerFormatter.value(pixels: 240, scale: 2, unit: .points), "120")
    XCTAssertEqual(ScreenRulerFormatter.value(pixels: 241, scale: 2, unit: .points), "120.5")
    XCTAssertEqual(ScreenRulerFormatter.value(pixels: 241, scale: 2, unit: .pixels), "241")
    XCTAssertEqual(ScreenRulerFormatter.value(pixels: 37, scale: 1, unit: .points), "37")
  }

  func testFormatter_labelAndCopyText() {
    let box = ScreenRulerMeasurement.box(ScreenRulerPixelRect(minX: 0, minY: 0, maxX: 239, maxY: 95))
    XCTAssertEqual(ScreenRulerFormatter.label(for: box, scale: 2, unit: .points), "120 × 48")
    XCTAssertEqual(ScreenRulerFormatter.copyText(for: box, scale: 2, unit: .pixels), "240 × 96 px")

    let horizontal = ScreenRulerMeasurement.span(
      ScreenRulerSpan(origin: ColorPickerPixel(x: 0, y: 0), axis: .horizontal, left: 0, right: 99, top: 0, bottom: 0)
    )
    XCTAssertEqual(ScreenRulerFormatter.copyText(for: horizontal, scale: 2, unit: .points), "50 pt")
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
      space: ColorPickerTestImages.sRGB,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ))
    let raster = try XCTUnwrap(ScreenRulerRaster(image: image))
    measure {
      _ = ScreenRulerEdgeScanner.span(in: raster, from: ColorPickerPixel(x: 2560, y: 1440), axis: .both, tolerance: 8)
    }
  }
}
