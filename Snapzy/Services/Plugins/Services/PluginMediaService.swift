import AppKit
import AVFoundation
import Foundation
import SnapzyPluginAPI

/// `snapzy.media` — duration / frame-at / audio extraction, AVFoundation and
/// host-side. Operates on the current invocation's asset URL only; the helper
/// cannot touch files directly.
final class PluginMediaService {
  func run(_ operation: PluginMediaOperation, assetURL: URL) async throws -> PluginMediaResult {
    switch operation.operation {
    case "duration":
      let asset = AVURLAsset(url: assetURL)
      let duration: Double?
      if #available(macOS 13.0, *) {
        duration = try? await asset.load(.duration).seconds
      } else {
        duration = asset.duration.seconds
      }
      let size = await Self.naturalSize(of: asset)
      let fps = await Self.frameRate(of: asset)
      return PluginMediaResult(
        duration: duration ?? 0,
        size: size,
        fps: fps
      )
    case "frameAt":
      let asset = AVURLAsset(url: assetURL)
      let time = operation.time ?? 0
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
      let cgImage = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
      let rep = NSBitmapImageRep(cgImage: cgImage)
      guard let png = rep.representation(using: .png, properties: [:]) else {
        throw PluginServiceError(code: "encodeFailed", message: "Could not encode the frame.")
      }
      return PluginMediaResult(
        duration: try? await asset.load(.duration).seconds,
        image: png
      )
    case "extractAudio":
      let asset = AVURLAsset(url: assetURL)
      guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
        throw PluginServiceError(code: "exportFailed", message: "Could not create an export session.")
      }
      let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapzy-plugin-audio-\(UUID().uuidString).m4a")
      session.outputURL = outputURL
      session.outputFileType = .m4a
      try await session.export(to: outputURL, as: .m4a)
      let data = try Data(contentsOf: outputURL)
      try? FileManager.default.removeItem(at: outputURL)
      return PluginMediaResult(audio: data)
    default:
      throw PluginServiceError(code: "unknownOperation", message: "Unknown media operation “\(operation.operation)”.")
    }
  }

  private static func naturalSize(of asset: AVURLAsset) async -> SnapzySize? {
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
    let size = try? await track.load(.naturalSize)
    let transform = try? await track.load(.preferredTransform)
    guard let size else { return nil }
    let isPortrait = abs((transform?.b ?? 0) + (transform?.c ?? 0)) > 0.1
    let width = isPortrait ? size.height : size.width
    let height = isPortrait ? size.width : size.height
    return SnapzySize(width: Double(abs(width)), height: Double(abs(height)))
  }

  private static func frameRate(of asset: AVURLAsset) async -> Double? {
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
    guard let rate = try? await track.load(.nominalFrameRate) else { return nil }
    return Double(rate)
  }
}

extension AVAssetExportSession {
  func export(to url: URL, as fileType: AVFileType) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      exportAsynchronously { [weak self] in
        guard let self else {
          continuation.resume(throwing: PluginServiceError(code: "exportFailed", message: "Export session vanished."))
          return
        }
        switch self.status {
        case .completed:
          continuation.resume()
        case .failed:
          continuation.resume(
            throwing: PluginServiceError(
              code: "exportFailed",
              message: self.error?.localizedDescription ?? "Export failed."
            )
          )
        case .cancelled:
          continuation.resume(throwing: PluginServiceError(code: "cancelled", message: "Export cancelled."))
        default:
          continuation.resume(throwing: PluginServiceError(code: "exportFailed", message: "Export failed."))
        }
      }
    }
  }
}

extension AVAssetImageGenerator {
  func image(at time: CMTime) async throws -> CGImage {
    try await withCheckedThrowingContinuation { continuation in
      generateCGImageAsynchronously(for: time) { cgImage, _, error in
        if let cgImage {
          continuation.resume(returning: cgImage)
        } else {
          continuation.resume(
            throwing: PluginServiceError(
              code: "frameFailed",
              message: error?.localizedDescription ?? "Could not extract the frame."
            )
          )
        }
      }
    }
  }
}
