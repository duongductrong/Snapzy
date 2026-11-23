//
//  AutomationImageTransforms.swift
//  Snapzy
//
//  Pure file → file image transforms for automation steps, built on the Quick
//  Access Optimize pipeline. Nonisolated: handlers run them off the main actor.
//

import CoreGraphics
import Foundation
import ImageIO

nonisolated enum AutomationImageTransformError: Error, Equatable {
  case unreadable
  case encodeFailed
}

nonisolated struct AutomationImageTransformResult: Equatable, Sendable {
  let url: URL
  let pixelWidth: Int
  let pixelHeight: Int
  /// The requested format couldn't be written; PNG was used instead.
  let fellBackToPNG: Bool
  /// A file-size cap was set and even the smallest attempt stayed above it.
  let exceedsFileSizeLimit: Bool
}

nonisolated enum AutomationImageTransforms {
  /// Pixel size of the longest edge after a resize; never upscales.
  static func targetSize(width: Int, height: Int, config: AutomationResizeConfig) -> (width: Int, height: Int) {
    let fraction: Double
    switch config.mode {
    case .maxDimension:
      let longest = max(width, height)
      fraction = longest > config.clampedMaxDimension ? Double(config.clampedMaxDimension) / Double(longest) : 1
    case .scalePercent:
      fraction = Double(config.clampedScalePercent) / 100
    }
    return (
      max(1, Int((Double(width) * fraction).rounded())),
      max(1, Int((Double(height) * fraction).rounded()))
    )
  }

  /// Resizes `source` into `directory`, keeping its format.
  static func resize(
    _ source: URL,
    config: AutomationResizeConfig,
    into directory: URL,
    baseName: String
  ) throws -> AutomationImageTransformResult {
    let info = try sourceInfo(source)
    guard let image = QuickAccessImageOptimizer.loadImage(at: source) else { throw AutomationImageTransformError.unreadable }
    let size = targetSize(width: info.pixelWidth, height: info.pixelHeight, config: config)
    let fileExtension = encodableExtension(source.pathExtension)
    guard let resized = QuickAccessImageOptimizer.resized(
      image,
      width: size.width,
      height: size.height,
      flattensAlpha: !QuickAccessImageOptimizer.supportsAlpha(fileExtension: fileExtension)
    ) else { throw AutomationImageTransformError.encodeFailed }
    let scale = info.nativeScale * CGFloat(size.width) / CGFloat(max(info.pixelWidth, 1))
    guard let data = QuickAccessImageOptimizer.encode(resized, fileExtension: fileExtension, scale: scale) else {
      throw AutomationImageTransformError.encodeFailed
    }
    let url = uniqueURL(in: directory, baseName: baseName, fileExtension: fileExtension)
    try data.write(to: url, options: .atomic)
    return AutomationImageTransformResult(
      url: url,
      pixelWidth: size.width,
      pixelHeight: size.height,
      fellBackToPNG: fileExtension != source.pathExtension.lowercased(),
      exceedsFileSizeLimit: false
    )
  }

  /// Re-encodes `source` with the Optimize pipeline (format, quality, file-size cap).
  static func convert(
    _ source: URL,
    settings: QuickAccessOptimizeSettings,
    into directory: URL,
    baseName: String,
    isCancelled: () -> Bool = { false }
  ) throws -> AutomationImageTransformResult {
    let info = try sourceInfo(source)
    guard let image = QuickAccessImageOptimizer.loadImage(at: source) else { throw AutomationImageTransformError.unreadable }
    let originalExtension = encodableExtension(source.pathExtension)
    guard let rendering = QuickAccessImageOptimizer.render(
      settings,
      from: image,
      source: info,
      originalExtension: originalExtension,
      isCancelled: isCancelled
    ) else { throw AutomationImageTransformError.encodeFailed }
    let url = uniqueURL(in: directory, baseName: baseName, fileExtension: rendering.fileExtension)
    try rendering.data.write(to: url, options: .atomic)
    let requested = settings.format.fileExtension(forOriginal: originalExtension)
    return AutomationImageTransformResult(
      url: url,
      pixelWidth: rendering.pixelWidth,
      pixelHeight: rendering.pixelHeight,
      fellBackToPNG: rendering.fileExtension != requested,
      exceedsFileSizeLimit: !rendering.meetsFileSizeLimit
    )
  }

  /// Re-encodes `source` in its own format with only DPI written, dropping EXIF,
  /// GPS, TIFF, IPTC and PNG text chunks. The color profile is kept.
  static func stripMetadata(_ source: URL, into directory: URL, baseName: String) throws -> AutomationImageTransformResult {
    let info = try sourceInfo(source)
    guard let image = QuickAccessImageOptimizer.loadImage(at: source) else { throw AutomationImageTransformError.unreadable }
    let fileExtension = encodableExtension(source.pathExtension)
    let quality: CGFloat? = QuickAccessOptimizeFormat.isLossy(fileExtension: fileExtension) ? 0.95 : nil
    guard let data = QuickAccessImageOptimizer.encode(
      image,
      fileExtension: fileExtension,
      scale: info.nativeScale,
      quality: quality
    ) else { throw AutomationImageTransformError.encodeFailed }
    let url = uniqueURL(in: directory, baseName: baseName, fileExtension: fileExtension)
    try data.write(to: url, options: .atomic)
    return AutomationImageTransformResult(
      url: url,
      pixelWidth: info.pixelWidth,
      pixelHeight: info.pixelHeight,
      fellBackToPNG: fileExtension != source.pathExtension.lowercased(),
      exceedsFileSizeLimit: false
    )
  }

  // MARK: - Helpers

  private static func sourceInfo(_ url: URL) throws -> QuickAccessOptimizeSourceInfo {
    guard let info = QuickAccessImageOptimizer.sourceInfo(at: url, fallbackScale: 1) else {
      throw AutomationImageTransformError.unreadable
    }
    return info
  }

  /// The file's extension when this Mac can write it, else `png`.
  private static func encodableExtension(_ fileExtension: String) -> String {
    let ext = fileExtension.lowercased()
    if ext == "webp" { return ext }
    guard let type = ImageEncoderSupport.typeIdentifier(forExtension: ext),
          ImageEncoderSupport.canEncode(typeIdentifier: type)
    else { return "png" }
    return ext
  }

  private static func uniqueURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
    var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(baseName)_\(suffix).\(fileExtension)")
      suffix += 1
    }
    return candidate
  }
}
