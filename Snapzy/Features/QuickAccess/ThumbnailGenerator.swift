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

private let logger = Logger(subsystem: "com.zapshot", category: "ThumbnailGenerator")

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

  // MARK: - Private Methods

  private static func generateFromImage(url: URL, maxSize: CGFloat) async -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }

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
