//
//  VideoEditorControlsFitPolicyTests.swift
//  SnapzyTests
//
//  Geometry coverage for the playback controls row's badge decision (issue #780).
//

import AppKit
@testable import Snapzy
import SwiftUI
import XCTest

/// The badge decision reads one number: the width the trailing side frame was actually given.
/// These tests pin that rule against the widths measured from the #780 screenshot; the frame
/// widths themselves are measured in `VideoControlsLayoutLawTests`, on a copy of the row's
/// structure, so nothing below assumes how SwiftUI divides the row.
final class VideoEditorControlsFitPolicyTests: XCTestCase {
  // Widths as they come out at the reported size: the `.compact` style of a ~530 pt controls
  // container inside a 1200 pt window with both sidebars and the AI panel open.
  private let badgeSpacing: CGFloat = 6
  private let zoom: CGFloat = 74 // minus / fit / plus capsule
  private let status: CGFloat = 129 // zoom count + ✂ trimmed duration badges

  private func shows(trailing: CGFloat, zoom: CGFloat = 74, status: CGFloat = 129) -> Bool {
    VideoControlsFitPolicy.showsStatus(
      trailingWidth: trailing,
      zoomWidth: zoom,
      statusWidth: status,
      badgeSpacing: badgeSpacing
    )
  }

  func testReportedSize_hidesBadgesBecauseTheTrailingFrameCannotHoldThem() {
    // 147 pt is what the trailing frame is laid out in at a 530 pt container, measured in
    // `VideoControlsLayoutLawTests`; the group needs 209 pt.
    XCTAssertFalse(shows(trailing: 147))
  }

  /// The bug itself, in one line: the four clusters really do pack into the container, which is
  /// what the old check priced the badges against, while the trailing side is given only part of
  /// what is left. If the two models ever agree again, this test says so.
  func testOldPackingArithmeticWasTheFlaw() {
    let container: CGFloat = 530
    let leading: CGFloat = 76
    let transport: CGFloat = 212
    let outerSpacing: CGFloat = 12
    XCTAssertLessThanOrEqual(
      leading + transport + zoom + badgeSpacing + status + 2 * outerSpacing,
      container,
      "old model: the row packs into 521 of the 530 pt, so the badges were priced as fitting"
    )
    XCTAssertFalse(
      shows(trailing: 147),
      "new model: the 147 pt the trailing side is laid out in cannot hold the group"
    )
  }

  func testThreshold_isTheGroupWidthExactly() {
    let group = zoom + badgeSpacing + status
    XCTAssertTrue(shows(trailing: group))
    XCTAssertFalse(shows(trailing: group - 1))
  }

  /// The point of measuring the frame instead of deriving it: whatever the row decides to give the
  /// trailing side — a narrow container, an oversized leading cluster, a different layout style —
  /// the badges are priced against that number and nothing else.
  func testDecisionFollowsTheFrameNotAnAssumptionAboutTheRow() {
    let group = zoom + badgeSpacing + status
    for trailing in stride(from: CGFloat(1), through: 400, by: 1) {
      XCTAssertEqual(shows(trailing: trailing), trailing >= group, "at \(trailing) pt of frame")
    }
  }

  func testUnmeasuredWidths_keepTheFirstPassLayout() {
    // The measurements arrive one pass after the view appears, so an unknown anything must not
    // hide the badges forever.
    XCTAssertTrue(shows(trailing: 0))
    XCTAssertTrue(shows(trailing: 500, status: 0))
    XCTAssertTrue(shows(trailing: 500, zoom: 0))
  }

  /// Whatever the decision, the configuration it chose fits the frame it was priced against — the
  /// invariant the #780 overlap broke. Swept from the zoom cluster's own width up: below it the
  /// cluster that is part of the row's minimum is what no longer fits, which is a regime the badge
  /// decision cannot fix and the row's minimum keeps the window out of.
  func testShowingBadgesAlwaysImpliesTheGroupFitsItsFrame() {
    for trailing in stride(from: zoom, through: 1200, by: 1) {
      let shown = shows(trailing: trailing)
      let needed = shown ? zoom + badgeSpacing + status : zoom
      XCTAssertGreaterThanOrEqual(trailing, needed - 0.001, "at \(trailing) pt of frame")
    }
  }
}
