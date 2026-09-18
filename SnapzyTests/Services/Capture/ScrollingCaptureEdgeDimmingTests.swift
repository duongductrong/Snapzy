//
//  ScrollingCaptureEdgeDimmingTests.swift
//  SnapzyTests
//
//  Unit tests for bottom-edge fade handling in scrolling capture.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ScrollingCaptureEdgeDimmingTests: XCTestCase {

  private let width = 240
  private let height = 400

  // MARK: - Detector

  func testDimmedDepth_measuresFadedBottomBand() throws {
    let previous = try lumaPlane(offset: 0, fadeDepth: 90)
    let current = try lumaPlane(offset: 40, fadeDepth: 90)

    let depth = try XCTUnwrap(
      ScrollingCaptureEdgeDimmingDetector.dimmedDepth(previous: previous, current: current, offset: 40)
    )

    XCTAssertGreaterThanOrEqual(depth, 70)
    XCTAssertLessThanOrEqual(depth, 90)
  }

  func testDimmedDepth_unfadedPageReportsNoBand() throws {
    let previous = try lumaPlane(offset: 0, fadeDepth: 0)
    let current = try lumaPlane(offset: 40, fadeDepth: 0)

    let depth = ScrollingCaptureEdgeDimmingDetector.dimmedDepth(previous: previous, current: current, offset: 40)

    XCTAssertEqual(depth, 0)
  }

  func testDimmedDepth_zeroOffsetCannotAnswer() throws {
    let frame = try lumaPlane(offset: 0, fadeDepth: 90)

    XCTAssertNil(ScrollingCaptureEdgeDimmingDetector.dimmedDepth(previous: frame, current: frame, offset: 0))
  }

  // MARK: - Stitcher

  func testStitch_fadedPage_keepsFadeOutOfCommittedRows() throws {
    let step = 40
    let steps = 8
    let merged = try stitch(fadeDepth: 90, step: step, steps: steps)

    XCTAssertEqual(merged.height, height + step * steps)

    // Only the final tail comes from the last frame, which still shows the
    // fade. Everything above it must match the unfaded page exactly.
    let reference = try XCTUnwrap(
      TestImageFactory.texturedScrollingFrame(width: width, height: merged.height, logicalYOffset: 0)
    )
    let cleanRows = merged.height - height / 3
    XCTAssertEqual(try rows(of: merged, count: cleanRows), try rows(of: reference, count: cleanRows))
  }

  func testStitch_unfadedPage_matchesReferenceExactly() throws {
    let step = 40
    let steps = 6
    let merged = try stitch(fadeDepth: 0, step: step, steps: steps)

    let reference = try XCTUnwrap(
      TestImageFactory.texturedScrollingFrame(width: width, height: height + step * steps, logicalYOffset: 0)
    )
    XCTAssertEqual(merged.height, reference.height)
    XCTAssertEqual(try rows(of: merged, count: merged.height), try rows(of: reference, count: reference.height))
  }

  func testStitch_outputHeightIncludesUncommittedTail() throws {
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try frame(offset: 0, fadeDepth: 90))

    let update = try XCTUnwrap(
      stitcher.append(try frame(offset: 40, fadeDepth: 90), maxOutputHeight: 10_000, expectedSignedDeltaPixels: 40)
    )

    guard case .appended(let deltaY) = update.outcome else {
      return XCTFail("Expected append, got \(update.outcome)")
    }
    XCTAssertEqual(deltaY, 40)
    XCTAssertEqual(update.outputHeight, height + 40)
    XCTAssertEqual(stitcher.mergedImage()?.height, height + 40)
  }

  // MARK: - Helpers

  private struct StitchFailure: Error {}

  private func stitch(fadeDepth: Int, step: Int, steps: Int) throws -> CGImage {
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try frame(offset: 0, fadeDepth: fadeDepth))

    for index in 1...steps {
      let update = try XCTUnwrap(
        stitcher.append(
          try frame(offset: index * step, fadeDepth: fadeDepth),
          maxOutputHeight: 10_000,
          expectedSignedDeltaPixels: step
        )
      )
      guard case .appended(let deltaY) = update.outcome else {
        XCTFail("Step \(index) did not append: \(update.outcome)")
        throw StitchFailure()
      }
      XCTAssertEqual(deltaY, step)
    }

    return try XCTUnwrap(stitcher.mergedImage())
  }

  private func frame(offset: Int, fadeDepth: Int) throws -> CGImage {
    try XCTUnwrap(
      TestImageFactory.texturedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: offset,
        fadeDepth: fadeDepth
      )
    )
  }

  private func lumaPlane(offset: Int, fadeDepth: Int) throws -> ScrollingCaptureLumaPlane {
    try XCTUnwrap(ScrollingCaptureLumaPlane(cgImage: try frame(offset: offset, fadeDepth: fadeDepth)))
  }

  /// RGBA bytes of the first `count` rows, drawn into a known pixel format.
  private func rows(of image: CGImage, count: Int) throws -> [UInt8] {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
    let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    XCTAssertTrue(drew)
    return Array(pixels[0..<(count * bytesPerRow)])
  }
}
