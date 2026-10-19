//
//  AnnotateCutOutInteractionTests.swift
//  SnapzyTests
//
//  Esc/cancel behavior while the Cut Out tool owns the editor: Esc discards
//  the drawn strip first, then leaves the mode and restores the prior tool.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateCutOutInteractionTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeCutOutState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    state.sourceImage = NSImage(size: CGSize(width: 100, height: 80))
    state.selectedTool = .rectangle
    state.beginCutOutInteraction()
    return state
  }

  func testCancelInteraction_withStrip_clearsStripAndStaysInMode() {
    let state = makeCutOutState()
    state.updateCutOutStrip(CGRect(x: 0, y: 20, width: 100, height: 10))
    XCTAssertNotNil(state.cutOutPreviewStrip)

    state.cancelCutOutInteraction()

    XCTAssertNil(state.cutOutPreviewStrip)
    XCTAssertTrue(state.isCutOutInteractionActive)
  }

  func testCancelInteraction_withoutStrip_exitsModeAndRestoresTool() {
    let state = makeCutOutState()
    XCTAssertTrue(state.isCutOutInteractionActive)

    state.cancelCutOutInteraction()

    XCTAssertFalse(state.isCutOutInteractionActive)
    XCTAssertEqual(state.selectedTool, .rectangle)
  }

  func testUpdateStrip_afterCancel_isIgnored() {
    let state = makeCutOutState()
    state.cancelCutOut()

    state.updateCutOutStrip(CGRect(x: 0, y: 20, width: 100, height: 10))

    XCTAssertNil(state.cutOutPreviewStrip)
  }
}
