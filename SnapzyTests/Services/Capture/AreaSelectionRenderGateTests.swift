//
//  AreaSelectionRenderGateTests.swift
//  SnapzyTests
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class AreaSelectionRenderGateTests: XCTestCase {
  func testSkipsOnlyWhenNothingDrawnAndNothingToDraw() {
    XCTAssertFalse(AreaSelectionRenderGate.shouldRender(
      hasContentOnScreen: false, pointerIsOverView: false, selectionIntersectsView: false
    ))
  }

  func testRendersWheneverAnyTermHolds() {
    for (content, pointer, intersects) in [
      (true, false, false),
      (false, true, false),
      (false, false, true),
      (true, true, true),
    ] {
      XCTAssertTrue(AreaSelectionRenderGate.shouldRender(
        hasContentOnScreen: content, pointerIsOverView: pointer, selectionIntersectsView: intersects
      ), "expected render for (\(content), \(pointer), \(intersects))")
    }
  }

  func testDisplayThePointerLeavesIsClearedExactlyOnceThenSkipped() {
    var hasContent = true
    var renders = 0
    for _ in 0 ..< 5 {
      guard AreaSelectionRenderGate.shouldRender(
        hasContentOnScreen: hasContent, pointerIsOverView: false, selectionIntersectsView: false
      ) else { continue }
      renders += 1
      hasContent = false
    }
    XCTAssertEqual(renders, 1)
  }
}
