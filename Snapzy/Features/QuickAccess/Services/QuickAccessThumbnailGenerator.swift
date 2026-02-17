//
//  ThumbnailGenerator.swift
//  Snapzy
//
//  Efficient thumbnail generation from image and video files
//

import AppKit
import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "ThumbnailGenerator")

/// Result of thumbnail generation containing optional thumbnail and duration
struct ThumbnailResult {
  let thumbnail: NSImage?
  let duration: TimeInterval?
}

/// Utility for generating thumbnails from image and video files
enum ThumbnailGenerator {

  private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

  private static func isVideoFile(_ url: URL) -> Bool {
    videoExtensions.contains(url.pathExtension.lowercased())
  }

  /// Generate thumbnail from image or video URL
  /// - Parameters:
  ///   - url: Source file URL (image or video)
  ///   - maxSize: Maximum dimension for thumbnail
  /// - Returns: ThumbnailResult with thumbnail and optional duration (for videos)
  static func generate(from url: URL, maxSize: CGFloat = 200) async -> ThumbnailResult {
    if isVideoFile(url) {
      return await generateFromVideo(url: url, maxSize: maxSize)
    } else {
      let thumbnail = await generateFromImage(url: url, maxSize: maxSize)
      return ThumbnailResult(thumbnail: thumbnail, duration: nil)
    }
  }

  /// Generate thumbnail from image file (backward compatible)
  static func generateImageThumbnail(from url: URL, maxSize: CGFloat = 200) async -> NSImage? {
    return await generateFromImage(url: url, maxSize: maxSize)
  }

  /// Generate a simple placeholder thumbnail for failed loads
  static func placeholderThumbnail(size: CGFloat = 200) -> NSImage {
    let thumbSize = NSSize(width: size, height: size)
    let image = NSImage(size: thumbSize)
    image.lockFocus()
    NSColor.systemGray.withAlphaComponent(0.3).setFill()
    NSBezierPath(roundedRect: NSRect(origin: .zero, size: thumbSize), xRadius: 8, yRadius: 8).fill()
    let iconRect = NSRect(x: size * 0.3, y: size * 0.3, width: size * 0.4, height: size * 0.4)
    NSColor.systemGray.withAlphaComponent(0.5).setFill()
    NSBezierPath(ovalIn: iconRect).fill()
    image.unlockFocus()
    return image
  }

  // MARK: - Private Methods

  private static func generateFromImage(url: URL, maxSize: CGFloat) async -> NSImage? {
    // Retry with backoff: 0ms, 100ms, 300ms
    let delays: [UInt64] = [0, 100, 300]

    for (attempt, delayMs) in delays.enumerated() {
      if delayMs > 0 {
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
      }

      guard FileManager.default.fileExists(atPath: url.path) else {
        logger.warning("File not found on attempt \(attempt + 1): \(url.lastPathComponent)")
        continue
      }

      if let image = NSImage(contentsOf: url) {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let scale: CGFloat
        if originalSize.width > originalSize.height {
          scale = min(maxSize / originalSize.width, 1.0)
        } else {
          scale = min(maxSize / originalSize.height, 1.0)
        }

        if scale >= 1.0 { return image }

        let newSize = CGSize(
          width: originalSize.width * scale,
          height: originalSize.height * scale
        )

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
          in: NSRect(origin: .zero, size: newSize),
          from: NSRect(origin: .zero, size: originalSize),
          operation: .copy,
          fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
      }

      logger.warning("NSImage load failed on attempt \(attempt + 1): \(url.lastPathComponent)")
    }

    logger.error("Thumbnail generation failed after \(delays.count) attempts: \(url.lastPathComponent)")
    return nil
  }

  private static func generateFromVideo(url: URL, maxSize: CGFloat) async -> ThumbnailResult {
    let asset = AVURLAsset(url: url)

    // Get duration
    let duration: TimeInterval?
    do {
      let cmDuration = try await asset.load(.duration)
      duration = CMTimeGetSeconds(cmDuration)
    } catch {
      duration = nil
    }

    // Generate thumbnail from first frame
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)

    let time = CMTimeMakeWithSeconds(0, preferredTimescale: 600)

    do {
      let (cgImage, _) = try await imageGenerator.image(at: time)
      let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)
      let scaledThumbnail = scaleImage(nsImage, maxSize: maxSize)
      return ThumbnailResult(thumbnail: scaledThumbnail, duration: duration)
    } catch {
      logger.error("Failed to generate video thumbnail: \(error.localizedDescription)")
      return ThumbnailResult(thumbnail: nil, duration: duration)
    }
  }

  private static func scaleImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
    let originalSize = image.size
    guard originalSize.width > 0, originalSize.height > 0 else { return image }

    let scale: CGFloat
    if originalSize.width > originalSize.height {
      scale = min(maxSize / originalSize.width, 1.0)
    } else {
      scale = min(maxSize / originalSize.height, 1.0)
    }

    if scale >= 1.0 { return image }

    let newSize = CGSize(
      width: originalSize.width * scale,
      height: originalSize.height * scale
    )

    let thumbnail = NSImage(size: newSize)
    thumbnail.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: originalSize),
      operation: .copy,
      fraction: 1.0
    )
    thumbnail.unlockFocus()

    return thumbnail
  }
}
