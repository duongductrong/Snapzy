//
//  WindowCaptureResolution.swift
//  Snapzy
//
//  Pure scale and output-size rules for independent window captures.
//

import CoreGraphics
import Foundation

nonisolated enum WindowCaptureResolution {
  /// Small differences can come from pixel rounding or transparent window
  /// margins. A result below this ratio is a density mismatch, not rounding.
  static let minimumAcceptedScaleRatio: CGFloat = 0.75

  static func scaleFactor(
    displayBackingScaleFactor: CGFloat?,
    filterPointPixelScale: CGFloat?,
    fallback: CGFloat
  ) -> CGFloat {
    if let displayBackingScaleFactor,
       displayBackingScaleFactor.isFinite,
       displayBackingScaleFactor > 0 {
      return displayBackingScaleFactor
    }

    if let filterPointPixelScale,
       filterPointPixelScale.isFinite,
       filterPointPixelScale > 0 {
      return filterPointPixelScale
    }

    return max(fallback, 1)
  }

  static func actualScaleFactor(
    pixelSize: CGSize,
    logicalSize: CGSize
  ) -> CGFloat? {
    guard
      pixelSize.width > 0,
      pixelSize.height > 0,
      logicalSize.width > 0,
      logicalSize.height > 0
    else {
      return nil
    }

    let widthScale = pixelSize.width / logicalSize.width
    let heightScale = pixelSize.height / logicalSize.height
    let scale = min(widthScale, heightScale)
    return scale.isFinite && scale > 0 ? scale : nil
  }

  static func expectedPixelSize(
    logicalSize: CGSize,
    scaleFactor: CGFloat
  ) -> CGSize {
    let scale = max(scaleFactor, 1)
    return CGSize(
      width: max(1, (logicalSize.width * scale).rounded()),
      height: max(1, (logicalSize.height * scale).rounded())
    )
  }

  static func isUndersized(
    pixelSize: CGSize,
    logicalSize: CGSize,
    expectedScaleFactor: CGFloat
  ) -> Bool {
    guard
      expectedScaleFactor.isFinite,
      expectedScaleFactor > 0,
      let actualScaleFactor = actualScaleFactor(pixelSize: pixelSize, logicalSize: logicalSize)
    else {
      return false
    }

    return actualScaleFactor < expectedScaleFactor * minimumAcceptedScaleRatio
  }
}
