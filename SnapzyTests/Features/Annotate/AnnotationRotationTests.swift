//
//  AnnotationRotationTests.swift
//  SnapzyTests
//
//  Unit tests for per-annotation rotation: rotatable types, angle clamping,
//  rotated hit-testing and rotated selection bounds.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotationRotationTests: XCTestCase {

  // A 100×20 bar centered on (50, 10). Rotated 90° it covers x 40…60, y -40…60,
  // so the assertions below hold whichever way the rotation turns.
  private let barBounds = CGRect(x: 0, y: 0, width: 100, height: 20)

  private func item(_ type: AnnotationType, rotation: CGFloat, bounds: CGRect? = nil) -> AnnotationItem {
    AnnotationItem(
      type: type,
      bounds: bounds ?? barBounds,
      properties: AnnotationProperties(rotationDegrees: rotation)
    )
  }

  // MARK: - Rotatable types

  func testSupportsRotation_onlyBoxTypes() {
    XCTAssertTrue(AnnotationType.text("a").supportsRotation)
    XCTAssertTrue(AnnotationType.embeddedImage(UUID()).supportsRotation)
    XCTAssertTrue(AnnotationType.rectangle.supportsRotation)
    XCTAssertTrue(AnnotationType.filledRectangle.supportsRotation)
    XCTAssertTrue(AnnotationType.oval.supportsRotation)

    XCTAssertFalse(AnnotationType.watermark("w").supportsRotation)
    XCTAssertFalse(AnnotationType.blur(.gaussian).supportsRotation)
    XCTAssertFalse(AnnotationType.spotlight.supportsRotation)
    XCTAssertFalse(AnnotationType.counter(1).supportsRotation)
    XCTAssertFalse(AnnotationType.line(start: .zero, end: CGPoint(x: 1, y: 1)).supportsRotation)
    XCTAssertFalse(AnnotationType.path([.zero]).supportsRotation)
  }

  func testRotationTransform_nilForZeroAngleOrUnsupportedType() {
    XCTAssertNil(item(.rectangle, rotation: 0).rotationTransform)
    XCTAssertNil(item(.watermark("w"), rotation: 30).rotationTransform)
    XCTAssertNil(item(.blur(.gaussian), rotation: 30).rotationTransform)
    XCTAssertNotNil(item(.rectangle, rotation: 30).rotationTransform)
  }

  // MARK: - Clamping

  func testClampedRotation_rotatableTypesWrapIntoHalfTurn() {
    XCTAssertEqual(AnnotationType.rectangle.clampedRotationDegrees(120), 120)
    XCTAssertEqual(AnnotationType.rectangle.clampedRotationDegrees(200), -160)
    XCTAssertEqual(AnnotationType.text("a").clampedRotationDegrees(-190), 170)
    XCTAssertEqual(AnnotationType.oval.clampedRotationDegrees(180), 180)
    XCTAssertEqual(AnnotationType.oval.clampedRotationDegrees(-180), 180)
    XCTAssertEqual(AnnotationType.oval.clampedRotationDegrees(720), 0)
    XCTAssertEqual(AnnotationType.oval.clampedRotationDegrees(.nan), 0)
  }

  func testClampedRotation_watermarkKeepsFortyFiveDegreeLimit() {
    XCTAssertEqual(AnnotationType.watermark("w").clampedRotationDegrees(60), 45)
    XCTAssertEqual(AnnotationType.watermark("w").clampedRotationDegrees(-60), -45)
  }

  @MainActor
  func testUpdateAnnotationProperties_rotatableTypeAcceptsAnglesBeyondWatermarkLimit() throws {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    let rectangle = item(.rectangle, rotation: 0)
    state.annotations = [rectangle]

    state.updateAnnotationProperties(id: rectangle.id, rotationDegrees: 120)

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.rotationDegrees, 120)
  }

  // MARK: - Hit testing

  func testRotatedRectangle_hitTestFollowsRotatedShape() {
    let rotated = item(.rectangle, rotation: 90)
    XCTAssertTrue(rotated.containsPoint(CGPoint(x: 50, y: 50)))
    XCTAssertFalse(rotated.containsPoint(CGPoint(x: 90, y: 10)))
  }

  func testRotatedOval_hitTestFollowsRotatedShape() {
    let rotated = item(.oval, rotation: 90)
    XCTAssertTrue(rotated.containsPoint(CGPoint(x: 50, y: -30)))
    XCTAssertFalse(rotated.containsPoint(CGPoint(x: 90, y: 10)))
  }

  func testRotatedEmbeddedImage_hitTestFollowsRotatedShape() {
    let rotated = item(.embeddedImage(UUID()), rotation: 90)
    XCTAssertTrue(rotated.containsPoint(CGPoint(x: 50, y: 50)))
    XCTAssertFalse(rotated.containsPoint(CGPoint(x: 5, y: 10)))
  }

  func testRotatedRectangle_edgeBandFollowsRotatedOutline() {
    let rotated = item(.rectangle, rotation: 90)
    // Rotated top/bottom edges sit at y = -40 and y = 60.
    XCTAssertTrue(rotated.edgeBandContains(CGPoint(x: 50, y: 60)))
    // The unrotated short edge at x = 100 is empty space after rotation.
    XCTAssertFalse(rotated.edgeBandContains(CGPoint(x: 100, y: 10)))
  }

  func testRotatedFilledRectangle_occludesRotatedBodyOnly() {
    let rotated = item(.filledRectangle, rotation: 90)
    XCTAssertTrue(rotated.occludesItemsBelow(at: CGPoint(x: 50, y: 50)))
    XCTAssertFalse(rotated.occludesItemsBelow(at: CGPoint(x: 90, y: 10)))
  }

  func testWatermarkRotation_doesNotChangeHitTest() {
    let watermark = item(.watermark("w"), rotation: 45)
    XCTAssertTrue(watermark.containsPoint(CGPoint(x: 90, y: 10)))
  }

  // MARK: - Callout tail stays pinned

  func testRotatedCallout_tailTargetStaysHittableAndInsideSelection() {
    let tailTarget = CGPoint(x: 50, y: 120)
    var properties = AnnotationProperties(rotationDegrees: 90)
    properties.textPresentation = .callout
    properties.calloutTailTarget = tailTarget
    let callout = AnnotationItem(type: .text("hi"), bounds: barBounds, properties: properties)

    XCTAssertTrue(callout.containsPoint(tailTarget))
    XCTAssertTrue(callout.selectionBounds.contains(tailTarget))
  }

  // MARK: - Selection bounds

  func testRotatedSelectionBounds_coverRotatedShape() {
    let rotated = item(.rectangle, rotation: 90)
    let bounds = rotated.selectionBounds
    // Rectangle selection pads by max(6, strokeWidth / 2) = 6.
    XCTAssertEqual(bounds.minX, 34, accuracy: 0.001)
    XCTAssertEqual(bounds.maxX, 66, accuracy: 0.001)
    XCTAssertEqual(bounds.minY, -46, accuracy: 0.001)
    XCTAssertEqual(bounds.maxY, 66, accuracy: 0.001)
  }

  func testUnrotatedSelectionBounds_unchanged() {
    let plain = item(.rectangle, rotation: 0)
    XCTAssertEqual(plain.selectionBounds, barBounds.insetBy(dx: -6, dy: -6))
  }
  // MARK: - Rotation gesture

  func testSnappedDegrees_shiftRoundsToFifteenDegreeSteps() {
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(22, shiftHeld: true), 15)
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(23, shiftHeld: true), 30)
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(-176, shiftHeld: true), 180)
  }

  func testSnappedDegrees_magnetAttractsRightAnglesWithoutShift() {
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(2.5, shiftHeld: false), 0)
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(-88, shiftHeld: false), -90)
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(-178, shiftHeld: false), 180)
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(4, shiftHeld: false), 4)
    XCTAssertEqual(AnnotationRotationGesture.snappedDegrees(47, shiftHeld: false), 47)
  }

  func testRotationDegrees_followsPointerAngleDeltaAroundCenter() {
    let degrees = AnnotationRotationGesture.rotationDegrees(
      originalDegrees: 10,
      center: CGPoint(x: 0, y: 0),
      press: CGPoint(x: 0, y: 50),
      current: CGPoint(x: -50, y: 50),
      shiftHeld: false
    )
    XCTAssertEqual(degrees, 55, accuracy: 0.001)
  }

  func testHandleCenter_sitsAboveTopEdgeAndTurnsWithItem() {
    let plain = item(.rectangle, rotation: 0)
    XCTAssertEqual(AnnotationRotationGesture.handleCenter(for: plain, offset: 10), CGPoint(x: 50, y: 30))

    let quarterTurn = item(.rectangle, rotation: 90)
    let center = AnnotationRotationGesture.handleCenter(for: quarterTurn, offset: 10)
    // Local top-middle (50, 30) is 20 above the center (50, 10); a quarter
    // turn moves it 20 to the side.
    XCTAssertEqual(abs(center.x - 50), 20, accuracy: 0.001)
    XCTAssertEqual(center.y, 10, accuracy: 0.001)
  }

  func testAnchoredBounds_keepsOppositeCornerFixedOnScreen() throws {
    let original = item(.rectangle, rotation: 30)
    let transform = try XCTUnwrap(original.rotationTransform)
    // Grow from the local top-right corner: bottom-left stays put locally.
    let localResize = CGRect(x: 0, y: 0, width: 160, height: 60)
    let stored = AnnotationRotationGesture.anchoredBounds(forLocalResize: localResize, originalTransform: transform)

    var resized = original
    resized.bounds = stored
    let resizedTransform = try XCTUnwrap(resized.rotationTransform)

    let anchorBefore = CGPoint(x: 0, y: 0).applying(transform)
    let anchorAfter = CGPoint(x: stored.minX, y: stored.minY).applying(resizedTransform)
    XCTAssertEqual(anchorAfter.x, anchorBefore.x, accuracy: 0.001)
    XCTAssertEqual(anchorAfter.y, anchorBefore.y, accuracy: 0.001)
    XCTAssertEqual(stored.size, localResize.size)
  }

  // MARK: - Quick bar angle field

  @MainActor
  private func makeState(with annotations: [AnnotationItem]) -> AnnotateState {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedStates.append(state)
    state.annotations = annotations
    state.setSelectedAnnotationIds(Set(annotations.map(\.id)))
    return state
  }

  // AnnotateState teardown is not test-safe; keep instances alive like the other suites.
  @MainActor private static var retainedStates: [AnnotateState] = []

  @MainActor
  func testQuickRotation_insertedImageGetsAngleField() {
    let image = item(.embeddedImage(UUID()), rotation: 30)
    let state = makeState(with: [image])

    XCTAssertTrue(state.quickPropertiesSupportsAnnotationRotation)
    XCTAssertEqual(state.quickAnnotationRotationDegrees, 30)
  }

  @MainActor
  func testQuickRotation_hiddenForNonRotatableSelection() {
    let arrow = AnnotationItem(
      type: .arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 50, y: 0), style: .straight)),
      bounds: CGRect(x: 0, y: 0, width: 50, height: 1),
      properties: AnnotationProperties()
    )
    let state = makeState(with: [arrow])

    XCTAssertFalse(state.quickPropertiesSupportsAnnotationRotation)
  }

  @MainActor
  func testQuickRotation_mixedAnglesShowNoValueAndCommitAppliesToRotatableOnly() throws {
    let rectangle = item(.rectangle, rotation: 10)
    let text = item(.text("a"), rotation: -20)
    let arrow = AnnotationItem(
      type: .arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 50, y: 0), style: .straight)),
      bounds: CGRect(x: 0, y: 0, width: 50, height: 1),
      properties: AnnotationProperties(rotationDegrees: 5)
    )
    let state = makeState(with: [rectangle, text, arrow])

    XCTAssertNil(state.quickAnnotationRotationDegrees)

    state.setQuickAnnotationRotation(200)

    let angles = state.annotations.map(\.properties.rotationDegrees)
    XCTAssertEqual(angles, [-160, -160, 5])
    XCTAssertEqual(state.quickAnnotationRotationDegrees, -160)
  }

  @MainActor
  func testQuickRotation_commitIsOneUndoStep() {
    let rectangle = item(.rectangle, rotation: 10)
    let oval = item(.oval, rotation: 40)
    let state = makeState(with: [rectangle, oval])

    state.setQuickAnnotationRotation(90)
    state.undo()

    XCTAssertEqual(state.annotations.map(\.properties.rotationDegrees), [10, 40])
  }
}
