//
//  CaptureSubjectGeometry.swift
//  Snapzy
//
//  Mapping between AppKit bottom-left screen points and top-left image pixels
//  for Capture Subject snapped previews.
//

import CoreGraphics
import Foundation

enum CaptureSubjectGeometry {
  /// Convert a top-left pixel rect inside `image` (captured from
  /// `capturedScreenRect`) into AppKit bottom-left global screen points.
  nonisolated static func screenRect(
    forPixelRect pixelRect: CGRect,
    image: CGImage,
    capturedScreenRect: CGRect
  ) -> CGRect {
    guard image.width > 0, image.height > 0,
          capturedScreenRect.width > 0, capturedScreenRect.height > 0 else {
      return .zero
    }
    let scaleX = CGFloat(image.width) / capturedScreenRect.width
    let scaleY = CGFloat(image.height) / capturedScreenRect.height
    return CGRect(
      x: capturedScreenRect.minX + pixelRect.minX / scaleX,
      y: capturedScreenRect.maxY - pixelRect.maxY / scaleY,
      width: pixelRect.width / scaleX,
      height: pixelRect.height / scaleY
    )
  }

  /// Convert an AppKit bottom-left screen rect into a top-left pixel rect
  /// inside `image` (captured from `capturedScreenRect`).
  nonisolated static func pixelRect(
    forScreenRect screenRect: CGRect,
    image: CGImage,
    capturedScreenRect: CGRect
  ) -> CGRect {
    guard image.width > 0, image.height > 0,
          capturedScreenRect.width > 0, capturedScreenRect.height > 0 else {
      return .zero
    }
    let scaleX = CGFloat(image.width) / capturedScreenRect.width
    let scaleY = CGFloat(image.height) / capturedScreenRect.height
    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let pixel = CGRect(
      x: (screenRect.minX - capturedScreenRect.minX) * scaleX,
      y: (capturedScreenRect.maxY - screenRect.maxY) * scaleY,
      width: screenRect.width * scaleX,
      height: screenRect.height * scaleY
    )
    return pixel.integral.intersection(imageBounds)
  }
}

struct CaptureSubjectSnappedPreview: Equatable {
  let rect: CGRect
  let image: CGImage?
  let pixelSize: CGSize
  let displayID: CGDirectDisplayID
  let selectionContext: CaptureContext?

  static func == (lhs: CaptureSubjectSnappedPreview, rhs: CaptureSubjectSnappedPreview) -> Bool {
    lhs.rect == rhs.rect
      && lhs.pixelSize == rhs.pixelSize
      && lhs.displayID == rhs.displayID
      && lhs.image === rhs.image
      && lhs.selectionContext == rhs.selectionContext
  }

  var dimensionText: String {
    let width = max(1, Int(pixelSize.width.rounded()))
    let height = max(1, Int(pixelSize.height.rounded()))
    return "\(width) × \(height)"
  }
}

enum CaptureSubjectSnapper: Sendable {
  nonisolated static let minimumSnapSide: CGFloat = 8
  nonisolated static let snapPadding: CGFloat = 8

  /// Tightens `selectionRect` to the distinct object inside it. Falls back to
  /// the original selection when no inset object is found.
  nonisolated static func snap(
    selectionRect: CGRect,
    in image: CGImage,
    capturedScreenRect: CGRect
  ) -> (screenRect: CGRect, image: CGImage?, pixelSize: CGSize) {
    let search = CaptureSubjectGeometry.pixelRect(
      forScreenRect: selectionRect,
      image: image,
      capturedScreenRect: capturedScreenRect
    )
    if let object = PixelObjectSnapper.objectBounds(in: image, searchRect: search) {
      let snappedScreen = CaptureSubjectGeometry.screenRect(
        forPixelRect: object,
        image: image,
        capturedScreenRect: capturedScreenRect
      ).integral
      if snappedScreen.width >= minimumSnapSide,
         snappedScreen.height >= minimumSnapSide {
        return (
          snappedScreen,
          image.cropping(to: object),
          CGSize(width: object.width, height: object.height)
        )
      }
    }

    let cropped = image.cropping(to: search)
    return (
      selectionRect.integral,
      cropped,
      search.isEmpty
        ? selectionRect.size
        : CGSize(width: search.width, height: search.height)
    )
  }
}
