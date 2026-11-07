//
//  MeasureImageLoader.swift
//  SnapzyMeasureCore
//
//  Reads an image file for measuring: the first frame as a CGImage plus its pixels per point,
//  taken from the file's DPI (DPI ÷ 72), the same rule Annotate uses when it opens a file.
//

import CoreGraphics
import Foundation
import ImageIO

public struct MeasureLoadedImage: @unchecked Sendable {
  public let image: CGImage
  /// Pixels per point; 1 when the file carries no DPI.
  public let scale: Double
}

public enum MeasureImageLoaderError: Error, Equatable, Sendable {
  case notFound(String)
  case unreadable(String)
  case tooLarge(width: Int, height: Int, maxPixels: Int)
}

public enum MeasureImageLoader {
  /// 100 megapixels: far above any display (6K is ~20 MP). Decoding plus the RGBA raster
  /// copy needs about 8 bytes per pixel, so this caps peak memory near 800 MB.
  public static let defaultMaxPixels = 100_000_000

  public static func load(url: URL, maxPixels: Int = defaultMaxPixels) throws -> MeasureLoadedImage {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
      throw MeasureImageLoaderError.notFound(url.path)
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) > 0 else {
      throw MeasureImageLoaderError.unreadable(url.path)
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    if width > 0, height > 0, width.multipliedReportingOverflow(by: height).partialValue > maxPixels
      || width.multipliedReportingOverflow(by: height).overflow {
      throw MeasureImageLoaderError.tooLarge(width: width, height: height, maxPixels: maxPixels)
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw MeasureImageLoaderError.unreadable(url.path)
    }
    if image.width * image.height > maxPixels {
      throw MeasureImageLoaderError.tooLarge(width: image.width, height: image.height, maxPixels: maxPixels)
    }
    return MeasureLoadedImage(image: image, scale: scale(from: properties))
  }

  /// DPI ÷ 72, rounded to a quarter so 143.99 DPI reads as 2×; 1 when absent or implausible.
  static func scale(from properties: [CFString: Any]) -> Double {
    let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
      ?? (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
    guard let dpi, dpi.isFinite, dpi > 0 else { return 1 }
    let scale = (dpi / 72 * 4).rounded() / 4
    return (1...8).contains(scale) ? scale : 1
  }
}
