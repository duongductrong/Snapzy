//
//  ImageEncoderSupport.swift
//  Snapzy
//
//  Which still-image formats ImageIO can encode on this Mac, and the shared
//  extension → type mapping for the formats Snapzy writes through ImageIO.
//

import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageEncoderSupport {
  static let pngType = "public.png"
  static let jpegType = "public.jpeg"
  static let heicType = "public.heic"
  static let avifType = "public.avif"

  /// Default lossy quality for JPEG, HEIC and AVIF screenshots.
  static let defaultLossyQuality: CGFloat = 0.9

  /// Read once: the system encoder list does not change while the app runs.
  private static let encodableTypes: Set<String> = {
    let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    return Set(identifiers)
  }()

  static func canEncode(typeIdentifier: String) -> Bool {
    encodableTypes.contains(typeIdentifier)
  }

  /// HEIC encoding ships with macOS 10.13+, but stays a runtime check.
  static var canEncodeHEIC: Bool { canEncode(typeIdentifier: heicType) }

  /// AVIF encoding depends on the macOS release; older systems only decode it.
  static var canEncodeAVIF: Bool { canEncode(typeIdentifier: avifType) }

  /// ImageIO type for an extension Snapzy encodes through ImageIO. `nil` for
  /// WebP (own encoder) and for anything else.
  static func typeIdentifier(forExtension fileExtension: String) -> String? {
    switch fileExtension.lowercased() {
    case "png": pngType
    case "jpg", "jpeg": jpegType
    case "heic", "heif": heicType
    case "avif": avifType
    default: nil
    }
  }

  /// Whether this Mac can write the given extension (WebP is always available).
  static func canEncode(fileExtension: String) -> Bool {
    let ext = fileExtension.lowercased()
    if ext == "webp" { return true }
    guard let type = typeIdentifier(forExtension: ext) else { return false }
    return canEncode(typeIdentifier: type)
  }

  static func isLossy(fileExtension: String) -> Bool {
    ["jpg", "jpeg", "webp", "heic", "heif", "avif"].contains(fileExtension.lowercased())
  }

  /// JPEG is the only output format without an alpha channel.
  static func supportsAlpha(fileExtension: String) -> Bool {
    !["jpg", "jpeg"].contains(fileExtension.lowercased())
  }
}
