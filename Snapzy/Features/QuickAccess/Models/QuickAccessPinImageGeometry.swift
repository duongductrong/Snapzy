//
//  QuickAccessPinImageGeometry.swift
//  Snapzy
//
//  Geometry for transforming a pinned image inside its fixed viewport.
//

import AppKit

enum QuickAccessPinImageGeometry {
  static func fittedContentSize(imageSize: CGSize, viewportSize: CGSize) -> CGSize {
    guard imageSize.width > 0, imageSize.height > 0,
          viewportSize.width > 0, viewportSize.height > 0 else {
      return .zero
    }

    let scale = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  }

  static func fixedViewportContentSize(imageSize: CGSize, viewportSize: CGSize, zoomFactor: CGFloat) -> CGSize {
    guard imageSize.width > 0, imageSize.height > 0, viewportSize.width > 0 else { return .zero }
    let scale = min(1, viewportSize.width / imageSize.width)
    return CGSize(width: imageSize.width * scale * zoomFactor, height: imageSize.height * scale * zoomFactor)
  }

  static func clampedPanOffset(
    _ offset: CGPoint,
    viewportSize: CGSize,
    contentSize: CGSize
  ) -> CGPoint {
    CGPoint(
      x: clampedAxis(offset.x, viewportExtent: viewportSize.width, contentExtent: contentSize.width),
      y: clampedAxis(offset.y, viewportExtent: viewportSize.height, contentExtent: contentSize.height)
    )
  }

  /// Converts the visible document rect reported by `NSScrollView` into the
  /// centered, positive-down pan offset exposed by pin-window state.
  static func panOffset(
    documentSize: CGSize,
    visibleRect: CGRect,
    magnification: CGFloat
  ) -> CGPoint {
    guard magnification > 0, magnification.isFinite else { return .zero }
    return CGPoint(
      x: (documentSize.width / 2 - visibleRect.midX) * magnification,
      y: (documentSize.height / 2 - visibleRect.midY) * magnification
    )
  }

  /// Finds the document-space origin that gives `NSScrollView` the requested
  /// centered, positive-down pan offset.
  static func visibleRectOrigin(
    panOffset: CGPoint,
    documentSize: CGSize,
    visibleSize: CGSize,
    magnification: CGFloat
  ) -> CGPoint {
    guard magnification > 0, magnification.isFinite else { return .zero }
    return CGPoint(
      x: documentSize.width / 2 - panOffset.x / magnification - visibleSize.width / 2,
      y: documentSize.height / 2 - panOffset.y / magnification - visibleSize.height / 2
    )
  }

  private static func clampedAxis(
    _ offset: CGFloat,
    viewportExtent: CGFloat,
    contentExtent: CGFloat
  ) -> CGFloat {
    guard viewportExtent > 0, contentExtent > viewportExtent else { return 0 }
    let limit = (contentExtent - viewportExtent) / 2
    return min(max(offset, -limit), limit)
  }
}
