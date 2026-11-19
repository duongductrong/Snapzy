//
//  HistoryThumbnailGenerator.swift
//  Snapzy
//
//  Lazy thumbnail generation and caching for capture history
//

import AppKit
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "HistoryThumbnailGenerator")

/// Generates and caches thumbnails for capture history items
final class HistoryThumbnailGenerator {

  static let shared = HistoryThumbnailGenerator()

  private let cacheVersion = "preview-v2"
  private let maxDimension: CGFloat = 208
  private let compressionFactor: CGFloat = 0.58
  private let workerQueue = DispatchQueue(
    label: "snapzy.history-thumbnail-generator.worker",
    qos: .utility,
    attributes: .concurrent
  )
  private let thumbnailsDirectoryURL: URL
  private let stateQueue = DispatchQueue(label: "snapzy.history-thumbnail-generator.state")
  private let memoryCache = NSCache<NSString, NSImage>()
  // Serialize enlarged decodes; cancelled hover requests skip queued work.
  private let previewQueue = DispatchQueue(label: "snapzy.history-preview.worker", qos: .utility)
  private let previewMemoryCache = HistoryPreviewMemoryCache()
  private var inFlightRequests: [String: [(NSImage?) -> Void]] = [:]
  private var memoryCacheKeysByRecordId: [UUID: Set<String>] = [:]

  var thumbnailsDirectory: URL {
    thumbnailsDirectoryURL
  }

  init(thumbnailsDirectory: URL? = nil) {
    self.thumbnailsDirectoryURL = thumbnailsDirectory ?? Self.defaultThumbnailsDirectory()
    do {
      try FileManager.default.createDirectory(
        at: thumbnailsDirectoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      DiagnosticLogger.shared.logError(.history, error, "History thumbnail directory creation failed")
    }
    memoryCache.countLimit = 160
    memoryCache.totalCostLimit = 48 * 1024 * 1024
  }

  // Avoid the synthesized isolated-deinit back-deployment path on macOS 13–15.
  deinit {}

  private static func defaultThumbnailsDirectory() -> URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("HistoryThumbnails", isDirectory: true)
  }

  // MARK: - Public API

  // The security scope must outlive decoding even after cancellation.
  @MainActor
  func loadPreviewImage(for record: CaptureHistoryRecord) async -> NSImage? {
    guard !Task.isCancelled else { return nil }
    let url = record.fileURL
    let access = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { access.stop() }

    let request = HistoryPreviewDecodeRequest()
    let cache = previewMemoryCache
    let isVideo = record.captureType == .video
    let duration = record.duration ?? 0
    let posterTime = duration.isFinite && duration > 0 ? min(duration / 2, 1) : 0
    let decodedImage: HistoryPreviewImage? = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        previewQueue.async {
          let decodedImage: HistoryPreviewImage? = autoreleasepool {
            guard !request.isCancelled,
              let sourceKey = Self.previewSourceKey(at: url)
            else { return nil }
            let key = NSString(string: "\(sourceKey)|\(isVideo)|\(posterTime)")
            if let cached = cache.images.object(forKey: key) {
              return HistoryPreviewImage(
                cgImage: cached,
                size: NSSize(width: cached.width, height: cached.height)
              )
            }

            let cgImage: CGImage?
            if isVideo {
              cgImage = Self.previewVideoImage(at: url, seconds: posterTime)
            } else {
              cgImage = self.downsampledImage(at: url, maxPixelSize: 1200)
            }
            // An edit or deletion during decoding must not populate the cache or UI.
            guard let cgImage, !request.isCancelled,
              Self.previewSourceKey(at: url) == sourceKey
            else { return nil }

            let size = NSSize(width: cgImage.width, height: cgImage.height)
            cache.images.setObject(
              cgImage,
              forKey: key,
              cost: cgImage.bytesPerRow * cgImage.height
            )
            return HistoryPreviewImage(cgImage: cgImage, size: size)
          }
          continuation.resume(returning: decodedImage)
        }
      }
    } onCancel: {
      request.cancel()
    }
    guard !Task.isCancelled, let decodedImage else { return nil }
    return NSImage(cgImage: decodedImage.cgImage, size: decodedImage.size)
  }

  func loadThumbnailImage(for record: CaptureHistoryRecord) async -> NSImage? {
    await withCheckedContinuation { continuation in
      loadThumbnailImage(for: record) { image in
        continuation.resume(returning: image)
      }
    }
  }

  func loadThumbnailImage(
    for record: CaptureHistoryRecord,
    completion: @escaping (NSImage?) -> Void
  ) {
    let identity = cacheIdentity(for: record)
    let cacheKey = NSString(string: identity.cacheKey)

    if let cachedImage = memoryCache.object(forKey: cacheKey) {
      DispatchQueue.main.async {
        completion(cachedImage)
      }
      return
    }

    let shouldStartWork = stateQueue.sync { () -> Bool in
      if inFlightRequests[identity.cacheKey] != nil {
        inFlightRequests[identity.cacheKey]?.append(completion)
        return false
      }

      inFlightRequests[identity.cacheKey] = [completion]
      return true
    }

    guard shouldStartWork else { return }

    workerQueue.async { [weak self] in
      guard let self else { return }
      let image = self.resolveThumbnailImage(for: record, identity: identity)

      if let image {
        let cost = max(Int(image.size.width * image.size.height * 4), 1)
        self.storeInMemory(image, identity: identity, cost: cost)
      }

      let completions = self.stateQueue.sync {
        self.inFlightRequests.removeValue(forKey: identity.cacheKey) ?? []
      }

      DispatchQueue.main.async {
        completions.forEach { $0(image) }
      }
    }
  }

  func preloadThumbnails(for records: [CaptureHistoryRecord]) {
    records.forEach { record in
      loadThumbnailImage(for: record) { _ in }
    }
  }

  /// Generate a thumbnail for a history record and cache it to disk.
  /// Returns the cached thumbnail URL if successful.
  func generate(for record: CaptureHistoryRecord) async -> URL? {
    await withCheckedContinuation { continuation in
      let identity = cacheIdentity(for: record)
      let preferredURL = existingThumbnailURL(for: record, identity: identity)
      loadThumbnailImage(for: record) { image in
        guard image != nil else {
          continuation.resume(returning: nil)
          return
        }

        continuation.resume(returning: preferredURL ?? identity.thumbnailURL)
      }
    }
  }

  /// Load a thumbnail from disk for a record
  func thumbnailURL(for record: CaptureHistoryRecord) -> URL? {
    let identity = cacheIdentity(for: record)
    return existingThumbnailURL(for: record, identity: identity)
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
    let contents: [URL]
    do {
      contents = try fm.contentsOfDirectory(
        at: thumbnailsDirectory,
        includingPropertiesForKeys: nil
      )
    } catch {
      DiagnosticLogger.shared.logError(.history, error, "History thumbnails clear failed to list directory")
      return
    }

    for url in contents {
      do {
        try fm.removeItem(at: url)
      } catch {
        DiagnosticLogger.shared.logError(
          .history,
          error,
          "History thumbnail delete failed during clear all",
          context: ["fileName": url.lastPathComponent]
        )
      }
    }

    memoryCache.removeAllObjects()

    // Clear all thumbnail paths in database
    DispatchQueue.main.async {
      CaptureHistoryStore.shared.clearAllThumbnailPaths()
      logger.info("All history thumbnails cleared")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "All history thumbnails cleared",
        context: ["thumbnailCount": "\(contents.count)"]
      )
    }
  }

  /// Delete thumbnail for a specific record ID
  func deleteThumbnail(for recordId: UUID) {
    deleteThumbnailFiles(for: recordId)
    let keys = stateQueue.sync {
      Array(memoryCacheKeysByRecordId.removeValue(forKey: recordId) ?? [])
    }
    keys.forEach { key in
      memoryCache.removeObject(forKey: NSString(string: key))
    }
  }

  // MARK: - Private

  private nonisolated static func previewSourceKey(at url: URL) -> String? {
    // Read live filesystem metadata, not the (potentially older) history record.
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let modified = attributes[.modificationDate] as? Date,
      let size = attributes[.size] as? NSNumber
    else { return nil }
    let fileNumber = attributes[.systemFileNumber] as? NSNumber
    return "\(url.standardizedFileURL.path)|\(modified.timeIntervalSince1970)|\(size)|\(fileNumber?.stringValue ?? "")"
  }

  private nonisolated static func previewVideoImage(at url: URL, seconds: TimeInterval) -> CGImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1200, height: 1200)
    return try? generator.copyCGImage(
      at: CMTimeMakeWithSeconds(seconds, preferredTimescale: 600), actualTime: nil
    )
  }

  private func resolveThumbnailImage(for record: CaptureHistoryRecord, identity: ThumbnailCacheIdentity) -> NSImage? {
    if let cachedURL = existingThumbnailURL(for: record, identity: identity),
      let cachedImage = decodeThumbnail(at: cachedURL)
    {
      return cachedImage
    }

    guard FileManager.default.fileExists(atPath: record.filePath) else {
      logger.debug("File missing, skipping thumbnail: \(record.fileName)")
      DiagnosticLogger.shared.log(
        .debug,
        .history,
        "History thumbnail skipped; source file missing",
        context: ["fileName": record.fileName, "type": record.captureType.rawValue]
      )
      return nil
    }

    let generatedThumbnail: GeneratedThumbnail?
    switch record.captureType {
    case .screenshot, .gif:
      generatedThumbnail = generateImageThumbnail(for: record, identity: identity)
    case .video:
      generatedThumbnail = generateVideoThumbnail(for: record, identity: identity)
    }

    guard let generatedThumbnail else { return nil }

    DispatchQueue.main.async {
      CaptureHistoryStore.shared.updateThumbnailPath(id: record.id, path: generatedThumbnail.url.path)
    }

    return generatedThumbnail.image
  }

  private func generateImageThumbnail(for record: CaptureHistoryRecord, identity: ThumbnailCacheIdentity) -> GeneratedThumbnail? {
    let url = record.fileURL
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { scopedAccess.stop() }

    guard let cgImage = downsampledImage(at: url, maxPixelSize: Int(maxDimension * 2)) else {
      logger.warning("Failed to load image for thumbnail: \(record.fileName)")
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "History image thumbnail generation failed",
        context: ["fileName": record.fileName]
      )
      return nil
    }

    return saveThumbnail(cgImage, identity: identity)
  }

  private func generateVideoThumbnail(for record: CaptureHistoryRecord, identity: ThumbnailCacheIdentity) -> GeneratedThumbnail? {
    let url = record.fileURL
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
      let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
      return saveThumbnail(cgImage, identity: identity)
    } catch {
      logger.error("Failed to generate video thumbnail: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "History video thumbnail generation failed",
        context: ["fileName": record.fileName]
      )
      return nil
    }
  }

  private func existingThumbnailURL(for record: CaptureHistoryRecord, identity: ThumbnailCacheIdentity) -> URL? {
    let currentURL = identity.thumbnailURL

    if FileManager.default.fileExists(atPath: currentURL.path) {
      return currentURL
    }

    guard
      let storedURL = record.thumbnailURL,
      storedURL.lastPathComponent == currentURL.lastPathComponent,
      FileManager.default.fileExists(atPath: storedURL.path)
    else {
      return nil
    }

    return storedURL
  }

  private func cacheIdentity(for record: CaptureHistoryRecord) -> ThumbnailCacheIdentity {
    let capturedAtMs = Int64((record.capturedAt.timeIntervalSince1970 * 1000).rounded())
    let signature = "\(capturedAtMs)-\(record.fileSize)"
    let cacheKey = "\(record.id.uuidString)-\(cacheVersion)-\(signature)"
    return ThumbnailCacheIdentity(
      recordId: record.id,
      cacheKey: cacheKey,
      thumbnailURL: thumbnailsDirectory.appendingPathComponent("\(cacheKey).jpg")
    )
  }


  private func legacyThumbnailURL(for recordId: UUID) -> URL {
    thumbnailsDirectory.appendingPathComponent("\(recordId.uuidString).jpg")
  }

  private func deleteThumbnailFiles(for recordId: UUID, keeping keptURL: URL? = nil) {
    let prefix = "\(recordId.uuidString)-"
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: thumbnailsDirectory,
      includingPropertiesForKeys: nil
    )) ?? []

    for url in contents where url.lastPathComponent.hasPrefix(prefix) {
      if keptURL?.standardizedFileURL == url.standardizedFileURL { continue }
      do {
        try FileManager.default.removeItem(at: url)
      } catch {
        DiagnosticLogger.shared.logError(
          .history,
          error,
          "History thumbnail old cache delete failed",
          context: ["fileName": url.lastPathComponent]
        )
      }
    }

    let legacyURL = legacyThumbnailURL(for: recordId)
    if keptURL?.standardizedFileURL != legacyURL.standardizedFileURL {
      guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
      do {
        try FileManager.default.removeItem(at: legacyURL)
      } catch {
        DiagnosticLogger.shared.logError(
          .history,
          error,
          "History thumbnail legacy cache delete failed",
          context: ["fileName": legacyURL.lastPathComponent]
        )
      }
    }
  }

  private func storeInMemory(_ image: NSImage, identity: ThumbnailCacheIdentity, cost: Int) {
    memoryCache.setObject(image, forKey: NSString(string: identity.cacheKey), cost: cost)
    stateQueue.sync {
      var keys = memoryCacheKeysByRecordId[identity.recordId] ?? []
      keys.insert(identity.cacheKey)
      memoryCacheKeysByRecordId[identity.recordId] = keys
    }
  }

  private nonisolated func downsampledImage(at url: URL, maxPixelSize: Int) -> CGImage? {
    let sourceOptions: [CFString: Any] = [
      kCGImageSourceShouldCache: false
    ]

    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
      return nil
    }

    let downsampleOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]

    return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary)
  }

  private func decodeThumbnail(at url: URL) -> NSImage? {
    let options: [CFString: Any] = [
      kCGImageSourceShouldCacheImmediately: true
    ]
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      return nil
    }

    return NSImage(
      cgImage: cgImage,
      size: NSSize(width: cgImage.width, height: cgImage.height)
    )
  }

  private func saveThumbnail(_ image: CGImage, identity: ThumbnailCacheIdentity) -> GeneratedThumbnail? {
    let url = identity.thumbnailURL

    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    ) else {
      logger.warning("Failed to create thumbnail destination for \(identity.recordId)")
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "History thumbnail destination creation failed",
        context: ["recordId": identity.recordId.uuidString]
      )
      return nil
    }

    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: compressionFactor
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
      logger.warning("Failed to encode thumbnail as JPEG for \(identity.recordId)")
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "History thumbnail JPEG encode failed",
        context: ["recordId": identity.recordId.uuidString]
      )
      return nil
    }

    deleteThumbnailFiles(for: identity.recordId, keeping: url)

    let thumbnailImage = NSImage(
      cgImage: image,
      size: NSSize(width: image.width, height: image.height)
    )

    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
      storeInMemory(thumbnailImage, identity: identity, cost: max(fileSize, 1))
      return GeneratedThumbnail(url: url, image: thumbnailImage)
    } catch {
      logger.error("Failed to read thumbnail metadata: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "History thumbnail metadata read failed",
        context: ["recordId": identity.recordId.uuidString]
      )
      return nil
    }
  }
}

// NSCache synchronizes access internally; stored preview images are immutable.
private nonisolated final class HistoryPreviewMemoryCache: @unchecked Sendable {
  let images = NSCache<NSString, CGImage>()

  init() {
    images.countLimit = 6
    images.totalCostLimit = 24 * 1024 * 1024
  }
}

/// Shared only between the cancellation handler and the serial preview worker.
private nonisolated final class HistoryPreviewDecodeRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool { lock.withLock { cancelled } }

  func cancel() {
    lock.withLock { cancelled = true }
  }
}

private struct ThumbnailCacheIdentity {
  let recordId: UUID
  let cacheKey: String
  let thumbnailURL: URL
}

private struct HistoryPreviewImage: Sendable {
  let cgImage: CGImage
  let size: NSSize
}

private struct GeneratedThumbnail {
  let url: URL
  let image: NSImage
}
