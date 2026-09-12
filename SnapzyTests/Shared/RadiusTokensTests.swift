//
//  RadiusTokensTests.swift
//  SnapzyTests
//
//  The corner-radius scale is a proportionality claim: guard the proportion, not the literals.
//

import SwiftUI
import XCTest

@testable import Snapzy

final class RadiusTokensTests: XCTestCase {

  // MARK: - Ramp shape

  func testControlRamp_isAscendingAndDistinct() {
    let ramp = Radius.controlRamp
    XCTAssertFalse(ramp.isEmpty)
    XCTAssertEqual(ramp, ramp.sorted())
    XCTAssertEqual(Set(ramp).count, ramp.count, "A duplicated step makes two heights indistinguishable")
  }

  func testControl_alwaysReturnsARampValue() {
    for height in stride(from: CGFloat(8), through: 80, by: 1) {
      XCTAssertTrue(
        Radius.controlRamp.contains(Radius.control(forHeight: height)),
        "height \(height) resolved off-ramp"
      )
    }
  }

  func testControl_isMonotonic() {
    var previous = Radius.control(forHeight: 8)
    for height in stride(from: CGFloat(9), through: 80, by: 1) {
      let current = Radius.control(forHeight: height)
      XCTAssertGreaterThanOrEqual(current, previous, "radius shrank going from \(height - 1) to \(height)")
      previous = current
    }
  }

  // MARK: - Proportionality

  /// The whole point of the scale: roundness stays proportional across the range of control
  /// heights the app ships, so a 24pt chip and a 32pt button read as the same family. Outside
  /// 0.28–0.44 a control starts reading either as a box or as a pill.
  func testControl_roundnessStaysInBand_acrossShippedHeights() {
    for height in stride(from: CGFloat(18), through: 44, by: 1) {
      let ratio = Radius.control(forHeight: height) / height
      XCTAssertGreaterThanOrEqual(ratio, 0.28, "height \(height) reads square at ratio \(ratio)")
      XCTAssertLessThanOrEqual(ratio, 0.44, "height \(height) reads as a pill at ratio \(ratio)")
    }
  }

  func testControl_clampsAtRampEnds() {
    XCTAssertEqual(Radius.control(forHeight: 4), Radius.controlRamp.first)
    XCTAssertEqual(Radius.control(forHeight: 400), Radius.controlRamp.last)
  }

  // MARK: - Shipped control steps

  /// The heights the shared chrome is actually built at. These assertions are the contract the
  /// Annotate toolbar's icon buttons and its `Done` capsule were reconciled against.
  func testControl_resolvesShippedHeights() {
    XCTAssertEqual(Radius.control(forHeight: ControlMetrics.propertyChip), Radius.controlS)
    XCTAssertEqual(Radius.control(forHeight: ControlMetrics.toolbarButton), Radius.controlM)
    XCTAssertEqual(Radius.control(forHeight: ControlMetrics.bottomBarControl), Radius.controlM)
    XCTAssertEqual(Radius.control(forHeight: 32), Radius.controlL)
  }

  /// A 28pt icon button used to sit at 8pt — noticeably squarer than the capsule `Done` button
  /// beside it. It has to stay rounder than that, and still short of a circle.
  func testToolbarButton_isRounderThanLegacyButNotACircle() {
    let height = ControlMetrics.toolbarButton
    let radius = Radius.control(forHeight: height)
    XCTAssertGreaterThan(radius, 8, "the icon button regressed to its old square corner")
    XCTAssertLessThan(radius, height / 2, "a square icon button must not resolve to a circle")
  }

  // MARK: - Alias integrity

  /// `LiquidGlassTokens` and `Size` are pass-throughs now; a divergence there reintroduces the
  /// parallel scales this replaced.
  func testGlassAndLegacyTokens_aliasTheScale() {
    XCTAssertEqual(LiquidGlassTokens.controlRadius, Radius.controlM)
    XCTAssertEqual(LiquidGlassTokens.cardRadius, Radius.card)
    XCTAssertEqual(LiquidGlassTokens.surfaceRadius, Radius.panel)
    XCTAssertEqual(LiquidGlassTokens.windowRadius, Radius.window)
    XCTAssertEqual(Size.radiusXs, Radius.ornament)
    XCTAssertEqual(Size.radiusMd, Radius.tile)
    XCTAssertEqual(Size.radiusLg, Radius.controlL)
  }

  // MARK: - Shape helpers

  func testShapeHelpers_pinContinuousCorners() {
    XCTAssertEqual(Radius.rect(Radius.card).style, .continuous)
    XCTAssertEqual(Radius.controlRect(forHeight: ControlMetrics.toolbarButton).style, .continuous)
    XCTAssertEqual(
      Radius.controlRect(forHeight: ControlMetrics.toolbarButton).cornerSize,
      CGSize(width: Radius.controlM, height: Radius.controlM)
    )
  }
}
