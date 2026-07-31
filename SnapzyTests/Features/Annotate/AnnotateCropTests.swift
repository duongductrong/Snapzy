//
//  AnnotateCropTests.swift
//  SnapzyTests
//
//  Characterization tests for the crop lifecycle on AnnotateState: init to full
//  bounds, updateCropRect normalization (standardize + min-size floor, NO image
//  clamping), applyCrop/confirm/cancel/reset/revert state transitions, aspect
//  ratio math (center-anchored), and orientation toggle.
//
//  Numeric ratio values (CropAspectRatio.ratio) and retina render-crop are
//  covered in AnnotateCoreTests; this file exercises the state-action behavior.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateCropTests: XCTestCase {
  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  private static let imageWidth = 400
  private static let imageHeight = 300

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  /// State with a known-size solid source image loaded so crop has a source.
  @MainActor
  private func makeLoadedState() throws -> AnnotateState {
    let cgImage = try XCTUnwrap(
      TestImageFactory.solidColor(width: Self.imageWidth, height: Self.imageHeight)
    )
    let image = NSImage(
      cgImage: cgImage,
      size: NSSize(width: Self.imageWidth, height: Self.imageHeight)
    )
    let state = makeAnnotateState()
    state.loadImage(image)
    return state
  }

  @MainActor
  private func makeRectangle(_ bounds: CGRect) -> AnnotationItem {
    AnnotationItem(type: .rectangle, bounds: bounds, properties: AnnotationProperties())
  }

  // MARK: - Initialize

  @MainActor
  func testInitializeCropSetsFullImageBoundsAndActivates() throws {
    let state = try makeLoadedState()

    state.initializeCrop()

    let rect = try XCTUnwrap(state.cropRect)
    XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 400, height: 300))
    XCTAssertTrue(state.isCropActive)
    // activeAnnotationBounds tracks the crop rect once set.
    XCTAssertEqual(state.activeAnnotationBounds, rect)
  }

  // MARK: - updateCropRect normalization (no image clamping)

  @MainActor
  func testUpdateCropRectDoesNotClampToImageBoundsAndPreservesOversizedRect() throws {
    let state = try makeLoadedState()
    state.initializeCrop()

    // A rect extending well beyond the source image. Current behavior allows
    // crop expansion outside the source, so it is retained verbatim (only
    // standardized + min-size enforced).
    let oversized = CGRect(x: -50, y: -25, width: 700, height: 500)
    state.updateCropRect(oversized)

    XCTAssertEqual(state.cropRect, oversized)
  }

  @MainActor
  func testUpdateCropRectStandardizesNegativeSizeRect() throws {
    let state = try makeLoadedState()

    // Origin at bottom-right with negative extents -> standardized to positive.
    state.updateCropRect(CGRect(x: 200, y: 150, width: -80, height: -60))

    let rect = try XCTUnwrap(state.cropRect)
    XCTAssertEqual(rect, CGRect(x: 120, y: 90, width: 80, height: 60))
  }

  @MainActor
  func testUpdateCropRectEnforcesMinimumSize() throws {
    let state = try makeLoadedState()

    state.updateCropRect(CGRect(x: 10, y: 10, width: 4, height: 3))

    let rect = try XCTUnwrap(state.cropRect)
    // Minimum crop size floor is 20 on each axis; origin is untouched.
    XCTAssertEqual(rect.origin.x, 10, accuracy: 0.0001)
    XCTAssertEqual(rect.origin.y, 10, accuracy: 0.0001)
    XCTAssertEqual(rect.width, 20, accuracy: 0.0001)
    XCTAssertEqual(rect.height, 20, accuracy: 0.0001)
  }

  // MARK: - Apply / confirm

  @MainActor
  func testApplyCropDeactivatesInteractionAndMarksUnsavedKeepingRect() throws {
    let state = try makeLoadedState()
    state.initializeCrop()
    let cropped = CGRect(x: 40, y: 30, width: 200, height: 150)
    state.updateCropRect(cropped)
    state.hasUnsavedChanges = false

    state.applyCrop()

    XCTAssertFalse(state.isCropActive)
    XCTAssertTrue(state.hasUnsavedChanges)
    // Rect is retained (used for export); annotation bounds now follow it.
    XCTAssertEqual(state.cropRect, cropped)
    XCTAssertEqual(state.activeAnnotationBounds, cropped)
  }

  @MainActor
  func testApplyCropDoesNotShiftAnnotationCoordinates() throws {
    let state = try makeLoadedState()
    let rectangle = makeRectangle(CGRect(x: 80, y: 70, width: 40, height: 30))
    state.annotations = [rectangle]
    state.initializeCrop()
    state.updateCropRect(CGRect(x: 40, y: 30, width: 200, height: 150))

    state.applyCrop()

    // Crop is non-destructive at the state layer: annotation coordinates stay
    // in source space (the crop-origin shift happens only at export/render).
    XCTAssertEqual(state.annotations.first?.bounds, rectangle.bounds)
  }

  @MainActor
  func testConfirmCropInteractionAppliesCropAndRestoresTool() throws {
    let state = try makeLoadedState()
    state.beginCropInteraction()
    XCTAssertEqual(state.selectedTool, .crop)
    let cropped = CGRect(x: 20, y: 20, width: 160, height: 120)
    state.updateCropRect(cropped)

    state.confirmCropInteraction()

    XCTAssertFalse(state.isCropActive)
    XCTAssertEqual(state.cropRect, cropped)
    // Crop tool is never left active after confirming; falls back to selection.
    XCTAssertEqual(state.selectedTool, .selection)
  }

  // MARK: - Cancel / reset

  @MainActor
  func testCancelCropRestoresPreInteractionRect() throws {
    let state = try makeLoadedState()
    // Establish a committed crop, then start a fresh interaction and mutate it.
    state.initializeCrop()
    let committed = CGRect(x: 30, y: 20, width: 180, height: 140)
    state.updateCropRect(committed)
    state.applyCrop()

    state.beginCropInteraction()
    state.updateCropRect(CGRect(x: 0, y: 0, width: 50, height: 50))

    state.cancelCrop()

    // Cancel reverts to the rect captured when the interaction began.
    XCTAssertEqual(state.cropRect, committed)
    XCTAssertFalse(state.isCropActive)
  }

  @MainActor
  func testResetCropClearsRectAndAspectState() throws {
    let state = try makeLoadedState()
    state.initializeCrop()
    state.applyCropAspectRatio(.ratio16x9)
    state.isCropPortraitOrientation = true

    state.resetCrop()

    XCTAssertNil(state.cropRect)
    XCTAssertFalse(state.isCropActive)
    XCTAssertEqual(state.cropAspectRatio, .free)
    XCTAssertFalse(state.isCropPortraitOrientation)
  }

  // MARK: - Revert to original bounds

  @MainActor
  func testRevertCropToOriginalBoundsRestoresFullImageRectAndFreeRatio() throws {
    let state = try makeLoadedState()
    state.initializeCrop()
    state.applyCropAspectRatio(.ratio4x3)
    state.updateCropRect(CGRect(x: 60, y: 40, width: 120, height: 90))

    state.revertCropToOriginalBounds()

    XCTAssertEqual(state.cropRect, CGRect(x: 0, y: 0, width: 400, height: 300))
    XCTAssertTrue(state.isCropActive)
    XCTAssertEqual(state.cropAspectRatio, .free)
    XCTAssertFalse(state.isCropPortraitOrientation)
    // Full-bounds crop means annotation space is the whole source image again.
    XCTAssertEqual(state.activeAnnotationBounds, state.sourceImageBounds)
  }

  @MainActor
  func testApplyThenRevertRestoresFullBoundsRoundTrip() throws {
    let state = try makeLoadedState()
    let originalBounds = state.sourceImageBounds
    state.initializeCrop()
    state.updateCropRect(CGRect(x: 50, y: 50, width: 100, height: 80))
    state.applyCrop()

    state.beginCropInteraction()
    state.revertCropToOriginalBounds()

    XCTAssertEqual(state.cropRect, originalBounds)
    XCTAssertEqual(state.activeAnnotationBounds, originalBounds)
  }

  // MARK: - Aspect ratio math (center-anchored)

  @MainActor
  func testApplyCropAspectRatioFreeLeavesRectUnchanged() throws {
    let state = try makeLoadedState()
    state.initializeCrop()
    let before = state.cropRect

    state.applyCropAspectRatio(.free)

    // `.free` only records the selection; the rect is not reshaped.
    XCTAssertEqual(state.cropAspectRatio, .free)
    XCTAssertEqual(state.cropRect, before)
  }

  @MainActor
  func testApplyCropAspectRatioSquareProducesEqualWidthAndHeight() throws {
    let state = try makeLoadedState()
    state.initializeCrop()  // base 400x300

    state.applyCropAspectRatio(.square)

    let rect = try XCTUnwrap(state.cropRect)
    XCTAssertEqual(rect.width, rect.height, accuracy: 0.0001)
    // Landscape base is too wide -> width reduced to match height, centered.
    XCTAssertEqual(rect.height, 300, accuracy: 0.0001)
    XCTAssertEqual(rect.width, 300, accuracy: 0.0001)
    XCTAssertEqual(rect.midX, 200, accuracy: 0.0001)  // centered horizontally
    XCTAssertEqual(rect.origin.y, 0, accuracy: 0.0001)
  }

  @MainActor
  func testApplyCropAspectRatio4x3MatchesRatioWithinEpsilon() throws {
    let state = try makeLoadedState()
    state.initializeCrop()

    state.applyCropAspectRatio(.ratio4x3)

    let rect = try XCTUnwrap(state.cropRect)
    XCTAssertEqual(rect.width / rect.height, 4.0 / 3.0, accuracy: 0.0001)
  }

  @MainActor
  func testApplyCropAspectRatio16x9MatchesRatioWithinEpsilon() throws {
    let state = try makeLoadedState()
    state.initializeCrop()

    state.applyCropAspectRatio(.ratio16x9)

    let rect = try XCTUnwrap(state.cropRect)
    XCTAssertEqual(rect.width / rect.height, 16.0 / 9.0, accuracy: 0.0001)
  }

  @MainActor
  func testApplyCropAspectRatioAllPresetsMatchTheirNumericRatio() throws {
    for ratio in CropAspectRatio.allCases where ratio != .free {
      let state = try makeLoadedState()
      state.initializeCrop()

      state.applyCropAspectRatio(ratio)

      let rect = try XCTUnwrap(state.cropRect)
      XCTAssertEqual(
        rect.width / rect.height,
        ratio.ratio,
        accuracy: 0.0001,
        "aspect ratio \(ratio.rawValue) should yield matching w/h"
      )
    }

    // Guard against a preset being added without test coverage.
    XCTAssertEqual(CropAspectRatio.allCases.count, 6)
  }

  // MARK: - Orientation toggle

  @MainActor
  func testToggleCropOrientationSwapsEffectiveRatioForNonSquarePreset() throws {
    let state = try makeLoadedState()
    state.initializeCrop()
    state.applyCropAspectRatio(.ratio16x9)
    let landscape = try XCTUnwrap(state.cropRect)
    XCTAssertGreaterThan(landscape.width, landscape.height)

    state.toggleCropOrientation()

    XCTAssertTrue(state.isCropPortraitOrientation)
    let portrait = try XCTUnwrap(state.cropRect)
    // Portrait swaps to a 9:16 effective ratio (taller than wide).
    XCTAssertEqual(portrait.width / portrait.height, 9.0 / 16.0, accuracy: 0.0001)
  }

  @MainActor
  func testToggleCropOrientationIsNoOpForFreeAndSquare() throws {
    let state = try makeLoadedState()
    state.initializeCrop()

    // Free: guard returns early, orientation stays false.
    state.applyCropAspectRatio(.free)
    state.toggleCropOrientation()
    XCTAssertFalse(state.isCropPortraitOrientation)

    // Square: also guarded (1:1 has no distinct orientation).
    state.applyCropAspectRatio(.square)
    state.toggleCropOrientation()
    XCTAssertFalse(state.isCropPortraitOrientation)
  }

  // MARK: - Snap-to-edges preference

  @MainActor
  func testCropEdgeSnappingEnabledDefaultsToTrueWhenUnset() {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedAnnotateStates.append(state)

    XCTAssertTrue(state.isCropEdgeSnappingEnabled)
  }

  @MainActor
  func testCropEdgeSnappingEnabledPersistsToDefaultsAndReadsBack() {
    let defaults = UserDefaultsFactory.make()
    let state = AnnotateState(defaults: defaults)
    Self.retainedAnnotateStates.append(state)

    state.isCropEdgeSnappingEnabled = false

    XCTAssertEqual(
      defaults.object(forKey: PreferencesKeys.annotateCropSnapToEdgesEnabled) as? Bool,
      false
    )
    // A fresh state over the same defaults reads the persisted value back.
    let fresh = AnnotateState(defaults: defaults)
    Self.retainedAnnotateStates.append(fresh)
    XCTAssertFalse(fresh.isCropEdgeSnappingEnabled)
  }

  // MARK: - Auto-crop to content

  /// Loaded state whose NSImage point size equals the fixture's pixel size, so
  /// top-left-origin pixel rects map to bottom-left points as y' = H - y.
  @MainActor
  private func makeLoadedState(cgImage: CGImage, pointWidth: Int, pointHeight: Int) -> AnnotateState {
    let state = makeAnnotateState()
    state.loadImage(NSImage(cgImage: cgImage, size: NSSize(width: pointWidth, height: pointHeight)))
    return state
  }

  @MainActor
  func testAutoCropToContentTightensRoughRectToContentBorders() async throws {
    // 800x600 light-gray (0.95) background with one dark 200x150 rect at
    // top-left pixels (300, 200) -> bottom-left points (300, 250, 200, 150).
    let cgImage = try XCTUnwrap(TestImageFactory.solidWithRects(
      width: 800,
      height: 600,
      backgroundGray: 242,
      rects: [(CGRect(x: 300, y: 200, width: 200, height: 150), 40)]
    ))
    let state = makeLoadedState(cgImage: cgImage, pointWidth: 800, pointHeight: 600)
    state.beginCropInteraction()
    // Rough rect ~40pt outside the dark rect on every side.
    state.updateCropRect(CGRect(x: 260, y: 210, width: 280, height: 230))

    await state.autoCropToContent()

    let rect = try XCTUnwrap(state.cropRect)
    XCTAssertEqual(rect.origin.x, 300, accuracy: 3)
    XCTAssertEqual(rect.origin.y, 250, accuracy: 3)
    XCTAssertEqual(rect.width, 200, accuracy: 3)
    XCTAssertEqual(rect.height, 150, accuracy: 3)
    // Auto-crop never leaves crop mode.
    XCTAssertTrue(state.isCropActive)
  }

  @MainActor
  func testAutoCropToContentWithUniformImageLeavesRectUnchanged() async throws {
    let state = try makeLoadedState()  // 400x300 uniform solid, no content borders
    state.beginCropInteraction()
    let rough = CGRect(x: 40, y: 30, width: 200, height: 150)
    state.updateCropRect(rough)

    await state.autoCropToContent()

    XCTAssertEqual(state.cropRect, rough)
    XCTAssertTrue(state.isCropActive)
  }

  @MainActor
  func testAutoCropToContentVisionFallbackTightensAroundSoftSubject() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.isOperatingSystemAtLeast(
        .init(majorVersion: 14, minorVersion: 0, patchVersion: 0)
      ),
      "Vision foreground cutout requires macOS 14+"
    )
    // Soft-edged dark blob: gradients stay below the edge detector's noise
    // floor, so the deterministic edge path finds nothing and the Vision
    // fallback must produce the tightening. Blob center (top-left px)
    // (400, 300) -> bottom-left points (400, 300).
    let cgImage = try XCTUnwrap(TestImageFactory.softRadialBlob(
      width: 800,
      height: 600,
      center: CGPoint(x: 400, y: 300),
      radius: 120
    ))
    let state = makeLoadedState(cgImage: cgImage, pointWidth: 800, pointHeight: 600)
    state.beginCropInteraction()
    let rough = CGRect(x: 200, y: 150, width: 400, height: 300)
    state.updateCropRect(rough)

    await state.autoCropToContent()

    // Guard the premise: the edge profile holds only the image-bounds edges,
    // so contentBounds returned nil and the Vision path did the work.
    let profile = try XCTUnwrap(state.cropEdgeProfile)
    XCTAssertEqual(profile.verticalEdges, [0, 800])
    XCTAssertEqual(profile.horizontalEdges, [0, 600])

    let rect = try XCTUnwrap(state.cropRect)
    // Meaningfully tighter than the rough selection, roughly on the blob
    // (expected diameter ~240pt); tolerances are loose on purpose — the exact
    // subject bounds are Vision's call.
    XCTAssertLessThan(rect.width * rect.height, rough.width * rough.height * 0.9)
    XCTAssertEqual(rect.midX, 400, accuracy: 80)
    XCTAssertEqual(rect.midY, 300, accuracy: 80)
    XCTAssertEqual(rect.width, 240, accuracy: 140)
    XCTAssertEqual(rect.height, 240, accuracy: 140)
    XCTAssertTrue(state.isCropActive)
  }
}
