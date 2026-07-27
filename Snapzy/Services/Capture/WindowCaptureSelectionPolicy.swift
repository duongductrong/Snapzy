//
//  WindowCaptureSelectionPolicy.swift
//  Snapzy
//
//  Pure classification rules for application-capture candidates and image paths.
//

import CoreGraphics
import Foundation

nonisolated enum WindowCaptureSelectionPolicy {
  static let minimumCandidateDimension: CGFloat = 32
  static let menuBarAnchorTolerance: CGFloat = 8
  static let menuBarPopoverCornerRadius: CGFloat = 12

  static func targetKind(
    windowLayer: Int,
    frame: CGRect,
    visibleFrame: CGRect?,
    alpha: Double,
    isOwnApplication: Bool,
    isSystemOwned: Bool
  ) -> WindowCaptureTargetKind? {
    // Keep the established layer-0 behaviour unchanged. The query service
    // applies the existing size, display, and alpha guards before this call.
    if windowLayer == 0 {
      return .normal
    }

    guard
      frame.width > minimumCandidateDimension,
      frame.height > minimumCandidateDimension,
      alpha > 0,
      !isOwnApplication,
      !isSystemOwned,
      let visibleFrame,
      abs(frame.maxY - visibleFrame.maxY) <= menuBarAnchorTolerance
    else {
      return nil
    }

    return .menuBarPopover
  }

  static func isSystemOwned(bundleIdentifier: String?, ownerName: String) -> Bool {
    let bundleIdentifier = bundleIdentifier?.lowercased() ?? ""
    let ownerName = ownerName.lowercased()
    let excludedBundleIdentifiers = [
      "com.apple.dock",
      "com.apple.controlcenter",
      "com.apple.notificationcenterui",
    ]
    let excludedOwnerNames = ["dock", "control center", "notification center"]

    return excludedBundleIdentifiers.contains(bundleIdentifier)
      || excludedOwnerNames.contains(where: { ownerName.contains($0) })
  }

  /// A retained crop is only a visual substitute after the source WindowServer window
  /// disappeared. Keeping it hidden while the original is still present avoids a double image.
  static func shouldShowRetainedMenuBarPopover(isWindowStillOnScreen: Bool) -> Bool {
    !isWindowStillOnScreen
  }

  /// Display snapshots are flattened against the desktop. Restore transparent rounded corners
  /// for the transient menu panels that use this retained-image fallback.
  static func alphaMaskedMenuBarPopoverImage(
    _ image: CGImage,
    cornerRadiusInPoints: CGFloat = menuBarPopoverCornerRadius,
    scaleFactor: CGFloat
  ) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    let radius = min(max(cornerRadiusInPoints * max(scaleFactor, 1), 0), min(rect.width, rect.height) / 2)
    context.clear(rect)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(image, in: rect)
    return context.makeImage()
  }

  /// Converts an AppKit global frame into a Core Graphics image crop rectangle.
  /// AppKit's coordinate system is bottom-left based while `CGImage` is top-left based.
  static func displaySnapshotCropRect(
    frame: CGRect,
    displayFrame: CGRect,
    imagePixelWidth: Int,
    imagePixelHeight: Int
  ) -> CGRect? {
    guard
      displayFrame.width > 0,
      displayFrame.height > 0,
      imagePixelWidth > 0,
      imagePixelHeight > 0
    else {
      return nil
    }

    let displayBounds = CGRect(origin: .zero, size: displayFrame.size)
    let relativeFrame = CGRect(
      x: frame.minX - displayFrame.minX,
      y: frame.minY - displayFrame.minY,
      width: frame.width,
      height: frame.height
    ).intersection(displayBounds)
    guard !relativeFrame.isEmpty else { return nil }

    let scaleX = CGFloat(imagePixelWidth) / displayFrame.width
    let scaleY = CGFloat(imagePixelHeight) / displayFrame.height
    let pixelRect = CGRect(
      x: floor(relativeFrame.minX * scaleX),
      y: floor((displayFrame.height - relativeFrame.maxY) * scaleY),
      width: ceil(relativeFrame.width * scaleX),
      height: ceil(relativeFrame.height * scaleY)
    ).intersection(CGRect(x: 0, y: 0, width: imagePixelWidth, height: imagePixelHeight)).integral

    return pixelRect.isEmpty ? nil : pixelRect
  }
}

nonisolated enum WindowCaptureImagePath: Equatable, Sendable {
  case screenCaptureKit
  case retainedMenuBarPopover
  case coreGraphicsWindow
  case areaFallback

  static func resolve(
    targetKind: WindowCaptureTargetKind,
    hasShareableWindow: Bool,
    hasRetainedMenuBarPopover: Bool = false
  ) -> WindowCaptureImagePath {
    if hasShareableWindow {
      return .screenCaptureKit
    }
    if targetKind == .menuBarPopover, hasRetainedMenuBarPopover {
      return .retainedMenuBarPopover
    }
    if targetKind == .menuBarPopover {
      return .coreGraphicsWindow
    }
    return .areaFallback
  }
}
