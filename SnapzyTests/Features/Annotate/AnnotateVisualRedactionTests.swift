//
//  AnnotateVisualRedactionTests.swift
//  SnapzyTests
//
//  Face/people auto-redaction: Vision box → annotate-space conversion, padding,
//  clamping, and the single-undo-checkpoint insert. The Vision requests
//  themselves are not exercised here (no fixture photos in the test bundle).
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateVisualRedactionTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  func testFaceRegionsAreInAnnotateSpaceAndPaddedMostlyAbove() throws {
    let imageSize = CGSize(width: 1000, height: 500)
    // Normalized, bottom-left origin: x 400...500, y 200...300 in image points.
    let box = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.2)

    let regions = AnnotateSensitiveRedactionService.visualRegions(
      fromVisionBoundingBoxes: [(box, 0.9)],
      target: .faces,
      imageSize: imageSize
    )

    XCTAssertEqual(regions.count, 1)
    let region = try XCTUnwrap(regions.first)
    XCTAssertEqual(region.kind, .face)
    let raw = CGRect(x: 400, y: 200, width: 100, height: 100)
    let bounds = region.bounds
    XCTAssertTrue(bounds.contains(raw))
    // More room above (maxY) than below (minY): forehead and hair.
    XCTAssertGreaterThan(bounds.maxY - raw.maxY, raw.minY - bounds.minY)
  }

  func testRegionsAreClampedToImageAndTinyBoxesDropped() {
    let imageSize = CGSize(width: 200, height: 100)
    let regions = AnnotateSensitiveRedactionService.visualRegions(
      fromVisionBoundingBoxes: [
        (CGRect(x: 0.9, y: 0.8, width: 0.1, height: 0.2), 0.8),
        (CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001), 0.8)
      ],
      target: .people,
      imageSize: imageSize
    )

    XCTAssertEqual(regions.count, 1)
    let bounds = regions[0].bounds
    XCTAssertEqual(regions[0].kind, .person)
    XCTAssertLessThanOrEqual(bounds.maxX, imageSize.width + 0.0001)
    XCTAssertLessThanOrEqual(bounds.maxY, imageSize.height + 0.0001)
    XCTAssertGreaterThanOrEqual(bounds.minX, 0)
  }

  func testSeveralFacesBecomeOneBlurEachAndUndoRemovesThemTogether() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 800, height: 400))
    let boxes: [(boundingBox: CGRect, confidence: Float)] = [
      (CGRect(x: 0.1, y: 0.4, width: 0.08, height: 0.16), 0.9),
      (CGRect(x: 0.4, y: 0.4, width: 0.08, height: 0.16), 0.9),
      (CGRect(x: 0.7, y: 0.4, width: 0.08, height: 0.16), 0.9)
    ]
    let regions = AnnotateSensitiveRedactionService.visualRegions(
      fromVisionBoundingBoxes: boxes,
      target: .faces,
      imageSize: CGSize(width: 800, height: 400)
    )

    let inserted = state.applySensitiveRedactionRegions(regions)

    XCTAssertEqual(inserted, 3)
    XCTAssertEqual(state.annotations.count, 3)
    XCTAssertTrue(state.annotations.allSatisfy {
      if case .blur = $0.type { return true }
      return false
    })

    state.undo()
    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertFalse(state.canUndo)
  }
}
