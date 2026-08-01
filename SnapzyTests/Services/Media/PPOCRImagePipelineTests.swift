//
//  PPOCRImagePipelineTests.swift
//  SnapzyTests
//
//  Pixel-level coverage for PP-OCR cropping and tensor preprocessing.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PPOCRImagePipelineTests: XCTestCase {

  private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

  private static let red: RGBA = (255, 0, 0, 255)
  private static let green: RGBA = (0, 255, 0, 255)
  private static let blue: RGBA = (0, 0, 255, 255)
  private static let white: RGBA = (255, 255, 255, 255)

  /// Builds a non-premultiplied RGBA image, row 0 at the top, so alpha
  /// survives into the code under test untouched.
  private func makeImage(width: Int, height: Int, pixel: (Int, Int) -> RGBA) -> CGImage? {
    var bytes = [UInt8]()
    bytes.reserveCapacity(width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let value = pixel(x, y)
        bytes.append(contentsOf: [value.r, value.g, value.b, value.a])
      }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  /// A 40×20 image split into four solid quadrants — asymmetric in both axes,
  /// so any flipped or inverted term in the crop transform shows up.
  private func quadrantImage() -> CGImage? {
    makeImage(width: 40, height: 20) { x, y in
      switch (x < 20, y < 10) {
      case (true, true): return Self.red
      case (false, true): return Self.green
      case (true, false): return Self.blue
      case (false, false): return Self.white
      }
    }
  }

  private func colorAt(_ x: Int, _ y: Int, in image: CGImage) -> RGBA? {
    guard let pixels = PPOCRImageTensor.rgbaPixels(
      from: image, width: image.width, height: image.height
    ) else { return nil }
    let base = (y * image.width + x) * 4
    guard base + 3 < pixels.count else { return nil }
    return (pixels[base], pixels[base + 1], pixels[base + 2], pixels[base + 3])
  }

  private func assertColor(
    _ actual: RGBA?,
    _ expected: RGBA,
    _ message: String,
    line: UInt = #line
  ) {
    guard let actual else { return XCTFail("no pixel: \(message)", line: line) }
    // Resampling nudges edge values; the quadrant interiors stay saturated.
    XCTAssertEqual(Int(actual.r), Int(expected.r), accuracy: 8, message, line: line)
    XCTAssertEqual(Int(actual.g), Int(expected.g), accuracy: 8, message, line: line)
    XCTAssertEqual(Int(actual.b), Int(expected.b), accuracy: 8, message, line: line)
  }

  // MARK: - rotatedCrop

  /// A zero-angle crop covering the whole image must reproduce it exactly.
  /// This pins the flip chain: get it wrong and the crop comes out mirrored.
  func testRotatedCropAtZeroAngleReproducesTheSourceOrientation() throws {
    let image = try XCTUnwrap(quadrantImage())
    let rect = PPOCRRotatedRect(
      center: CGPoint(x: 20, y: 10), size: CGSize(width: 40, height: 20), angle: 0
    )
    let crop = try XCTUnwrap(PPOCRRecognizer.rotatedCrop(rect, in: image))

    XCTAssertEqual(crop.width, 40)
    XCTAssertEqual(crop.height, 20)
    assertColor(colorAt(5, 5, in: crop), Self.red, "top-left stays red")
    assertColor(colorAt(35, 5, in: crop), Self.green, "top-right stays green")
    assertColor(colorAt(5, 15, in: crop), Self.blue, "bottom-left stays blue")
    assertColor(colorAt(35, 15, in: crop), Self.white, "bottom-right stays white")
  }

  /// The angle is clockwise-positive in the y-down pixel space boxes live in.
  /// At +90° the box's width axis points down the image, so the source's
  /// top-right corner lands at the crop's top-left. A flipped sign would put
  /// the bottom-left there instead.
  func testRotatedCropAtNinetyDegreesRotatesClockwiseInImageSpace() throws {
    let image = try XCTUnwrap(quadrantImage())
    let rect = PPOCRRotatedRect(
      center: CGPoint(x: 20, y: 10), size: CGSize(width: 20, height: 40), angle: .pi / 2
    )
    let crop = try XCTUnwrap(PPOCRRecognizer.rotatedCrop(rect, in: image))

    XCTAssertEqual(crop.width, 20)
    XCTAssertEqual(crop.height, 40)
    assertColor(colorAt(5, 5, in: crop), Self.green, "source top-right → crop top-left")
    assertColor(colorAt(15, 5, in: crop), Self.white, "source bottom-right → crop top-right")
    assertColor(colorAt(5, 35, in: crop), Self.red, "source top-left → crop bottom-left")
    assertColor(colorAt(15, 35, in: crop), Self.blue, "source bottom-left → crop bottom-right")
  }

  /// A box reaching past the image edge pads with white, not black — black
  /// padding would read as inverted text to the recognizer.
  func testRotatedCropPadsOutsideTheImageWithWhite() throws {
    let image = try XCTUnwrap(makeImage(width: 20, height: 20) { _, _ in Self.red })
    let rect = PPOCRRotatedRect(
      center: CGPoint(x: 10, y: 10), size: CGSize(width: 60, height: 60), angle: .pi / 8
    )
    let crop = try XCTUnwrap(PPOCRRecognizer.rotatedCrop(rect, in: image))

    XCTAssertEqual(crop.width, 60)
    XCTAssertEqual(crop.height, 60)
    assertColor(colorAt(2, 2, in: crop), Self.white, "corner beyond the image is white")
    assertColor(colorAt(30, 30, in: crop), Self.red, "centre still samples the image")
  }

  func testRotatedCropRejectsNonFiniteGeometry() {
    let image = quadrantImage()
    let rect = PPOCRRotatedRect(
      center: CGPoint(x: CGFloat.nan, y: 10), size: CGSize(width: 40, height: 20), angle: 0
    )
    XCTAssertFalse(rect.isFinite)
    XCTAssertNil(image.flatMap { PPOCRRecognizer.rotatedCrop(rect, in: $0) })
  }

  // MARK: - Tensor preprocessing

  /// Transparent captures (rounded window corners, transparent PNGs) must
  /// composite onto white. Premultiplying onto the zeroed buffer would hand
  /// the model white-on-black text.
  func testTransparentPixelsCompositeOntoWhiteNotBlack() throws {
    let image = try XCTUnwrap(makeImage(width: 8, height: 8) { _, _ in (0, 0, 0, 0) })
    let pixels = try XCTUnwrap(PPOCRImageTensor.rgbaPixels(from: image, width: 8, height: 8))

    XCTAssertEqual(pixels.count, 8 * 8 * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      XCTAssertEqual(pixels[index], 255, "red channel at byte \(index)")
      XCTAssertEqual(pixels[index + 1], 255, "green channel at byte \(index)")
      XCTAssertEqual(pixels[index + 2], 255, "blue channel at byte \(index)")
    }
  }

  /// Opaque content is unaffected by the white fill underneath it.
  func testOpaquePixelsSurviveTheWhiteFill() throws {
    let image = try XCTUnwrap(makeImage(width: 8, height: 8) { _, _ in Self.blue })
    let pixels = try XCTUnwrap(PPOCRImageTensor.rgbaPixels(from: image, width: 8, height: 8))

    XCTAssertEqual(pixels[0], 0, "red")
    XCTAssertEqual(pixels[1], 0, "green")
    XCTAssertEqual(pixels[2], 255, "blue")
  }
}
