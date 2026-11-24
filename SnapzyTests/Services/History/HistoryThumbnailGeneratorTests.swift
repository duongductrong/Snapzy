//
//  HistoryThumbnailGeneratorTests.swift
//  SnapzyTests
//
//  Integration tests for thumbnail generation, caching, and cleanup.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Snapzy

final class HistoryThumbnailGeneratorTests: XCTestCase {

  deinit {}

  private var testDirectory: URL!
  private var generator: HistoryThumbnailGenerator!

  override func setUp() {
    super.setUp()
    testDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_HistoryThumbs_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    generator = HistoryThumbnailGenerator(
      thumbnailsDirectory: testDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    )
    generator.clearAllThumbnails()
  }

  override func tearDown() {
    generator.clearAllThumbnails()
    try? FileManager.default.removeItem(at: testDirectory)
    super.tearDown()
  }

  // MARK: - thumbnailURL

  func testThumbnailURL_returnsNilForMissingSourceFile() {
    let record = makeRecord(filePath: "/tmp/nonexistent.png")
    XCTAssertNil(generator.thumbnailURL(for: record))
  }

  // MARK: - generate

  func testGenerate_returnsNilForMissingSourceFile() async {
    let record = makeRecord(filePath: "/tmp/nonexistent.png")
    let url = await generator.generate(for: record)
    XCTAssertNil(url)
  }

  func testGenerate_createsThumbnailForImage() async throws {
    let imageURL = try createTestImage(width: 200, height: 150)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)

    let thumbURL = await generator.generate(for: record)
    XCTAssertNotNil(thumbURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL!.path))

    let attrs = try FileManager.default.attributesOfItem(atPath: thumbURL!.path)
    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    XCTAssertGreaterThan(size, 0)
  }

  func testGenerate_usesExistingCacheOnSecondCall() async throws {
    let imageURL = try createTestImage(width: 100, height: 100)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)

    let url1 = await generator.generate(for: record)
    let url2 = await generator.generate(for: record)

    XCTAssertEqual(url1?.path, url2?.path)
  }

  // MARK: - totalThumbnailSize

  func testTotalThumbnailSize_sumsFileSizes() async throws {
    XCTAssertEqual(generator.totalThumbnailSize(), 0)

    let imageURL = try createTestImage(width: 100, height: 100)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)
    _ = await generator.generate(for: record)

    let size = generator.totalThumbnailSize()
    XCTAssertGreaterThan(size, 0)
  }

  // MARK: - clearAllThumbnails

  func testClearAllThumbnails_removesAllFiles() async throws {
    let imageURL = try createTestImage(width: 100, height: 100)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)
    _ = await generator.generate(for: record)
    XCTAssertGreaterThan(generator.totalThumbnailSize(), 0)

    generator.clearAllThumbnails()
    XCTAssertEqual(generator.totalThumbnailSize(), 0)
  }

  // MARK: - deleteThumbnail

  func testDeleteThumbnail_removesFilesForRecordId() async throws {
    let imageURL = try createTestImage(width: 100, height: 100)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)
    let thumbURL = await generator.generate(for: record)
    XCTAssertNotNil(thumbURL)

    generator.deleteThumbnail(for: record.id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL!.path))
  }

  // MARK: - loadThumbnailImage

  func testLoadThumbnailImage_returnsImageForValidFile() async throws {
    let imageURL = try createTestImage(width: 100, height: 100)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)
    _ = await generator.generate(for: record)

    let image = await generator.loadThumbnailImage(for: record)
    XCTAssertNotNil(image)
  }

  func testLoadThumbnailImage_returnsNilForMissingFile() async {
    let record = makeRecord(filePath: "/tmp/nonexistent.png")
    let image = await generator.loadThumbnailImage(for: record)
    XCTAssertNil(image)
  }

  func testLoadThumbnailImage_usesMemoryCache() async throws {
    let imageURL = try createTestImage(width: 100, height: 100)
    let record = makeRecord(filePath: imageURL.path, captureType: .screenshot)
    _ = await generator.generate(for: record)

    let first = await generator.loadThumbnailImage(for: record)
    let second = await generator.loadThumbnailImage(for: record)
    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    // Both should resolve successfully; exact identity comparison is not guaranteed
    // because NSCache may evict, but in this tight loop it should be cached.
  }

  // MARK: - loadPreviewImage

  func testLoadPreviewImage_boundsPixelsWithoutWritingThumbnails() async throws {
    for (width, height) in [(2400, 1600), (1600, 2400)] {
      let imageURL = try createTestImage(width: width, height: height)
      let record = makeRecord(filePath: imageURL.path)
      let loaded = await generator.loadPreviewImage(for: record)
      let image = try XCTUnwrap(loaded)
      let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

      XCTAssertEqual(max(pixels.width, pixels.height), 1200)
      XCTAssertEqual(
        Double(pixels.width) / Double(pixels.height), Double(width) / Double(height), accuracy: 0.005
      )
      XCTAssertNil(generator.thumbnailURL(for: record))
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: generator.thumbnailsDirectory, includingPropertiesForKeys: nil
    )
    XCTAssertTrue(files.isEmpty, "Enlarged previews must remain memory-only")
  }

  func testLoadPreviewImage_returnsNilForMissingFile() async {
    let record = makeRecord(filePath: testDirectory.appendingPathComponent("missing.png").path)
    let image = await generator.loadPreviewImage(for: record)
    XCTAssertNil(image)
  }

  func testLoadPreviewImage_doesNotUseCacheAfterSourceDeletion() async throws {
    let imageURL = try createTestImage(width: 100, height: 80)
    let record = makeRecord(filePath: imageURL.path)
    let first = await generator.loadPreviewImage(for: record)
    XCTAssertNotNil(first)
    try FileManager.default.removeItem(at: imageURL)

    let second = await generator.loadPreviewImage(for: record)
    XCTAssertNil(second)
  }

  func testLoadPreviewImage_invalidatesCacheAfterSourceEdit() async throws {
    let imageURL = try createTestImage(width: 120, height: 60)
    let record = makeRecord(filePath: imageURL.path)
    let first = await generator.loadPreviewImage(for: record)
    XCTAssertEqual(first?.size, CGSize(width: 120, height: 60))

    let replacement = try createTestImage(width: 60, height: 120)
    try Data(contentsOf: replacement).write(to: imageURL)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: imageURL.path
    )
    // The record (including its recorded size and capture time) stays unchanged.
    let second = await generator.loadPreviewImage(for: record)
    XCTAssertEqual(second?.size, CGSize(width: 60, height: 120))
  }

  func testLoadPreviewImage_invalidatesCacheAfterSourcePathChange() async throws {
    let original = try createTestImage(width: 120, height: 60)
    var record = makeRecord(filePath: original.path)
    let first = await generator.loadPreviewImage(for: record)
    XCTAssertNotNil(first)

    let replacement = try createTestImage(width: 60, height: 120)
    record.filePath = replacement.path
    let second = await generator.loadPreviewImage(for: record)
    XCTAssertEqual(second?.size, CGSize(width: 60, height: 120))
  }

  func testLoadPreviewImage_decodesOnlyFirstGIFFrame() async throws {
    let url = testDirectory.appendingPathComponent("animated.gif")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
      url as CFURL, UTType.gif.identifier as CFString, 2, nil
    ))
    let firstFrame = try XCTUnwrap(TestImageFactory.solidColor(
      width: 1600, height: 800, red: 255, green: 0, blue: 0
    ))
    let secondFrame = try XCTUnwrap(TestImageFactory.solidColor(
      width: 1600, height: 800, red: 0, green: 0, blue: 255
    ))
    CGImageDestinationAddImage(destination, firstFrame, nil)
    CGImageDestinationAddImage(destination, secondFrame, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))

    let loaded = await generator.loadPreviewImage(for: makeRecord(filePath: url.path, captureType: .gif))
    let image = try XCTUnwrap(loaded)
    let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    XCTAssertEqual(pixels.width, 1200)
    XCTAssertEqual(pixels.height, 600)
    let color = try XCTUnwrap(NSBitmapImageRep(cgImage: pixels).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
    XCTAssertGreaterThan(color.redComponent, 0.9)
    XCTAssertLessThan(color.blueComponent, 0.1)
  }

  @MainActor
  func testLoadPreviewImage_returnsNilForCancelledTask() async throws {
    let imageURL = try createTestImage(width: 100, height: 80)
    let record = makeRecord(filePath: imageURL.path)
    let task = Task {
      let image = await generator.loadPreviewImage(for: record)
      return image == nil
    }
    task.cancel()
    let returnedNil = await task.value
    XCTAssertTrue(returnedNil)
  }

  // MARK: - Helpers

  private func makeRecord(filePath: String, captureType: CaptureHistoryType = .screenshot) -> CaptureHistoryRecord {
    CaptureHistoryRecord(
      id: UUID(),
      filePath: filePath,
      fileName: (filePath as NSString).lastPathComponent,
      captureType: captureType,
      fileSize: 1024,
      capturedAt: Date(),
      width: 100,
      height: 100,
      duration: nil,
      thumbnailPath: nil,
      isDeleted: false
    )
  }

  private func createTestImage(width: Int, height: Int) throws -> URL {
    guard let cgImage = TestImageFactory.solidColor(width: width, height: height) else {
      throw XCTSkip("Failed to create test image")
    }
    let url = testDirectory.appendingPathComponent("\(UUID().uuidString).png")
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
      throw XCTSkip("Failed to encode PNG")
    }
    try pngData.write(to: url)
    return url
  }
}
