//
//  ClipboardHelper.swift
//  Snapzy
//
//  Format-aware clipboard write utility.
//  Uses file-based clipboard (NSURL) so the pasted file preserves
//  the original format (JPEG/WebP/PNG) — matching CleanShot behavior.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "ClipboardHelper")

/// Centralized helper for copying images to clipboard while respecting the configured format.
///
/// Strategy: write the file URL as `NSURL` to the pasteboard so that receiving apps
/// (Finder, Preview, etc.) copy/paste the actual file with its original format intact.
/// Temp files must NOT be deleted immediately — the receiving app needs them at paste time.
/// Orphaned temp files are cleaned up on next launch by `TempCaptureManager.cleanupOrphanedFiles()`.
enum ClipboardHelper {

  // MARK: - File-based copy

  /// Copy an image file to clipboard as a file reference (NSURL).
  /// The pasted result preserves the file's original format (JPEG/WebP/PNG).
  ///
  /// - Important: Do NOT delete the file after calling this — the receiving app
  ///   needs it to exist at paste time.
  static func copyImage(from url: URL) {
    let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { fileAccess.stop() }

    guard FileManager.default.fileExists(atPath: url.path) else {
      logger.error("ClipboardHelper: file not found \(url.lastPathComponent)")
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([url as NSURL])

    logger.info("Clipboard: copied file \(url.lastPathComponent)")
  }

  // MARK: - Render-based copy

  /// Copy an in-memory NSImage to clipboard by saving to a temp file first,
  /// then writing the file URL. This ensures the pasted result uses the correct format.
  ///
  /// Used by Annotate / Mockup copy where the image is rendered on-the-fly.
  static func copyImage(_ image: NSImage, format: ImageFormatOption? = nil) {
    let resolvedFormat = format ?? currentFormat()
    let ext = resolvedFormat.format.fileExtension

    guard let data = AnnotateExporter.imageData(from: image, for: ext) else {
      logger.error("ClipboardHelper: failed to encode image as \(resolvedFormat.rawValue)")
      // Fallback: write NSImage directly (will produce PNG but at least something lands)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([image])
      return
    }

    // Write to a temp file so the pasteboard can reference it
    let tempDir = TempCaptureManager.shared.tempCaptureDirectory
    let fileName = "Snapzy_clipboard_\(UUID().uuidString).\(ext)"
    let tempURL = tempDir.appendingPathComponent(fileName)

    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      try data.write(to: tempURL, options: .atomic)
    } catch {
      logger.error("ClipboardHelper: failed to write temp file: \(error.localizedDescription)")
      // Fallback
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([image])
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([tempURL as NSURL])

    logger.info("Clipboard: copied rendered image as \(ext) via temp file")
  }

  // MARK: - Helpers

  /// Read the user's preferred screenshot format from UserDefaults
  private static func currentFormat() -> ImageFormatOption {
    if let raw = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
       let option = ImageFormatOption(rawValue: raw) {
      return option
    }
    return .png
  }
}
