//
//  QuickAccessImageOptimizerTests.swift
//  SnapzyTests
//

import CoreGraphics
import ImageIO
import XCTest
@testable import Snapzy

final class QuickAccessImageOptimizerTests: XCTestCase {
  func testRetinaCaptureOffersHalfOneAndOneAndAHalfXThenOriginal() {
    let levels = QuickAccessImageOptimizer.levels(
      for: QuickAccessOptimizeSourceInfo(pixelWidth: 2880, pixelHeight: 1800, nativeScale: 2)
    )

    XCTAssertEqual(levels.map(\.scaleLabel), ["0.5x", "1x", "1.5x", "2x"])
    XCTAssertEqual(levels.map(\.dimensionsLabel), ["720×450", "1440×900", "2160×1350", "2880×1800"])
    XCTAssertEqual(levels.last?.isOriginal, true)
    XCTAssertEqual(levels.filter(\.isOriginal).count, 1)
  }

  func testStandardDensityCaptureOffersHalfAndThreeQuarters() {
    let levels = QuickAccessImageOptimizer.levels(
      for: QuickAccessOptimizeSourceInfo(pixelWidth: 1920, pixelHeight: 1080, nativeScale: 1)
    )

    XCTAssertEqual(levels.map(\.scaleLabel), ["0.5x", "0.75x", "1x"])
  }

  func testLevelsThatWouldBeTooSmallAreHidden() {
    let levels = QuickAccessImageOptimizer.levels(
      for: QuickAccessOptimizeSourceInfo(pixelWidth: 800, pixelHeight: 400, nativeScale: 2)
    )

    // 0.25 → 200px long edge is below the minimum; 0.5 → 400px stays.
    XCTAssertEqual(levels.map(\.scaleLabel), ["1x", "1.5x", "2x"])
  }

  func testTinyCaptureOnlyOffersOriginal() {
    let levels = QuickAccessImageOptimizer.levels(
      for: QuickAccessOptimizeSourceInfo(pixelWidth: 300, pixelHeight: 200, nativeScale: 2)
    )

    XCTAssertEqual(levels.count, 1)
    XCTAssertEqual(levels.first?.isOriginal, true)
  }

  func testNativeScaleIsReadFromDPIAndSnapped() {
    XCTAssertEqual(QuickAccessImageOptimizer.nativeScale(from: [kCGImagePropertyDPIWidth: 144]), 2)
    XCTAssertEqual(QuickAccessImageOptimizer.nativeScale(from: [kCGImagePropertyDPIWidth: 143.99]), 2)
    XCTAssertEqual(QuickAccessImageOptimizer.nativeScale(from: [kCGImagePropertyDPIWidth: 72]), 1)
    XCTAssertNil(QuickAccessImageOptimizer.nativeScale(from: [:]))
  }

  func testRenderShrinksPixelsWritesNewDPIAndReducesBytes() throws {
    let original = try XCTUnwrap(makeNoisyImage(width: 1200, height: 800))
    let source = QuickAccessOptimizeSourceInfo(pixelWidth: 1200, pixelHeight: 800, nativeScale: 2)
    let half = try XCTUnwrap(QuickAccessImageOptimizer.levels(for: source).first { $0.fraction == 0.5 })

    let originalData = try XCTUnwrap(
      QuickAccessImageOptimizer.encode(original, fileExtension: "png", scale: 2)
    )
    let renderedData = try XCTUnwrap(
      QuickAccessImageOptimizer.render(half, from: original, fileExtension: "png")
    )

    XCTAssertLessThan(renderedData.count, originalData.count)

    let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(renderedData as CFData, nil))
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    )
    XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 600)
    XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 400)
    XCTAssertEqual(QuickAccessImageOptimizer.nativeScale(from: properties), 1)
  }

  func testRenderKeepsJPEGAndWebPFormats() throws {
    let original = try XCTUnwrap(makeNoisyImage(width: 800, height: 600))
    let level = QuickAccessOptimizeLevel(fraction: 0.5, scale: 1, pixelWidth: 400, pixelHeight: 300)

    let jpeg = try XCTUnwrap(QuickAccessImageOptimizer.render(level, from: original, fileExtension: "jpg"))
    XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])

    let webp = try XCTUnwrap(QuickAccessImageOptimizer.render(level, from: original, fileExtension: "webp"))
    XCTAssertEqual(String(data: webp.subdata(in: 8 ..< 12), encoding: .ascii), "WEBP")
  }

  func testSavingsLabel() {
    XCTAssertEqual(QuickAccessOptimizeMenuFormatting.savingsLabel(byteCount: 380, originalByteCount: 1000), "−62%")
    XCTAssertNil(QuickAccessOptimizeMenuFormatting.savingsLabel(byteCount: 1000, originalByteCount: 1000))
    XCTAssertNil(QuickAccessOptimizeMenuFormatting.savingsLabel(byteCount: 10, originalByteCount: nil))
  }

  func testSupportedExtensions() {
    XCTAssertTrue(QuickAccessImageOptimizer.supports(url: URL(fileURLWithPath: "/tmp/a.PNG")))
    XCTAssertTrue(QuickAccessImageOptimizer.supports(url: URL(fileURLWithPath: "/tmp/a.webp")))
    XCTAssertFalse(QuickAccessImageOptimizer.supports(url: URL(fileURLWithPath: "/tmp/a.gif")))
    XCTAssertFalse(QuickAccessImageOptimizer.supports(url: URL(fileURLWithPath: "/tmp/a.mov")))
  }

  /// Deterministic noise so PNG cannot compress the image down to nothing.
  private func makeNoisyImage(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let data = context.data else {
      return nil
    }
    let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
    var seed: UInt32 = 0x9E37_79B9
    for y in 0 ..< height {
      for x in 0 ..< width {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let offset = y * context.bytesPerRow + x * 4
        pixels[offset] = UInt8(truncatingIfNeeded: seed >> 24)
        pixels[offset + 1] = UInt8(truncatingIfNeeded: (x * 255) / width)
        pixels[offset + 2] = UInt8(truncatingIfNeeded: (y * 255) / height)
        pixels[offset + 3] = 255
      }
    }
    return context.makeImage()
  }
}
