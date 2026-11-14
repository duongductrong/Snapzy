//
//  AnnotateImageRotationTests.swift
//  SnapzyTests
//
//  Unit tests for 90° point/rect rotation helpers used by the editor rotation tools.
//  Coordinate system is bottom-left origin (y-up), matching AppKit annotation storage.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateImageRotationTests: XCTestCase {
  private let imageSize = CGSize(width: 400, height: 200)
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  // MARK: - rotatePoint

  func testRotatePoint_clockwise_bottomLeftCornerMovesToTopLeft() {
    let rotated = AnnotateImageRotation.rotatePoint(.zero, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(rotated, CGPoint(x: 0, y: imageSize.width))
  }

  func testRotatePoint_clockwise_bottomRightCornerMovesToBottomLeft() {
    let rotated = AnnotateImageRotation.rotatePoint(
      CGPoint(x: imageSize.width, y: 0),
      oldSize: imageSize,
      clockwise: true
    )
    XCTAssertEqual(rotated, .zero)
  }

  func testRotatePoint_clockwise_topRightCornerMovesToBottomRight() {
    let rotated = AnnotateImageRotation.rotatePoint(
      CGPoint(x: imageSize.width, y: imageSize.height),
      oldSize: imageSize,
      clockwise: true
    )
    XCTAssertEqual(rotated, CGPoint(x: imageSize.height, y: 0))
  }

  func testRotatePoint_counterClockwise_bottomLeftCornerMovesToBottomRight() {
    let rotated = AnnotateImageRotation.rotatePoint(.zero, oldSize: imageSize, clockwise: false)
    XCTAssertEqual(rotated, CGPoint(x: imageSize.height, y: 0))
  }

  func testRotatePoint_counterClockwise_topLeftCornerMovesToBottomLeft() {
    let rotated = AnnotateImageRotation.rotatePoint(
      CGPoint(x: 0, y: imageSize.height),
      oldSize: imageSize,
      clockwise: false
    )
    XCTAssertEqual(rotated, .zero)
  }

  func testRotatePoint_fourClockwiseRotationsReturnsToOriginal() {
    let point = CGPoint(x: 137, y: 92)
    let pass1 = AnnotateImageRotation.rotatePoint(point, oldSize: imageSize, clockwise: true)
    let pass2 = AnnotateImageRotation.rotatePoint(
      pass1,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: true
    )
    let pass3 = AnnotateImageRotation.rotatePoint(pass2, oldSize: imageSize, clockwise: true)
    let pass4 = AnnotateImageRotation.rotatePoint(
      pass3,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: true
    )
    XCTAssertEqual(pass4, point)
  }

  func testRotatePoint_clockwiseThenCounterClockwiseReturnsToOriginal() {
    let point = CGPoint(x: 137, y: 92)
    let forward = AnnotateImageRotation.rotatePoint(point, oldSize: imageSize, clockwise: true)
    let back = AnnotateImageRotation.rotatePoint(
      forward,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: false
    )
    XCTAssertEqual(back, point)
  }

  // MARK: - rotateRect

  func testRotateRect_clockwise_swapsDimensionsAndRepositions() {
    let rect = CGRect(x: 10, y: 20, width: 80, height: 60)
    let rotated = AnnotateImageRotation.rotateRect(rect, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(
      rotated,
      CGRect(
        x: rect.minY,
        y: imageSize.width - rect.minX - rect.width,
        width: rect.height,
        height: rect.width
      )
    )
  }

  func testRotateRect_counterClockwise_swapsDimensionsAndRepositions() {
    let rect = CGRect(x: 10, y: 20, width: 80, height: 60)
    let rotated = AnnotateImageRotation.rotateRect(rect, oldSize: imageSize, clockwise: false)
    XCTAssertEqual(
      rotated,
      CGRect(
        x: imageSize.height - rect.minY - rect.height,
        y: rect.minX,
        width: rect.height,
        height: rect.width
      )
    )
  }

  func testRotateRect_fullImageRectClockwiseProducesFullRotatedCanvas() {
    let fullRect = CGRect(origin: .zero, size: imageSize)
    let rotated = AnnotateImageRotation.rotateRect(fullRect, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(rotated, CGRect(x: 0, y: 0, width: imageSize.height, height: imageSize.width))
  }

  func testRotateRect_handlesNonStandardRectByStandardising() {
    let nonStandard = CGRect(x: 100, y: 90, width: -40, height: -20)
    let expectedStandardised = nonStandard.standardized
    let rotated = AnnotateImageRotation.rotateRect(nonStandard, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(rotated.width, expectedStandardised.height)
    XCTAssertEqual(rotated.height, expectedStandardised.width)
  }

  func testRotateLayoutRectPreservingSize_clockwiseMovesCenterWithoutSwappingDimensions() {
    let rect = CGRect(x: 100, y: 80, width: 120, height: 30)
    let rotated = AnnotateImageRotation.rotateLayoutRectPreservingSize(rect, oldSize: imageSize, clockwise: true)

    XCTAssertEqual(rotated.size, rect.size)
    XCTAssertEqual(rotated.midX, rect.midY)
    XCTAssertEqual(rotated.midY, imageSize.width - rect.midX)
  }

  func testRotateLayoutRectPreservingSize_clockwiseThenCounterClockwiseReturnsToOriginal() {
    let rect = CGRect(x: 100, y: 80, width: 120, height: 30)
    let clockwise = AnnotateImageRotation.rotateLayoutRectPreservingSize(
      rect,
      oldSize: imageSize,
      clockwise: true
    )
    let restored = AnnotateImageRotation.rotateLayoutRectPreservingSize(
      clockwise,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: false
    )

    XCTAssertEqual(restored, rect)
  }

  // MARK: - NSImage.rotated90

  func testNSImageRotated90Clockwise_swapsLogicalPointSize() {
    let image = makeImage(width: 200, height: 100)
    let rotated = image.rotated90(clockwise: true)
    XCTAssertNotNil(rotated)
    XCTAssertEqual(rotated?.size, NSSize(width: 100, height: 200))
  }

  func testNSImageRotated90CounterClockwise_swapsLogicalPointSize() {
    let image = makeImage(width: 200, height: 100)
    let rotated = image.rotated90(clockwise: false)
    XCTAssertNotNil(rotated)
    XCTAssertEqual(rotated?.size, NSSize(width: 100, height: 200))
  }

  func testNSImageRotated90Twice_preservesOriginalAspectRatio() {
    let image = makeImage(width: 300, height: 100)
    let rotated = image.rotated90(clockwise: true)?.rotated90(clockwise: true)
    XCTAssertEqual(rotated?.size, NSSize(width: 300, height: 100))
  }

  func testNSImageRotated90Clockwise_matchesBottomLeftAnnotationGeometry() throws {
    let image = makeCornerMarkerImage()
    let rotated = try XCTUnwrap(image.rotated90(clockwise: true))
    let cgImage = try XCTUnwrap(rotated.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let pixels = try rgbaBytes(from: cgImage)

    XCTAssertEqual(
      AnnotateImageRotation.rotatePoint(CGPoint(x: 0, y: 2), oldSize: CGSize(width: 3, height: 2), clockwise: true),
      CGPoint(x: 2, y: 3)
    )

    XCTAssertPixel(
      pixels,
      at: CGPoint(x: 1, y: 0),
      width: cgImage.width,
      equals: MarkerColor.topLeftRed,
      "Clockwise image rotation should move the old top-left marker to the new top-right."
    )
    XCTAssertPixel(
      pixels,
      at: CGPoint(x: 1, y: 2),
      width: cgImage.width,
      equals: MarkerColor.topRightGreen,
      "Clockwise image rotation should move the old top-right marker to the new bottom-right."
    )
  }

  func testNSImageRotated90CounterClockwise_matchesBottomLeftAnnotationGeometry() throws {
    let image = makeCornerMarkerImage()
    let rotated = try XCTUnwrap(image.rotated90(clockwise: false))
    let cgImage = try XCTUnwrap(rotated.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let pixels = try rgbaBytes(from: cgImage)

    XCTAssertEqual(
      AnnotateImageRotation.rotatePoint(CGPoint(x: 0, y: 2), oldSize: CGSize(width: 3, height: 2), clockwise: false),
      .zero
    )

    XCTAssertPixel(
      pixels,
      at: CGPoint(x: 0, y: 2),
      width: cgImage.width,
      equals: MarkerColor.topLeftRed,
      "Counter-clockwise image rotation should move the old top-left marker to the new bottom-left."
    )
    XCTAssertPixel(
      pixels,
      at: CGPoint(x: 0, y: 0),
      width: cgImage.width,
      equals: MarkerColor.topRightGreen,
      "Counter-clockwise image rotation should move the old top-right marker to the new top-left."
    )
  }

  @MainActor
  func testRotateImage_clockwiseMovesAnnotationItemsWithRenderedCanvas() throws {
    let state = makeAnnotateState()
    state.loadImage(makeImage(width: imageSize.width, height: imageSize.height))
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 20, width: 80, height: 60),
      properties: AnnotationProperties()
    )
    let line = AnnotationItem(
      type: .line(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 120, y: 90)),
      bounds: CGRect(x: 20, y: 30, width: 100, height: 60),
      properties: AnnotationProperties()
    )
    state.annotations = [rectangle, line]
    state.setSelectedAnnotationIds([rectangle.id, line.id])

    state.rotateImage(clockwise: true)

    XCTAssertEqual(state.sourceImage?.size, NSSize(width: imageSize.height, height: imageSize.width))
    XCTAssertEqual(
      try XCTUnwrap(state.annotations.first(where: { $0.id == rectangle.id })).bounds,
      CGRect(x: 20, y: 310, width: 60, height: 80)
    )
    let rotatedLine = try XCTUnwrap(state.annotations.first(where: { $0.id == line.id }))
    guard case .line(let start, let end) = rotatedLine.type else {
      return XCTFail("Expected rotated line annotation.")
    }
    XCTAssertEqual(start, CGPoint(x: 30, y: 380))
    XCTAssertEqual(end, CGPoint(x: 90, y: 280))
    XCTAssertTrue(state.isAnnotationSelected(rectangle.id))
    XCTAssertTrue(state.isAnnotationSelected(line.id))

    state.undo()

    XCTAssertEqual(state.sourceImage?.size, NSSize(width: imageSize.width, height: imageSize.height))
    XCTAssertEqual(try XCTUnwrap(state.annotations.first(where: { $0.id == rectangle.id })).bounds, rectangle.bounds)
    let restoredLine = try XCTUnwrap(state.annotations.first(where: { $0.id == line.id }))
    XCTAssertEqual(restoredLine.bounds, line.bounds)
  }

  @MainActor
  func testRotateImage_clockwiseMovesTextByCenterWithoutShrinkingLayoutWidth() throws {
    let state = makeAnnotateState()
    state.loadImage(makeImage(width: imageSize.width, height: imageSize.height))
    let text = AnnotationItem(
      type: .text("text"),
      bounds: CGRect(x: 100, y: 80, width: 120, height: 30),
      properties: AnnotationProperties(fontSize: 28)
    )
    state.annotations = [text]
    state.setSelectedAnnotationIds([text.id])

    state.rotateImage(clockwise: true)

    let rotated = try XCTUnwrap(state.annotations.first(where: { $0.id == text.id }))
    XCTAssertEqual(rotated.bounds.size, text.bounds.size)
    XCTAssertEqual(rotated.bounds.midX, text.bounds.midY)
    XCTAssertEqual(rotated.bounds.midY, imageSize.width - text.bounds.midX)
    XCTAssertTrue(state.isAnnotationSelected(text.id))

    state.undo()

    let restored = try XCTUnwrap(state.annotations.first(where: { $0.id == text.id }))
    XCTAssertEqual(restored.bounds, text.bounds)
  }

  // MARK: - Flip

  func testFlipPoint_horizontalMirrorsX() {
    XCTAssertEqual(
      AnnotateImageRotation.flipPoint(CGPoint(x: 10, y: 30), size: imageSize, axis: .horizontal),
      CGPoint(x: 390, y: 30)
    )
  }

  func testFlipPoint_verticalMirrorsY() {
    XCTAssertEqual(
      AnnotateImageRotation.flipPoint(CGPoint(x: 10, y: 30), size: imageSize, axis: .vertical),
      CGPoint(x: 10, y: 170)
    )
  }

  func testFlipRect_preservesSizeAndIsInvolution() {
    let rect = CGRect(x: 10, y: 20, width: 80, height: 60)
    for axis in AnnotateImageFlipAxis.allCases {
      let flipped = AnnotateImageRotation.flipRect(rect, size: imageSize, axis: axis)
      XCTAssertEqual(flipped.size, rect.size)
      XCTAssertEqual(AnnotateImageRotation.flipRect(flipped, size: imageSize, axis: axis), rect)
    }
    XCTAssertEqual(
      AnnotateImageRotation.flipRect(rect, size: imageSize, axis: .horizontal),
      CGRect(x: 310, y: 20, width: 80, height: 60)
    )
    XCTAssertEqual(
      AnnotateImageRotation.flipRect(rect, size: imageSize, axis: .vertical),
      CGRect(x: 10, y: 120, width: 80, height: 60)
    )
  }

  func testFlipRect_handlesNonStandardRectByStandardising() {
    let rect = CGRect(x: 90, y: 80, width: -80, height: -60)
    XCTAssertEqual(
      AnnotateImageRotation.flipRect(rect, size: imageSize, axis: .horizontal),
      CGRect(x: 310, y: 20, width: 80, height: 60)
    )
  }

  func testNSImageFlipped_preservesLogicalPointSize() {
    let image = makeImage(width: 200, height: 100)
    XCTAssertEqual(image.flipped(.horizontal)?.size, NSSize(width: 200, height: 100))
    XCTAssertEqual(image.flipped(.vertical)?.size, NSSize(width: 200, height: 100))
  }

  func testNSImageFlippedHorizontal_swapsLeftAndRightMarkers() throws {
    let flipped = try XCTUnwrap(makeCornerMarkerImage().flipped(.horizontal))
    let cgImage = try XCTUnwrap(flipped.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let pixels = try rgbaBytes(from: cgImage)

    XCTAssertPixel(pixels, at: CGPoint(x: 0, y: 0), width: cgImage.width, equals: MarkerColor.topRightGreen,
      "Horizontal flip should move the old top-right marker to the top-left.")
    XCTAssertPixel(pixels, at: CGPoint(x: 2, y: 1), width: cgImage.width, equals: MarkerColor.bottomLeftBlue,
      "Horizontal flip should move the old bottom-left marker to the bottom-right.")
  }

  func testNSImageFlippedVertical_swapsTopAndBottomMarkers() throws {
    let flipped = try XCTUnwrap(makeCornerMarkerImage().flipped(.vertical))
    let cgImage = try XCTUnwrap(flipped.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let pixels = try rgbaBytes(from: cgImage)

    XCTAssertPixel(pixels, at: CGPoint(x: 0, y: 1), width: cgImage.width, equals: MarkerColor.topLeftRed,
      "Vertical flip should move the old top-left marker to the bottom-left.")
    XCTAssertPixel(pixels, at: CGPoint(x: 2, y: 0), width: cgImage.width, equals: MarkerColor.bottomRightYellow,
      "Vertical flip should move the old bottom-right marker to the top-right.")
  }

  @MainActor
  func testFlipImage_horizontalMirrorsAnnotationsAndUndoRestores() throws {
    let state = makeAnnotateState()
    state.loadImage(makeImage(width: imageSize.width, height: imageSize.height))
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 20, width: 80, height: 60),
      properties: AnnotationProperties()
    )
    let line = AnnotationItem(
      type: .line(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 120, y: 90)),
      bounds: CGRect(x: 20, y: 30, width: 100, height: 60),
      properties: AnnotationProperties()
    )
    let text = AnnotationItem(
      type: .text("text"),
      bounds: CGRect(x: 100, y: 80, width: 120, height: 30),
      properties: AnnotationProperties(fontSize: 28)
    )
    state.annotations = [rectangle, line, text]
    state.setSelectedAnnotationIds([rectangle.id])

    state.flipImage(.horizontal)

    XCTAssertEqual(state.sourceImage?.size, NSSize(width: imageSize.width, height: imageSize.height))
    XCTAssertEqual(
      try XCTUnwrap(state.annotations.first(where: { $0.id == rectangle.id })).bounds,
      CGRect(x: 310, y: 20, width: 80, height: 60)
    )
    let flippedLine = try XCTUnwrap(state.annotations.first(where: { $0.id == line.id }))
    guard case .line(let start, let end) = flippedLine.type else {
      return XCTFail("Expected flipped line annotation.")
    }
    XCTAssertEqual(start, CGPoint(x: 380, y: 30))
    XCTAssertEqual(end, CGPoint(x: 280, y: 90))
    let flippedText = try XCTUnwrap(state.annotations.first(where: { $0.id == text.id }))
    XCTAssertEqual(flippedText.bounds, CGRect(x: 180, y: 80, width: 120, height: 30))
    XCTAssertTrue(state.isAnnotationSelected(rectangle.id))
    XCTAssertTrue(state.hasUnsavedChanges)

    state.undo()

    XCTAssertEqual(try XCTUnwrap(state.annotations.first(where: { $0.id == rectangle.id })).bounds, rectangle.bounds)
    XCTAssertEqual(try XCTUnwrap(state.annotations.first(where: { $0.id == line.id })).type, line.type)
    XCTAssertEqual(try XCTUnwrap(state.annotations.first(where: { $0.id == text.id })).bounds, text.bounds)
  }

  @MainActor
  func testFlipImage_verticalTwiceRestoresGeometry() throws {
    let state = makeAnnotateState()
    state.loadImage(makeImage(width: imageSize.width, height: imageSize.height))
    let path = AnnotationItem(
      type: .path([CGPoint(x: 5, y: 10), CGPoint(x: 50, y: 150)]),
      bounds: CGRect(x: 5, y: 10, width: 45, height: 140),
      properties: AnnotationProperties()
    )
    state.annotations = [path]

    state.flipImage(.vertical)
    let once = try XCTUnwrap(state.annotations.first)
    guard case .path(let points) = once.type else { return XCTFail("Expected path.") }
    XCTAssertEqual(points, [CGPoint(x: 5, y: 190), CGPoint(x: 50, y: 50)])
    XCTAssertEqual(once.bounds, CGRect(x: 5, y: 50, width: 45, height: 140))

    state.flipImage(.vertical)
    XCTAssertEqual(state.annotations.first?.type, path.type)
    XCTAssertEqual(state.annotations.first?.bounds, path.bounds)
  }

  // MARK: - Helpers

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeImage(width: CGFloat, height: CGFloat) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }

  private enum MarkerColor {
    static let topLeftRed: [UInt8] = [255, 0, 0, 255]
    static let topRightGreen: [UInt8] = [0, 255, 0, 255]
    static let bottomLeftBlue: [UInt8] = [0, 0, 255, 255]
    static let bottomRightYellow: [UInt8] = [255, 255, 0, 255]
  }

  private func makeCornerMarkerImage() -> NSImage {
    let width = 3
    let height = 2
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    setPixel(MarkerColor.topLeftRed, atX: 0, y: 0, width: width, in: &pixels)
    setPixel(MarkerColor.topRightGreen, atX: 2, y: 0, width: width, in: &pixels)
    setPixel(MarkerColor.bottomLeftBlue, atX: 0, y: 1, width: width, in: &pixels)
    setPixel(MarkerColor.bottomRightYellow, atX: 2, y: 1, width: width, in: &pixels)

    let data = Data(pixels) as CFData
    let provider = CGDataProvider(data: data)!
    let bitmapInfo = CGBitmapInfo(rawValue:
      CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )
    let cgImage = CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo,
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )!
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  private func setPixel(
    _ color: [UInt8],
    atX x: Int,
    y: Int,
    width: Int,
    in pixels: inout [UInt8]
  ) {
    let offset = (y * width + x) * 4
    pixels[offset] = color[0]
    pixels[offset + 1] = color[1]
    pixels[offset + 2] = color[2]
    pixels[offset + 3] = color[3]
  }

  private func rgbaBytes(from cgImage: CGImage) throws -> [UInt8] {
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
      throw NSError(domain: "AnnotateImageRotationTests", code: 1)
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
  }

  private func XCTAssertPixel(
    _ pixels: [UInt8],
    at point: CGPoint,
    width: Int,
    equals expected: [UInt8],
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let offset = (Int(point.y) * width + Int(point.x)) * 4
    XCTAssertEqual(Array(pixels[offset..<offset + 4]), expected, message, file: file, line: line)
  }
}
