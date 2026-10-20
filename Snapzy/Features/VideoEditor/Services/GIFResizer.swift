//
//  GIFResizer.swift
//  Snapzy
//
//  Resizes animated GIF files using ImageIO
//  Preserves frame delays, loop count, and animation metadata
//

import CoreGraphics
import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers

private nonisolated let logger = Logger(subsystem: "Snapzy", category: "GIFResizer")

/// Resizes an animated GIF to target dimensions using ImageIO
@MainActor
final class GIFResizer {
  /// Resize a GIF file to the specified dimensions.
  /// Frames are decoded and redrawn off the main actor.
  /// - Parameters:
  ///   - sourceURL: URL of the source GIF
  ///   - targetSize: Desired output dimensions
  ///   - outputURL: URL for the resized GIF output
  ///   - onProgress: Progress callback (0.0 - 1.0), called off the main actor
  static func resize(
    sourceURL: URL,
    targetSize: CGSize,
    outputURL: URL,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    let outputDirAccess = SandboxFileAccessManager.shared.beginAccessingURL(
      outputURL.deletingLastPathComponent()
    )
    defer {
      sourceAccess.stop()
      outputDirAccess.stop()
    }

    try await Task.detached(priority: .userInitiated) {
      try resizeFrames(
        sourceURL: sourceURL,
        targetSize: targetSize,
        outputURL: outputURL,
        onProgress: onProgress
      )
    }.value
  }

  private nonisolated static func resizeFrames(
    sourceURL: URL,
    targetSize: CGSize,
    outputURL: URL,
    onProgress: (Double) -> Void
  ) throws {
    // Create image source
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw GIFResizeError.cannotReadSource
    }

    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0 else {
      throw GIFResizeError.noFrames
    }

    // Read global GIF properties (loop count)
    let sourceProperties = CGImageSourceCopyProperties(source, nil) as? [String: Any]
    let gifProperties = sourceProperties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
    let loopCount = gifProperties?[kCGImagePropertyGIFLoopCount as String] as? Int ?? 0

    // Remove existing output if any
    try? FileManager.default.removeItem(at: outputURL)

    // Create output directory if needed
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    // Create destination
    guard let destination = CGImageDestinationCreateWithURL(
      outputURL as CFURL,
      UTType.gif.identifier as CFString,
      frameCount,
      nil
    ) else {
      throw GIFResizeError.cannotCreateDestination
    }

    // Set GIF-level properties
    let destGIFProperties: [String: Any] = [
      kCGImagePropertyGIFDictionary as String: [
        kCGImagePropertyGIFLoopCount as String: loopCount,
        kCGImagePropertyGIFHasGlobalColorMap as String: true,
      ],
    ]
    CGImageDestinationSetProperties(destination, destGIFProperties as CFDictionary)

    let targetWidth = Int(targetSize.width)
    let targetHeight = Int(targetSize.height)

    // Process each frame; the pool releases each decoded and resized frame before the next.
    for i in 0 ..< frameCount {
      autoreleasepool {
        addResizedFrame(
          at: i,
          from: source,
          to: destination,
          targetWidth: targetWidth,
          targetHeight: targetHeight
        )
      }

      // Report progress
      let progress = Double(i + 1) / Double(frameCount)
      onProgress(progress * 0.95) // Reserve 5% for finalization
    }

    // Finalize
    guard CGImageDestinationFinalize(destination) else {
      throw GIFResizeError.finalizationFailed
    }

    onProgress(1.0)

    // Log result
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
    let fileSizeMB = String(format: "%.1f", Double(fileSize) / 1_048_576.0)
    logger.info(
      "GIF resized: \(outputURL.lastPathComponent) — \(frameCount) frames, \(targetWidth)×\(targetHeight), \(fileSizeMB)MB"
    )
  }

  private nonisolated static func addResizedFrame(
    at i: Int,
    from source: CGImageSource,
    to destination: CGImageDestination,
    targetWidth: Int,
    targetHeight: Int
  ) {
    guard let sourceImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
      return
    }

    // Get frame properties (delay time)
    let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
    let frameGIFProps = frameProperties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]

    let delayTime = frameGIFProps?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
      ?? frameGIFProps?[kCGImagePropertyGIFDelayTime as String] as? Double
      ?? 0.1

    // Resize frame
    let colorSpace = sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: targetHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return
    }

    context.interpolationQuality = .high
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

    let fittedRect = VideoEditorExportLayout.aspectFitRect(
      sourceSize: CGSize(width: sourceImage.width, height: sourceImage.height),
      in: CGSize(width: targetWidth, height: targetHeight)
    )
    context.draw(sourceImage, in: fittedRect)

    guard let resizedImage = context.makeImage() else {
      return
    }

    // Write frame with preserved delay
    let outputFrameProperties: [String: Any] = [
      kCGImagePropertyGIFDictionary as String: [
        kCGImagePropertyGIFDelayTime as String: delayTime,
        kCGImagePropertyGIFUnclampedDelayTime as String: delayTime,
      ],
    ]
    CGImageDestinationAddImage(destination, resizedImage, outputFrameProperties as CFDictionary)
  }

  /// Get metadata from a GIF file
  static func metadata(for url: URL) -> GIFMetadata? {
    let access = SandboxFileAccessManager.shared.beginAccessingURL(url)
    defer { access.stop() }

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }

    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0, let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }

    // Calculate total duration from frame delays
    var totalDuration: Double = 0
    for i in 0 ..< frameCount {
      let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
      let gifProps = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
      let delay = gifProps?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
        ?? gifProps?[kCGImagePropertyGIFDelayTime as String] as? Double
        ?? 0.1
      totalDuration += delay
    }

    return GIFMetadata(
      width: firstFrame.width,
      height: firstFrame.height,
      frameCount: frameCount,
      duration: totalDuration
    )
  }
}

// MARK: - GIF Metadata

struct GIFMetadata {
  let width: Int
  let height: Int
  let frameCount: Int
  let duration: Double

  var size: CGSize {
    CGSize(width: width, height: height)
  }

  var fps: Double {
    guard duration > 0 else { return 0 }
    return Double(frameCount) / duration
  }
}

// MARK: - Errors

nonisolated enum GIFResizeError: Error, LocalizedError {
  case cannotReadSource
  case noFrames
  case cannotCreateDestination
  case finalizationFailed

  var errorDescription: String? {
    switch self {
    case .cannotReadSource: L10n.GIF.cannotReadSource
    case .noFrames: L10n.GIF.noFramesInGIF
    case .cannotCreateDestination: L10n.GIF.cannotCreateOutputFile
    case .finalizationFailed: L10n.GIF.finalizeResizedFailed
    }
  }
}
