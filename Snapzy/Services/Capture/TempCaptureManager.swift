//
//  TempCaptureManager.swift
//  Snapzy
//
//  Manages temporary capture files for the "Auto-save" toggle.
//  When auto-save is OFF, captures are stored in a temp directory.
//  Users can manually save via Quick Access Card or dismiss to delete.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "TempCaptureManager")

/// Manages lifecycle of temporary capture files when auto-save is disabled
@MainActor
final class TempCaptureManager {

  static let shared = TempCaptureManager()

  private let preferencesManager = PreferencesManager.shared
  private let fileAccessManager = SandboxFileAccessManager.shared

  /// Temp directory for unsaved captures (Application Support/Snapzy/Captures/).
  /// Uses Application Support instead of /tmp/ so macOS won't purge files
  /// during drag-and-drop — same pattern as CleanShot X.
  let tempCaptureDirectory: URL = {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else {
      // Fallback if Application Support unavailable
      let fallback = FileManager.default.temporaryDirectory
        .appendingPathComponent("Snapzy_Captures", isDirectory: true)
      try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
      return fallback
    }
    let capturesDir = appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("Captures", isDirectory: true)
    try? FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
    return capturesDir
  }()

  private init() {}

  // MARK: - Public API

  /// Resolve save directory based on auto-save toggle state.
  /// Returns temp directory if auto-save is OFF, export directory if ON.
  func resolveSaveDirectory(
    for captureType: CaptureType,
    exportDirectory: URL
  ) -> URL {
    let autoSaveEnabled = preferencesManager.isActionEnabled(.save, for: captureType)
    let typeLabel = captureType == .screenshot ? "screenshot" : "recording"

    if autoSaveEnabled {
      print("[Snapzy:TempCapture] Auto-save ON (\(typeLabel)) → export dir")
      logger.info("Auto-save ON for \(typeLabel), using export directory")
      DiagnosticLogger.shared.log(.info, .capture, "[TempCapture] Auto-save ON (\(typeLabel)) → export dir")
      return exportDirectory
    }

    // Auto-save OFF: use temp directory
    print("[Snapzy:TempCapture] Auto-save OFF (\(typeLabel)) → temp dir")
    logger.info("Auto-save OFF for \(typeLabel), using temp directory")
    DiagnosticLogger.shared.log(.info, .capture, "[TempCapture] Auto-save OFF (\(typeLabel)) → temp dir")
    return tempCaptureDirectory
  }

  /// Move a temp file to the permanent export location.
  /// Returns the new URL on success, nil on failure.
  func saveToExportLocation(tempURL: URL) -> URL? {
    guard isTempFile(tempURL) else {
      logger.warning("saveToExportLocation called on non-temp file: \(tempURL.lastPathComponent)")
      return nil
    }

    let exportDir = fileAccessManager.resolvedExportDirectoryURL()
    let exportAccess = fileAccessManager.beginAccessingURL(exportDir)
    defer { exportAccess.stop() }

    let destinationURL = exportAccess.url.appendingPathComponent(tempURL.lastPathComponent)

    do {
      // Create export directory if needed
      try FileManager.default.createDirectory(
        at: exportAccess.url,
        withIntermediateDirectories: true
      )

      // Move file from temp to export
      try FileManager.default.moveItem(at: tempURL, to: destinationURL)

      // Also move recording metadata if it exists (for video files)
      moveRecordingMetadataIfNeeded(from: tempURL, to: destinationURL)

      print("[Snapzy:TempCapture] Saved to export: \(destinationURL.lastPathComponent)")
      logger.info("Saved temp file to export: \(destinationURL.lastPathComponent)")
      DiagnosticLogger.shared.log(.info, .action, "[TempCapture] Saved to export: \(destinationURL.lastPathComponent)")
      return destinationURL
    } catch {
      print("[Snapzy:TempCapture] Save failed: \(error.localizedDescription)")
      logger.error("Failed to save temp file: \(error.localizedDescription)")
      DiagnosticLogger.shared.log(.error, .action, "[TempCapture] Save failed: \(error.localizedDescription)")
      return nil
    }
  }

  /// Delete a temp file
  func deleteTempFile(at url: URL) {
    guard isTempFile(url) else { return }

    do {
      try FileManager.default.removeItem(at: url)
      // Also clean up recording metadata if exists
      try? RecordingMetadataStore.delete(for: url)
      print("[Snapzy:TempCapture] Deleted temp: \(url.lastPathComponent)")
      logger.debug("Deleted temp file: \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.info, .action, "[TempCapture] Deleted temp: \(url.lastPathComponent)")
    } catch {
      print("[Snapzy:TempCapture] Delete failed: \(url.lastPathComponent) — \(error.localizedDescription)")
      logger.error("Failed to delete temp file: \(error.localizedDescription)")
      DiagnosticLogger.shared.log(.error, .action, "[TempCapture] Delete failed: \(url.lastPathComponent) — \(error.localizedDescription)")
    }
  }

  /// Check if a URL is in the temp capture directory
  func isTempFile(_ url: URL) -> Bool {
    let tempPath = tempCaptureDirectory.standardizedFileURL.path
    let filePath = url.standardizedFileURL.path
    return filePath.hasPrefix(tempPath)
  }

  /// Cleanup all orphaned temp files (call on app launch)
  func cleanupOrphanedFiles() {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
      at: tempCaptureDirectory,
      includingPropertiesForKeys: nil
    ) else { return }

    var count = 0
    for fileURL in contents {
      do {
        try fm.removeItem(at: fileURL)
        try? RecordingMetadataStore.delete(for: fileURL)
        count += 1
      } catch {
        logger.error("Failed to cleanup orphan: \(fileURL.lastPathComponent)")
      }
    }

    if count > 0 {
      print("[Snapzy:TempCapture] Startup cleanup: removed \(count) orphaned file(s)")
      logger.info("Cleaned up \(count) orphaned temp capture file(s)")
      DiagnosticLogger.shared.log(.info, .lifecycle, "[TempCapture] Startup cleanup: removed \(count) orphaned file(s)")
    }
  }

  // MARK: - Private

  /// Move associated recording metadata sidecar when saving a video
  private func moveRecordingMetadataIfNeeded(from sourceURL: URL, to destinationURL: URL) {
    // RecordingMetadataStore uses a sidecar file pattern
    // We need to re-save metadata at the new location
    if let metadata = RecordingMetadataStore.load(for: sourceURL) {
      try? RecordingMetadataStore.save(metadata, for: destinationURL)
      try? RecordingMetadataStore.delete(for: sourceURL)
    }
  }
}
