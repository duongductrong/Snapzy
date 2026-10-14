//
//  ScrollingCaptureWindowCaptureTests.swift
//  SnapzyTests
//
//  Unit tests for scrolling capture of a whole app window, where large static
//  areas such as a toolbar and a sidebar surround the scrolling content.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ScrollingCaptureWindowCaptureTests: XCTestCase {

  private let width = 320
  private let height = 400
  private let toolbarHeight = 60
  private let sidebarWidth = 110

  // MARK: - Detector

  func testDetectSides_findsWideSidebar() throws {
    let sides = ScrollingCaptureStickyEdgeDetector.detectSides(
      previous: try lumaPlane(offset: 0),
      current: try lumaPlane(offset: 40),
      rowStart: toolbarHeight,
      rowEnd: height
    )

    XCTAssertGreaterThanOrEqual(sides.leading, sidebarWidth)
    XCTAssertEqual(sides.trailing, 0)
  }

  func testDetectSides_scrollingContentHasNoStaticSides() throws {
    let previous = try XCTUnwrap(
      ScrollingCaptureLumaPlane(
        cgImage: try XCTUnwrap(TestImageFactory.texturedScrollingFrame(width: width, height: height, logicalYOffset: 0))
      )
    )
    let current = try XCTUnwrap(
      ScrollingCaptureLumaPlane(
        cgImage: try XCTUnwrap(TestImageFactory.texturedScrollingFrame(width: width, height: height, logicalYOffset: 40))
      )
    )

    let sides = ScrollingCaptureStickyEdgeDetector.detectSides(
      previous: previous,
      current: current,
      rowStart: 0,
      rowEnd: height
    )

    XCTAssertEqual(sides, .none)
  }

  // MARK: - Stitcher

  func testStitch_windowWithWideSidebar_appendsEveryStep() throws {
    let step = 40
    let steps = 8
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try frame(offset: 0))

    for index in 1...steps {
      let update = try XCTUnwrap(
        stitcher.append(try frame(offset: index * step), maxOutputHeight: 10_000, expectedSignedDeltaPixels: step)
      )
      guard case .appended(let deltaY) = update.outcome else {
        return XCTFail("Step \(index) did not append: \(update.outcome)")
      }
      XCTAssertEqual(deltaY, step)
    }

    let merged = try XCTUnwrap(stitcher.mergedImage())
    let reference = try XCTUnwrap(
      TestImageFactory.windowScrollingFrame(
        width: width,
        height: height + step * steps,
        logicalYOffset: 0,
        toolbarHeight: toolbarHeight,
        sidebarWidth: sidebarWidth
      )
    )
    XCTAssertEqual(merged.height, reference.height)
    // The sidebar is stitched from whichever frame each strip came from, so
    // only the scrolling columns have a single right answer.
    XCTAssertEqual(contentColumns(of: merged), contentColumns(of: reference))
  }

  func testStitch_sparsePageSmallScroll_isNotMistakenForBoundary() throws {
    let step = 16
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try sparseFrame(offset: 0))

    for index in 1...6 {
      let update = try XCTUnwrap(
        stitcher.append(try sparseFrame(offset: index * step), maxOutputHeight: 10_000, expectedSignedDeltaPixels: step)
      )
      XCTAssertFalse(update.likelyReachedBoundary, "Step \(index) was reported as the end of the page")
      guard case .appended(let deltaY) = update.outcome else {
        return XCTFail("Step \(index) did not append: \(update.outcome)")
      }
      XCTAssertEqual(deltaY, step)
    }

    let merged = try XCTUnwrap(stitcher.mergedImage())
    let reference = try XCTUnwrap(
      TestImageFactory.sparseTextScrollingFrame(width: width, height: height + step * 6, logicalYOffset: 0)
    )
    XCTAssertEqual(
      TestImageFactory.rgbaRows(of: merged, rowCount: merged.height),
      TestImageFactory.rgbaRows(of: reference, rowCount: reference.height)
    )
  }

  func testStitch_sparsePageWithoutScroll_isStillABoundary() throws {
    let stitcher = ScrollingCaptureStitcher()
    let frame = try sparseFrame(offset: 0)
    _ = stitcher.start(with: frame)

    let update = try XCTUnwrap(stitcher.append(frame, maxOutputHeight: 10_000, expectedSignedDeltaPixels: 16))

    guard case .ignoredNoMovement = update.outcome else {
      return XCTFail("Expected no movement, got \(update.outcome)")
    }
    XCTAssertTrue(update.likelyReachedBoundary)
  }

  func testStitch_sparsePageLongScroll_stillAppends() throws {
    // A step close to half the viewport, as Auto Scroll takes on a tall window.
    // Chrome measured from a single frame pair used to report bands hundreds of
    // pixels deep on a page this flat, leaving no overlap left to match.
    let step = height * 45 / 100
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try sparseFrame(offset: 0))

    for index in 1...4 {
      let update = try XCTUnwrap(
        stitcher.append(try sparseFrame(offset: index * step), maxOutputHeight: 30_000, expectedSignedDeltaPixels: -step)
      )
      guard case .appended(let deltaY) = update.outcome else {
        return XCTFail("Long step \(index) did not append: \(update.outcome)")
      }
      XCTAssertEqual(deltaY, step)
    }
  }

  func testStitch_chromeCoversMostOfTheFrame_stillAppends() throws {
    // A whole browser window: tab bar, address bar, page header and a prompt
    // box are all fixed, so more than half the frame never moves. Those rows
    // cannot agree at any offset, and judging them alongside the content voted
    // the true offset down.
    let header = height * 40 / 100
    let footer = height * 20 / 100
    let step = 40
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try chromeFrame(offset: 0, header: header, footer: footer))

    for index in 1...5 {
      let update = try XCTUnwrap(
        stitcher.append(
          try chromeFrame(offset: index * step, header: header, footer: footer),
          maxOutputHeight: 30_000,
          expectedSignedDeltaPixels: -step
        )
      )
      guard case .appended(let deltaY) = update.outcome else {
        return XCTFail("Step \(index) did not append: \(update.outcome)")
      }
      XCTAssertEqual(deltaY, step)
    }
  }

  func testDetectSides_blankMarginsAreNotASidebar() throws {
    // Wide blank margins carry no verdict either way. Skipping over them let a
    // thin fixed line at the very edge drag the band across everything in
    // between, which read as a sidebar taking most of the frame.
    let previous = try XCTUnwrap(
      ScrollingCaptureLumaPlane(cgImage: try centredFrame(offset: 0))
    )
    let current = try XCTUnwrap(
      ScrollingCaptureLumaPlane(cgImage: try centredFrame(offset: 60))
    )

    let sides = ScrollingCaptureStickyEdgeDetector.detectSides(
      previous: previous,
      current: current,
      rowStart: 0,
      rowEnd: height
    )

    XCTAssertLessThan(sides.leading, width / 4)
    XCTAssertLessThan(sides.trailing, width / 4)
  }

  func testStitch_centredColumnWithBlankMargins_appendsEveryStep() throws {
    let step = 60
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: try centredFrame(offset: 0))

    for index in 1...5 {
      let update = try XCTUnwrap(
        stitcher.append(
          try centredFrame(offset: index * step),
          maxOutputHeight: 30_000,
          expectedSignedDeltaPixels: -step
        )
      )
      guard case .appended(let deltaY) = update.outcome else {
        return XCTFail("Step \(index) did not append: \(update.outcome)")
      }
      XCTAssertEqual(deltaY, step)
    }
  }

  // MARK: - Helpers

  func testStitch_blankViewportThatStopped_reachesTheEnd() throws {
    // Blank page scrolling and blank page standing still look the same, so the
    // stitcher may cross some of it, but not forever: a page that ends in white
    // space used to be extended until the height limit, and Auto Scroll never
    // saw the end.
    let blank = try XCTUnwrap(
      TestImageFactory.solidColor(width: width, height: height, red: 255, green: 255, blue: 255)
    )
    let stitcher = ScrollingCaptureStitcher()
    _ = stitcher.start(with: blank)

    var appendedRows = 0
    var quietSteps = 0
    for _ in 0 ..< 30 {
      let update = try XCTUnwrap(stitcher.append(blank, maxOutputHeight: 10_000, expectedSignedDeltaPixels: 48))
      switch update.outcome {
      case .appended(let deltaY):
        XCTAssertEqual(quietSteps, 0, "Appended again after reporting the end")
        appendedRows += deltaY
      case .ignoredNoMovement:
        XCTAssertTrue(update.likelyReachedBoundary)
        quietSteps += 1
      default:
        XCTFail("Unexpected outcome \(update.outcome)")
      }
    }

    XCTAssertLessThanOrEqual(appendedRows, height)
    XCTAssertGreaterThanOrEqual(quietSteps, ScrollingCaptureAutoScrollPolicy.noMovementFinishThreshold)
  }

  func testStitch_contentAfterBlankStretch_resetsTheBlankAllowance() throws {
    // A page whose content scrolls into a long blank stretch and stops there.
    let contentRows = 520
    func pageFrame(offset: Int) throws -> CGImage {
      let content = try XCTUnwrap(
        TestImageFactory.texturedScrollingFrame(width: width, height: height, logicalYOffset: offset)
      )
      let context = try XCTUnwrap(
        CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      )
      context.draw(content, in: CGRect(x: 0, y: 0, width: width, height: height))
      let blankFromRow = max(0, contentRows - offset)
      if blankFromRow < height {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height - blankFromRow))
      }
      return try XCTUnwrap(context.makeImage())
    }

    let step = 40
    let stitcher = ScrollingCaptureStitcher()
    _ = try stitcher.start(with: pageFrame(offset: 0))
    var offset = 0
    while offset < contentRows {
      offset += step
      let update = try XCTUnwrap(
        stitcher.append(pageFrame(offset: offset), maxOutputHeight: 10_000, expectedSignedDeltaPixels: step)
      )
      guard case .appended = update.outcome else {
        return XCTFail("Scrolling content at \(offset) did not append: \(update.outcome)")
      }
    }

    let heightAtEnd = try XCTUnwrap(
      stitcher.append(pageFrame(offset: offset), maxOutputHeight: 10_000)
    ).outputHeight
    var finalUpdate: ScrollingCaptureStitchUpdate?
    for _ in 0 ..< 20 {
      finalUpdate = try XCTUnwrap(
        stitcher.append(pageFrame(offset: offset), maxOutputHeight: 10_000, expectedSignedDeltaPixels: step)
      )
    }

    let update = try XCTUnwrap(finalUpdate)
    guard case .ignoredNoMovement = update.outcome else {
      return XCTFail("A stalled blank end kept appending: \(update.outcome)")
    }
    XCTAssertTrue(update.likelyReachedBoundary)
    XCTAssertLessThanOrEqual(update.outputHeight - heightAtEnd, height)
  }

  func testStitch_minimumAutoScrollStepOnA1xDisplay_appendsEveryStep() throws {
    // The smallest step Auto Scroll posts, at 1 px per point. A single 8 px
    // tick never aligned here.
    let frameHeight = 140
    let step = Int(
      ScrollingCaptureAutoScrollPolicy.stepPlan(regionHeight: CGFloat(frameHeight), isRetry: true).postedDistancePoints
    )
    XCTAssertGreaterThan(step, 8)
    let stitcher = ScrollingCaptureStitcher()
    _ = try stitcher.start(with: XCTUnwrap(
      TestImageFactory.sparseTextScrollingFrame(width: width, height: frameHeight, logicalYOffset: 0)
    ))

    for index in 1 ... 10 {
      let image = try XCTUnwrap(
        TestImageFactory.sparseTextScrollingFrame(width: width, height: frameHeight, logicalYOffset: index * step)
      )
      let update = try XCTUnwrap(stitcher.append(image, maxOutputHeight: 10_000, expectedSignedDeltaPixels: step))
      guard case .appended(let deltaY) = update.outcome else {
        return XCTFail("Step \(index) did not append: \(update.outcome)")
      }
      XCTAssertEqual(deltaY, step)
    }
  }

  private func centredFrame(offset: Int) throws -> CGImage {
    try XCTUnwrap(
      TestImageFactory.centredColumnScrollingFrame(width: width, height: height, logicalYOffset: offset)
    )
  }

  private func chromeFrame(offset: Int, header: Int, footer: Int) throws -> CGImage {
    try XCTUnwrap(
      TestImageFactory.chromeScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: offset,
        headerHeight: header,
        footerHeight: footer
      )
    )
  }

  private func sparseFrame(offset: Int) throws -> CGImage {
    try XCTUnwrap(TestImageFactory.sparseTextScrollingFrame(width: width, height: height, logicalYOffset: offset))
  }

  private func frame(offset: Int) throws -> CGImage {
    try XCTUnwrap(
      TestImageFactory.windowScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: offset,
        toolbarHeight: toolbarHeight,
        sidebarWidth: sidebarWidth
      )
    )
  }

  private func lumaPlane(offset: Int) throws -> ScrollingCaptureLumaPlane {
    try XCTUnwrap(ScrollingCaptureLumaPlane(cgImage: try frame(offset: offset)))
  }

  /// RGBA bytes of every row, limited to the columns right of the sidebar.
  private func contentColumns(of image: CGImage) -> [UInt8] {
    let bytes = TestImageFactory.rgbaRows(of: image, rowCount: image.height)
    let bytesPerRow = image.width * 4
    var columns: [UInt8] = []
    for row in 0..<image.height {
      let start = row * bytesPerRow + sidebarWidth * 4
      columns.append(contentsOf: bytes[start..<((row + 1) * bytesPerRow)])
    }
    return columns
  }
}
