import CoreGraphics
import XCTest
@testable import Snapzy

final class CombineImagesLayoutTests: XCTestCase {
  func testHorizontalLayoutMatchesBaseHeightAndHasExactGap() throws {
    let baseID = UUID()
    let secondID = UUID()
    let result = CombineImagesLayout.layout(
      items: [
        CombineImagesLayoutItem(id: baseID, size: CGSize(width: 400, height: 300)),
        CombineImagesLayoutItem(id: secondID, size: CGSize(width: 200, height: 100))
      ],
      direction: .horizontal,
      gap: 12
    )

    let base = try XCTUnwrap(result.boundsByID[baseID])
    let second = try XCTUnwrap(result.boundsByID[secondID])
    XCTAssertEqual(base, CGRect(x: 0, y: 0, width: 400, height: 300))
    XCTAssertEqual(second.height, 300, accuracy: 0.001)
    XCTAssertEqual(second.width, 600, accuracy: 0.001)
    XCTAssertEqual(second.minX - base.maxX, 12, accuracy: 0.001)
  }

  func testVerticalLayoutMatchesBaseWidthAndHasNoGapByDefault() throws {
    let baseID = UUID()
    let secondID = UUID()
    let result = CombineImagesLayout.layout(
      items: [
        CombineImagesLayoutItem(id: baseID, size: CGSize(width: 300, height: 200)),
        CombineImagesLayoutItem(id: secondID, size: CGSize(width: 600, height: 200))
      ],
      direction: .vertical,
      gap: 0
    )

    let base = try XCTUnwrap(result.boundsByID[baseID])
    let second = try XCTUnwrap(result.boundsByID[secondID])
    XCTAssertEqual(second.width, 300, accuracy: 0.001)
    XCTAssertEqual(second.height, 100, accuracy: 0.001)
    // Canvas space is y-up: the next image stacks below the base on screen.
    XCTAssertEqual(second.maxY, base.minY, accuracy: 0.001)
    XCTAssertEqual(base, CGRect(x: 0, y: 0, width: 300, height: 200))
  }

  func testSmartDirectionChoosesHorizontalForPortraitScreenshots() {
    let items = (0 ..< 3).map { _ in
      CombineImagesLayoutItem(id: UUID(), size: CGSize(width: 1170, height: 2532))
    }
    XCTAssertEqual(CombineImagesLayout.resolveDirection(requested: .smart, items: items), .horizontal)
  }

  func testSmartDirectionChoosesVerticalForWideScreenshots() {
    let items = (0 ..< 3).map { _ in
      CombineImagesLayoutItem(id: UUID(), size: CGSize(width: 1600, height: 900))
    }
    XCTAssertEqual(CombineImagesLayout.resolveDirection(requested: .smart, items: items), .vertical)
  }

  // MARK: - Stitch grid

  func testGridInsertSidesJoinRowAndTopBottomOpenRows() {
    let base = UUID(), right = UUID(), below = UUID(), above = UUID(), left = UUID()
    var grid = CombineStitchGrid(rows: [[base]])

    XCTAssertTrue(grid.insert(right, edge: .right, of: base))
    XCTAssertTrue(grid.insert(below, edge: .bottom, of: right))
    XCTAssertTrue(grid.insert(above, edge: .top, of: base))
    XCTAssertTrue(grid.insert(left, edge: .left, of: below))

    XCTAssertEqual(grid.rows, [[above], [base, right], [left, below]])
    XCTAssertNil(grid.stripDirection)
  }

  func testGridInsertMovesExistingIDAndRejectsUnknownAnchor() {
    let a = UUID(), b = UUID(), c = UUID()
    var grid = CombineStitchGrid(rows: [[a, b, c]])

    XCTAssertTrue(grid.insert(a, edge: .right, of: c))
    XCTAssertEqual(grid.rows, [[b, c, a]])
    XCTAssertFalse(grid.insert(a, edge: .left, of: UUID()))
    XCTAssertEqual(grid.rows, [[b, c, a]])
  }

  func testGridReconcileDropsMissingAndAppendsNew() {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    var row = CombineStitchGrid(rows: [[a, b]])
    row.reconcile(with: [a, c])
    XCTAssertEqual(row.rows, [[a, c]])

    var column = CombineStitchGrid(rows: [[a], [b]])
    column.reconcile(with: [a, b, d])
    XCTAssertEqual(column.rows, [[a], [b], [d]])
    XCTAssertEqual(column.stripDirection, .vertical)
  }

  // MARK: - Grid layout

  func testGridLayoutKeepsAnchorNativeAndJustifiesRows() throws {
    let base = UUID(), right = UUID(), below = UUID()
    let grid = CombineStitchGrid(rows: [[base, right], [below]])
    let result = CombineImagesLayout.layout(
      grid: grid,
      sizes: [
        base: CGSize(width: 400, height: 300),
        right: CGSize(width: 200, height: 300),
        below: CGSize(width: 1200, height: 300)
      ],
      anchorID: base,
      gap: 10
    )

    let baseRect = try XCTUnwrap(result.boundsByID[base])
    let rightRect = try XCTUnwrap(result.boundsByID[right])
    let belowRect = try XCTUnwrap(result.boundsByID[below])
    XCTAssertEqual(baseRect, CGRect(x: 0, y: 0, width: 400, height: 300))
    XCTAssertEqual(rightRect.minX - baseRect.maxX, 10, accuracy: 0.001)
    XCTAssertEqual(rightRect.height, 300, accuracy: 0.001)
    // The second row spans the first row's full width (400 + 10 + 200).
    XCTAssertEqual(belowRect.minX, 0, accuracy: 0.001)
    XCTAssertEqual(belowRect.width, 610, accuracy: 0.001)
    XCTAssertEqual(baseRect.minY - belowRect.maxY, 10, accuracy: 0.001)
    XCTAssertEqual(result.contentBounds.width, 610, accuracy: 0.001)
  }

  func testGridLayoutPlacesRowAboveAnchorAtPositiveY() throws {
    let base = UUID(), top = UUID()
    let result = CombineImagesLayout.layout(
      grid: CombineStitchGrid(rows: [[top], [base]]),
      sizes: [base: CGSize(width: 300, height: 200), top: CGSize(width: 300, height: 100)],
      anchorID: base,
      gap: 0
    )

    let baseRect = try XCTUnwrap(result.boundsByID[base])
    let topRect = try XCTUnwrap(result.boundsByID[top])
    XCTAssertEqual(baseRect, CGRect(x: 0, y: 0, width: 300, height: 200))
    XCTAssertEqual(topRect.minY, baseRect.maxY, accuracy: 0.001)
  }

  // MARK: - Drop resolver

  func testResolverStitchesNearEdgesAndOverlaysInCentre() {
    let base = UUID()
    let layers = [(id: base, rect: CGRect(x: 0, y: 0, width: 400, height: 300))]

    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 390, y: 150), layers: layers),
      .stitch(anchor: base, edge: .right)
    )
    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 200, y: 10), layers: layers),
      .stitch(anchor: base, edge: .bottom)
    )
    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 200, y: 290), layers: layers),
      .stitch(anchor: base, edge: .top)
    )
    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 200, y: 140), layers: layers),
      .overlay(at: CGPoint(x: 200, y: 140))
    )
    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 200, y: 140), layers: layers, allowsOverlay: false),
      .stitch(anchor: base, edge: .bottom)
    )
  }

  func testResolverOutsideContentPicksNearestImageAndSide() {
    let a = UUID(), b = UUID()
    let layers = [
      (id: a, rect: CGRect(x: 0, y: 0, width: 400, height: 300)),
      (id: b, rect: CGRect(x: 400, y: 0, width: 200, height: 300))
    ]

    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 500, y: -80), layers: layers),
      .stitch(anchor: b, edge: .bottom)
    )
    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: -50, y: 120), layers: layers),
      .stitch(anchor: a, edge: .left)
    )
    XCTAssertEqual(
      CombineDropResolver.resolve(point: CGPoint(x: 100, y: 360), layers: layers),
      .stitch(anchor: a, edge: .top)
    )
    XCTAssertNil(CombineDropResolver.resolve(point: .zero, layers: []))
  }
}
