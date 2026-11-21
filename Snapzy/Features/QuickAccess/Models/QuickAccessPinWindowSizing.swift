//
//  QuickAccessPinWindowSizing.swift
//  Snapzy
//
//  Sizing policy for pinned screenshot windows.
//

import AppKit
import Foundation
import QuartzCore

enum QuickAccessPinWindowSizing {
  static let minimumInteractiveSize = CGSize(width: 240, height: 180)

  /// Band the entrance is allowed to travel across, as a fraction of the resting size. A hairline
  /// selection would otherwise start from a sub-pixel speck, and a capture larger than the resting
  /// window would shrink into it from a size that reads as a different image.
  static let minimumEntranceScale: CGFloat = 0.08
  static let maximumEntranceScale: CGFloat = 1.25

  /// Room a flight window keeps around the travelling content so its shadow is not cut off.
  static let entranceShadowMargin: CGFloat = 40

  private static let absoluteMaxSize = CGSize(width: 1440, height: 920)
  private static let screenMaxRatio: CGFloat = 0.8
  private static let screenMargin: CGFloat = 24

  static func size(for imageSize: CGSize, visibleSize: CGSize, mode: QuickAccessPinZoomMode) -> CGSize {
    guard mode == .fixedViewport else { return size(for: imageSize, visibleSize: visibleSize) }
    let maxWidth = min(absoluteMaxSize.width, visibleSize.width * screenMaxRatio)
    let maxHeight = min(absoluteMaxSize.height, visibleSize.height * screenMaxRatio)
    let source = CGSize(width: max(imageSize.width, 1), height: max(imageSize.height, 1))
    let scale = min(1, maxWidth / source.width)
    let width = max(minimumInteractiveSize.width, source.width * scale)
    let imageHeight = source.height * scale
    let height = min(maxHeight, max(minimumInteractiveSize.height, imageHeight))
    return CGSize(width: min(width, maxWidth), height: height)
  }

  static func size(for imageSize: CGSize, visibleSize: CGSize) -> CGSize {
    let sourceSize = CGSize(width: max(imageSize.width, 1), height: max(imageSize.height, 1))
    let maxSize = CGSize(
      width: min(absoluteMaxSize.width, visibleSize.width * screenMaxRatio),
      height: min(absoluteMaxSize.height, visibleSize.height * screenMaxRatio)
    )
    let maxFitScale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height)
    let minFitScale = max(
      minimumInteractiveSize.width / sourceSize.width,
      minimumInteractiveSize.height / sourceSize.height
    )
    let preferredScale = max(1, minFitScale)
    let normalizedScale = min(preferredScale, maxFitScale)
    let fittedSize = CGSize(width: sourceSize.width * normalizedScale, height: sourceSize.height * normalizedScale)
    let baseSize = CGSize(
      width: min(max(fittedSize.width, minimumInteractiveSize.width), maxSize.width),
      height: min(max(fittedSize.height, minimumInteractiveSize.height), maxSize.height)
    )
    return baseSize
  }

  static func centeredFrame(size: CGSize, on screen: NSScreen) -> NSRect {
    let visibleFrame = screen.visibleFrame
    return NSRect(
      x: visibleFrame.midX - size.width / 2,
      y: visibleFrame.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func frame(size: CGSize, centeredAt center: CGPoint) -> NSRect {
    NSRect(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func resizedFrame(
    _ frame: NSRect,
    to size: CGSize,
    within visibleFrame: NSRect
  ) -> NSRect {
    let fittedSize = CGSize(
      width: min(size.width, visibleFrame.width),
      height: min(size.height, visibleFrame.height)
    )
    let centeredFrame = self.frame(
      size: fittedSize,
      centeredAt: CGPoint(x: frame.midX, y: frame.midY)
    )
    return NSRect(
      x: min(max(centeredFrame.minX, visibleFrame.minX), visibleFrame.maxX - fittedSize.width),
      y: min(max(centeredFrame.minY, visibleFrame.minY), visibleFrame.maxY - fittedSize.height),
      width: fittedSize.width,
      height: fittedSize.height
    )
  }

  static func resizedFrame(
    _ frame: NSRect,
    to size: CGSize,
    preservingAnchorFraction fraction: CGPoint
  ) -> NSRect {
    let anchor = CGPoint(
      x: frame.minX + frame.width * fraction.x,
      y: frame.minY + frame.height * fraction.y
    )
    return NSRect(
      x: anchor.x - size.width * fraction.x,
      y: anchor.y - size.height * fraction.y,
      width: size.width,
      height: size.height
    )
  }

  static func constrainedFrame(_ frame: NSRect, on screen: NSScreen) -> NSRect {
    constrainedFrame(frame, visibleFrame: screen.visibleFrame)
  }

  static func constrainedFrame(_ frame: NSRect, visibleFrame: NSRect) -> NSRect {
    let bounds = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
    let width = min(frame.width, max(bounds.width, 1))
    let height = min(frame.height, max(bounds.height, 1))
    return NSRect(
      x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
      y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
      width: width,
      height: height
    )
  }

  /// The window frame an entrance flies inside: the resting frame and the start frame together,
  /// widened by the shadow margin and trimmed to the display.
  ///
  /// The pin has to be laid out once at its resting size and then moved by the compositor, because
  /// animating the window frame itself resizes its surface and re-lays the content on every single
  /// frame — which is exactly what stutters on a large capture. A layer can only draw inside its
  /// window, so a flight that crosses the screen needs a window wide enough to hold the whole path.
  /// `nil` when the path cannot fit, so the caller can fall back to a plain fade.
  static func flightRect(
    resting: CGRect,
    start: CGRect,
    shadowMargin: CGFloat,
    screenFrame: CGRect
  ) -> CGRect? {
    let rect = resting.union(start).insetBy(dx: -shadowMargin, dy: -shadowMargin)
      .intersection(screenFrame)
    guard rect.contains(resting), rect.contains(start) else { return nil }
    return rect
  }

  /// The transform that draws a layer occupying `layerRect` exactly over `targetRect`.
  ///
  /// AppKit hosts a view's layer with the anchor point at its corner rather than its center, so the
  /// translation depends on the anchor: scaling about a corner shifts the origin, and the correction
  /// is `anchor * size * (scale - 1)`. Reading the anchor and the flipped geometry off the layer keeps
  /// this correct for a flipped or non-flipped host instead of assuming either.
  static func entranceTransform(
    targetRect: CGRect,
    layerRect: CGRect,
    anchorPoint: CGPoint,
    geometryFlipped: Bool
  ) -> CATransform3D {
    guard targetRect.width > 0, targetRect.height > 0, layerRect.width > 0, layerRect.height > 0 else {
      return CATransform3DIdentity
    }

    let scaleX = min(max(targetRect.width / layerRect.width, minimumEntranceScale), maximumEntranceScale)
    let scaleY = min(max(targetRect.height / layerRect.height, minimumEntranceScale), maximumEntranceScale)
    let offsetY = geometryFlipped ? layerRect.maxY - targetRect.maxY : targetRect.minY - layerRect.minY

    var transform = CATransform3DIdentity
    transform = CATransform3DTranslate(
      transform,
      targetRect.minX - layerRect.minX + anchorPoint.x * layerRect.width * (scaleX - 1),
      offsetY + anchorPoint.y * layerRect.height * (scaleY - 1),
      0
    )
    transform = CATransform3DScale(transform, scaleX, scaleY, 1)
    return transform
  }
}
