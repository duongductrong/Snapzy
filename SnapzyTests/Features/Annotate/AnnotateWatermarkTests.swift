//
//  AnnotateWatermarkTests.swift
//  SnapzyTests
//
//  Characterization tests for watermark text updates, the three watermark
//  styles and their per-style default rotation, and inheritance of remembered
//  opacity/rotation into newly created watermark defaults. Persistence of
//  remembered opacity/rotation across AnnotateState instances is covered in
//  AnnotateCoreTests and is not duplicated here.
//

import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateWatermarkTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeAnnotateState(defaults: UserDefaults) -> AnnotateState {
    let state = AnnotateState(defaults: defaults)
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeWatermarkAnnotation(_ text: String = "Snapzy") -> AnnotationItem {
    AnnotationItem(
      type: .watermark(text),
      bounds: CGRect(x: 0, y: 0, width: 420, height: 90),
      properties: AnnotationProperties()
    )
  }

  func testUpdateWatermarkTextReplacesText() throws {
    let state = makeAnnotateState()
    let annotation = makeWatermarkAnnotation("Snapzy")
    state.annotations = [annotation]

    state.updateWatermarkText(id: annotation.id, text: "Confidential")

    let updated = try XCTUnwrap(state.annotations.first)
    guard case .watermark(let text) = updated.type else {
      return XCTFail("Expected watermark annotation, got \(updated.type)")
    }
    XCTAssertEqual(text, "Confidential")
  }

  func testUpdateWatermarkTextIsNoOpForNonWatermarkAnnotation() {
    let state = makeAnnotateState()
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 0, y: 0, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    state.annotations = [rectangle]

    state.updateWatermarkText(id: rectangle.id, text: "Nope")

    XCTAssertEqual(state.annotations.first?.type, .rectangle)
  }

  func testUpdateWatermarkTextIgnoresUnknownId() throws {
    let state = makeAnnotateState()
    let annotation = makeWatermarkAnnotation("Snapzy")
    state.annotations = [annotation]

    state.updateWatermarkText(id: UUID(), text: "Ghost")

    let unchanged = try XCTUnwrap(state.annotations.first)
    guard case .watermark(let text) = unchanged.type else {
      return XCTFail("Expected watermark annotation, got \(unchanged.type)")
    }
    XCTAssertEqual(text, "Snapzy")
  }

  func testSetActiveWatermarkStyleAppliesEveryStyleToSelectedWatermark() throws {
    let state = makeAnnotateState()
    let annotation = makeWatermarkAnnotation()
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    for style in WatermarkStyle.allCases {
      state.setActiveWatermarkStyle(style)

      let updated = try XCTUnwrap(state.annotations.first)
      XCTAssertEqual(updated.properties.watermarkStyle, style)
      // Selecting a style also applies that style's default rotation.
      XCTAssertEqual(updated.properties.rotationDegrees, style.defaultRotationDegrees)
      XCTAssertEqual(state.activeWatermarkStyle, style)
    }

    // Guards against silently dropping a case if the enum grows.
    XCTAssertEqual(WatermarkStyle.allCases.count, 3)
  }

  func testWatermarkStyleDefaultRotationMatchesSpecifiedValues() {
    XCTAssertEqual(WatermarkStyle.single.defaultRotationDegrees, 0)
    XCTAssertEqual(WatermarkStyle.diagonal.defaultRotationDegrees, -24)
    XCTAssertEqual(WatermarkStyle.tiled.defaultRotationDegrees, -24)
  }

  func testSetActiveWatermarkStyleWithoutSelectionUpdatesToolDefaults() {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())

    state.setActiveWatermarkStyle(.single)

    XCTAssertEqual(state.activeWatermarkStyle, .single)
    let properties = state.annotationCreationProperties(for: .watermark)
    XCTAssertEqual(properties.watermarkStyle, .single)
    XCTAssertEqual(properties.rotationDegrees, WatermarkStyle.single.defaultRotationDegrees)
  }

  func testRememberedWatermarkOpacityAndRotationFlowIntoWatermarkCreationDefaults() {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    state.activateTool(.watermark)

    // With no watermark selected, the quick bindings persist as remembered
    // tool defaults rather than mutating an existing item.
    state.quickWatermarkOpacityBinding.wrappedValue = 0.5
    state.quickWatermarkRotationBinding.wrappedValue = -10

    let properties = state.annotationCreationProperties(for: .watermark)
    XCTAssertEqual(properties.opacity, 0.5, accuracy: 0.0001)
    XCTAssertEqual(properties.rotationDegrees, -10, accuracy: 0.0001)
  }

  /// Regression: inline watermark rotation slider displays `"-45deg"` (6 characters) and
  /// must have enough width so the readout never truncates to `"-45d..."`.
  func testInlineSliderValueReadoutFitsNegativeTwoDigitRotation() {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    let measuredWidth = ("-45deg" as NSString).size(withAttributes: [.font: font]).width
    XCTAssertGreaterThanOrEqual(
      InlineAreaSliderControl.valueReadoutMinWidth,
      ceil(measuredWidth),
      "Inline slider value readout width must fit \"-45deg\" without truncation"
    )
  }
}
