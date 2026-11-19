//
//  QuickAccessOptimizeStoreTests.swift
//  SnapzyTests
//
//  A custom optimize that changes the format renames the capture, and picking the
//  original level brings the untouched file back under its first name.
//

import CoreGraphics
import ImageIO
import XCTest
@testable import Snapzy

@MainActor
final class QuickAccessOptimizeStoreTests: XCTestCase {
  private var directory: URL!

  override func setUp() async throws {
    try await super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuickAccessOptimizeStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    QuickAccessManager.shared.dismissAll()
    try? FileManager.default.removeItem(at: directory)
    try await super.tearDown()
  }

  func testFormatChangeRenamesCaptureAndOriginalRestoresIt() async throws {
    let pngURL = directory.appendingPathComponent("capture.png")
    let image = try XCTUnwrap(makeImage(width: 900, height: 600))
    let pngData = try XCTUnwrap(QuickAccessImageOptimizer.encode(image, fileExtension: "png", scale: 2))
    try pngData.write(to: pngURL)

    let manager = QuickAccessManager.shared
    let added = await manager.addScreenshot(url: pngURL)
    let item = try XCTUnwrap(added)
    let store = QuickAccessOptimizeStore.shared

    try await store.apply(
      .custom(QuickAccessOptimizeSettings(scalePercent: 50, format: .webp, qualityPercent: 80, maxFileSize: nil)),
      to: item.id
    )

    let webpURL = directory.appendingPathComponent("capture.webp")
    XCTAssertEqual(manager.items.first { $0.id == item.id }?.url, webpURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: webpURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: pngURL.path))
    XCTAssertNil(store.currentFraction(for: item.id))

    let movedItem = try XCTUnwrap(manager.items.first { $0.id == item.id })
    let plan = try XCTUnwrap(store.plan(for: movedItem))
    XCTAssertEqual(plan.fileExtension, "png")
    let original = try XCTUnwrap(plan.levels.last)
    XCTAssertTrue(original.isOriginal)

    try await store.apply(.level(original), to: item.id)

    XCTAssertEqual(manager.items.first { $0.id == item.id }?.url, pngURL)
    XCTAssertEqual(try Data(contentsOf: pngURL), pngData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: webpURL.path))
    XCTAssertEqual(store.currentFraction(for: item.id), 1)
  }

  func testFormatChangeNeverOverwritesAnotherFile() async throws {
    let pngURL = directory.appendingPathComponent("shot.png")
    let bystanderURL = directory.appendingPathComponent("shot.webp")
    let image = try XCTUnwrap(makeImage(width: 800, height: 500))
    try XCTUnwrap(QuickAccessImageOptimizer.encode(image, fileExtension: "png", scale: 2)).write(to: pngURL)
    try Data("keep me".utf8).write(to: bystanderURL)

    let manager = QuickAccessManager.shared
    let added = await manager.addScreenshot(url: pngURL)
    let item = try XCTUnwrap(added)

    try await QuickAccessOptimizeStore.shared.apply(
      .custom(QuickAccessOptimizeSettings(scalePercent: 100, format: .webp, qualityPercent: 80, maxFileSize: nil)),
      to: item.id
    )

    XCTAssertEqual(try Data(contentsOf: bystanderURL), Data("keep me".utf8))
    XCTAssertEqual(
      manager.items.first { $0.id == item.id }?.url,
      directory.appendingPathComponent("shot 2.webp")
    )
  }

  private func makeImage(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    for index in 0 ..< 12 {
      context.setFillColor(CGColor(red: CGFloat(index) / 12, green: 0.4, blue: 1 - CGFloat(index) / 12, alpha: 1))
      context.fill(CGRect(x: index * width / 12, y: 0, width: width / 12 + 1, height: height))
    }
    return context.makeImage()
  }
}
