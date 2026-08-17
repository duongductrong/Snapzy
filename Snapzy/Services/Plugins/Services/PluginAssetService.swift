import AppKit
import Foundation
import SnapzyPluginAPI

/// `snapzy.asset.read` — host reads the file for the *current invocation
/// only*. 100 MB cap; bytes are produced only after the invocation token is
/// proven live.
enum PluginAssetService {
  static let maxAssetBytes = 100 * 1024 * 1024

  static func read(
    invocationID: UUID,
    invocations: PluginInvocationRegistry
  ) async throws -> Data {
    guard let url = invocations.assetURL(for: invocationID) else {
      throw PluginServiceError(code: "staleInvocation", message: "The invocation is no longer live.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
          guard size <= maxAssetBytes else {
            continuation.resume(throwing: PluginServiceError(code: "assetTooLarge", message: "The asset exceeds the 100 MB cap."))
            return
          }
          let data = try Data(contentsOf: url, options: [.mappedIfSafe])
          continuation.resume(returning: data)
        } catch {
          continuation.resume(throwing: PluginServiceError(code: "assetReadFailed", message: "\(error)"))
        }
      }
    }
  }

  static func thumbnail(
    invocationID: UUID,
    maxPixels: Int,
    invocations: PluginInvocationRegistry
  ) async throws -> Data {
    guard let url = invocations.assetURL(for: invocationID) else {
      throw PluginServiceError(code: "staleInvocation", message: "The invocation is no longer live.")
    }
    let capped = min(max(maxPixels, 64), 2048)
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "The asset could not be decoded."))
          return
        }
        let longest = max(cgImage.width, cgImage.height)
        let scale = longest > capped ? Double(capped) / Double(longest) : 1
        let targetWidth = Int(Double(cgImage.width) * scale)
        let targetHeight = Int(Double(cgImage.height) * scale)
        guard let context = CGContext(
          data: nil, width: targetWidth, height: targetHeight,
          bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "Could not create a bitmap context."))
          return
        }
        context.interpolationQuality = .high
        context.draw(
          cgImage,
          in: CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight))
        )
        guard let resized = context.makeImage() else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "Could not render the thumbnail."))
          return
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
          continuation.resume(throwing: PluginServiceError(code: "encodeFailed", message: "Could not encode the thumbnail."))
          return
        }
        CGImageDestinationAddImage(destination, resized, nil)
        CGImageDestinationFinalize(destination)
        continuation.resume(returning: data as Data)
      }
    }
  }
}
