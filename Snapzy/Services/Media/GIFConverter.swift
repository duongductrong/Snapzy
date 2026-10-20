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
import UniformTypeIdentifiers

/// Converts a video file to an animated GIF
@MainActor
final class GIFConverter {

  /// GIF generation parameters
  nonisolated struct Options {
    /// Frame rate for the GIF (higher = smoother but larger)
    var fps: Int = 15

    /// Max output width in pixels (source width used if smaller)
    var maxWidth: CGFloat = 960

    /// Infinite loop by default
    var loopCount: Int = 0

    /// Balanced defaults: 15fps @ up to 960px wide
    nonisolated static let `default` = Options()
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
    let sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(videoURL)
    let outputDirectoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(
      videoURL.deletingLastPathComponent())
    defer {
      sourceAccess.stop()
      outputDirectoryAccess.stop()
    }
    DiagnosticLogger.shared.log(.info, .recording, "GIF conversion pipeline started", context: [
      "file": videoURL.lastPathComponent,
      "fps": "\(options.fps)",
      "maxWidth": "\(Int(options.maxWidth))",
    ])

    let asset = AVURLAsset(url: videoURL)

    // Get video duration through AVFoundation's async loading API.
    let duration = try await asset.load(.duration)
    let durationSeconds = CMTimeGetSeconds(duration)

    guard durationSeconds > 0, durationSeconds.isFinite else {
      DiagnosticLogger.shared.log(.error, .recording, "GIF conversion invalid video duration", context: [
        "file": videoURL.lastPathComponent,
        "durationSeconds": "\(durationSeconds)",
      ])
      throw GIFConversionError.invalidVideo
    }

    // Get video dimensions for scaling
    let videoTrack = try? await asset.loadTracks(withMediaType: .video).first

    let naturalSize: CGSize
    if let track = videoTrack {
      naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 640, height: 480)
    } else {
      DiagnosticLogger.shared.log(.warning, .recording, "GIF conversion found no video track; using fallback size", context: [
        "file": videoURL.lastPathComponent
      ])
      naturalSize = CGSize(width: 640, height: 480)
    }

    // Scale only if source exceeds maxWidth — never upscale
    let scale = min(1.0, options.maxWidth / naturalSize.width)
    let outputWidth = Int(naturalSize.width * scale)
    let outputHeight = Int(naturalSize.height * scale)

    // Calculate frame times
    let totalFrames = Int(ceil(durationSeconds * Double(options.fps)))
    guard totalFrames > 0 else {
      DiagnosticLogger.shared.log(.error, .recording, "GIF conversion has no frame times", context: [
        "durationSeconds": String(format: "%.3f", durationSeconds),
        "fps": "\(options.fps)",
      ])
      throw GIFConversionError.noFrames
    }
    DiagnosticLogger.shared.log(.debug, .recording, "GIF conversion plan", context: [
      "durationSeconds": String(format: "%.3f", durationSeconds),
      "sourceSize": "\(Int(naturalSize.width))x\(Int(naturalSize.height))",
      "outputSize": "\(outputWidth)x\(outputHeight)",
      "expectedFrames": "\(totalFrames)",
    ])

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
      DiagnosticLogger.shared.log(.error, .recording, "GIF conversion destination creation failed", context: [
        "file": gifURL.lastPathComponent,
        "expectedFrames": "\(totalFrames)",
      ])
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

    // Frames are encoded as soon as they arrive, in order, so only a handful of decoded
    // frames are alive at once (ImageIO encodes on add once destination properties are set).
    let writer = GIFFrameWriter(
      destination: destination,
      sequencer: GIFFrameSequencer(frameDelay: 1.0 / Double(options.fps))
    )
    let expectedCount = frameTimes.count

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in

      generator.generateCGImagesAsynchronously(forTimes: frameTimes) {
        requestedTime, image, actualTime, result, error in

        // Map frame to its index by matching requested time
        let requestedSeconds = CMTimeGetSeconds(requestedTime)
        let frameIndex = Int(round(requestedSeconds * Double(options.fps)))
        let completedCount = writer.resolve(index: frameIndex, image: result == .succeeded ? image : nil)

        // Report progress on main thread
        let progress = Double(completedCount) / Double(expectedCount)
        Task { @MainActor in
          onProgress(progress * 0.98)  // Reserve the rest for finalization
        }

        if completedCount == expectedCount {
          writer.finish(frameCount: expectedCount)
          continuation.resume()
        }
      }
    }

    let writtenFrames = writer.writtenFrames
    guard writtenFrames > 0 else {
      DiagnosticLogger.shared.log(.error, .recording, "GIF conversion generated no frames", context: [
        "file": videoURL.lastPathComponent,
        "expectedFrames": "\(expectedCount)",
      ])
      try? FileManager.default.removeItem(at: gifURL)
      throw GIFConversionError.noFrames
    }
    if writtenFrames < totalFrames {
      DiagnosticLogger.shared.log(.warning, .recording, "GIF conversion generated fewer frames than expected", context: [
        "expectedFrames": "\(totalFrames)",
        "generatedFrames": "\(writtenFrames)",
      ])
    }

    // Finalize GIF
    guard CGImageDestinationFinalize(destination) else {
      DiagnosticLogger.shared.log(.error, .recording, "GIF conversion finalization failed", context: [
        "file": gifURL.lastPathComponent,
        "frames": "\(writtenFrames)",
      ])
      throw GIFConversionError.finalizationFailed
    }

    onProgress(1.0)

    let fileSize = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int) ?? 0
    let fileSizeMB = String(format: "%.1f", Double(fileSize) / 1_048_576.0)
    DiagnosticLogger.shared.log(.info, .recording, "GIF conversion completed", context: [
      "file": gifURL.lastPathComponent,
      "frames": "\(writtenFrames)",
      "fileSizeMB": fileSizeMB,
    ])

    return gifURL
  }
}

// MARK: - Frame Sequencing

/// Orders frames that may arrive out of order and assigns GIF delays. A frame that fails to
/// decode does not shorten the animation: its time is folded into the previous frame's delay.
nonisolated struct GIFFrameSequencer<Frame> {
  struct Output {
    let frame: Frame
    let delay: Double
  }

  let frameDelay: Double
  private var nextIndex = 0
  private var pendingResults: [Int: Frame?] = [:]
  private var held: Output?
  private var leadingMissingDelay = 0.0

  init(frameDelay: Double) {
    self.frameDelay = frameDelay
  }

  /// Records the result for `index` (nil = failed) and returns frames now ready to encode.
  mutating func resolve(index: Int, frame: Frame?) -> [Output] {
    guard index >= nextIndex, pendingResults[index] == nil else { return [] }
    pendingResults[index] = .some(frame)

    var ready: [Output] = []
    while let result = pendingResults.removeValue(forKey: nextIndex) {
      nextIndex += 1
      guard let frame = result else {
        if let current = held {
          held = Output(frame: current.frame, delay: current.delay + frameDelay)
        } else {
          leadingMissingDelay += frameDelay
        }
        continue
      }
      if let current = held {
        ready.append(current)
      }
      // A run of failures before the first frame stretches the first frame instead.
      held = Output(frame: frame, delay: frameDelay + leadingMissingDelay)
      leadingMissingDelay = 0
    }
    return ready
  }

  /// Flushes the last held frame. Indices below `frameCount` never resolved count as missing.
  mutating func finish(frameCount: Int) -> [Output] {
    var ready: [Output] = []
    while nextIndex < frameCount {
      ready += resolve(index: nextIndex, frame: nil)
    }
    pendingResults.removeAll()
    if let current = held {
      ready.append(current)
      held = nil
    }
    return ready
  }
}

/// Feeds generator callbacks into a GIF destination; callbacks may come from any thread.
private nonisolated final class GIFFrameWriter: @unchecked Sendable {
  private let lock = NSLock()
  private let destination: CGImageDestination
  private var sequencer: GIFFrameSequencer<CGImage>
  private var completedCount = 0
  private var _writtenFrames = 0

  init(destination: CGImageDestination, sequencer: GIFFrameSequencer<CGImage>) {
    self.destination = destination
    self.sequencer = sequencer
  }

  var writtenFrames: Int {
    lock.withLock { _writtenFrames }
  }

  /// Returns the number of generator results received so far.
  func resolve(index: Int, image: CGImage?) -> Int {
    lock.withLock {
      completedCount += 1
      write(sequencer.resolve(index: index, frame: image))
      return completedCount
    }
  }

  func finish(frameCount: Int) {
    lock.withLock {
      write(sequencer.finish(frameCount: frameCount))
    }
  }

  private func write(_ outputs: [GIFFrameSequencer<CGImage>.Output]) {
    for output in outputs {
      let frameProperties: [String: Any] = [
        kCGImagePropertyGIFDictionary as String: [
          kCGImagePropertyGIFDelayTime as String: output.delay,
          kCGImagePropertyGIFUnclampedDelayTime as String: output.delay,
        ]
      ]
      CGImageDestinationAddImage(destination, output.frame, frameProperties as CFDictionary)
      _writtenFrames += 1
    }
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
    case .invalidVideo: return L10n.GIF.invalidVideo
    case .noFrames: return L10n.GIF.noFramesFromVideo
    case .destinationCreationFailed: return L10n.GIF.cannotCreateOutputFile
    case .finalizationFailed: return L10n.GIF.finalizeFailed
    }
  }
}
