//
//  VideoEditorClipThumbnailCache.swift
//  Snapzy
//
//  Frame thumbnails for clips the user inserted into the timeline. The primary
//  recording's strip is extracted once by `VideoEditorState.extractFrames()`; this
//  covers the other assets, keyed by URL so duplicated clips share one strip.
//

import AVFoundation
import AppKit
import Combine
import Foundation

@MainActor
final class VideoEditorClipThumbnailCache: ObservableObject {
  @Published private(set) var strips: [URL: [NSImage]] = [:]

  private var inFlight: Set<URL> = []

  /// Frames per inserted clip. Lower than the primary strip's budget: inserted clips
  /// are usually short and several can be on screen at once.
  private static let frameCount = 12
  private static let targetSize = CGSize(width: 120, height: 68)

  func strip(for url: URL) -> [NSImage] {
    strips[url] ?? []
  }

  /// Generate a strip for `url` unless one is cached or already being generated.
  func ensureLoaded(for url: URL) {
    guard strips[url] == nil, !inFlight.contains(url) else { return }
    inFlight.insert(url)

    Task { [weak self] in
      let images = await Self.generate(url: url, count: Self.frameCount)
      guard let self else { return }
      self.strips[url] = images
      self.inFlight.remove(url)
    }
  }

  func forget(url: URL) {
    strips[url] = nil
    inFlight.remove(url)
  }

  // MARK: - Generation

  private nonisolated static func generate(url: URL, count: Int) async -> [NSImage] {
    let safeCount = max(count, 1)

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        autoreleasepool {
          let asset = AVAsset(url: url)
          let seconds = CMTimeGetSeconds(asset.duration)
          guard seconds > 0 else {
            continuation.resume(returning: [])
            return
          }

          let generator = AVAssetImageGenerator(asset: asset)
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = targetSize
          generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
          generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)

          // Sample each cell's centre, matching how the strip tiles its cells.
          var images: [NSImage] = []
          for index in 0..<safeCount {
            let progress = (Double(index) + 0.5) / Double(safeCount)
            let time = CMTime(seconds: seconds * progress, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            images.append(NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68)))
          }

          continuation.resume(returning: images)
        }
      }
    }
  }
}
