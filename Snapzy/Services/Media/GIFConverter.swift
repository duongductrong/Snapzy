//
//  GIFConverter.swift
//  Snapzy
//
//  Converts video files to animated GIF using AVFoundation + ImageIO
//  Optimizes for visual quality while keeping file size reasonable
//  No FFmpeg dependency — pure Apple frameworks
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "Snapzy", category: "GIFConverter")

/// Converts a video file to an animated GIF
@MainActor
final class GIFConverter {

  /// GIF generation parameters
  struct Options {
    /// Frame rate for the GIF (higher = smoother but larger)
    var fps: Int = 15

    /// Max output width in pixels (source width used if smaller)
    var maxWidth: CGFloat = 960

    /// Infinite loop by default
    var loopCount: Int = 0

    /// Balanced defaults: 15fps @ up to 960px wide
    static let `default` = Options()
  }

  /// Convert a video file to animated GIF
  /// - Parameters:
  ///   - videoURL: URL of the source video
  ///   - options: GIF generation options
  ///   - onProgress: Progress callback (0.0 - 1.0), called on MainActor
  /// - Returns: URL of the generated GIF file
  static func convert(
    videoURL: URL,
    options: Options = .default,
    onProgress: @escaping (Double) -> Void
  ) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)

    // Get video duration
    let duration: CMTime
    if #available(macOS 15.0, *) {
      duration = try await asset.load(.duration)
    } else {
      duration = asset.duration
    }
    let durationSeconds = CMTimeGetSeconds(duration)

    guard durationSeconds > 0, durationSeconds.isFinite else {
      throw GIFConversionError.invalidVideo
    }

    // Get video dimensions for scaling
    let videoTrack: AVAssetTrack?
    if #available(macOS 15.0, *) {
      videoTrack = try? await asset.loadTracks(withMediaType: .video).first
    } else {
      videoTrack = asset.tracks(withMediaType: .video).first
    }

    let naturalSize: CGSize
    if let track = videoTrack {
      if #available(macOS 15.0, *) {
        naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 640, height: 480)
      } else {
        naturalSize = track.naturalSize
      }
    } else {
      naturalSize = CGSize(width: 640, height: 480)
    }

    // Scale only if source exceeds maxWidth — never upscale
    let scale = min(1.0, options.maxWidth / naturalSize.width)
    let outputWidth = Int(naturalSize.width * scale)
    let outputHeight = Int(naturalSize.height * scale)

    // Calculate frame times
    let totalFrames = Int(ceil(durationSeconds * Double(options.fps)))
    guard totalFrames > 0 else { throw GIFConversionError.noFrames }

    var frameTimes: [NSValue] = []
    for i in 0..<totalFrames {
      let time = CMTime(
        seconds: Double(i) / Double(options.fps),
        preferredTimescale: 9600  // High timescale for sub-frame precision
      )
      frameTimes.append(NSValue(time: time))
    }

    // Setup image generator with quality-focused settings
    let generator = AVAssetImageGenerator(asset: asset)
    generator.maximumSize = CGSize(width: outputWidth, height: outputHeight)
    generator.appliesPreferredTrackTransform = true

    // Tight tolerance for accurate frame extraction (reduces ghosting)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 9600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 9600)

    // Generate output URL (same directory, .gif extension)
    let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")

    // Remove existing GIF if any
    try? FileManager.default.removeItem(at: gifURL)

    // Create GIF destination
    guard let destination = CGImageDestinationCreateWithURL(
      gifURL as CFURL,
      UTType.gif.identifier as CFString,
      totalFrames,
      nil
    ) else {
      throw GIFConversionError.destinationCreationFailed
    }

    // Set GIF-level properties (loop count + color model)
    let gifProperties: [String: Any] = [
      kCGImagePropertyGIFDictionary as String: [
        kCGImagePropertyGIFLoopCount as String: options.loopCount,
        kCGImagePropertyGIFHasGlobalColorMap as String: true,
      ]
    ]
    CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

    // Frame delay for each frame
    let frameDelay = 1.0 / Double(options.fps)
    let frameProperties: [String: Any] = [
      kCGImagePropertyGIFDictionary as String: [
        kCGImagePropertyGIFDelayTime as String: frameDelay,
        kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay,
      ]
    ]

    // Extract frames — collect with index to preserve ordering
    let orderedFrames = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<[CGImage], Error>) in

      // Use indexed storage to maintain temporal order
      var frameMap: [Int: CGImage] = [:]
      var completedCount = 0
      let expectedCount = frameTimes.count

      generator.generateCGImagesAsynchronously(forTimes: frameTimes) {
        requestedTime, image, actualTime, result, error in

        completedCount += 1

        if let image = image {
          // Map frame to its index by matching requested time
          let requestedSeconds = CMTimeGetSeconds(requestedTime)
          let frameIndex = Int(round(requestedSeconds * Double(options.fps)))
          frameMap[frameIndex] = image
        }

        // Report progress on main thread
        let progress = Double(completedCount) / Double(expectedCount)
        Task { @MainActor in
          onProgress(progress * 0.85)  // Reserve 15% for GIF assembly
        }

        if completedCount >= expectedCount {
          // Reconstruct frames in correct temporal order
          let sorted = (0..<expectedCount).compactMap { frameMap[$0] }
          if sorted.isEmpty {
            continuation.resume(throwing: GIFConversionError.noFrames)
          } else {
            continuation.resume(returning: sorted)
          }
        }
      }
    }

    // Add all frames to GIF destination
    for (idx, frame) in orderedFrames.enumerated() {
      CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)

      // Progress for assembly phase (85% → 100%)
      let assemblyProgress = 0.85 + (Double(idx) / Double(orderedFrames.count)) * 0.15
      onProgress(assemblyProgress)
    }

    // Finalize GIF
    guard CGImageDestinationFinalize(destination) else {
      throw GIFConversionError.finalizationFailed
    }

    onProgress(1.0)

    // Log file size for debugging
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int) ?? 0
    let fileSizeMB = String(format: "%.1f", Double(fileSize) / 1_048_576.0)
    logger.info(
      "GIF complete: \(gifURL.lastPathComponent) — \(orderedFrames.count) frames, \(fileSizeMB)MB"
    )

    return gifURL
  }
}

// MARK: - Errors

enum GIFConversionError: Error, LocalizedError {
  case invalidVideo
  case noFrames
  case destinationCreationFailed
  case finalizationFailed

  var errorDescription: String? {
    switch self {
    case .invalidVideo: return "Invalid or empty video file"
    case .noFrames: return "Could not extract any frames from video"
    case .destinationCreationFailed: return "Failed to create GIF output file"
    case .finalizationFailed: return "Failed to finalize GIF file"
    }
  }
}
