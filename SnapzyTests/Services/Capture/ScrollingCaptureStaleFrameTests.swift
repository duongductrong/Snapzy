//
//  ScrollingCaptureStaleFrameTests.swift
//  SnapzyTests
//
//  Unit tests for stitching against a frame that is known to be stale, as when
//  a manual scroll could not be locked before Auto Scroll took over.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ScrollingCaptureStaleFrameTests: XCTestCase {

  private let width = 320
  private let height = 400
  private let step = 40
  private let manualTravel = 160

  func testStaleFrame_offsetFarFromTheStep_isRefused() throws {
    // Only the step is expected, but the page also moved by the manual scroll
    // that never locked. The one confirmed offset is far from the step, and on
    // a repeating layout it could be a repeat, so it must not be committed.
    let stitcher = try startedStitcher()

    let update = try XCTUnwrap(
      stitcher.append(
        frame(offset: manualTravel + step),
        maxOutputHeight: 10_000,
        expectedSignedDeltaPixels: step,
        requiresExpectedTravel: true
      )
    )

    if case .appended(let deltaY) = update.outcome {
      XCTFail("Committed \(deltaY) px against a stale frame")
    }
  }

  func testStaleFrame_manualTravelAddedToTheStep_appends() throws {
    let stitcher = try startedStitcher()

    let update = try XCTUnwrap(
      stitcher.append(
        frame(offset: manualTravel + step),
        maxOutputHeight: 10_000,
        expectedSignedDeltaPixels: manualTravel + step,
        requiresExpectedTravel: true
      )
    )

    guard case .appended(let deltaY) = update.outcome else {
      return XCTFail("Expected an append, got \(update.outcome)")
    }
    XCTAssertEqual(deltaY, manualTravel + step)
  }

  func testCurrentFrame_singleConfirmedOffset_isStillTakenAtAnyDistance() throws {
    // Without a stale frame the frames stay the authority: a page that moved
    // farther than asked is committed where they confirm it.
    let stitcher = try startedStitcher()

    let update = try XCTUnwrap(
      stitcher.append(
        frame(offset: manualTravel + step),
        maxOutputHeight: 10_000,
        expectedSignedDeltaPixels: step
      )
    )

    guard case .appended(let deltaY) = update.outcome else {
      return XCTFail("Expected an append, got \(update.outcome)")
    }
    XCTAssertEqual(deltaY, manualTravel + step)
  }

  func testCommittedStrips_matchTheReferencePage() throws {
    // Strips are copied out of their frames when committed; the output must
    // still be the page, row for row.
    let steps = 12
    let stitcher = try startedStitcher()
    for index in 1 ... steps {
      let update = try XCTUnwrap(
        stitcher.append(frame(offset: index * step), maxOutputHeight: 10_000, expectedSignedDeltaPixels: step)
      )
      guard case .appended = update.outcome else {
        return XCTFail("Step \(index) did not append: \(update.outcome)")
      }
    }

    let merged = try XCTUnwrap(stitcher.mergedImage())
    let reference = try XCTUnwrap(
      TestImageFactory.texturedScrollingFrame(width: width, height: height + step * steps, logicalYOffset: 0)
    )
    XCTAssertEqual(merged.height, reference.height)
    XCTAssertEqual(
      TestImageFactory.rgbaRows(of: merged, rowCount: merged.height),
      TestImageFactory.rgbaRows(of: reference, rowCount: reference.height)
    )
  }

  private func startedStitcher() throws -> ScrollingCaptureStitcher {
    let stitcher = ScrollingCaptureStitcher()
    _ = try stitcher.start(with: frame(offset: 0))
    return stitcher
  }

  private func frame(offset: Int) throws -> CGImage {
    try XCTUnwrap(TestImageFactory.texturedScrollingFrame(width: width, height: height, logicalYOffset: offset))
  }
}
