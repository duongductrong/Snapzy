//
//  AnnotateMockupTests.swift
//  SnapzyTests
//
//  Characterization tests for the mockup preset/reset actions on AnnotateState
//  (the path the Annotate Window drives) plus the standalone `MockupState`
//  object. The AnnotateState mutations are ALWAYS-RUN; the MockupState render
//  path is GPU-gated.
//
//  REGRESSION: `MockupState`'s rotation/perspective setters clamp inside their
//  own `didSet` (AnnotateMockupState.swift). A prior version reassigned
//  unconditionally, so `didSet` re-triggered forever and any rotationX/Y/Z/
//  perspective write crashed the host (SIGSEGV, recursion depth ~74k). The
//  clamp is now guarded (`if clamped != value`), bounding recursion at depth 2.
//  `testMockupStateClampsOutOfRangeTransformWithoutRecursing` locks that in — it
//  would stack-overflow the whole suite under the old code.
//

import AppKit
import Foundation
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateMockupTests: XCTestCase {
  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  private static var retainedAnnotateStates: [AnnotateState] = []
  private static var retainedMockupStates: [MockupState] = []

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedAnnotateStates.append(state)
    return state
  }

  // MARK: - applyMockupPreset (ALWAYS-RUN state mutation)

  func testApplyMockupPresetSetsMockupStateFields() {
    let state = makeAnnotateState()
    state.hasUnsavedChanges = false

    state.applyMockupPreset(.isometricLeft)

    XCTAssertEqual(state.mockupRotationX, MockupPreset.isometricLeft.rotationX)
    XCTAssertEqual(state.mockupRotationY, MockupPreset.isometricLeft.rotationY)
    XCTAssertEqual(state.mockupRotationZ, MockupPreset.isometricLeft.rotationZ)
    XCTAssertEqual(state.mockupPerspective, MockupPreset.isometricLeft.perspective)
    XCTAssertEqual(state.mockupPadding, MockupPreset.isometricLeft.padding)
    XCTAssertEqual(state.selectedMockupPresetId, MockupPreset.isometricLeft.id)
    XCTAssertTrue(state.hasUnsavedChanges)
  }

  func testApplyMockupPresetOverwritesPreviousSelection() {
    let state = makeAnnotateState()

    state.applyMockupPreset(.flat)
    XCTAssertEqual(state.selectedMockupPresetId, MockupPreset.flat.id)

    state.applyMockupPreset(.dramatic)

    XCTAssertEqual(state.selectedMockupPresetId, MockupPreset.dramatic.id)
    XCTAssertEqual(state.mockupRotationY, MockupPreset.dramatic.rotationY)
    XCTAssertEqual(state.mockupPadding, MockupPreset.dramatic.padding)
  }

  // MARK: - resetMockup (ALWAYS-RUN state mutation)

  func testResetMockupClearsMockupStateToDefaults() {
    let state = makeAnnotateState()
    state.applyMockupPreset(.heroShot)

    state.resetMockup()

    XCTAssertEqual(state.mockupRotationX, 0)
    XCTAssertEqual(state.mockupRotationY, 0)
    XCTAssertEqual(state.mockupRotationZ, 0)
    XCTAssertEqual(state.mockupPerspective, 0.5)
    XCTAssertEqual(state.mockupShadowIntensity, 0.3)
    XCTAssertEqual(state.mockupCornerRadius, 12)
    XCTAssertEqual(state.mockupPadding, 40)
    XCTAssertNil(state.selectedMockupPresetId)
  }

  // MARK: - MockupExporter guard (ALWAYS-RUN, GPU-free early return)

  func testMockupExporterRenderFinalImageReturnsNilWithoutSourceImage() {
    let mockup = MockupState()
    Self.retainedMockupStates.append(mockup)

    XCTAssertNil(MockupExporter.renderFinalImage(state: mockup, scale: 1.0))
  }

  // MARK: - MockupState transform clamping (ALWAYS-RUN regression guard)

  private func makeMockupState() -> MockupState {
    let state = MockupState()
    Self.retainedMockupStates.append(state)
    return state
  }

  /// Writing out-of-range transform values must clamp to the valid range and
  /// return — under the old unconditional `didSet` reassignment this recursed
  /// until the test host crashed.
  func testMockupStateClampsOutOfRangeTransformWithoutRecursing() {
    let state = makeMockupState()

    state.rotationX = 100
    XCTAssertEqual(state.rotationX, 45)
    state.rotationX = -100
    XCTAssertEqual(state.rotationX, -45)

    state.rotationY = 100
    XCTAssertEqual(state.rotationY, 45)
    state.rotationY = -100
    XCTAssertEqual(state.rotationY, -45)

    state.rotationZ = 400
    XCTAssertEqual(state.rotationZ, 180)
    state.rotationZ = -400
    XCTAssertEqual(state.rotationZ, -180)

    state.perspective = 5
    XCTAssertEqual(state.perspective, 1.0)
    state.perspective = 0
    XCTAssertEqual(state.perspective, 0.1)
  }

  /// In-range values pass through untouched.
  func testMockupStateKeepsInRangeTransform() {
    let state = makeMockupState()

    state.rotationX = 30
    state.rotationY = -20
    state.rotationZ = 90
    state.perspective = 0.7

    XCTAssertEqual(state.rotationX, 30)
    XCTAssertEqual(state.rotationY, -20)
    XCTAssertEqual(state.rotationZ, 90)
    XCTAssertEqual(state.perspective, 0.7)
  }

  func testMockupStateApplyPresetSetsTransformAndSelection() {
    let state = makeMockupState()

    state.applyPreset(.dramatic)

    XCTAssertEqual(state.rotationX, MockupPreset.dramatic.rotationX)
    XCTAssertEqual(state.rotationY, MockupPreset.dramatic.rotationY)
    XCTAssertEqual(state.rotationZ, MockupPreset.dramatic.rotationZ)
    XCTAssertEqual(state.perspective, MockupPreset.dramatic.perspective)
    XCTAssertEqual(state.padding, MockupPreset.dramatic.padding)
    XCTAssertEqual(state.selectedPresetId, MockupPreset.dramatic.id)
  }

  func testMockupStateResetToDefaultsClearsSelection() {
    let state = makeMockupState()
    state.applyPreset(.heroShot)

    state.resetToDefaults()

    XCTAssertEqual(state.rotationX, 0)
    XCTAssertEqual(state.rotationY, 0)
    XCTAssertEqual(state.rotationZ, 0)
    XCTAssertEqual(state.perspective, 0.5)
    XCTAssertEqual(state.padding, 40)
    XCTAssertEqual(state.shadowIntensity, 0.3)
    XCTAssertEqual(state.cornerRadius, 12)
    XCTAssertNil(state.selectedPresetId)
  }

  /// Regression: MockupState.undo() and redo() must restore selectedPresetId alongside transforms.
  func testMockupStateUndoRedoRestoresSelectedPresetId() {
    let state = makeMockupState()
    XCTAssertNil(state.selectedPresetId)

    state.applyPreset(.dramatic)
    XCTAssertEqual(state.selectedPresetId, MockupPreset.dramatic.id)

    state.undo()
    XCTAssertNil(state.selectedPresetId)
    XCTAssertEqual(state.rotationX, 0)

    state.redo()
    XCTAssertEqual(state.selectedPresetId, MockupPreset.dramatic.id)
    XCTAssertEqual(state.rotationY, MockupPreset.dramatic.rotationY)
  }

  // MARK: - MockupExporter render (GPU path, CI-gated)

  func testMockupExporterRenderProducesImageWithSourceImage() throws {
    try skipIfRunningInCI()

    let state = makeMockupState()
    let source = NSImage(size: NSSize(width: 64, height: 64))
    source.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 64, height: 64).fill()
    source.unlockFocus()
    state.sourceImage = source

    let rendered = MockupExporter.renderFinalImage(state: state, scale: 1.0)

    let image = try XCTUnwrap(rendered)
    XCTAssertGreaterThan(image.size.width, 0)
    XCTAssertGreaterThan(image.size.height, 0)
  }
}
