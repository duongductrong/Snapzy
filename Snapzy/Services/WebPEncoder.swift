//
//  WebPEncoder.swift
//  Snapzy
//
//  WebP encoding service using SDWebImageWebPCoder (libwebp)
//

import AppKit
import Foundation
import SDWebImageWebPCoder

/// Encodes images to WebP format using SDWebImageWebPCoder (backed by libwebp).
enum WebPEncoder {

  /// Whether WebP encoding is available (always true when SDWebImageWebPCoder is linked)
  static var isAvailable: Bool { true }

  /// Encode an NSImage to WebP data
  /// - Parameters:
  ///   - image: The source image
  ///   - quality: Compression quality (0.0–1.0, default 0.9)
  /// - Returns: WebP data, or nil if encoding fails
  static func encode(_ image: NSImage, quality: CGFloat = 0.9) -> Data? {
    SDImageWebPCoder.shared.encodedData(
      with: image,
      format: .webP,
      options: [.encodeCompressionQuality: quality]
    )
  }

  /// Encode a CGImage to WebP data
  /// - Parameters:
  ///   - image: The source CGImage
  ///   - quality: Compression quality (0.0–1.0, default 0.9)
  /// - Returns: WebP data, or nil if encoding fails
  static func encode(_ image: CGImage, quality: CGFloat = 0.9) -> Data? {
    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    return encode(nsImage, quality: quality)
  }

  /// Encode a CGImage and write directly to a file URL
  /// - Parameters:
  ///   - image: The source CGImage
  ///   - url: Destination file URL
  ///   - quality: Compression quality (0.0–1.0, default 0.9)
  /// - Returns: true if successful
  @discardableResult
  static func write(_ image: CGImage, to url: URL, quality: CGFloat = 0.9) -> Bool {
    guard let data = encode(image, quality: quality) else {
      print("[WebPEncoder] Failed to encode WebP data")
      return false
    }
    do {
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      print("[WebPEncoder] Failed to write WebP file: \(error.localizedDescription)")
      return false
    }
  }
}
