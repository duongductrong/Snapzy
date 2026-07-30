//
//  QuickAccessClipboardPreservationTests.swift
//  SnapzyTests
//
//  Verify that dismissing a Quick Access card does NOT delete a temp capture
//  while the general pasteboard still references it (#234), and that deletion
//  proceeds normally once the pasteboard has moved on.
//

import AppKit
@testable import Snapzy
import XCTest

@MainActor
final class QuickAccessClipboardPreservationTests: XCTestCase {
  private var originalHistoryEnabled: Bool?
  private var testFiles: [URL] = []

  override func setUp() {
    super.setUp()
    originalHistoryEnabled = UserDefaults.standard.object(forKey: PreferencesKeys.historyEnabled) as? Bool
    // Isolate the pasteboard-reference path from the history-preservation path.
    UserDefaults.standard.set(false, forKey: PreferencesKeys.historyEnabled)
    ClipboardHelper.resetPasteboardReferenceTracking()
  }

  override func tearDown() async throws {
    QuickAccessManager.shared.dismissAll()

    for url in testFiles {
      CaptureHistoryStore.shared.removeByFilePath(url.path)
      try? FileManager.default.removeItem(at: url)
    }
    testFiles.removeAll()

    if let originalHistoryEnabled {
      UserDefaults.standard.set(originalHistoryEnabled, forKey: PreferencesKeys.historyEnabled)
    } else {
      UserDefaults.standard.removeObject(forKey: PreferencesKeys.historyEnabled)
    }
    ClipboardHelper.resetPasteboardReferenceTracking()
    try await super.tearDown()
  }

  // MARK: - Helpers

  private func createTempCapture() throws -> URL {
    let directory = TempCaptureManager.shared.tempCaptureDirectory
    let fileURL = directory.appendingPathComponent("test_\(UUID().uuidString).png")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      throw XCTSkip("Failed to create test image")
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    guard let data = AnnotateExporter.imageData(from: nsImage, for: "png") else {
      throw XCTSkip("Failed to encode test image")
    }
    try data.write(to: fileURL)
    testFiles.append(fileURL)
    return fileURL
  }

  private func addAndRemoveItem(for fileURL: URL) async throws {
    await QuickAccessManager.shared.addScreenshot(url: fileURL)
    let item = try XCTUnwrap(
      QuickAccessManager.shared.items.first { $0.url == fileURL },
      "Quick Access item should have been added"
    )
    QuickAccessManager.shared.removeItem(id: item.id)
  }

  private func settleCleanup() async {
    // scheduleDismissCleanup runs in a Task after `Task.yield()`; give it a
    // few run-loop turns to execute before asserting.
    try? await Task.sleep(nanoseconds: 300_000_000)
  }

  private func waitUntil(
    timeout: TimeInterval = 1.0,
    condition: @escaping @MainActor () -> Bool
  ) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return true
      }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
  }

  // MARK: - Tests

  func testDismissedTempFile_isPreservedWhileReferencedByPasteboard() async throws {
    let fileURL = try createTempCapture()
    // Simulate the post-capture auto copy-to-clipboard.
    ClipboardHelper.copyImage(from: fileURL)
    XCTAssertTrue(ClipboardHelper.isReferencedByGeneralPasteboard(fileURL))

    try await addAndRemoveItem(for: fileURL)
    await settleCleanup()

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: fileURL.path),
      "Temp file must survive dismiss cleanup while the pasteboard references it (#234)"
    )
  }

  func testDismissedTempFile_isDeletedWhenNotOnPasteboard() async throws {
    let fileURL = try createTempCapture()
    // No clipboard copy — cleanup must behave as before.

    try await addAndRemoveItem(for: fileURL)

    let didDelete = await waitUntil {
      !FileManager.default.fileExists(atPath: fileURL.path)
    }
    XCTAssertTrue(didDelete, "Unreferenced temp file should still be auto-deleted on dismiss")
  }

  func testDismissedTempFile_isDeletedAfterPasteboardMovesOn() async throws {
    let fileURL = try createTempCapture()
    ClipboardHelper.copyImage(from: fileURL)
    XCTAssertTrue(ClipboardHelper.isReferencedByGeneralPasteboard(fileURL))

    // The user copies something else before dismissing the card.
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("unrelated content", forType: .string)

    try await addAndRemoveItem(for: fileURL)

    let didDelete = await waitUntil {
      !FileManager.default.fileExists(atPath: fileURL.path)
    }
    XCTAssertTrue(
      didDelete,
      "Once newer clipboard content exists, the temp file must not be kept alive"
    )
  }
}
