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
    XCTAssertEqual(second.minY, base.maxY, accuracy: 0.001)
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
}
