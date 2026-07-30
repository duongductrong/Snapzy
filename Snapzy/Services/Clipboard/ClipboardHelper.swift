//
//  ClipboardHelper.swift
//  Snapzy
//
//  Format-aware clipboard write utility.
//  Writes one pasteboard item with file and pixel-data representations
//  so receiving apps see a single image while choosing the type they support.
//

import AppKit
import Foundation
import os.log
import UniformTypeIdentifiers

private nonisolated let logger = Logger(subsystem: "Snapzy", category: "ClipboardHelper")

/// Centralized helper for copying images to clipboard while respecting the configured format.
///
/// Strategy: write the file URL via `writeObjects([NSURL])` to obtain sandbox extensions,
/// then augment the first pasteboard item with pixel-data representations via `addTypes`
/// so file-aware apps (Finder, Preview) use the URL and image-consuming apps
/// (Telegram, Slack, Chrome, etc.) use image data, without treating the same
/// screenshot as separate clipboard items.
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
    let didWrite = pasteboard.writeObjects(urls.map { $0 as NSURL })
    if didWrite {
      PasteboardReferenceTracker.record(urls: urls, changeCount: pasteboard.changeCount)
    } else {
      logger.error("Clipboard: failed to write \(urls.count) file url(s)")
      DiagnosticLogger.shared.log(
        .warning,
        .clipboard,
        "File URLs clipboard write failed",
        context: ["count": "\(urls.count)"]
      )
    }

    logger.info("Clipboard: copied \(urls.count) file url(s)")
    DiagnosticLogger.shared.log(
      .info,
      .clipboard,
      "Copy file URLs",
      context: ["count": "\(urls.count)"]
    )
  }

  /// Copy a video/GIF/media file to clipboard as a file attachment.
  ///
  /// `writeObjects([NSURL])` stays the primary write because AppKit attaches
  /// the security-scoped handoff receivers need for sandboxed file reads.
  /// The extra URL/string representations live on the same pasteboard item and
  /// help Electron/WebView targets that inspect item-level fallback flavors.
  static func copyMediaFile(from url: URL) {
    DiagnosticLogger.shared.log(.info, .clipboard, "Copy media file", context: ["file": url.lastPathComponent])
    let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { fileAccess.stop() }

    guard FileManager.default.fileExists(atPath: url.path) else {
      logger.error("ClipboardHelper: media file not found \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.error, .clipboard, "Media file not found", context: ["file": url.lastPathComponent])
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let didWrite = pasteboard.writeObjects([url as NSURL])
    addFileURLFallbackRepresentations(to: pasteboard, fileURL: url)
    if didWrite {
      PasteboardReferenceTracker.record(urls: [url], changeCount: pasteboard.changeCount)
    }

    let readbackCount = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count ?? 0
    DiagnosticLogger.shared.log(
      didWrite && readbackCount > 0 ? .info : .warning,
      .clipboard,
      "Media file URL written to clipboard",
      context: [
        "file": url.lastPathComponent,
        "writeObjects": didWrite ? "true" : "false",
        "readbackCount": "\(readbackCount)",
        "types": pasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "none",
        "itemTypes": pasteboard.pasteboardItems?.first?.types.map(\.rawValue).joined(separator: ",") ?? "none",
      ]
    )
  }

  /// Copy an image file to clipboard with both file reference and image data.
  ///
  /// Writes a single pasteboard item with file URL plus encoded image data
  /// representations so apps can pick their preferred type without seeing
  /// duplicate clipboard items.
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

    let image = NSImage(contentsOf: url)
    let encodedData = try? Data(contentsOf: url)
    let encodedType = pasteboardImageType(for: url.pathExtension)

    writeSingleImageItem(
      to: pasteboard,
      fileURL: url,
      image: image,
      tiffData: image?.tiffRepresentation,
      encodedData: encodedData,
      encodedType: encodedType
    )

    if image == nil {
      // Fallback: file exists but NSImage can't decode it (e.g. WebP on macOS 13).
      // The pasteboard item still exposes the file URL and original encoded data.
      logger.warning("ClipboardHelper: could not decode image, file/data-only clipboard for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(
        .warning,
        .clipboard,
        "Image decode failed, file/data-only",
        context: ["file": url.lastPathComponent]
      )
    }

    logger.info("Clipboard: copied file \(url.lastPathComponent)")
  }

  /// Off-main variant of `copyImage(from:)` for the post-save re-copy path.
  /// File read, image decode and TIFF encode (the expensive parts, 50-150ms+ for
  /// Retina captures) run on the calling background queue; only the pasteboard
  /// write hops to main. Capture files live inside the app container, so no
  /// security scope is needed for the read — the scoped-access token is acquired
  /// on main for parity with the main-thread variant.
  nonisolated static func copyImageOffMain(from url: URL) async {
    DiagnosticLogger.shared.log(
      .info,
      .clipboard,
      "Copy image from file (off-main)",
      context: ["file": url.lastPathComponent]
    )

    guard FileManager.default.fileExists(atPath: url.path) else {
      logger.error("ClipboardHelper: file not found \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.error, .clipboard, "File not found", context: ["file": url.lastPathComponent])
      return
    }

    // Heavy work off-main
    let image = NSImage(contentsOf: url)
    let tiffData = image?.tiffRepresentation
    let encodedData = try? Data(contentsOf: url)
    let encodedType = pasteboardImageType(for: url.pathExtension)

    await MainActor.run {
      let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
      defer { fileAccess.stop() }

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      writeSingleImageItem(
        to: pasteboard,
        fileURL: url,
        image: image,
        tiffData: tiffData,
        encodedData: encodedData,
        encodedType: encodedType
      )

      if image == nil {
        logger.warning("ClipboardHelper: could not decode image, file/data-only clipboard for \(url.lastPathComponent)")
        DiagnosticLogger.shared.log(
          .warning,
          .clipboard,
          "Image decode failed, file/data-only",
          context: ["file": url.lastPathComponent]
        )
      }
    }

    logger.info("Clipboard: copied file \(url.lastPathComponent)")
  }

  // MARK: - Render-based copy

  /// Copy an in-memory NSImage to clipboard by saving to a temp file first,
  /// then writing the file URL. This ensures the pasted result uses the correct format.
  ///
  /// Used by Annotate / Mockup copy where the image is rendered on-the-fly.
  static func copyImage(_ image: NSImage, format: ImageFormatOption? = nil) {
    DiagnosticLogger.shared.log(
      .info,
      .clipboard,
      "Copy rendered image",
      context: ["format": (format ?? currentFormat()).rawValue]
    )
    let resolvedFormat = format ?? currentFormat()
    let ext = resolvedFormat.format.fileExtension

    guard let data = AnnotateExporter.imageData(from: image, for: ext) else {
      logger.error("ClipboardHelper: failed to encode image as \(resolvedFormat.rawValue)")
      DiagnosticLogger.shared.log(
        .error,
        .clipboard,
        "Image encode failed",
        context: ["format": resolvedFormat.rawValue]
      )
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
    writeSingleImageItem(
      to: pasteboard,
      fileURL: tempURL,
      image: image,
      tiffData: image.tiffRepresentation,
      encodedData: data,
      encodedType: pasteboardImageType(for: ext)
    )

    logger.info("Clipboard: copied rendered image as \(ext) via temp file")
  }

  // MARK: - Helpers

  private static func writeSingleImageItem(
    to pasteboard: NSPasteboard,
    fileURL: URL,
    image: NSImage?,
    tiffData: Data?,
    encodedData: Data?,
    encodedType: NSPasteboard.PasteboardType?
  ) {
    // Use writeObjects with NSURL to ensure macOS grants a sandbox extension
    // to the receiving app. NSPasteboardItem.setString(url, forType: .fileURL)
    // does NOT grant sandbox extensions — this was the root cause of Area
    // Capture's "auto copy" failing in sandboxed builds.
    let didWriteURL = pasteboard.writeObjects([fileURL as NSURL])

    // Augment the first pasteboard item with image data representations so
    // image-consuming apps (Telegram, Slack, etc.) can paste inline images
    // instead of a file reference.
    var extraTypes: [NSPasteboard.PasteboardType] = []
    if let encodedType {
      extraTypes.append(encodedType)
    }
    if image != nil {
      extraTypes.append(.tiff)
    }

    var didWriteRepresentations = true
    if !extraTypes.isEmpty {
      let declaredChangeCount = pasteboard.addTypes(extraTypes, owner: nil)
      if declaredChangeCount == 0 {
        didWriteRepresentations = false
      }

      if let encodedData, let encodedType {
        didWriteRepresentations = pasteboard.setData(encodedData, forType: encodedType) && didWriteRepresentations
      }
      if let tiffData {
        didWriteRepresentations = pasteboard.setData(tiffData, forType: .tiff) && didWriteRepresentations
      }
    }

    if didWriteURL, didWriteRepresentations {
      PasteboardReferenceTracker.record(urls: [fileURL], changeCount: pasteboard.changeCount)
    } else {
      // A silent failure here leaves the pasteboard holding older content —
      // log loudly so diagnostic bundles can tell "never copied" apart from
      // "copied, then the referenced file was deleted".
      logger
        .error(
          "Clipboard: pasteboard write incomplete for \(fileURL.lastPathComponent) (url: \(didWriteURL), representations: \(didWriteRepresentations))"
        )
      DiagnosticLogger.shared.log(
        .warning,
        .clipboard,
        "Clipboard image write incomplete",
        context: [
          "file": fileURL.lastPathComponent,
          "writeObjects": didWriteURL ? "true" : "false",
          "representations": didWriteRepresentations ? "true" : "false",
          "types": pasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "none",
        ]
      )
    }
  }

  private static func addFileURLFallbackRepresentations(
    to pasteboard: NSPasteboard,
    fileURL: URL
  ) {
    pasteboard.addTypes([.URL, .string], owner: nil)
    pasteboard.setString(fileURL.absoluteString, forType: .URL)
    pasteboard.setString(fileURL.path, forType: .string)
  }

  private nonisolated static func pasteboardImageType(for fileExtension: String) -> NSPasteboard.PasteboardType? {
    let ext = fileExtension.lowercased()
    switch ext {
    case "png":
      return .png
    case "jpg", "jpeg":
      return NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    case "webp":
      return NSPasteboard.PasteboardType(UTType.webP.identifier)
    case "tif", "tiff":
      return .tiff
    default:
      guard let type = UTType(filenameExtension: ext), type.conforms(to: .image) else {
        return nil
      }
      return NSPasteboard.PasteboardType(type.identifier)
    }
  }

  /// Read the user's preferred screenshot format from UserDefaults
  private static func currentFormat() -> ImageFormatOption {
    if let raw = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
       let option = ImageFormatOption(rawValue: raw) {
      return option
    }
    return .png
  }

  // MARK: - Pasteboard reference tracking

  /// `true` when the general pasteboard still holds exactly what Snapzy last
  /// copied and that content references `url` — i.e. nothing has been copied
  /// since, so receivers may still read the file at paste time.
  ///
  /// Temp-file cleanup uses this to avoid deleting a file the pasteboard still
  /// references: receivers (Slack, Messenger, Finder, ...) resolve the file URL
  /// at paste time, so deleting the file breaks the paste.
  static func isReferencedByGeneralPasteboard(_ url: URL) -> Bool {
    PasteboardReferenceTracker.contains(url, changeCount: NSPasteboard.general.changeCount)
  }

  /// Clears the pasteboard reference record. Used by tests.
  static func resetPasteboardReferenceTracking() {
    PasteboardReferenceTracker.reset()
  }

  /// Remembers the file URL(s) Snapzy most recently wrote to the general
  /// pasteboard, together with the pasteboard's change count after the write.
  /// Comparing by `changeCount` means any newer clipboard content (copied in
  /// any app) automatically releases the file for deletion — no pasteboard
  /// content reads (and no paste-consent prompts) required.
  private enum PasteboardReferenceTracker {
    private static let lock = NSLock()
    private static var lastWrite: (urls: Set<URL>, changeCount: Int)?

    static func record(urls: [URL], changeCount: Int) {
      lock.lock()
      lastWrite = (Set(urls.map(\.standardizedFileURL)), changeCount)
      lock.unlock()
    }

    static func contains(_ url: URL, changeCount: Int) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard let lastWrite, lastWrite.changeCount == changeCount else { return false }
      return lastWrite.urls.contains(url.standardizedFileURL)
    }

    static func reset() {
      lock.lock()
      lastWrite = nil
      lock.unlock()
    }
  }
}
