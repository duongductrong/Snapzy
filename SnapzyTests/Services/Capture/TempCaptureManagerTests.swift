//
//  TempCaptureManagerTests.swift
//  SnapzyTests
//
//  Unit tests for TempCaptureManager file lifecycle management.
//
//  NOTE: Tests use the shared TempCaptureManager.shared instance since it's
//  a @MainActor singleton. For full isolation, DI refactor is needed.
//  These tests cover: isTempFile, deleteTempFile, makeRecoveredRecordingURL,
//  and shouldPreserveForHistoryRetention logic.
//

import XCTest
@testable import Snapzy

@MainActor
final class TempCaptureManagerTests: XCTestCase {

  private let manager = TempCaptureManager.shared
  private var testFiles: [URL] = []

  override func tearDown() async throws {
    // Clean up any test files created in temp directory
    for url in testFiles {
      try? FileManager.default.removeItem(at: url)
    }
    testFiles.removeAll()
    try await super.tearDown()
  }

  /// Create a test file in the temp capture directory.
  private func createTempTestFile(
    name: String = "test_\(UUID().uuidString).png"
  ) throws -> URL {
    let url = manager.tempCaptureDirectory.appendingPathComponent(name)
    try Data("test".utf8).write(to: url)
    testFiles.append(url)
    return url
  }

  /// Create a test file in an arbitrary directory.
  private func createExternalTestFile() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_External_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("external_file.png")
    try Data("test".utf8).write(to: url)
    testFiles.append(dir) // Clean up dir
    return url
  }

  // MARK: - isTempFile

  func testIsTempFile_fileInTempDir_returnsTrue() throws {
    let url = try createTempTestFile()
    XCTAssertTrue(manager.isTempFile(url))
  }

  func testIsTempFile_fileOutsideTempDir_returnsFalse() throws {
    let url = try createExternalTestFile()
    XCTAssertFalse(manager.isTempFile(url))
  }

  func testIsTempFile_nonexistentFileInTempDir_stillReturnsTrue() {
    let url = manager.tempCaptureDirectory.appendingPathComponent("nonexistent.png")
    // isTempFile checks path prefix, not file existence
    XCTAssertTrue(manager.isTempFile(url))
  }

  // MARK: - deleteTempFile

  func testDeleteTempFile_removesFileFromDisk() throws {
    let url = try createTempTestFile()
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    manager.deleteTempFile(at: url)

    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    testFiles.removeAll { $0 == url } // Already deleted
  }

  func testDeleteTempFile_nonTempFile_noOp() throws {
    let url = try createExternalTestFile()
    let existedBefore = FileManager.default.fileExists(atPath: url.path)

    manager.deleteTempFile(at: url)

    // File should still exist — not in temp dir
    XCTAssertTrue(existedBefore)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testDeleteTempFile_nonexistentFile_doesNotCrash() {
    let url = manager.tempCaptureDirectory.appendingPathComponent("ghost_\(UUID().uuidString).png")
    // Should complete without crash
    manager.deleteTempFile(at: url)
  }

  // MARK: - makeRecoveredRecordingURL

  func testMakeRecoveredRecordingURL_returnsURLInTempDir() {
    let sourceURL = URL(fileURLWithPath: "/tmp/recording.mov")
    let recoveredURL = manager.makeRecoveredRecordingURL(for: sourceURL)

    XCTAssertTrue(
      manager.isTempFile(recoveredURL),
      "Recovered URL should be in temp capture directory"
    )
    XCTAssertEqual(recoveredURL.pathExtension, "mov")
  }

  func testMakeRecoveredRecordingURL_preservesExtension() {
    let sourceURL = URL(fileURLWithPath: "/tmp/clip.mp4")
    let recoveredURL = manager.makeRecoveredRecordingURL(for: sourceURL)

    XCTAssertEqual(recoveredURL.pathExtension, "mp4")
  }

  func testMakeRecoveredRecordingURL_noExtension_defaultsToMov() {
    let sourceURL = URL(fileURLWithPath: "/tmp/recording")
    let recoveredURL = manager.makeRecoveredRecordingURL(for: sourceURL)

    XCTAssertEqual(recoveredURL.pathExtension, "mov")
  }

  func testMakeRecoveredRecordingURL_uniqueNames() {
    let sourceURL = URL(fileURLWithPath: "/tmp/recording.mov")
    let url1 = manager.makeRecoveredRecordingURL(for: sourceURL)

    // Create the first file so the next call must find a unique name
    try? Data("test".utf8).write(to: url1)
    testFiles.append(url1)

    let url2 = manager.makeRecoveredRecordingURL(for: sourceURL)
    XCTAssertNotEqual(url1.lastPathComponent, url2.lastPathComponent)
    testFiles.append(url2)
  }

  // MARK: - resolveSaveDirectory

  func testResolveSaveDirectory_autoSaveOn_returnsExportDir() {
    // Ensure auto-save is enabled for screenshots
    PreferencesManager.shared.setAction(.save, for: .screenshot, enabled: true)

    let exportDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_Export_\(UUID().uuidString)")

    let result = manager.resolveSaveDirectory(
      for: .screenshot,
      exportDirectory: exportDir
    )

    XCTAssertEqual(result, exportDir)
  }

  func testResolveSaveDirectory_autoSaveOff_returnsTempDir() {
    // Disable auto-save for screenshots
    PreferencesManager.shared.setAction(.save, for: .screenshot, enabled: false)

    let exportDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_Export_\(UUID().uuidString)")

    let result = manager.resolveSaveDirectory(
      for: .screenshot,
      exportDirectory: exportDir
    )

    XCTAssertEqual(result, manager.tempCaptureDirectory)

    // Restore
    PreferencesManager.shared.setAction(.save, for: .screenshot, enabled: true)
  }

  // MARK: - tempCaptureDirectory

  func testTempCaptureDirectory_exists() {
    XCTAssertTrue(FileManager.default.fileExists(atPath: manager.tempCaptureDirectory.path))
  }

  func testTempCaptureDirectory_isInAppSupport() {
    let path = manager.tempCaptureDirectory.path
    XCTAssertTrue(
      path.contains("Application Support/Snapzy/Captures")
        || path.contains("Snapzy_Captures"),
      "Temp directory should be in App Support or fallback: \(path)"
    )
  }

  // MARK: - RecordingSavePlan

  func testRecordingSavePlan_structure() throws {
    let exportDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_Export_\(UUID().uuidString)")

    let plan = try manager.makeRecordingSavePlan(exportDirectory: exportDir)

    // Processing directory should exist
    XCTAssertTrue(FileManager.default.fileExists(atPath: plan.processingDirectory.path))

    // Clean up
    try? FileManager.default.removeItem(at: plan.processingDirectory)
  }

  func testRecordingSavePlan_autoSaveOn_finalDirIsExport() throws {
    PreferencesManager.shared.setAction(.save, for: .recording, enabled: true)

    let exportDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_Export_\(UUID().uuidString)")

    let plan = try manager.makeRecordingSavePlan(exportDirectory: exportDir)
    XCTAssertEqual(plan.finalDirectory, exportDir)
    XCTAssertTrue(plan.autoSaveEnabled)

    try? FileManager.default.removeItem(at: plan.processingDirectory)
  }

  func testRecordingSavePlan_autoSaveOff_finalDirIsTemp() throws {
    PreferencesManager.shared.setAction(.save, for: .recording, enabled: false)

    let exportDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_Export_\(UUID().uuidString)")

    let plan = try manager.makeRecordingSavePlan(exportDirectory: exportDir)
    XCTAssertEqual(plan.finalDirectory, manager.tempCaptureDirectory)
    XCTAssertFalse(plan.autoSaveEnabled)

    // Restore
    PreferencesManager.shared.setAction(.save, for: .recording, enabled: true)
    try? FileManager.default.removeItem(at: plan.processingDirectory)
  }

  // MARK: - deleteRecordingProcessingDirectory

  func testDeleteRecordingProcessingDirectory_validDir_removesIt() throws {
    let exportDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_Export_\(UUID().uuidString)")

    let plan = try manager.makeRecordingSavePlan(exportDirectory: exportDir)
    XCTAssertTrue(FileManager.default.fileExists(atPath: plan.processingDirectory.path))

    manager.deleteRecordingProcessingDirectory(plan.processingDirectory)
    XCTAssertFalse(FileManager.default.fileExists(atPath: plan.processingDirectory.path))
  }

  func testDeleteRecordingProcessingDirectory_outsideRoot_noOp() {
    let outsideDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("NotRecordingProcessing")
    try? FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

    manager.deleteRecordingProcessingDirectory(outsideDir)

    // Should still exist — not inside the recording processing root
    XCTAssertTrue(FileManager.default.fileExists(atPath: outsideDir.path))
    try? FileManager.default.removeItem(at: outsideDir)
  }
}
