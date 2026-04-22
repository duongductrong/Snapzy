//
//  ClipboardHelper.swift
//  Snapzy
//
//  Format-aware clipboard write utility.
//  Writes both NSURL (file reference) and NSImage (pixel data) to the pasteboard
//  so every receiving app can paste — Finder uses the file URL while chat apps,
//  browsers, and editors use the TIFF/PNG image representation.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "ClipboardHelper")

/// Centralized helper for copying images to clipboard while respecting the configured format.
///
/// Strategy: write **both** `NSURL` (file reference) and `NSImage` (pixel data) to the
/// pasteboard. File-aware apps (Finder, Preview) use the URL; image-consuming apps
/// (Telegram, Slack, Chrome, etc.) use the TIFF/PNG representation.
/// Temp files must NOT be deleted immediately — the receiving app needs them at paste time.
/// Orphaned temp files are cleaned up on next launch by `TempCaptureManager.cleanupOrphanedFiles()`.
enum ClipboardHelper {

  // MARK: - File-based copy

  /// Copy one or more file URLs to the clipboard.
  ///
  /// Used for non-image captures and multi-selection where Finder-style file copy
  /// semantics are more appropriate than rendering image pixel data.
  static func copyFileURLs(_ urls: [URL]) {
    guard !urls.isEmpty else { return }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(urls.map { $0 as NSURL })

    logger.info("Clipboard: copied \(urls.count) file url(s)")
    DiagnosticLogger.shared.log(
      .info,
      .clipboard,
      "Copy file URLs",
      context: ["count": "\(urls.count)"]
    )
  }

  /// Copy an image file to clipboard with both file reference and image data.
  ///
  /// Writes `NSURL` (preserves original format in Finder) **and** `NSImage`
  /// (provides TIFF/PNG data for apps that expect image types on the pasteboard).
  ///
  /// - Important: Do NOT delete the file after calling this — the receiving app
  ///   needs it to exist at paste time.
  static func copyImage(from url: URL) {
    DiagnosticLogger.shared.log(.info, .clipboard, "Copy image from file", context: ["file": url.lastPathComponent])
    let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { fileAccess.stop() }

    guard FileManager.default.fileExists(atPath: url.path) else {
      logger.error("ClipboardHelper: file not found \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.error, .clipboard, "File not found", context: ["file": url.lastPathComponent])
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    // Write NSURL + NSImage for maximum compatibility.
    // NSURL: Finder/Preview paste the actual file with its original format.
    // NSImage: Telegram, Slack, Chrome, etc. paste TIFF/PNG image data.
    if let image = NSImage(contentsOf: url) {
      pasteboard.writeObjects([url as NSURL, image])
    } else {
      // Fallback: file exists but NSImage can't decode it (e.g. WebP on macOS 13)
      pasteboard.writeObjects([url as NSURL])
      logger.warning("ClipboardHelper: could not decode image, NSURL-only clipboard for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.warning, .clipboard, "Image decode failed, NSURL-only", context: ["file": url.lastPathComponent])
    }

    logger.info("Clipboard: copied file \(url.lastPathComponent)")
  }

  // MARK: - Render-based copy

  /// Copy an in-memory NSImage to clipboard by saving to a temp file first,
  /// then writing the file URL. This ensures the pasted result uses the correct format.
  ///
  /// Used by Annotate / Mockup copy where the image is rendered on-the-fly.
  static func copyImage(_ image: NSImage, format: ImageFormatOption? = nil) {
    DiagnosticLogger.shared.log(.info, .clipboard, "Copy rendered image", context: ["format": (format ?? currentFormat()).rawValue])
    let resolvedFormat = format ?? currentFormat()
    let ext = resolvedFormat.format.fileExtension

    guard let data = AnnotateExporter.imageData(from: image, for: ext) else {
      logger.error("ClipboardHelper: failed to encode image as \(resolvedFormat.rawValue)")
      DiagnosticLogger.shared.log(.error, .clipboard, "Image encode failed", context: ["format": resolvedFormat.rawValue])
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
      DiagnosticLogger.shared.logError(.clipboard, error, "Temp file write failed")
      // Fallback
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([image])
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    // Write both NSURL (format-preserving) and NSImage (universal image data)
    pasteboard.writeObjects([tempURL as NSURL, image])

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
