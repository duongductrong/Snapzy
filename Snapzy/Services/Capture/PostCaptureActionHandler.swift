//
//  PostCaptureActionHandler.swift
//  Snapzy
//
//  Executes post-capture actions based on user preferences
//

import AppKit
import AVFoundation
import CoreGraphics
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

    // Add to capture history
    await addScreenshotToHistory(url: url)
  }

  /// Add a screenshot to capture history
  private func addScreenshotToHistory(url: URL) async {
    guard FileManager.default.fileExists(atPath: url.path) else { return }

    let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
    var width: Int?
    var height: Int?
    if let source = imageSource {
      if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
        if let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int {
          width = pixelWidth
        }
        if let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int {
          height = pixelHeight
        }
      }
    }

    CaptureHistoryStore.shared.addCapture(
      url: url,
      captureType: .screenshot,
      width: width,
      height: height
    )
  }

  /// Execute all enabled post-capture actions for a video recording
  /// - Parameter skipQuickAccess: When true, skip adding to QuickAccess (e.g. GIF flow already added it)
  func handleVideoCapture(url: URL, skipQuickAccess: Bool = false) async {
    await executeActions(for: .recording, url: url, skipQuickAccess: skipQuickAccess)

    // Add to capture history
    await addVideoToHistory(url: url)
  }

  /// Add a video or GIF to capture history
  private func addVideoToHistory(url: URL) async {
    guard FileManager.default.fileExists(atPath: url.path) else { return }

    let isGIF = url.pathExtension.lowercased() == "gif"
    let captureType: CaptureHistoryType = isGIF ? .gif : .video

    var duration: TimeInterval?
    var width: Int?
    var height: Int?

    if !isGIF {
      let asset = AVURLAsset(url: url)
      let assetDuration: CMTime
      if #available(macOS 15.0, *) {
        assetDuration = (try? await asset.load(.duration)) ?? .invalid
      } else {
        assetDuration = asset.duration
      }
      let seconds = CMTimeGetSeconds(assetDuration)
      if seconds.isFinite && seconds > 0 {
        duration = seconds
      }

      let videoTrack: AVAssetTrack?
      if #available(macOS 15.0, *) {
        videoTrack = try? await asset.loadTracks(withMediaType: .video).first
      } else {
        videoTrack = asset.tracks(withMediaType: .video).first
      }
      if let track = videoTrack {
        let naturalSize: CGSize
        if #available(macOS 15.0, *) {
          naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        } else {
          naturalSize = track.naturalSize
        }
        width = Int(naturalSize.width)
        height = Int(naturalSize.height)
      }
    }

    CaptureHistoryStore.shared.addCapture(
      url: url,
      captureType: captureType,
      duration: duration,
      width: width,
      height: height
    )
  }

  /// Re-run clipboard automation after an in-place edit save succeeds.
  func copyEditedCaptureToClipboardIfEnabled(for captureType: CaptureType, url: URL) {
    guard preferencesManager.isActionEnabled(.copyFile, for: captureType) else { return }

    copyToClipboard(url: url, isVideo: captureType == .recording)

    let label = captureType == .screenshot ? "screenshot" : "recording"
    logger.debug("Clipboard re-copy executed for edited \(url.lastPathComponent)")
    DiagnosticLogger.shared.log(.info, .action, "Clipboard re-copy: \(label) \(url.lastPathComponent)")
  }

  // MARK: - Private

  private func executeActions(for captureType: CaptureType, url: URL, skipQuickAccess: Bool = false) async {
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
    if !skipQuickAccess && preferencesManager.isActionEnabled(.showQuickAccess, for: captureType) {
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
      let label = captureType == .screenshot ? "screenshot" : "recording"
      logger.debug("Clipboard copy executed for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.info, .action, "Clipboard copy: \(label) \(url.lastPathComponent)")
    }

    // Open Annotate Editor (screenshots only)
    if captureType == .screenshot && preferencesManager.isActionEnabled(.openAnnotate, for: captureType) {
      AnnotateManager.shared.openAnnotation(url: url)
      logger.debug("Annotate editor opened for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(.info, .action, "Annotate editor: \(url.lastPathComponent)")
    }
  }

  /// Copy file to clipboard (format-aware image data for screenshots, file URL for videos)
  private func copyToClipboard(url: URL, isVideo: Bool) {
    if isVideo {
      let fileAccess = fileAccessManager.beginAccessingURL(url)
      defer { fileAccess.stop() }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([url as NSURL])
    } else {
      ClipboardHelper.copyImage(from: url)
    }
  }
}
