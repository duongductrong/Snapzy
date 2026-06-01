//
//  AnnotateImageRotation.swift
//  Snapzy
//
//  90° rotation helpers for NSImage and CGRect used by the editor's
//  rotate-left / rotate-right toolbar buttons.
//

import AppKit
import CoreGraphics

extension NSImage {
  /// Returns a new `NSImage` rotated 90° clockwise or counter-clockwise.
  ///
  /// Preserves backing-pixel resolution (Retina) by rotating the underlying
  /// `CGImage` and constructing an `NSImage` whose logical `size` is the
  /// original size with width/height swapped.
  func rotated90(clockwise: Bool) -> NSImage? {
    guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    let pixelWidth = cgImage.width
    let pixelHeight = cgImage.height
    let newPixelWidth = pixelHeight
    let newPixelHeight = pixelWidth

    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
      data: nil,
      width: newPixelWidth,
      height: newPixelHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      return nil
    }

    context.interpolationQuality = .high

    // Translate origin to the rotation pivot (centre of the new canvas), rotate, then draw the
    // source centred on the origin. CGContext uses bottom-left origin which is fine — we operate
    // on a square-equivalent rotation that's orientation-agnostic.
    context.translateBy(x: CGFloat(newPixelWidth) / 2, y: CGFloat(newPixelHeight) / 2)
    context.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
    context.translateBy(x: -CGFloat(pixelWidth) / 2, y: -CGFloat(pixelHeight) / 2)
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

    guard let rotatedCGImage = context.makeImage() else { return nil }

    // Preserve logical point size (swap width/height) so display scale is unchanged on Retina.
    let pointSize = NSSize(width: self.size.height, height: self.size.width)
    return NSImage(cgImage: rotatedCGImage, size: pointSize)
  }
}

/// Pure geometry helpers for rotating annotation coordinates in image-pixel space
/// (top-left origin, y-down).
enum AnnotateImageRotation {
  /// Rotate a point 90° within an image of `oldSize`.
  static func rotatePoint(
    _ point: CGPoint,
    oldSize: CGSize,
    clockwise: Bool
  ) -> CGPoint {
    if clockwise {
      return CGPoint(x: oldSize.height - point.y, y: point.x)
    } else {
      return CGPoint(x: point.y, y: oldSize.width - point.x)
    }
  }

  /// Rotate a rect 90° within an image of `oldSize`. The returned rect is standardised.
  static func rotateRect(
    _ rect: CGRect,
    oldSize: CGSize,
    clockwise: Bool
  ) -> CGRect {
    let standardised = rect.standardized
    if clockwise {
      return CGRect(
        x: oldSize.height - standardised.minY - standardised.height,
        y: standardised.minX,
        width: standardised.height,
        height: standardised.width
      )
    } else {
      return CGRect(
        x: standardised.minY,
        y: oldSize.width - standardised.minX - standardised.width,
        width: standardised.height,
        height: standardised.width
      )
    }
  }
}
