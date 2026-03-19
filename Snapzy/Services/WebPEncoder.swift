//
//  WebPEncoder.swift
//  Snapzy
//
//  High-performance WebP encoding service using Swift-WebP (libwebp)
//

import AppKit
import Foundation
import WebP

/// High-performance WebP encoder backed by ainame/Swift-WebP (libwebp).
///
/// Uses raw pixel pointer encoding with optimised libwebp params:
/// - `method = 1` (fast, ~5x vs default method=4)
/// - `threadLevel = 1` (multi-threaded VP8 encoding)
/// - `preset = .photo` (optimised for screenshots / photographic content)
enum WebPEncoderService {

  /// Whether WebP encoding is available (always true when Swift-WebP is linked)
  static var isAvailable: Bool { true }

  /// Encode an NSImage to WebP data
  /// - Parameters:
  ///   - image: The source image
  ///   - quality: Compression quality (0.0–1.0, default 0.85)
  /// - Returns: WebP data, or nil if encoding fails
  static func encode(_ image: NSImage, quality: CGFloat = 0.85) -> Data? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    return encode(cgImage, quality: quality)
  }

  /// Encode a CGImage to WebP data using raw pixel pointer for maximum performance
  /// - Parameters:
  ///   - image: The source CGImage
  ///   - quality: Compression quality (0.0–1.0, default 0.85)
  /// - Returns: WebP data, or nil if encoding fails
  static func encode(_ image: CGImage, quality: CGFloat = 0.85) -> Data? {
    let width = image.width
    let height = image.height

    // Re-render into a known RGBA layout so the pointer is always valid
    let bytesPerRow = width * 4
    let totalBytes = bytesPerRow * height

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue  // RGBA
    ) else {
      print("[WebPEncoderService] Failed to create bitmap context")
      return nil
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let pixelData = context.data else {
      print("[WebPEncoderService] Failed to get pixel data from context")
      return nil
    }

    // Configure encoder for speed
    var config = WebPEncoderConfig.preset(.photo, quality: Float(quality * 100))
    config.method = 1         // 0=fastest, 6=best compression. 1 = great speed/quality tradeoff
    config.threadLevel = 1    // Enable multi-threaded encoding

    let encoder = WebP.WebPEncoder()
    let pointer = pixelData.assumingMemoryBound(to: UInt8.self)
    let buffer = UnsafeBufferPointer(start: pointer, count: totalBytes)

    do {
      return try encoder.encode(
        buffer,
        format: .rgba,
        config: config,
        originWidth: width,
        originHeight: height,
        stride: bytesPerRow
      )
    } catch {
      print("[WebPEncoderService] Encoding failed: \(error)")
      return nil
    }
  }

  /// Encode a CGImage and write directly to a file URL
  /// - Parameters:
  ///   - image: The source CGImage
  ///   - url: Destination file URL
  ///   - quality: Compression quality (0.0–1.0, default 0.85)
  /// - Returns: true if successful
  @discardableResult
  static func write(_ image: CGImage, to url: URL, quality: CGFloat = 0.85) -> Bool {
    guard let data = encode(image, quality: quality) else {
      print("[WebPEncoderService] Failed to encode WebP data")
      return false
    }
    do {
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      print("[WebPEncoderService] Failed to write WebP file: \(error.localizedDescription)")
      return false
    }
  }
}
