//
//  ColorPickerTests.swift
//  SnapzyTests
//
//  Unit tests for Pick Color's pixel math, color conversion, frame reading and wiring.
//  Window- and session-level tests live in `ColorPickerSessionTests`.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ColorPickerTests: XCTestCase {

  // MARK: - Pixel sampler

  func testSampler_mapsBottomLeftPointsToTopLeftPixels() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)

    // 2× snapshot: each point covers 2×2 pixels.
    XCTAssertEqual(
      ColorPickerPixelSampler.pixel(at: CGPoint(x: 0.2, y: 49.9), bounds: bounds, imageWidth: 200, imageHeight: 100),
      ColorPickerPixel(x: 0, y: 0)
    )
    XCTAssertEqual(
      ColorPickerPixelSampler.pixel(at: CGPoint(x: 10.6, y: 0.1), bounds: bounds, imageWidth: 200, imageHeight: 100),
      ColorPickerPixel(x: 21, y: 99)
    )
    XCTAssertEqual(
      ColorPickerPixelSampler.pixel(at: CGPoint(x: 500, y: -20), bounds: bounds, imageWidth: 200, imageHeight: 100),
      ColorPickerPixel(x: 199, y: 99)
    )
  }

  func testSampler_pixelCenterRoundTrips() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
    for pixel in [ColorPickerPixel(x: 0, y: 0), ColorPickerPixel(x: 37, y: 61), ColorPickerPixel(x: 199, y: 99)] {
      let center = ColorPickerPixelSampler.point(forCenterOf: pixel, bounds: bounds, imageWidth: 200, imageHeight: 100)
      XCTAssertEqual(
        ColorPickerPixelSampler.pixel(at: center, bounds: bounds, imageWidth: 200, imageHeight: 100),
        pixel
      )
    }
  }

  func testSampler_readsExactSRGBValues() throws {
    let image = ColorPickerTestImages.image(width: 4, height: 4, colorSpace: ColorPickerTestImages.sRGB) { x, _ in
      x < 2 ? (0x1A, 0x2B, 0x3C) : (0xFF, 0x80, 0x00)
    }

    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 1, y: 2), in: image)?.hex, "#1A2B3C")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 3, y: 0), in: image)?.hex, "#FF8000")
  }

  func testSampler_convertsDisplayP3ToSRGB() throws {
    // sRGB #3366CC expressed in Display P3, as a wide-gamut display would hold it.
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let source = CGColor(srgbRed: 0x33 / 255.0, green: 0x66 / 255.0, blue: 0xCC / 255.0, alpha: 1)
    let inP3 = try XCTUnwrap(source.converted(to: p3, intent: .relativeColorimetric, options: nil)?.components)
    let image = ColorPickerTestImages.image(width: 1, height: 1, colorSpace: p3) { _, _ in
      (UInt8((inP3[0] * 255).rounded()), UInt8((inP3[1] * 255).rounded()), UInt8((inP3[2] * 255).rounded()))
    }

    let color = try XCTUnwrap(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 0, y: 0), in: image))
    XCTAssertEqual(Int(color.red), 0x33, accuracy: 1)
    XCTAssertEqual(Int(color.green), 0x66, accuracy: 1)
    XCTAssertEqual(Int(color.blue), 0xCC, accuracy: 1)
  }

  func testSampler_neighborhoodIsCenteredAndBlackOutsideImage() throws {
    let image = ColorPickerTestImages.image(width: 5, height: 5, colorSpace: ColorPickerTestImages.sRGB) { x, y in
      (x == 0 && y == 0) ? (255, 255, 255) : (0, 0, 255)
    }

    let neighborhood = try XCTUnwrap(
      ColorPickerPixelSampler.neighborhood(of: ColorPickerPixel(x: 0, y: 0), radius: 1, in: image)
    )
    XCTAssertEqual(neighborhood.width, 3)
    XCTAssertEqual(neighborhood.height, 3)
    // Center = the sampled pixel; above/left of it is off the image.
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 1, y: 1), in: neighborhood)?.hex, "#FFFFFF")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 0, y: 0), in: neighborhood)?.hex, "#000000")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 2), in: neighborhood)?.hex, "#0000FF")
  }

  // MARK: - Pixel buffer reader (live stream frames)

  func testPixelBufferReader_readsBGRAFrames() throws {
    let buffer = try makePixelBuffer(width: 6, height: 4) { x, y in
      x == 2 && y == 1 ? (0x1A, 0x2B, 0x3C) : (0, 0, 255)
    }

    XCTAssertEqual(ColorPickerPixelBufferReader.color(of: ColorPickerPixel(x: 2, y: 1), in: buffer)?.hex, "#1A2B3C")
    XCTAssertEqual(ColorPickerPixelBufferReader.color(of: ColorPickerPixel(x: 99, y: 99), in: buffer)?.hex, "#0000FF")

    let neighborhood = try XCTUnwrap(
      ColorPickerPixelBufferReader.neighborhood(of: ColorPickerPixel(x: 2, y: 1), radius: 2, in: buffer)
    )
    XCTAssertEqual(neighborhood.width, 5)
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 2), in: neighborhood)?.hex, "#1A2B3C")
    // Row above the frame is black; the row below the center is still inside the frame.
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 0), in: neighborhood)?.hex, "#000000")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 3), in: neighborhood)?.hex, "#0000FF")
  }

  // MARK: - Loupe

  func testLoupe_radiusAlwaysCoversTheCircle() {
    for cellIndex in ColorPickerLoupe.cellSizes.indices {
      for diameterIndex in ColorPickerLoupe.diameters.indices {
        let loupe = ColorPickerLoupe(cellSizeIndex: cellIndex, diameterIndex: diameterIndex, hintText: "")
        XCTAssertGreaterThanOrEqual(CGFloat(loupe.radiusInPixels * 2 + 1) * loupe.cellSize, loupe.diameter)
      }
    }
  }

  // MARK: - Shortcut wiring

  func testPickColorShortcutShipsUnbound() {
    XCTAssertEqual(GlobalShortcutKind.pickColor.configKey, "pick_color")
    XCTAssertFalse(GlobalShortcutKind.pickColor.isSystemConflictRelevant)
    XCTAssertEqual(GlobalShortcutKind.pickColor.displayName, L10n.Actions.pickColor)
    XCTAssertEqual(MenuBarItemKind.pickColor.group, .tools)
  }

  // MARK: - Helpers

  /// A 32BGRA buffer, the format the live stream delivers. `pixel(x, y)` is top-left based.
  private func makePixelBuffer(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
  ) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    XCTAssertEqual(status, kCVReturnSuccess)
    let pixelBuffer = try XCTUnwrap(buffer)
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = pixel(x, y)
        let offset = y * bytesPerRow + x * 4
        base[offset] = b
        base[offset + 1] = g
        base[offset + 2] = r
        base[offset + 3] = 255
      }
    }
    return pixelBuffer
  }
}
