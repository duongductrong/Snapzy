//
//  HistoryThumbnailGenerator.swift
//  Snapzy
//
//  Lazy thumbnail generation and caching for capture history
//

import AppKit
import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "HistoryThumbnailGenerator")

/// Generates and caches thumbnails for capture history items
@MainActor
final class HistoryThumbnailGenerator {

  static let shared = HistoryThumbnailGenerator()

  private let maxDimension: CGFloat = 256
  private let compressionFactor: CGFloat = 0.7

  private var inFlightTasks: Set<UUID> = []

  var thumbnailsDirectory: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("HistoryThumbnails", isDirectory: true)
  }

  private init() {
    try? FileManager.default.createDirectory(
      at: thumbnailsDirectory,
      withIntermediateDirectories: true
    )
  }

  // MARK: - Public API

  /// Generate a thumbnail for a history record and cache it to disk.
  /// Returns the cached thumbnail URL if successful.
  func generate(for record: CaptureHistoryRecord) async -> URL? {
    // Check if already cached
    if let cachedURL = record.thumbnailURL,
      FileManager.default.fileExists(atPath: cachedURL.path) {
      return cachedURL
    }

    // Prevent duplicate generation for same record
    guard !inFlightTasks.contains(record.id) else { return nil }
    inFlightTasks.insert(record.id)
    defer { inFlightTasks.remove(record.id) }

    guard FileManager.default.fileExists(atPath: record.filePath) else {
      logger.debug("File missing, skipping thumbnail: \(record.fileName)")
      return nil
    }

    let result: URL?
    switch record.captureType {
    case .screenshot, .gif:
      result = await generateImageThumbnail(for: record)
    case .video:
      result = await generateVideoThumbnail(for: record)
    }

    if let url = result {
      CaptureHistoryStore.shared.updateThumbnailPath(id: record.id, path: url.path)
    }

    return result
  }

  /// Load a thumbnail from disk for a record
  func thumbnailURL(for record: CaptureHistoryRecord) -> URL? {
    record.thumbnailURL
  }

  /// Total size of all cached thumbnails in bytes
  func totalThumbnailSize() -> Int64 {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
      at: thumbnailsDirectory,
      includingPropertiesForKeys: [.fileSizeKey]
    ) else { return 0 }

    var total: Int64 = 0
    for url in contents {
      if let attrs = try? fm.attributesOfItem(atPath: url.path),
        let size = attrs[.size] as? Int64 {
        total += size
      }
    }
    return total
  }

  /// Delete all cached thumbnails and clear thumbnail paths in database
  func clearAllThumbnails() {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
      at: thumbnailsDirectory,
      includingPropertiesForKeys: nil
    ) else { return }

    for url in contents {
      try? fm.removeItem(at: url)
    }

    // Clear all thumbnail paths in database
    CaptureHistoryStore.shared.clearAllThumbnailPaths()
    logger.info("All history thumbnails cleared")
  }

  /// Delete thumbnail for a specific record ID
  func deleteThumbnail(for recordId: UUID) {
    let url = thumbnailsDirectory.appendingPathComponent("\(recordId.uuidString).jpg")
    try? FileManager.default.removeItem(at: url)
  }

  // MARK: - Private

  private func generateImageThumbnail(for record: CaptureHistoryRecord) async -> URL? {
    let url = URL(fileURLWithPath: record.filePath)
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { scopedAccess.stop() }

    guard let image = NSImage(contentsOf: url) else {
      logger.warning("Failed to load image for thumbnail: \(record.fileName)")
      return nil
    }

    let thumbnail = scaleAndCompress(image: image)
    return saveThumbnail(thumbnail, recordId: record.id)
  }

  private func generateVideoThumbnail(for record: CaptureHistoryRecord) async -> URL? {
    let url = URL(fileURLWithPath: record.filePath)
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { scopedAccess.stop() }

    let asset = AVURLAsset(url: url)

    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.maximumSize = CGSize(width: maxDimension * 2, height: maxDimension * 2)

    // Extract at mid-point or 1s, whichever is smaller
    let extractTime: TimeInterval
    if let duration = record.duration, duration > 0 {
      extractTime = min(duration / 2, 1.0)
    } else {
      extractTime = 0
    }

    let time = CMTimeMakeWithSeconds(extractTime, preferredTimescale: 600)

    do {
      let (cgImage, _) = try await imageGenerator.image(at: time)
      let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)
      let thumbnail = scaleAndCompress(image: nsImage)
      return saveThumbnail(thumbnail, recordId: record.id)
    } catch {
      logger.error("Failed to generate video thumbnail: \(error.localizedDescription)")
      return nil
    }
  }

  private func scaleAndCompress(image: NSImage) -> NSImage {
    let originalSize = image.size
    guard originalSize.width > 0, originalSize.height > 0 else { return image }

    let scale = min(
      maxDimension / originalSize.width,
      maxDimension / originalSize.height,
      1.0
    )

    let newSize = NSSize(
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

  private func saveThumbnail(_ image: NSImage, recordId: UUID) -> URL? {
    guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    else {
      logger.warning("Failed to encode thumbnail as JPEG for \(recordId)")
      return nil
    }

    let url = thumbnailsDirectory.appendingPathComponent("\(recordId.uuidString).jpg")
    do {
      try jpegData.write(to: url, options: .atomic)
      return url
    } catch {
      logger.error("Failed to write thumbnail: \(error.localizedDescription)")
      return nil
    }
  }
}
