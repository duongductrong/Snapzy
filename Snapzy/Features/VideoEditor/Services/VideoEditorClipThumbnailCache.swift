//
//  VideoEditorClipThumbnailCache.swift
//  Snapzy
//
//  Frame thumbnails for clips the user inserted into the timeline. The primary
//  recording's strip is extracted once by `VideoEditorState.extractFrames()`; this
//  covers the other assets, keyed by URL so duplicated clips share one strip.
//

import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class VideoEditorClipThumbnailCache: ObservableObject {
  @Published private(set) var strips: [URL: [NSImage]] = [:]

  private var inFlight: Set<URL> = []

  /// Frames per inserted clip at 2× Retina resolution so inserted B-roll matches
  /// the primary recording's filmstrip sharpness without bloating memory.
  private nonisolated static let frameCount = 18
  private nonisolated static let targetSize = CGSize(width: 420, height: 236)

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

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
      strips[url] = images
      inFlight.remove(url)
    }
  }

  func forget(url: URL) {
    strips[url] = nil
    inFlight.remove(url)
  }

  // MARK: - Generation

  private nonisolated static func generate(url: URL, count: Int) async -> [NSImage] {
    let safeCount = max(count, 1)
    let durationAsset = AVAsset(url: url)
    guard let duration = try? await durationAsset.load(.duration) else { return [] }
    let seconds = CMTimeGetSeconds(duration)
    guard seconds > 0 else { return [] }

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        autoreleasepool {
          let asset = AVAsset(url: url)
          let generator = AVAssetImageGenerator(asset: asset)
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = targetSize
          generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
          generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)

          // Sample each cell's centre, matching how the strip tiles its cells.
          var images: [NSImage] = []
          for index in 0 ..< safeCount {
            let progress = (Double(index) + 0.5) / Double(safeCount)
            let time = CMTime(seconds: seconds * progress, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            let pointSize = NSSize(
              width: max(1, CGFloat(cgImage.width) / 2.0),
              height: max(1, CGFloat(cgImage.height) / 2.0)
            )
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = pointSize
            let nsImage = NSImage(size: pointSize)
            nsImage.addRepresentation(rep)
            images.append(nsImage)
          }

          continuation.resume(returning: images)
        }
      }
    }
  }
}
