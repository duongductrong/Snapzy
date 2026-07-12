import CoreGraphics
import XCTest
@testable import Snapzy

final class CombineSnappingTests: XCTestCase {
  func testSnapsToRightEdgeWithoutGap() throws {
    let result = try XCTUnwrap(CombineSnapping.resolve(
      draggedBounds: CGRect(x: 506, y: 1, width: 200, height: 300),
      candidateBounds: [CGRect(x: 0, y: 0, width: 500, height: 300)],
      gap: 0,
      tolerance: 14
    ))
    XCTAssertEqual(result.origin, CGPoint(x: 500, y: 0))
  }

  func testRespectsConfiguredGap() throws {
    let result = try XCTUnwrap(CombineSnapping.resolve(
      draggedBounds: CGRect(x: 514, y: 0, width: 200, height: 300),
      candidateBounds: [CGRect(x: 0, y: 0, width: 500, height: 300)],
      gap: 8,
      tolerance: 14
    ))
    XCTAssertEqual(result.minX, 508)
  }

  func testDoesNotSnapOutsideTolerance() {
    XCTAssertNil(CombineSnapping.resolve(
      draggedBounds: CGRect(x: 530, y: 0, width: 200, height: 300),
      candidateBounds: [CGRect(x: 0, y: 0, width: 500, height: 300)],
      gap: 0,
      tolerance: 14
    ))
  }
}
