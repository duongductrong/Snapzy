//
//  AnnotateCutOutTransformTests.swift
//  SnapzyTests
//
//  Unit tests for the Cut Out tool pure transforms: strip image removal and
//  insertion, plus the point/rect shift rules. Image space is bottom-left
//  origin (y-up), matching AppKit annotation storage.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateCutOutTransformTests: XCTestCase {
  private struct Pixel: Equatable {
    var r: Int
    var g: Int
    var b: Int
    var a: Int

    static let red = Pixel(r: 255, g: 0, b: 0, a: 255)
    static let green = Pixel(r: 0, g: 255, b: 0, a: 255)
    static let blue = Pixel(r: 0, g: 0, b: 255, a: 255)
    static let transparent = Pixel(r: 0, g: 0, b: 0, a: 0)
  }

  // MARK: - Helpers

  /// Deterministic pure-byte fixture (no CGColor conversions): each entry is a
  /// 2-pixel-tall band, `rows[i]` first from the TOP of the image. 2x Retina.
  private func makeBandImage(width: CGFloat, rows: [Pixel]) -> NSImage {
    let pw = Int(width * 2)
    let ph = rows.count * 2
    var raw = [UInt8](repeating: 0, count: pw * ph * 4)

    // CGImage byte row 0 is the TOP image row.
    for (index, color) in rows.enumerated() {
      for rowOffset in 0..<2 {
        for col in 0..<pw {
          let byteRow = index * 2 + rowOffset
          let i = (byteRow * pw + col) * 4
          raw[i] = UInt8(color.r); raw[i + 1] = UInt8(color.g)
          raw[i + 2] = UInt8(color.b); raw[i + 3] = UInt8(color.a)
        }
      }
    }

    let provider = CGDataProvider(data: Data(raw) as CFData)!
    let cgImage = CGImage(
      width: pw, height: ph, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pw * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
    return NSImage(cgImage: cgImage, size: CGSize(width: width, height: CGFloat(rows.count)))
  }

  private func cg(_ image: NSImage) -> CGImage {
    image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  }

  /// Reads one pixel of the image. `x`, `y` are points (bottom-left origin,
  /// y-up, like annotation space); pixel coords multiply by the image scale.
  private func pixel(_ image: NSImage, x: CGFloat, y: CGFloat) -> Pixel {
    let cgImage = cg(image)
    let scaleX = CGFloat(cgImage.width) / image.size.width
    let scaleY = CGFloat(cgImage.height) / image.size.height
    let pixelY = Int(y * scaleY)
    let flipped = cgImage.height - 1 - pixelY
    let raw = cgImage.dataProvider!.data! as Data
    let rowStride = cgImage.bytesPerRow
    let index = flipped * rowStride + Int(x * scaleX) * 4
    return Pixel(
      r: Int(raw[index]), g: Int(raw[index + 1]), b: Int(raw[index + 2]), a: Int(raw[index + 3])
    )
  }

  // MARK: - Remove, horizontal

  func testRemoveHorizontalRow_joinsBelowAndAbove() {
    // Image rows top→bottom: red / green / blue / blue (points y-up: red is the
    // top 1 point, blue the two bottom rows). Remove the green band [2, 3).
    let image = makeBandImage(width: 2, rows: [.red, .green, .blue, .blue])
    let strip = CGRect(x: 0, y: 2.0, width: 2, height: 1.0)

    let result = AnnotateCutOutTransform.apply(
      to: image, strip: strip, orientation: .horizontal, mode: .remove
    )

    let out = try! XCTUnwrap(result)
    XCTAssertEqual(cg(out).width, 4)
    XCTAssertEqual(cg(out).height, 6)
    // Point size keeps the strip shrink: 4 rows - 1 point.
    XCTAssertEqual(out.size.height, 3, accuracy: 0.001)

    // Bottom stays blue, joined top row is red, no green remains.
    XCTAssertEqual(pixel(out, x: 1, y: 0.5), .blue)
    XCTAssertEqual(pixel(out, x: 1, y: 2.5), .red)
  }

  func testRemoveHorizontalStripAcrossTwoRows_joinsHalfRows() {
    // Top→bottom: blue / blue / red / red. Strip [1, 3) removes the two blue rows.
    let image = makeBandImage(width: 2, rows: [.blue, .blue, .red, .red])
    let strip = CGRect(x: 0, y: 1.0, width: 2, height: 2.0)

    let result = AnnotateCutOutTransform.apply(
      to: image, strip: strip, orientation: .horizontal, mode: .remove
    )

    let out = try! XCTUnwrap(result)
    XCTAssertEqual(cg(out).height, 4)
    XCTAssertEqual(pixel(out, x: 1, y: 0.5), .red) // bottom half still red
    XCTAssertEqual(pixel(out, x: 1, y: 1.5), .blue) // top blue row joined down
    XCTAssertEqual(out.size.height, 2, accuracy: 0.001)
  }

  // MARK: - Remove, vertical

  func testRemoveVerticalColumn_joinsLeftAndRight() {
    let image = makeBandImage(width: 4, rows: [.red, .blue])
    let strip = CGRect(x: 1.5, y: 0, width: 1.0, height: 2)

    let result = AnnotateCutOutTransform.apply(
      to: image, strip: strip, orientation: .vertical, mode: .remove
    )

    let out = try! XCTUnwrap(result)
    XCTAssertEqual(cg(out).width, 6)
    XCTAssertEqual(out.size.height, 2, accuracy: 0.001)
    // Both joined halves keep their content: red top / blue bottom per half.
    XCTAssertEqual(pixel(out, x: 1, y: 1.5), .red)
    XCTAssertEqual(pixel(out, x: 1, y: 0.5), .blue)
    XCTAssertEqual(pixel(out, x: 4, y: 1.5), .red)
    XCTAssertEqual(pixel(out, x: 4, y: 0.5), .blue)
  }

  // MARK: - Insert, horizontal

  func testInsertHorizontal_addsTransparentGapAndShiftsContentUp() {
    // Top→bottom: blue / blue / red / red. Insert a 1-point gap starting at y=1:
    // red stays, gap transparent, the two blue rows shift up by 1 point, and
    // the appended topmost point row stays empty (transparent).
    let image = makeBandImage(width: 2, rows: [.blue, .blue, .red, .red])
    let strip = CGRect(x: 0, y: 1.0, width: 2, height: 1.0)

    let result = AnnotateCutOutTransform.apply(
      to: image, strip: strip, orientation: .horizontal, mode: .insert
    )

    let out = try! XCTUnwrap(result)
    let cgImage = cg(out)
    XCTAssertEqual(cgImage.height, 10) // 8 + 1 point gap (2px)
    XCTAssertEqual(out.size.height, 5, accuracy: 0.001)

    XCTAssertEqual(pixel(out, x: 1, y: 0.5), .red)
    XCTAssertEqual(pixel(out, x: 1, y: 1.5), .transparent)
    XCTAssertEqual(pixel(out, x: 1, y: 3.5), .blue)
    XCTAssertEqual(pixel(out, x: 1, y: 4.5), .blue) // shifted content reaches the new top
  }

  // MARK: - Rejection

  func testStripCoveringWholeImage_isRejected() {
    let image = makeBandImage(width: 2, rows: [.red, .red])
    let strip = CGRect(x: 0, y: 0, width: 2, height: 2)

    XCTAssertNil(AnnotateCutOutTransform.apply(to: image, strip: strip, orientation: .horizontal, mode: .remove))
  }

  func testZeroSizeStrip_isRejected() {
    let image = makeBandImage(width: 2, rows: [.red, .red])
    XCTAssertNil(AnnotateCutOutTransform.apply(to: image, strip: .zero, orientation: .horizontal, mode: .remove))
  }

  // MARK: - fullCrossingStrip

  func testFullCrossingStrip_forcesFullWidthOnHorizontal() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
    let drag = CGRect(x: 30, y: 10, width: 20, height: 12)
    let strip = AnnotateCutOutTransform.fullCrossingStrip(
      from: drag, orientation: .horizontal, imageBounds: bounds
    )
    XCTAssertEqual(strip, CGRect(x: 0, y: 10, width: 100, height: 12))
  }

  func testFullCrossingStrip_forcesFullHeightOnVertical() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
    let drag = CGRect(x: 30, y: 10, width: 20, height: 12)
    let strip = AnnotateCutOutTransform.fullCrossingStrip(
      from: drag, orientation: .vertical, imageBounds: bounds
    )
    XCTAssertEqual(strip, CGRect(x: 30, y: 0, width: 20, height: 50))
  }

  func testFullCrossingStrip_clampsToImageBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
    let drag = CGRect(x: 30, y: -20, width: 20, height: 80)
    let strip = AnnotateCutOutTransform.fullCrossingStrip(
      from: drag, orientation: .vertical, imageBounds: bounds
    )
    XCTAssertEqual(strip, CGRect(x: 30, y: 0, width: 20, height: 50))
  }

  // MARK: - Point shift

  func testShiftPoint_removeHorizontal_farSideBoundaryIsMaxY() {
    let strip = CGRect(x: 0, y: 10, width: 100, height: 5)
    XCTAssertTrue(AnnotateCutOutTransform.isFarSidePoint(CGPoint(x: 5, y: 18), strip: strip, orientation: .horizontal, mode: .remove))
    XCTAssertTrue(AnnotateCutOutTransform.isFarSidePoint(CGPoint(x: 5, y: 15), strip: strip, orientation: .horizontal, mode: .remove))
    XCTAssertFalse(AnnotateCutOutTransform.isFarSidePoint(CGPoint(x: 5, y: 9), strip: strip, orientation: .horizontal, mode: .remove))
  }

  func testShiftPoint_insert_farBoundaryIsStripMin() {
    let strip = CGRect(x: 0, y: 10, width: 100, height: 5)
    XCTAssertTrue((AnnotateCutOutTransform.isFarSidePoint(CGPoint(x: 5, y: 10), strip: strip, orientation: .horizontal, mode: .insert)))
    XCTAssertFalse(AnnotateCutOutTransform.isFarSidePoint(CGPoint(x: 5, y: 9.5), strip: strip, orientation: .horizontal, mode: .insert))
  }

  // MARK: - Rect shift (majority rule)

  func testShiftRect_majorityBelow_stays() {
    let strip = CGRect(x: 0, y: 10, width: 100, height: 5)
    let rect = CGRect(x: 0, y: 0, width: 40, height: 9) // fully below
    XCTAssertEqual(AnnotateCutOutTransform.shiftRect(rect, strip: strip, orientation: .horizontal, mode: .remove), rect)
  }

  func testShiftRect_majorityAbove_movesDownByStripHeight() {
    let strip = CGRect(x: 0, y: 10, width: 100, height: 5)
    let rect = CGRect(x: 10, y: 16, width: 40, height: 20) // fully above
    XCTAssertEqual(
      AnnotateCutOutTransform.shiftRect(rect, strip: strip, orientation: .horizontal, mode: .remove),
      CGRect(x: 10, y: 11, width: 40, height: 20)
    )
  }

  func testShiftRect_crossing_followsMajorityHalf() {
    let strip = CGRect(x: 0, y: 10, width: 100, height: 5) // y 10..15

    // Mostly above the strip: 8 above vs 2 below → moves down.
    let mostlyAbove = CGRect(x: 0, y: 3, width: 50, height: 20) // y 3..23
    XCTAssertEqual(
      AnnotateCutOutTransform.shiftRect(mostlyAbove, strip: strip, orientation: .horizontal, mode: .remove),
      CGRect(x: 0, y: -2, width: 50, height: 20)
    )

    // Mostly below: 7 below vs 3 above → stays.
    let mostlyBelow = CGRect(x: 0, y: 0, width: 50, height: 18) // y 0..18
    XCTAssertEqual(
      AnnotateCutOutTransform.shiftRect(mostlyBelow, strip: strip, orientation: .horizontal, mode: .remove),
      mostlyBelow
    )
  }

  func testShiftRect_insertMovesContentUp() {
    let strip = CGRect(x: 0, y: 10, width: 100, height: 5)
    let rect = CGRect(x: 10, y: 12, width: 20, height: 10) // above insertion line
    XCTAssertEqual(
      AnnotateCutOutTransform.shiftRect(rect, strip: strip, orientation: .horizontal, mode: .insert),
      CGRect(x: 10, y: 17, width: 20, height: 10)
    )
  }

  func testShiftRect_verticalRemoveMovesRightHalfLeft() {
    let strip = CGRect(x: 10, y: 0, width: 5, height: 100)
    let rect = CGRect(x: 20, y: 5, width: 30, height: 10) // right of strip
    XCTAssertEqual(
      AnnotateCutOutTransform.shiftRect(rect, strip: strip, orientation: .vertical, mode: .remove),
      CGRect(x: 15, y: 5, width: 30, height: 10)
    )
  }
}
