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

  /// Transparent room, in points, added on every side of a shadowed window's
  /// output canvas. The filter's content rect excludes the shadow, and
  /// ScreenCaptureKit shrinks a shadowed window that does not fit its canvas
  /// (issue #569). macOS shadows measured about 56pt per side, so this leaves
  /// headroom; the unused margin is trimmed after capture.
  static let shadowCanvasPadding: CGFloat = 128

  /// Points a cached `SCWindow` frame may drift from WindowServer's live
  /// bounds before the cached window is treated as stale.
  static let staleFrameTolerance: CGFloat = 1

  /// Pixels a padded capture may fall short of native size from rounding.
  static let nativeSizeTolerance: CGFloat = 2

  /// A cached `SCShareableContent` keeps the frame a window had when it was
  /// fetched. Sizing a capture from it after a resize shrinks or crops the
  /// window (issue #634), so a frame that moved or resized needs a refresh.
  static func isFrameStale(_ cachedFrame: CGRect, currentFrame: CGRect?) -> Bool {
    guard let currentFrame, !currentFrame.isEmpty else { return false }

    let tolerance = staleFrameTolerance
    return abs(cachedFrame.minX - currentFrame.minX) > tolerance
      || abs(cachedFrame.minY - currentFrame.minY) > tolerance
      || abs(cachedFrame.width - currentFrame.width) > tolerance
      || abs(cachedFrame.height - currentFrame.height) > tolerance
  }

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

  /// Output canvas for an independent window capture. A shadowed window needs
  /// padding so it renders 1:1 instead of being scaled down to fit.
  static func canvasPixelSize(
    logicalSize: CGSize,
    scaleFactor: CGFloat,
    includesShadow: Bool
  ) -> CGSize {
    let padding = includesShadow ? shadowCanvasPadding * 2 : 0
    return expectedPixelSize(
      logicalSize: CGSize(
        width: logicalSize.width + padding,
        height: logicalSize.height + padding
      ),
      scaleFactor: scaleFactor
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

  /// A padded capture is trimmed to the window plus its shadow, so at native
  /// scale it is never smaller than the window itself. Falling short on both
  /// axes means ScreenCaptureKit scaled the window down to fit its canvas,
  /// which `isUndersized` lets through down to 75%. A shrink smaller than the
  /// shadow's share of the image stays hidden, so fresh frames still matter.
  static func isScaledBelowNative(
    pixelSize: CGSize,
    logicalSize: CGSize,
    scaleFactor: CGFloat
  ) -> Bool {
    guard
      scaleFactor.isFinite,
      scaleFactor > 0,
      logicalSize.width > 0,
      logicalSize.height > 0
    else {
      return false
    }

    let nativeSize = expectedPixelSize(logicalSize: logicalSize, scaleFactor: scaleFactor)
    return pixelSize.width < nativeSize.width - nativeSizeTolerance
      && pixelSize.height < nativeSize.height - nativeSizeTolerance
  }
}
