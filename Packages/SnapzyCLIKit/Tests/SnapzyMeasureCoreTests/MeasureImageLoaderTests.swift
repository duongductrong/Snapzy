//
//  MeasureImageLoaderTests.swift
//  SnapzyMeasureCoreTests
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SnapzyMeasureCore

final class MeasureImageLoaderTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func writePNG(dpi: Double?) throws -> URL {
    let url = directory.appendingPathComponent("image.png")
    let image = MeasureTestImages.image(width: 40, height: 20, colorSpace: MeasureTestImages.sRGB) { _, _ in (255, 255, 255) }
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let dpi {
      properties[kCGImagePropertyDPIWidth] = dpi
      properties[kCGImagePropertyDPIHeight] = dpi
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }

  func testLoad_readsDPIAsScale() throws {
    let loaded = try MeasureImageLoader.load(url: try writePNG(dpi: 144))
    XCTAssertEqual(loaded.image.width, 40)
    XCTAssertEqual(loaded.scale, 2)
  }

  func testLoad_withoutDPIUsesScaleOne() throws {
    XCTAssertEqual(try MeasureImageLoader.load(url: try writePNG(dpi: nil)).scale, 1)
  }

  func testLoad_missingFile() {
    let url = directory.appendingPathComponent("missing.png")
    XCTAssertThrowsError(try MeasureImageLoader.load(url: url)) { error in
      XCTAssertEqual(error as? MeasureImageLoaderError, .notFound(url.path))
    }
  }

  func testLoad_notAnImage() throws {
    let url = directory.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: url)
    XCTAssertThrowsError(try MeasureImageLoader.load(url: url)) { error in
      XCTAssertEqual(error as? MeasureImageLoaderError, .unreadable(url.path))
    }
  }

  func testLoad_rejectsImagesOverThePixelCap() throws {
    let url = try writePNG(dpi: nil)
    XCTAssertThrowsError(try MeasureImageLoader.load(url: url, maxPixels: 100)) { error in
      XCTAssertEqual(error as? MeasureImageLoaderError, .tooLarge(width: 40, height: 20, maxPixels: 100))
    }
  }

  func testScale_roundsNearRetinaDPI() {
    XCTAssertEqual(MeasureImageLoader.scale(from: [kCGImagePropertyDPIWidth: 143.99]), 2)
    XCTAssertEqual(MeasureImageLoader.scale(from: [kCGImagePropertyDPIWidth: 72]), 1)
    XCTAssertEqual(MeasureImageLoader.scale(from: [kCGImagePropertyDPIWidth: 5000]), 1)
  }
}
