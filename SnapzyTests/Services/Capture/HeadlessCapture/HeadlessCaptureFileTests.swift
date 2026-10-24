//
//  HeadlessCaptureFileTests.swift
//  SnapzyTests
//
//  Staging folder naming/retention and the max-dimension post-processor.
//

import ImageIO
@testable import Snapzy
import UniformTypeIdentifiers
import XCTest

final class HeadlessCaptureStagingTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HeadlessCaptureStagingTests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testDirectoryIsOutsideTempCaptureRoot() {
    let path = HeadlessCaptureStaging.directory.path

    XCTAssertTrue(path.hasSuffix("Snapzy/CLI/Captures"), path)
    XCTAssertFalse(path.contains("Snapzy/Captures"), "TempCaptureManager sweeps Snapzy/Captures at launch")
  }

  func testFileNameShape() throws {
    let date = try XCTUnwrap(DateComponents(
      calendar: .current,
      year: 2026,
      month: 10,
      day: 25,
      hour: 9,
      minute: 30,
      second: 12
    ).date)
    let name = HeadlessCaptureStaging.makeFileName(now: date)

    XCTAssertTrue(name.hasPrefix("snapzy-cli-20261025-093012-"), name)
    XCTAssertEqual(name.count, "snapzy-cli-20261025-093012-".count + 6)
    XCTAssertNotEqual(name, HeadlessCaptureStaging.makeFileName(now: date))
  }

  func testPrepareCreatesPrivateDirectoryAndSweepsExpiredFiles() throws {
    let now = Date()
    try HeadlessCaptureStaging.prepare(in: directory, now: now)
    let fresh = directory.appendingPathComponent("fresh.png")
    let expired = directory.appendingPathComponent("expired.png")
    try Data("a".utf8).write(to: fresh)
    try Data("b".utf8).write(to: expired)
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-HeadlessCaptureStaging.retention - 60)],
      ofItemAtPath: expired.path
    )

    try HeadlessCaptureStaging.prepare(in: directory, now: now)

    XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
    let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
    XCTAssertEqual(mode, 0o700)
  }
}

final class HeadlessCapturePostProcessorTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HeadlessCapturePostProcessorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  /// A solid image written at `scale`× (DPI = 72 × scale), like Snapzy's saver.
  private func writeImage(width: Int, height: Int, scale: Double, type: UTType, name: String) throws -> URL {
    let context = try XCTUnwrap(CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())

    let url = directory.appendingPathComponent(name)
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    let dpi = scale * 72
    CGImageDestinationAddImage(destination, image, [
      kCGImagePropertyDPIWidth: dpi,
      kCGImagePropertyDPIHeight: dpi,
    ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }

  func testFileInfoReadsSizeAndScale() throws {
    let url = try writeImage(width: 400, height: 200, scale: 2, type: .png, name: "a.png")

    let info = try HeadlessCapturePostProcessor.fileInfo(at: url)

    XCTAssertEqual(info.pixelWidth, 400)
    XCTAssertEqual(info.pixelHeight, 200)
    XCTAssertEqual(info.scale, 2, accuracy: 0.001)
    XCTAssertGreaterThan(info.byteCount, 0)
  }

  func testDownscaleKeepsAspectRatioAndAdjustsScale() throws {
    let url = try writeImage(width: 400, height: 200, scale: 2, type: .png, name: "b.png")

    try HeadlessCapturePostProcessor.downscale(fileAt: url, format: .png, maxDimension: 100)
    let info = try HeadlessCapturePostProcessor.fileInfo(at: url)

    XCTAssertEqual(info.pixelWidth, 100)
    XCTAssertEqual(info.pixelHeight, 50)
    XCTAssertEqual(info.scale, 0.5, accuracy: 0.001)
  }

  func testProcessKeepsDPIScaleForPNG() throws {
    let url = try writeImage(width: 400, height: 200, scale: 2, type: .png, name: "e.png")

    let info = try HeadlessCapturePostProcessor.process(fileAt: url, format: .png, maxDimension: 200, displayScale: 3)

    XCTAssertEqual(info.pixelWidth, 200)
    XCTAssertEqual(info.scale, 1, accuracy: 0.01, "PNG scale comes from its DPI, not the display")
  }

  func testDownscaleNeverUpscales() throws {
    let url = try writeImage(width: 80, height: 40, scale: 1, type: .png, name: "c.png")

    try HeadlessCapturePostProcessor.downscale(fileAt: url, format: .png, maxDimension: 1568)

    XCTAssertEqual(try HeadlessCapturePostProcessor.fileInfo(at: url).pixelWidth, 80)
  }

  func testDownscaleKeepsJPEG() throws {
    let url = try writeImage(width: 300, height: 600, scale: 2, type: .jpeg, name: "d.jpg")

    try HeadlessCapturePostProcessor.downscale(fileAt: url, format: .jpeg(quality: 0.8), maxDimension: 150)

    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    let info = try HeadlessCapturePostProcessor.fileInfo(at: url)
    XCTAssertEqual(info.pixelWidth, 75)
    XCTAssertEqual(info.pixelHeight, 150)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
    XCTAssertEqual(leftovers, [])
  }
}
