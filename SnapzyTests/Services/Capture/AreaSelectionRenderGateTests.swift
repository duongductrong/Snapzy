//
//  AreaSelectionRenderGateTests.swift
//  SnapzyTests
//
//  The multi-display render fan-out gate. These stand in for a multi-display rig: the risk in
//  skipping a render is stranding pixels on a display the selection has left, so the clearing
//  pass is pinned explicitly.
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
      (true, false, false),  // must still clear what the last pass drew
      (false, true, false),  // owns crosshair / coordinate / magnifier
      (false, false, true),  // selection rect reaches this display
      (true, true, true),
    ] {
      XCTAssertTrue(AreaSelectionRenderGate.shouldRender(
        hasContentOnScreen: content, pointerIsOverView: pointer, selectionIntersectsView: intersects
      ), "expected render for (\(content), \(pointer), \(intersects))")
    }
  }

  /// The regression the gate must not introduce: a display the pointer just left, with the rect
  /// elsewhere, gets exactly one clearing pass and only then goes quiet.
  func testDisplayThePointerLeavesIsClearedExactlyOnceThenSkipped() {
    var hasContent = true // last pass drew the crosshair while the pointer was here
    var renders = 0
    for _ in 0 ..< 5 {
      guard AreaSelectionRenderGate.shouldRender(
        hasContentOnScreen: hasContent, pointerIsOverView: false, selectionIntersectsView: false
      ) else { continue }
      renders += 1
      hasContent = false // the pass cleared it
    }
    XCTAssertEqual(renders, 1)
  }
}
