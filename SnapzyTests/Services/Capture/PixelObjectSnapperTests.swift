//
//  PixelObjectSnapperTests.swift
//  SnapzyTests
//
//  Pixel-space object snapping used by Capture Subject's PixelSnap-style preview.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PixelObjectSnapperTests: XCTestCase {
  func testSnapsToCenteredRectangle() throws {
    let image = try XCTUnwrap(
      TestImageFactory.solidWithRects(
        width: 100,
        height: 80,
        backgroundGray: 255,
        rects: [(rect: CGRect(x: 20, y: 15, width: 40, height: 30), gray: 0)]
      )
    )

    let bounds = try XCTUnwrap(
      PixelObjectSnapper.objectBounds(
        in: image,
        searchRect: CGRect(x: 0, y: 0, width: 100, height: 80)
      )
    )

    XCTAssertEqual(bounds, CGRect(x: 20, y: 15, width: 40, height: 30))
  }

  func testUniformImageReturnsNil() throws {
    let image = try XCTUnwrap(TestImageFactory.solidColor(width: 64, height: 64, red: 200, green: 200, blue: 200))
    let bounds = PixelObjectSnapper.objectBounds(
      in: image,
      searchRect: CGRect(x: 0, y: 0, width: 64, height: 64)
    )
    XCTAssertNil(bounds)
  }

  func testSearchRectClampsToObject() throws {
    let image = try XCTUnwrap(
      TestImageFactory.solidWithRects(
        width: 120,
        height: 120,
        backgroundGray: 240,
        rects: [(rect: CGRect(x: 30, y: 40, width: 50, height: 25), gray: 10)]
      )
    )

    let bounds = try XCTUnwrap(
      PixelObjectSnapper.objectBounds(
        in: image,
        searchRect: CGRect(x: 20, y: 30, width: 80, height: 50)
      )
    )

    XCTAssertEqual(bounds, CGRect(x: 30, y: 40, width: 50, height: 25))
  }

  func testTinySearchReturnsNil() throws {
    let image = try XCTUnwrap(TestImageFactory.solidColor(width: 32, height: 32))
    XCTAssertNil(
      PixelObjectSnapper.objectBounds(
        in: image,
        searchRect: CGRect(x: 4, y: 4, width: 2, height: 2)
      )
    )
  }

  func testNoisyBackgroundSnapsWithDefaultTolerance() throws {
    let image = try XCTUnwrap(
      TestImageFactory.checkerboardWithRects(
        width: 80,
        height: 80,
        evenGray: 220,
        oddGray: 180,
        rects: [(rect: CGRect(x: 20, y: 20, width: 30, height: 24), gray: 0)]
      )
    )

    let tight = PixelObjectSnapper.Options(colorTolerance: 28)
    XCTAssertNil(
      PixelObjectSnapper.objectBounds(
        in: image,
        searchRect: CGRect(x: 0, y: 0, width: 80, height: 80),
        options: tight
      )
    )

    let bounds = try XCTUnwrap(
      PixelObjectSnapper.objectBounds(
        in: image,
        searchRect: CGRect(x: 0, y: 0, width: 80, height: 80)
      )
    )
    XCTAssertEqual(bounds, CGRect(x: 20, y: 20, width: 30, height: 24))
  }
}

final class CaptureSubjectGeometryTests: XCTestCase {
  func testScreenRectFlipsPixelY() throws {
    let image = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 100))
    let captured = CGRect(x: 50, y: 80, width: 100, height: 50)
    let pixel = CGRect(x: 20, y: 10, width: 40, height: 20)

    let screen = CaptureSubjectGeometry.screenRect(
      forPixelRect: pixel,
      image: image,
      capturedScreenRect: captured
    )

    XCTAssertEqual(screen.minX, 60, accuracy: 0.01)
    XCTAssertEqual(screen.width, 20, accuracy: 0.01)
    XCTAssertEqual(screen.height, 10, accuracy: 0.01)
    XCTAssertEqual(screen.maxY, 125, accuracy: 0.01)
  }

  func testPixelRectRoundTrips() throws {
    let image = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 100))
    let captured = CGRect(x: 10, y: 20, width: 100, height: 50)
    let original = CGRect(x: 30, y: 30, width: 40, height: 20)

    let pixel = CaptureSubjectGeometry.pixelRect(
      forScreenRect: original,
      image: image,
      capturedScreenRect: captured
    )
    let roundTrip = CaptureSubjectGeometry.screenRect(
      forPixelRect: pixel,
      image: image,
      capturedScreenRect: captured
    )

    XCTAssertEqual(roundTrip.minX, original.minX, accuracy: 1)
    XCTAssertEqual(roundTrip.minY, original.minY, accuracy: 1)
    XCTAssertEqual(roundTrip.width, original.width, accuracy: 1)
    XCTAssertEqual(roundTrip.height, original.height, accuracy: 1)
  }

  func testSnapTightensCenteredObject() throws {
    let image = try XCTUnwrap(
      TestImageFactory.solidWithRects(
        width: 100,
        height: 80,
        backgroundGray: 255,
        rects: [(rect: CGRect(x: 20, y: 15, width: 40, height: 30), gray: 0)]
      )
    )
    let captured = CGRect(x: 0, y: 0, width: 100, height: 80)
    let snapped = CaptureSubjectSnapper.snap(
      selectionRect: captured,
      in: image,
      capturedScreenRect: captured
    )
    XCTAssertEqual(snapped.screenRect, CGRect(x: 20, y: 35, width: 40, height: 30))
    XCTAssertEqual(snapped.pixelSize, CGSize(width: 40, height: 30))
  }
}
