import AppKit
import Foundation
import SnapzyPluginAPI

/// `snapzy.image` — decode / resize / crop / encode, host-side and native
/// (ImageIO + `WebPEncoderService`). Plugins orchestrate; the host executes.
final class PluginImageService {
  func run(_ operation: PluginImageOperation) async throws -> PluginImageResult {
    switch operation.operation {
    case "decode":
      guard let data = operation.image else {
        throw PluginServiceError(code: "badPayload", message: "decode needs image bytes.")
      }
      return try await Self.decode(data, format: operation.format)
    case "resize":
      guard let data = operation.image, let targetSize = operation.targetSize else {
        throw PluginServiceError(code: "badPayload", message: "resize needs image bytes and targetSize.")
      }
      return try await Self.resize(data, targetSize: targetSize, format: operation.format ?? "png", quality: operation.quality ?? 0.9)
    case "crop":
      guard let data = operation.image, let cropRect = operation.cropRect else {
        throw PluginServiceError(code: "badPayload", message: "crop needs image bytes and cropRect.")
      }
      return try await Self.crop(data, cropRect: cropRect, format: operation.format ?? "png")
    case "encode":
      guard let data = operation.image else {
        throw PluginServiceError(code: "badPayload", message: "encode needs image bytes.")
      }
      return try await Self.encode(data, format: operation.format ?? "png", quality: operation.quality ?? 0.9)
    default:
      throw PluginServiceError(code: "unknownOperation", message: "Unknown image operation “\(operation.operation)”.")
    }
  }

  private static func decode(_ data: Data, format: String?) async throws -> PluginImageResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "The image could not be decoded."))
          return
        }
        let output = encode(cgImage: cgImage, format: format ?? "png", quality: 0.9)
          ?? data
        continuation.resume(
          returning: PluginImageResult(
            image: output,
            size: SnapzySize(width: Double(cgImage.width), height: Double(cgImage.height)),
            format: format ?? "png"
          )
        )
      }
    }
  }

  private static func resize(_ data: Data, targetSize: SnapzySize, format: String, quality: Double) async throws -> PluginImageResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "The image could not be decoded."))
          return
        }
        let width = max(Int(targetSize.width), 1)
        let height = max(Int(targetSize.height), 1)
        guard let context = CGContext(
          data: nil, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "Could not create a bitmap context."))
          return
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage(),
          let output = encode(cgImage: resized, format: format, quality: quality)
        else {
          continuation.resume(throwing: PluginServiceError(code: "encodeFailed", message: "Could not encode the resized image."))
          return
        }
        continuation.resume(
          returning: PluginImageResult(
            image: output,
            size: SnapzySize(width: Double(width), height: Double(height)),
            format: format
          )
        )
      }
    }
  }

  private static func crop(_ data: Data, cropRect: SnapzyRect, format: String) async throws -> PluginImageResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "The image could not be decoded."))
          return
        }
        let rect = CGRect(
          x: cropRect.x,
          y: cropRect.y,
          width: cropRect.width,
          height: cropRect.height
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard !rect.isEmpty, let cropped = cgImage.cropping(to: rect),
          let output = encode(cgImage: cropped, format: format, quality: 0.9)
        else {
          continuation.resume(throwing: PluginServiceError(code: "cropFailed", message: "The crop rect is invalid."))
          return
        }
        continuation.resume(
          returning: PluginImageResult(
            image: output,
            size: SnapzySize(width: Double(cropped.width), height: Double(cropped.height)),
            format: format
          )
        )
      }
    }
  }

  private static func encode(_ data: Data, format: String, quality: Double) async throws -> PluginImageResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          continuation.resume(throwing: PluginServiceError(code: "decodeFailed", message: "The image could not be decoded."))
          return
        }
        guard let output = encode(cgImage: cgImage, format: format, quality: quality) else {
          continuation.resume(throwing: PluginServiceError(code: "encodeFailed", message: "The image could not be encoded as \(format)."))
          return
        }
        continuation.resume(
          returning: PluginImageResult(
            image: output,
            size: SnapzySize(width: Double(cgImage.width), height: Double(cgImage.height)),
            format: format
          )
        )
      }
    }
  }

  private static func encode(cgImage: CGImage, format: String, quality: Double) -> Data? {
    switch format {
    case "webp":
      return WebPEncoderService.encode(cgImage, quality: quality)
    case "jpeg", "jpg":
      return imageData(cgImage: cgImage, type: "public.jpeg", quality: quality)
    case "heic":
      return imageData(cgImage: cgImage, type: "public.heic", quality: quality)
    case "tiff":
      return imageData(cgImage: cgImage, type: "public.tiff", quality: quality)
    default:
      return imageData(cgImage: cgImage, type: "public.png", quality: quality)
    }
  }

  private static func imageData(cgImage: CGImage, type: String, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
      return nil
    }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
