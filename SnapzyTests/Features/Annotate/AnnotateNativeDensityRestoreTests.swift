//
//  AnnotateNativeDensityRestoreTests.swift
//  SnapzyTests
//
//  Regression tests for native-density (1×) capture restores: annotation sessions
//  must reopen in the exact logical coordinate space they were authored in,
//  regardless of the current main display's scale factor (issue #414 follow-up).
//

import AppKit
import ImageIO
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateNativeDensityRestoreTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_AnnotateNativeDensity_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    super.tearDown()
  }

  // MARK: - File DPI density (Layer 2: file opens trust the file, not the screen)

  func testFileDensityScaleFactor_readsSnapzyWrittenDPI() throws {
    let retinaURL = try writePNG(named: "retina.png", pixelWidth: 400, pixelHeight: 300, dpi: 144)
    XCTAssertEqual(try XCTUnwrap(AnnotateState.fileDensityScaleFactor(from: retinaURL)), 2.0, accuracy: 0.001)

    let nativeURL = try writePNG(named: "native.png", pixelWidth: 400, pixelHeight: 300, dpi: 72)
    XCTAssertEqual(try XCTUnwrap(AnnotateState.fileDensityScaleFactor(from: nativeURL)), 1.0, accuracy: 0.001)
  }

  func testFileDensityScaleFactor_returnsNilWithoutDPIMetadata() throws {
    let url = try writePNG(named: "nodpi.png", pixelWidth: 400, pixelHeight: 300, dpi: nil)
    XCTAssertNil(AnnotateState.fileDensityScaleFactor(from: url))
  }

  func testLoadImageWithCorrectScale_keepsNative1xCaptureAtAuthoredLogicalSize() throws {
    // A non-Retina (1×) capture must keep pixel == logical size even when the
    // main display is Retina — the pre-fix heuristic halved it here.
    let url = try writePNG(named: "capture1x.png", pixelWidth: 400, pixelHeight: 300, dpi: 72)

    let image = try XCTUnwrap(AnnotateState.loadImageWithCorrectScale(from: url))

    XCTAssertEqual(image.size.width, 400, accuracy: 0.5)
    XCTAssertEqual(image.size.height, 300, accuracy: 0.5)
  }

  func testLoadImageWithCorrectScale_normalizesRetinaCaptureFromFileDPI() throws {
    // A 2× capture must normalize to points even when the main display is 1×.
    let url = try writePNG(named: "capture2x.png", pixelWidth: 400, pixelHeight: 300, dpi: 144)

    let image = try XCTUnwrap(AnnotateState.loadImageWithCorrectScale(from: url))

    XCTAssertEqual(image.size.width, 200, accuracy: 0.5)
    XCTAssertEqual(image.size.height, 150, accuracy: 0.5)
  }

  // MARK: - Legacy normalize heuristic branches (pure, screen-independent)

  func testNormalizedRetinaLogicalSize_scale1LeavesImageUntouched() throws {
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)
    XCTAssertNil(AnnotateState.normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: 1.0))
  }

  func testNormalizedRetinaLogicalSize_scale2HalvesPixelSizedImage() throws {
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)
    let normalized = try XCTUnwrap(
      AnnotateState.normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: 2.0)
    )
    XCTAssertEqual(normalized.width, 200, accuracy: 0.001)
    XCTAssertEqual(normalized.height, 150, accuracy: 0.001)
  }

  func testNormalizedRetinaLogicalSize_scale2LeavesAlreadyNormalizedImage() throws {
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)
    image.size = NSSize(width: 200, height: 150)
    XCTAssertNil(AnnotateState.normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: 2.0))
  }

  func testNormalizedRetinaLogicalSize_scale2LeavesNonIntegralDensityUntouched() throws {
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)
    image.size = NSSize(width: 267, height: 200)
    XCTAssertNil(AnnotateState.normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: 2.0))
  }

  // MARK: - Session restore (Layer 1: sidecar logical size wins over the heuristic)

  func testRestoredSessionImage_usesStoredLogicalSizeVerbatim() throws {
    // Authored at 400×300 pt; stored size must win on any display arrangement.
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)

    let restored = AnnotateWindowController.restoredSessionImage(
      image,
      sourceLogicalSize: CGSize(width: 400, height: 300)
    )

    XCTAssertEqual(restored.size.width, 400, accuracy: 0.001)
    XCTAssertEqual(restored.size.height, 300, accuracy: 0.001)
  }

  func testRestoredSessionImage_fallsBackToHeuristicWhenSizeMissing() throws {
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)

    let restored = AnnotateWindowController.restoredSessionImage(image, sourceLogicalSize: nil)

    XCTAssertTrue(restored === image)
  }

  func testRestoredSessionImage_fallsBackToHeuristicWhenSizeIsZero() throws {
    let image = try makePixelBackedImage(pixelWidth: 400, pixelHeight: 300)

    let restored = AnnotateWindowController.restoredSessionImage(image, sourceLogicalSize: .zero)

    XCTAssertTrue(restored === image)
  }

  // MARK: - Helpers

  private func makePixelBackedImage(pixelWidth: Int, pixelHeight: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: pixelWidth, height: pixelHeight))
    // NSBitmapImageRep keeps pixelsWide == CGImage width; NSImage(cgImage:size:)
    // would rasterize an NSCGImageSnapshotRep at the host screen's backing scale.
    let rep = NSBitmapImageRep(cgImage: cgImage)
    let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
    image.addRepresentation(rep)
    return image
  }

  /// Writes a PNG the way `ScreenCaptureManager.imageDestinationProperties` does:
  /// DPI = scale × 72 when provided, no density metadata otherwise.
  private func writePNG(named name: String, pixelWidth: Int, pixelHeight: Int, dpi: Double?) throws -> URL {
    let url = tempDirectory.appendingPathComponent(name)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: pixelWidth, height: pixelHeight))
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    )
    var properties: [CFString: Any] = [:]
    if let dpi {
      properties[kCGImagePropertyDPIWidth] = dpi
      properties[kCGImagePropertyDPIHeight] = dpi
    }
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }
}
