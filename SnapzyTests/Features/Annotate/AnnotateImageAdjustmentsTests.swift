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

  // MARK: - Color-grading parameters

  private func pixel(_ image: CGImage, x: Int? = nil, y: Int? = nil) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let rep = NSBitmapImageRep(cgImage: image)
    let color = try XCTUnwrap(rep.colorAt(x: x ?? image.width / 2, y: y ?? image.height / 2)?.usingColorSpace(.sRGB))
    return (color.redComponent, color.greenComponent, color.blueComponent)
  }

  private func render(_ image: CGImage, _ adjustments: ImageAdjustments) throws -> CGImage {
    try XCTUnwrap(AnnotateImageAdjustmentRenderer.render(image, adjustments: adjustments))
  }

  func testOldSidecarsDecodeWithFullPresetIntensity() throws {
    let json = #"{"brightness": 10, "contrast": 0, "saturation": 0, "sharpness": 0, "preset": "noir"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ImageAdjustments.self, from: json)
    XCTAssertEqual(decoded.presetIntensity, 100)
    XCTAssertEqual(decoded.exposure, 0)
    XCTAssertEqual(decoded.vignette, 0)
  }

  func testFullCodableRoundTrip() throws {
    let adjustments = ImageAdjustments(
      exposure: 12, brightness: -3, contrast: 20, highlights: -40, shadows: 35, whites: 10, blacks: -15,
      temperature: 25, tint: -8, saturation: 5, vibrance: 30, clarity: 45, sharpness: 20, vignette: -30,
      preset: .matte, presetIntensity: 60
    )
    let data = try JSONEncoder().encode(adjustments)
    XCTAssertEqual(try JSONDecoder().decode(ImageAdjustments.self, from: data), adjustments)
  }

  func testIdentityIgnoresStrengthOfNoPresetAndZeroStrength() {
    XCTAssertTrue(ImageAdjustments(preset: .none, presetIntensity: 40).isIdentity)
    XCTAssertTrue(ImageAdjustments(preset: .noir, presetIntensity: 0).isIdentity)
    XCTAssertFalse(ImageAdjustments(preset: .noir, presetIntensity: 1).isIdentity)
    XCTAssertFalse(ImageAdjustments(vignette: -1).isIdentity)
  }

  func testTemperatureAndTintShiftInTheExpectedDirection() throws {
    let gray = try XCTUnwrap(TestImageFactory.solidColor(width: 16, height: 16))
    let warm = try pixel(render(gray, ImageAdjustments(temperature: 60)))
    XCTAssertGreaterThan(warm.r, warm.b + 0.05, "+temperature renders warmer")
    let cool = try pixel(render(gray, ImageAdjustments(temperature: -60)))
    XCTAssertGreaterThan(cool.b, cool.r + 0.05, "-temperature renders cooler")
    let magenta = try pixel(render(gray, ImageAdjustments(tint: 60)))
    XCTAssertLessThan(magenta.g, min(magenta.r, magenta.b), "+tint renders magenta")
  }

  func testExposureAndShadowsLiftLuminance() throws {
    let gray = try XCTUnwrap(TestImageFactory.solidColor(width: 16, height: 16, red: 70, green: 70, blue: 70))
    let base = try pixel(gray).g
    XCTAssertGreaterThan(try pixel(render(gray, ImageAdjustments(exposure: 50))).g, base + 0.05)
    XCTAssertGreaterThan(try pixel(render(gray, ImageAdjustments(shadows: 100))).g, base + 0.02)
  }

  func testToneCurveStaysMonotonicAtExtremes() {
    let extremes = [-100.0, 100.0]
    for highlights in extremes { for shadows in extremes { for whites in extremes { for blacks in extremes {
      let points = AnnotateImageAdjustmentRenderer.toneCurvePoints(
        ImageAdjustments(highlights: highlights, shadows: shadows, whites: whites, blacks: blacks)
      )
      for (a, b) in zip(points, points.dropFirst()) {
        XCTAssertLessThan(a.x, b.x)
        XCTAssertLessThan(a.y, b.y)
      }
    } } } }
  }

  func testVignetteDarkensCornersNotCenter() throws {
    let gray = try XCTUnwrap(TestImageFactory.solidColor(width: 64, height: 64, red: 200, green: 200, blue: 200))
    let rendered = try render(gray, ImageAdjustments(vignette: -100))
    XCTAssertGreaterThan(try pixel(rendered).g, try pixel(rendered, x: 0, y: 0).g + 0.1)
  }

  func testPresetIntensityBlendsTowardOriginal() throws {
    let color = try XCTUnwrap(TestImageFactory.solidColor(width: 16, height: 16, red: 220, green: 40, blue: 40))
    let full = try pixel(render(color, ImageAdjustments(preset: .mono)))
    let half = try pixel(render(color, ImageAdjustments(preset: .mono, presetIntensity: 50)))
    XCTAssertEqual(full.r, full.g, accuracy: 0.02, "full mono is gray")
    XCTAssertGreaterThan(half.r - half.g, 0.2, "half strength keeps some color")
  }

  func testEveryPresetAndParameterRenders() throws {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 120, height: 80))
    for preset in ImageFilterPreset.allCases {
      XCTAssertEqual(try render(cgImage, ImageAdjustments(preset: preset)).width, 120, preset.rawValue)
    }
    for parameter in ImageAdjustmentParameter.allCases {
      var adjustments = ImageAdjustments()
      adjustments[keyPath: parameter.keyPath] = parameter.range.upperBound
      XCTAssertEqual(try render(cgImage, adjustments).height, 80, parameter.rawValue)
    }
  }

  func testThumbnailBaseIsCenterCroppedToTileSize() throws {
    let wide = try XCTUnwrap(TestImageFactory.solidColor(width: 1600, height: 400))
    let thumbnail = try XCTUnwrap(AnnotateImageAdjustmentRenderer.makeThumbnailBase(wide, pixelSize: CGSize(width: 168, height: 168)))
    XCTAssertEqual(thumbnail.width, 168)
    XCTAssertEqual(thumbnail.height, 168)
  }

  @MainActor
  func testSelectingNewPresetRestoresFullStrengthAndGroupReset() throws {
    let state = try makeState()
    state.setImageAdjustments(ImageAdjustments(exposure: 20, temperature: 30, preset: .noir, presetIntensity: 40))
    state.selectImageFilterPreset(.noir)
    XCTAssertEqual(state.imageAdjustments.presetIntensity, 40, "re-picking keeps strength")
    state.selectImageFilterPreset(.sepia)
    XCTAssertEqual(state.imageAdjustments.presetIntensity, 100)

    state.resetImageAdjustmentGroup(.light)
    XCTAssertEqual(state.imageAdjustments.exposure, 0)
    XCTAssertEqual(state.imageAdjustments.temperature, 30, "other groups untouched")
    XCTAssertEqual(state.imageAdjustments.preset, .sepia)
  }

  func testNegativeClaritySoftensEdges() throws {
    let edge = try XCTUnwrap(TestImageFactory.solidColor(width: 64, height: 64, red: 40, green: 40, blue: 40))
    // Left half dark, right half bright: build via the renderer-independent CGContext.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(edge, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
    let image = try XCTUnwrap(ctx.makeImage())
    let before = try pixel(image, x: 30, y: 32).g
    let after = try pixel(render(image, ImageAdjustments(clarity: -100)), x: 30, y: 32).g
    XCTAssertGreaterThan(after, before + 0.03, "dark side next to the edge picks up blur")
  }
}
