//
//  ClipboardHelperPasteboardReferenceTests.swift
//  SnapzyTests
//
//  Verify that Snapzy tracks which file URL the general pasteboard currently
//  references, so temp-file cleanup can preserve paste-integrity (#234).
//

import AppKit
@testable import Snapzy
import XCTest

@MainActor
final class ClipboardHelperPasteboardReferenceTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    ClipboardHelper.resetPasteboardReferenceTracking()
    tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    ClipboardHelper.resetPasteboardReferenceTracking()
    if let tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    tempDir = nil
    super.tearDown()
  }

  // MARK: - Helpers

  private func createPNGFile(named name: String = "test.png") throws -> URL {
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      throw XCTSkip("Failed to create test image")
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    guard let data = AnnotateExporter.imageData(from: nsImage, for: "png") else {
      throw XCTSkip("Failed to encode test image")
    }
    let fileURL = tempDir.appendingPathComponent(name)
    try data.write(to: fileURL)
    return fileURL
  }

  // MARK: - Tests

  func testCopyImage_marksFileAsReferencedByPasteboard() throws {
    let fileURL = try createPNGFile()

    ClipboardHelper.copyImage(from: fileURL)

    XCTAssertTrue(
      ClipboardHelper.isReferencedByGeneralPasteboard(fileURL),
      "Freshly copied file should be reported as referenced by the pasteboard"
    )
    XCTAssertFalse(
      ClipboardHelper.isReferencedByGeneralPasteboard(tempDir.appendingPathComponent("other.png")),
      "A file that was never copied should not be reported as referenced"
    )
  }

  func testNewerClipboardContent_releasesReference() throws {
    let fileURL = try createPNGFile()
    ClipboardHelper.copyImage(from: fileURL)
    XCTAssertTrue(ClipboardHelper.isReferencedByGeneralPasteboard(fileURL))

    // Simulate the user copying something else anywhere on the system.
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("unrelated content", forType: .string)

    XCTAssertFalse(
      ClipboardHelper.isReferencedByGeneralPasteboard(fileURL),
      "Once the pasteboard holds newer content, the file must be released for deletion"
    )
  }

  func testCopyMediaFile_marksFileAsReferenced() throws {
    let fileURL = tempDir.appendingPathComponent("recording.mp4")
    try Data([0, 1, 2, 3]).write(to: fileURL)

    ClipboardHelper.copyMediaFile(from: fileURL)

    XCTAssertTrue(ClipboardHelper.isReferencedByGeneralPasteboard(fileURL))
  }

  func testCopyFileURLs_marksAllFilesAsReferenced() throws {
    let url1 = tempDir.appendingPathComponent("file1.png")
    let url2 = tempDir.appendingPathComponent("file2.png")
    try Data([1, 2, 3]).write(to: url1)
    try Data([4, 5, 6]).write(to: url2)

    ClipboardHelper.copyFileURLs([url1, url2])

    XCTAssertTrue(ClipboardHelper.isReferencedByGeneralPasteboard(url1))
    XCTAssertTrue(ClipboardHelper.isReferencedByGeneralPasteboard(url2))
  }

  func testMissingFileCopy_doesNotMarkReference() {
    let missingURL = tempDir.appendingPathComponent("missing.png")

    ClipboardHelper.copyImage(from: missingURL)

    XCTAssertFalse(
      ClipboardHelper.isReferencedByGeneralPasteboard(missingURL),
      "A failed copy must not mark the file as referenced"
    )
  }
}
