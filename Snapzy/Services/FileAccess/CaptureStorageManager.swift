//
//  CaptureStorageManager.swift
//  Snapzy
//
//  Manages temporary capture storage in Application Support/Snapzy/Captures.
//  Provides cache size calculation and safe cleanup operations.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "CaptureStorageManager")

@MainActor
final class CaptureStorageManager {
  static let shared = CaptureStorageManager()

  private let fileManager = FileManager.default
  private let appSupportFolderName = "Snapzy"
  private let capturesFolderName = "Captures"

  private init() {}

  // MARK: - Directory

  /// URL to the captures cache directory: Application Support/Snapzy/Captures
  var capturesDirectoryURL: URL? {
    guard
      let appSupportURL = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else {
      return nil
    }

    return appSupportURL
      .appendingPathComponent(appSupportFolderName, isDirectory: true)
      .appendingPathComponent(capturesFolderName, isDirectory: true)
  }

  /// Ensures the captures directory exists, creating it if needed.
  @discardableResult
  func ensureCapturesDirectory() -> URL? {
    guard let url = capturesDirectoryURL else { return nil }

    if !fileManager.fileExists(atPath: url.path) {
      do {
        try fileManager.createDirectory(
          at: url, withIntermediateDirectories: true, attributes: nil)
        logger.info("Created captures directory at \(url.path, privacy: .public)")
      } catch {
        logger.error(
          "Failed to create captures directory: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }

    return url
  }

  // MARK: - Cache Size

  /// Calculates total size of all files in the captures directory (in bytes).
  /// Runs on a background thread.
  func calculateCacheSize() async -> Int64 {
    guard let dirURL = capturesDirectoryURL,
      fileManager.fileExists(atPath: dirURL.path)
    else {
      return 0
    }

    return await Task.detached {
      let fm = FileManager.default
      guard
        let enumerator = fm.enumerator(
          at: dirURL,
          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
          options: [.skipsHiddenFiles],
          errorHandler: nil
        )
      else {
        return Int64(0)
      }

      var totalSize: Int64 = 0
      for case let fileURL as URL in enumerator {
        guard
          let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
          values.isRegularFile == true,
          let size = values.fileSize
        else {
          continue
        }
        totalSize += Int64(size)
      }

      return totalSize
    }.value
  }

  /// Formats a byte count into a human-readable string (e.g. "12.3 MB").
  static func formattedSize(_ bytes: Int64) -> String {
    if bytes == 0 { return L10n.CaptureStorage.empty }

    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  // MARK: - Safety Check

  /// Whether it is safe to perform cache cleanup right now.
  /// Returns `false` if a capture or recording is in progress.
  var isSafeToCleanup: Bool {
    !ScreenCaptureManager.shared.isCapturing
      && !ScreenRecordingManager.shared.isRecording
  }

  // MARK: - Clear Cache

  /// Removes all files in the captures directory while keeping the directory itself.
  /// Gracefully skips files that cannot be deleted (e.g. locked by an active operation).
  /// - Returns: Number of files successfully deleted.
  @discardableResult
  func clearCache() async throws -> Int {
    guard isSafeToCleanup else {
      logger.warning("Cannot clear cache: capture or recording is in progress")
      throw CacheCleanupError.operationInProgress
    }

    guard let dirURL = capturesDirectoryURL,
      fileManager.fileExists(atPath: dirURL.path)
    else {
      return 0
    }

    let deletedPaths = await Task.detached(priority: .utility) { () -> [String] in
      let fm = FileManager.default
      var deletedPaths: [String] = []
      let backgroundLogger = Logger(subsystem: "Snapzy", category: "CaptureStorageManager")

      guard let contents = try? fm.contentsOfDirectory(
        at: dirURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ) else {
        return []
      }

      for fileURL in contents {
        do {
          try fm.removeItem(at: fileURL)
          deletedPaths.append(fileURL.path)
        } catch {
          // Skip files that can't be deleted (in-use, locked, etc.)
          backgroundLogger.warning(
            "Skipped deleting \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
          )
        }
      }

      return deletedPaths
    }.value

    for path in deletedPaths {
      CaptureHistoryStore.shared.removeByFilePath(path)
      try? RecordingMetadataStore.delete(for: URL(fileURLWithPath: path))
    }

    logger.info("Cache cleared: \(deletedPaths.count) item(s) removed")
    return deletedPaths.count
  }
}

// MARK: - Errors

enum CacheCleanupError: LocalizedError {
  case operationInProgress

  var errorDescription: String? {
    switch self {
    case .operationInProgress:
      return L10n.CaptureStorage.operationInProgress
    }
  }
}
