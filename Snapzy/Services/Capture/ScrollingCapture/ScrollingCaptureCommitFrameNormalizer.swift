//
//  ScrollingCaptureCommitFrameNormalizer.swift
//  Snapzy
//
//  Keeps every frame submitted to the scrolling stitcher at one pixel scale.
//

import CoreGraphics

enum ScrollingCaptureCommitFrameNormalizer {

  static func normalize(
    _ image: CGImage,
    logicalSize: CGSize,
    sourceScaleFactor: CGFloat,
    minimumOutputScaleFactor: CGFloat,
    colorSpaceName: CFString?
  ) -> CGImage? {
    let outputScaleFactor = max(sourceScaleFactor, minimumOutputScaleFactor)
    guard outputScaleFactor.isFinite,
          outputScaleFactor > 0,
          logicalSize.width.isFinite,
          logicalSize.width > 0,
          logicalSize.height.isFinite,
          logicalSize.height > 0
    else {
      return nil
    }

    let targetWidth = max(1, Int((logicalSize.width * outputScaleFactor).rounded()))
    let targetHeight = max(1, Int((logicalSize.height * outputScaleFactor).rounded()))
    if image.width == targetWidth, image.height == targetHeight {
      return image
    }

    let normalized = FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      image,
      logicalSize: logicalSize,
      sourceScaleFactor: sourceScaleFactor,
      minimumOutputScaleFactor: minimumOutputScaleFactor,
      colorSpaceName: colorSpaceName
    ).image
    guard normalized.width == targetWidth, normalized.height == targetHeight else {
      return nil
    }

    return normalized
  }
}
