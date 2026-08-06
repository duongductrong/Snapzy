//
//  InlineAreaMagnifierHostViewTests.swift
//  SnapzyTests
//
//  Unit tests for the coordinate bubble that stands in for plain area screenshot's
//  `updateCoordinateIndicator` while the magnifier is inactive in this SwiftUI-based flow.
//

import AppKit
import XCTest
@testable import Snapzy

final class InlineAreaMagnifierHostViewTests: XCTestCase {

  /// `displayBounds` mirrors what `InlineAreaMagnifierOverlay` pushes in from SwiftUI — tests
  /// must set it explicitly since it's no longer read off `frame`/`bounds` (see
  /// `InlineAreaMagnifierHostView.displayBounds`).
  private func makeView(size: CGSize) -> InlineAreaMagnifierHostView {
    let view = InlineAreaMagnifierHostView(frame: CGRect(origin: .zero, size: size))
    view.displayBounds = CGRect(origin: .zero, size: size)
    return view
  }

  private func makeSolidColorImage(size: CGSize) -> CGImage {
    let width = Int(size.width)
    let height = Int(size.height)
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )
    context?.setFillColor(NSColor.white.cgColor)
    context?.fill(CGRect(origin: .zero, size: size))
    return context!.makeImage()!
  }

  func testCoordinateBubble_visibleWhileMagnifierInactive() {
    let view = makeView(size: CGSize(width: 800, height: 600))
    view.backdropImage = makeSolidColorImage(size: CGSize(width: 800, height: 600))

    // Magnifier stays at its default (inactive) zoom.
    view.update(at: CGPoint(x: 200, y: 150))

    XCTAssertFalse(view.coordinateBubbleBackgroundLayer?.isHidden ?? true)
    XCTAssertFalse(view.coordinateBubbleTextLayer?.isHidden ?? true)
    // Same single-line "x, y" format and solid-pill style (`CoordinateBubbleStyle`) as plain
    // area screenshot's coordinate indicator (top-left origin reporting: 600 - 150 = 450).
    XCTAssertEqual(view.coordinateBubbleTextLayer?.string as? String, "200, 450")
    XCTAssertEqual(view.coordinateBubbleBackgroundLayer?.backgroundColor, CoordinateBubbleStyle.backgroundColor.cgColor)
  }

  func testCoordinateBubble_hidesOnceMagnifierBecomesActive() {
    let view = makeView(size: CGSize(width: 800, height: 600))
    view.backdropImage = makeSolidColorImage(size: CGSize(width: 800, height: 600))

    view.update(at: CGPoint(x: 200, y: 150))
    XCTAssertFalse(view.coordinateBubbleBackgroundLayer?.isHidden ?? true)

    // Activate the magnifier — its own panel (`showsCoordinatesInPanel`) takes over.
    view.applyScroll(delta: 6, hasPreciseScrollingDeltas: false)

    XCTAssertTrue(view.coordinateBubbleBackgroundLayer?.isHidden ?? false)
    XCTAssertTrue(view.coordinateBubbleTextLayer?.isHidden ?? false)
  }

  func testCoordinateBubble_hiddenOnHide() {
    let view = makeView(size: CGSize(width: 800, height: 600))
    view.backdropImage = makeSolidColorImage(size: CGSize(width: 800, height: 600))
    view.update(at: CGPoint(x: 200, y: 150))
    XCTAssertFalse(view.coordinateBubbleBackgroundLayer?.isHidden ?? true)

    view.hide()

    XCTAssertTrue(view.coordinateBubbleBackgroundLayer?.isHidden ?? false)
    XCTAssertTrue(view.coordinateBubbleTextLayer?.isHidden ?? false)
  }

  /// Regression for the magnifier appearing pinned to the bottom-left corner on first render
  /// in screenshot-and-annotate: `AreaSelectionMagnifier.update(bounds:)` clamps the container
  /// into `bounds` and divides by its width/height, so a `.zero` bounds collapses every
  /// position to the origin. `displayBounds` must be used instead of `self.bounds` so this
  /// works correctly even before AppKit has applied the SwiftUI-driven frame — simulated here
  /// by leaving the view's own `frame` at `.zero` while setting `displayBounds` explicitly, the
  /// way `InlineAreaMagnifierOverlay` does before its first `updateNSView` call.
  func testMagnifierPosition_usesDisplayBoundsEvenWhenViewFrameIsStillZero() throws {
    let view = InlineAreaMagnifierHostView(frame: .zero)
    view.displayBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    view.backdropImage = makeSolidColorImage(size: CGSize(width: 800, height: 600))
    view.magnifier.zoom = 6.0

    view.update(at: CGPoint(x: 400, y: 300))

    let origin = try XCTUnwrap(view.magnifier.containerLayer?.frame.origin)
    XCTAssertNotEqual(
      origin, .zero,
      "magnifier must not be pinned to the origin when displayBounds is set, regardless of the AppKit view's own (possibly not-yet-laid-out) frame"
    )
  }
}
