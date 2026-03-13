//
//  PostCaptureActionHandler.swift
//  Snapzy
//
//  Executes post-capture actions based on user preferences
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "PostCaptureActionHandler")

/// Handles execution of post-capture actions based on user preferences
@MainActor
final class PostCaptureActionHandler {

  static let shared = PostCaptureActionHandler()

  private let preferencesManager = PreferencesManager.shared
  private let quickAccessManager = QuickAccessManager.shared
  private let fileAccessManager = SandboxFileAccessManager.shared

  private init() {}

  // MARK: - Public API

  /// Execute all enabled post-capture actions for a screenshot
  func handleScreenshotCapture(url: URL) async {
    await executeActions(for: .screenshot, url: url)
  }

  /// Execute all enabled post-capture actions for a video recording
  func handleVideoCapture(url: URL) async {
    await executeActions(for: .recording, url: url)
  }

  // MARK: - Private

  private func executeActions(for captureType: CaptureType, url: URL) async {
    let fileAccess = fileAccessManager.beginAccessingURL(url)
    defer { fileAccess.stop() }

    // Validate file exists before processing
    guard FileManager.default.fileExists(atPath: url.path) else {
      logger.error("Capture file missing at \(url.lastPathComponent), skipping post-capture actions")
      return
    }

    logger.info("Executing post-capture actions for \(captureType == .screenshot ? "screenshot" : "recording"): \(url.lastPathComponent)")
    let isTempCapture = TempCaptureManager.shared.isTempFile(url)
    let locationLabel = isTempCapture ? "temp" : "export"
    let typeLabel = captureType == .screenshot ? "screenshot" : "recording"
    print("[Snapzy:PostCapture] \(typeLabel) \(url.lastPathComponent) [location=\(locationLabel)]")
    DiagnosticLogger.shared.log(.info, .action, "Post-capture: \(typeLabel) \(url.lastPathComponent) [location=\(locationLabel)]")

    // Show Quick Access Overlay
    if preferencesManager.isActionEnabled(.showQuickAccess, for: captureType) {
      switch captureType {
      case .screenshot:
        await quickAccessManager.addScreenshot(url: url)
      case .recording:
        await quickAccessManager.addVideo(url: url)
      }
      logger.debug("Quick access overlay shown for \(url.lastPathComponent)")
    }

    // Copy file to clipboard
    if preferencesManager.isActionEnabled(.copyFile, for: captureType) {
      copyToClipboard(url: url, isVideo: captureType == .recording)
      logger.debug("Clipboard copy executed for \(url.lastPathComponent)")
    }
  }

  /// Copy file to clipboard (image data for screenshots, file URL for videos)
  private func copyToClipboard(url: URL, isVideo: Bool) {
    let fileAccess = fileAccessManager.beginAccessingURL(url)
    defer { fileAccess.stop() }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    if isVideo {
      pasteboard.writeObjects([url as NSURL])
    } else {
      if let image = NSImage(contentsOf: url) {
        pasteboard.writeObjects([image])
      } else {
        logger.error("Failed to load image for clipboard: \(url.lastPathComponent)")
      }
    }

    // Play feedback sound
    NSSound(named: "Pop")?.play()
  }
}
