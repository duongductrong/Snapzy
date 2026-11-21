//
//  AnnotateImageAdjustmentsTests.swift
//  SnapzyTests
//
//  Image adjustments (#788): tolerant sidecar decoding, renderer geometry, export uses
//  adjusted full-resolution pixels, undo per change, reset restores the original.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateImageAdjustmentsTests: XCTestCase {
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  @MainActor
  private func makeState() throws -> AnnotateState {
    let suite = "AnnotateImageAdjustmentsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let state = AnnotateState(defaults: defaults, appliesDefaultCanvasPresetOnNewImages: false)
    Self.retainedAnnotateStates.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 100, red: 200, green: 60, blue: 40))
    state.loadImage(NSImage(cgImage: cgImage, size: CGSize(width: 100, height: 50)))
    return state
  }

  func testDecodingIsTolerant() throws {
    let json = #"{"brightness": 250, "preset": "from-the-future"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ImageAdjustments.self, from: json)
    XCTAssertEqual(decoded.brightness, 100)
    XCTAssertEqual(decoded.contrast, 0)
    XCTAssertEqual(decoded.preset, .none)
  }

  func testCodableRoundTrip() throws {
    let adjustments = ImageAdjustments(brightness: 10, contrast: -20, saturation: 30, sharpness: 40, preset: .noir)
    let data = try JSONEncoder().encode(adjustments)
    XCTAssertEqual(try JSONDecoder().decode(ImageAdjustments.self, from: data), adjustments)
  }

  func testRendererKeepsPixelSizeAndPreviewDownscales() throws {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 400, height: 200))
    let adjustments = ImageAdjustments(saturation: -100, sharpness: 50, preset: .sepia)
    let full = try XCTUnwrap(AnnotateImageAdjustmentRenderer.render(cgImage, adjustments: adjustments))
    XCTAssertEqual(full.width, 400)
    XCTAssertEqual(full.height, 200)
    let preview = try XCTUnwrap(AnnotateImageAdjustmentRenderer.render(cgImage, adjustments: adjustments, maxPixelCount: 20_000))
    XCTAssertLessThanOrEqual(preview.width * preview.height, 20_500)
  }

  func testSemiTransparentPixelsKeepTheirAlpha() throws {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 8, height: 8, alpha: 128))
    let rendered = try XCTUnwrap(AnnotateImageAdjustmentRenderer.render(
      cgImage, adjustments: ImageAdjustments(brightness: 50, preset: .mono)
    ))
    let rep = NSBitmapImageRep(cgImage: rendered)
    let alpha = try XCTUnwrap(rep.colorAt(x: 4, y: 4)).alphaComponent
    XCTAssertEqual(alpha, 128.0 / 255.0, accuracy: 0.02)
  }

  @MainActor
  func testExportUsesAdjustedPixelsAndResetRestoresOriginal() throws {
    let state = try makeState()
    let original = try XCTUnwrap(state.sourceImage)
    XCTAssertTrue(state.exportSourceImage() === original)

    state.selectImageFilterPreset(.mono)
    let adjusted = try XCTUnwrap(state.exportSourceImage())
    XCTAssertFalse(adjusted === original)
    XCTAssertEqual(adjusted.size, original.size)
    let cgImage = try XCTUnwrap(AnnotateExporter.bestCGImage(from: adjusted))
    XCTAssertEqual(cgImage.width, 200)
    XCTAssertTrue(state.effectiveSourceImage === adjusted)
    XCTAssertTrue(state.sourceImage === original, "source pixels stay untouched")

    state.resetImageAdjustments()
    XCTAssertTrue(state.effectiveSourceImage === original)
    XCTAssertTrue(state.exportSourceImage() === original)
  }

  @MainActor
  func testSliderDragIsOneUndoStep() throws {
    let state = try makeState()
    state.beginImageAdjustmentGesture()
    for value in stride(from: 5.0, through: 40.0, by: 5.0) {
      state.updateImageAdjustmentGesture(ImageAdjustments(brightness: value))
    }
    state.endImageAdjustmentGesture()
    XCTAssertEqual(state.imageAdjustments.brightness, 40)
    XCTAssertTrue(state.canUndo)

    state.undo()
    XCTAssertTrue(state.imageAdjustments.isIdentity)
    XCTAssertFalse(state.canUndo)

    state.redo()
    XCTAssertEqual(state.imageAdjustments.brightness, 40)
  }

  @MainActor
  func testSessionDataRoundTripsAdjustments() throws {
    let state = try makeState()
    state.setImageAdjustments(ImageAdjustments(contrast: 25, preset: .chrome))
    let sessionData = AnnotationSessionData.snapshot(from: state, originalImageData: Data())
    XCTAssertEqual(sessionData.imageAdjustments, ImageAdjustments(contrast: 25, preset: .chrome))

    let restored = try makeState()
    restored.restoreImageAdjustments(sessionData.imageAdjustments)
    XCTAssertEqual(restored.imageAdjustments.preset, .chrome)
    XCTAssertFalse(restored.hasUnsavedChanges)
    XCTAssertFalse(restored.canUndo)
    XCTAssertFalse(restored.effectiveSourceImage === restored.sourceImage, "small images render on restore")
  }
}
