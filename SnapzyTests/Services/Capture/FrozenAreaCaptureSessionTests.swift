//
//  FrozenAreaCaptureSessionTests.swift
//  SnapzyTests
//
//  Unit tests for FrozenAreaCaptureSession crop math and pixel alignment.
//

import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class FrozenAreaCaptureSessionTests: XCTestCase {

  // MARK: - Helpers

  /// Create a test session with a single display snapshot.
  private func makeSession(
    displayID: CGDirectDisplayID = 1,
    width: Int = 200,
    height: Int = 200,
    scaleFactor: CGFloat = 2.0,
    screenOriginX: CGFloat = 0,
    screenOriginY: CGFloat = 0
  ) -> FrozenAreaCaptureSession? {
    guard let image = TestImageFactory.solidColor(
      width: Int(CGFloat(width) * scaleFactor),
      height: Int(CGFloat(height) * scaleFactor),
      red: 100, green: 150, blue: 200
    ) else {
      return nil
    }

    let snapshot = FrozenDisplaySnapshot(
      displayID: displayID,
      screenFrame: CGRect(
        x: screenOriginX,
        y: screenOriginY,
        width: CGFloat(width),
        height: CGFloat(height)
      ),
      scaleFactor: scaleFactor,
      colorSpaceName: nil,
      image: image
    )

    return FrozenAreaCaptureSession.fromSnapshot(snapshot)
  }

  /// Create an AreaSelectionResult for testing.
  private func makeSelection(
    rect: CGRect,
    displayID: CGDirectDisplayID = 1
  ) -> AreaSelectionResult {
    AreaSelectionResult(
      target: .rect(rect),
      displayID: displayID,
      mode: .screenshot
    )
  }

  // MARK: - Valid Crop

  func testCropImage_validSelectionInsideBounds_returnsCroppedImage() throws {
    guard let session = makeSession() else {
      XCTFail("Failed to create test session")
      return
    }

    let selection = makeSelection(rect: CGRect(x: 10, y: 10, width: 50, height: 50))
    let result = try session.cropImage(for: selection)

    // At 2x scale, a 50x50 pt selection → ~100x100 px image
    XCTAssertEqual(result.scaleFactor, 2.0)
    XCTAssertGreaterThan(result.image.width, 0)
    XCTAssertGreaterThan(result.image.height, 0)
    // Pixel dimensions should be approximately 100x100
    XCTAssertEqual(result.image.width, 100)
    XCTAssertEqual(result.image.height, 100)
  }

  func testCropImage_fullScreenSelection_returnsFullImage() throws {
    guard let session = makeSession() else {
      XCTFail("Failed to create test session")
      return
    }

    let selection = makeSelection(rect: CGRect(x: 0, y: 0, width: 200, height: 200))
    let result = try session.cropImage(for: selection)

    XCTAssertEqual(result.image.width, 400) // 200 * 2
    XCTAssertEqual(result.image.height, 400)
  }

  // MARK: - Partial Overlap

  func testCropImage_selectionPartiallyOutsideBounds_returnsClamped() throws {
    guard let session = makeSession() else {
      XCTFail("Failed to create test session")
      return
    }

    // Selection extends beyond right and bottom edges (200pt screen, 160+100=260pt)
    let selection = makeSelection(rect: CGRect(x: 160, y: 160, width: 100, height: 100))
    let result = try session.cropImage(for: selection)

    // Clamped region should be smaller than the requested 100x100 pt
    // At 2x scale, 40pt → 80px, but pixel alignment may adjust slightly
    XCTAssertLessThanOrEqual(result.image.width, 80)
    XCTAssertLessThanOrEqual(result.image.height, 80)
    XCTAssertGreaterThan(result.image.width, 0)
    XCTAssertGreaterThan(result.image.height, 0)
  }

  // MARK: - Completely Outside

  func testCropImage_selectionCompletelyOutsideBounds_throws() {
    guard let session = makeSession() else {
      XCTFail("Failed to create test session")
      return
    }

    let selection = makeSelection(rect: CGRect(x: 500, y: 500, width: 50, height: 50))

    XCTAssertThrowsError(try session.cropImage(for: selection)) { error in
      XCTAssertTrue(error is CaptureError)
    }
  }

  // MARK: - Unknown Display

  func testCropImage_unknownDisplayID_throws() {
    guard let session = makeSession(displayID: 1) else {
      XCTFail("Failed to create test session")
      return
    }

    // Use a different displayID that doesn't exist in the session
    let selection = makeSelection(rect: CGRect(x: 0, y: 0, width: 50, height: 50), displayID: 999)

    XCTAssertThrowsError(try session.cropImage(for: selection)) { error in
      XCTAssertTrue(error is CaptureError)
    }
  }

  // MARK: - Scale Factors

  func testCropImage_at1xScaleFactor() throws {
    guard let session = makeSession(width: 100, height: 100, scaleFactor: 1.0) else {
      XCTFail("Failed to create test session")
      return
    }

    let selection = makeSelection(rect: CGRect(x: 10, y: 10, width: 30, height: 30))
    let result = try session.cropImage(for: selection)

    XCTAssertEqual(result.scaleFactor, 1.0)
    XCTAssertEqual(result.image.width, 30)
    XCTAssertEqual(result.image.height, 30)
  }

  // MARK: - Very Small Selection

  func testCropImage_verySmallSelection_returnsMinimalImage() throws {
    guard let session = makeSession(scaleFactor: 2.0) else {
      XCTFail("Failed to create test session")
      return
    }

    // 1x1 pt selection at 2x → should produce at least 2x2 px
    let selection = makeSelection(rect: CGRect(x: 50, y: 50, width: 1, height: 1))
    let result = try session.cropImage(for: selection)

    XCTAssertGreaterThanOrEqual(result.image.width, 1)
    XCTAssertGreaterThanOrEqual(result.image.height, 1)
  }

  // MARK: - Invalidate

  func testInvalidate_thenCrop_throws() {
    guard let session = makeSession() else {
      XCTFail("Failed to create test session")
      return
    }

    session.invalidate()

    let selection = makeSelection(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
    XCTAssertThrowsError(try session.cropImage(for: selection))
  }

  // MARK: - Backdrops

  func testBackdrops_returnsBackdropForEachDisplay() {
    guard let session = makeSession(displayID: 42) else {
      XCTFail("Failed to create test session")
      return
    }

    let backdrops = session.backdrops
    XCTAssertEqual(backdrops.count, 1)
    XCTAssertNotNil(backdrops[42])
    XCTAssertEqual(backdrops[42]?.displayID, 42)
    XCTAssertEqual(backdrops[42]?.scaleFactor, 2.0)
  }

  // MARK: - Non-zero Screen Origin

  func testCropImage_withNonZeroScreenOrigin_adjustsCorrectly() throws {
    // Simulate a secondary display with origin at (1920, 0)
    guard let session = makeSession(
      displayID: 2,
      width: 100,
      height: 100,
      scaleFactor: 2.0,
      screenOriginX: 1920,
      screenOriginY: 0
    ) else {
      XCTFail("Failed to create test session")
      return
    }

    // Selection in global coordinates on the second display
    let selection = makeSelection(
      rect: CGRect(x: 1930, y: 10, width: 50, height: 50),
      displayID: 2
    )
    let result = try session.cropImage(for: selection)

    // 50x50 pt at 2x → 100x100 px
    XCTAssertEqual(result.image.width, 100)
    XCTAssertEqual(result.image.height, 100)
  }
}
