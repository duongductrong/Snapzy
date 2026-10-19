//
//  AnnotateCutOutTransform.swift
//  Snapzy
//
//  Pure helpers for the Cut Out tool: remove a full-crossing strip from an
//  image and join the halves, or insert empty space and push content apart.
//  Mirrors the pure helpers in AnnotateImageRotation.swift.
//
//  Geometry helpers operate in image points (bottom-left origin, y-up) — the
//  coordinate space of `AnnotateState.cropRect` and annotations. Image ops
//  work in the backing pixel space and preserve the logical point size
//  contract used by `NSImage.rotated90`.
//

import AppKit
import CoreGraphics

nonisolated enum CutOutOrientation: Equatable {
  case horizontal
  case vertical
}

nonisolated enum CutOutMode: Equatable {
  /// Join the content above/below (or left/right of) the strip.
  case remove
  /// Push content apart and add an empty strip.
  case insert
}

enum AnnotateCutOutTransform {
  /// Remove (or insert) a full-crossing strip. Returns nil when the strip is
  /// empty or spans the whole remaining image (nothing would remain to show).
  static func apply(
    to image: NSImage,
    strip: CGRect,
    orientation: CutOutOrientation,
    mode: CutOutMode
  ) -> NSImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    let pw = CGFloat(cgImage.width)
    let ph = CGFloat(cgImage.height)
    let size = image.size
    guard pw > 0, ph > 0, size.width > 0, size.height > 0 else { return nil }

    let scaleX = pw / size.width
    let scaleY = ph / size.height

    let bounds = CGRect(origin: .zero, size: size)
    let clamped = strip.standardized.intersection(bounds)
    guard clamped.width.isFinite, clamped.height.isFinite else { return nil }

    // Strip in pixel space (both CG context and image-point space use a
    // bottom-left origin, so y maps linearly). Full-crossing: the extent along
    // the crossing axis is forced to the full image extent.
    let stripPixel: CGRect
    switch orientation {
    case .horizontal:
      stripPixel = CGRect(x: 0, y: clamped.minY * scaleY, width: pw, height: clamped.height * scaleY)
    case .vertical:
      stripPixel = CGRect(x: clamped.minX * scaleX, y: 0, width: clamped.width * scaleX, height: ph)
    }

    // Integral pixel geometry so the joined halves cannot leave a seam.
    let hp = CGPoint(x: stripPixel.minX.rounded(), y: stripPixel.minY.rounded())
    let hs = CGSize(
      width: orientation == .vertical ? stripPixel.width.rounded() : pw,
      height: orientation == .horizontal ? stripPixel.height.rounded() : ph
    )
    guard hs.width > 0, hs.height > 0 else { return nil }

    // Source slices (pixel space, bottom-left origin) and where the second
    // slice lands in the target canvas.
    let firstSlice: CGRect
    let secondSlice: CGRect
    let secondDestination: CGPoint
    let targetPixelSize: CGSize

    switch (orientation, mode) {
    case (.horizontal, .remove):
      targetPixelSize = CGSize(width: pw, height: ph - hs.height)
      firstSlice = CGRect(x: 0, y: 0, width: pw, height: hp.y) // below the strip
      secondSlice = CGRect(x: 0, y: hp.y + hs.height, width: pw, height: ph - hp.y - hs.height) // above
      secondDestination = CGPoint(x: 0, y: hp.y)
    case (.horizontal, .insert):
      targetPixelSize = CGSize(width: pw, height: ph + hs.height)
      firstSlice = CGRect(x: 0, y: 0, width: pw, height: hp.y)
      secondSlice = CGRect(x: 0, y: hp.y, width: pw, height: ph - hp.y)
      secondDestination = CGPoint(x: 0, y: hp.y + hs.height) // gap left empty
    case (.vertical, .remove):
      targetPixelSize = CGSize(width: pw - hs.width, height: ph)
      firstSlice = CGRect(x: 0, y: 0, width: hp.x, height: ph) // left of strip
      secondSlice = CGRect(x: hp.x + hs.width, y: 0, width: pw - hp.x - hs.width, height: ph) // right
      secondDestination = CGPoint(x: hp.x, y: 0)
    case (.vertical, .insert):
      targetPixelSize = CGSize(width: pw + hs.width, height: ph)
      firstSlice = CGRect(x: 0, y: 0, width: hp.x, height: ph)
      secondSlice = CGRect(x: hp.x, y: 0, width: pw - hp.x, height: ph)
      secondDestination = CGPoint(x: hp.x + hs.width, y: 0) // gap left empty
    }

    guard targetPixelSize.width >= 1, targetPixelSize.height >= 1 else { return nil }

    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: Int(targetPixelSize.width),
      height: Int(targetPixelSize.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .none

    // Draw a 1:1 pixel slice: clip to the destination rect, then draw the
    // full image translated so the source slice lands exactly in it.
    func drawSlice(source: CGRect, destination: CGPoint) {
      guard source.width.rounded() > 0, source.height.rounded() > 0 else { return }
      let dest = CGRect(
        x: destination.x.rounded(),
        y: destination.y.rounded(),
        width: source.width.rounded(),
        height: source.height.rounded()
      )
      context.saveGState()
      context.clip(to: dest)
      context.draw(
        cgImage,
        in: CGRect(x: dest.minX - source.minX, y: dest.minY - source.minY, width: pw, height: ph)
      )
      context.restoreGState()
    }

    drawSlice(source: firstSlice, destination: firstSlice.origin)
    drawSlice(source: secondSlice, destination: secondDestination)
    // Insert mode leaves the gap between the two slices empty (transparent).

    guard let outImage = context.makeImage() else { return nil }

    // Preserve the logical point size contract (insert grows, remove shrinks).
    // Derived from the integral pixel result so the pixel/point scale never
    // drifts across repeated cuts (a fractional strip would otherwise leave
    // e.g. 1111px at 555.55pt and skew every later save/restore).
    let pointSize = CGSize(
      width: targetPixelSize.width / scaleX,
      height: targetPixelSize.height / scaleY
    )
    return NSImage(cgImage: outImage, size: pointSize)
  }

  /// Snap a strip's edges onto the image's backing pixel grid (in points), so
  /// the amount removed from the image matches the amount annotations shift.
  static func pixelAlignedStrip(_ strip: CGRect, in image: NSImage, orientation: CutOutOrientation) -> CGRect {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          image.size.width > 0, image.size.height > 0 else { return strip }
    let scaleX = CGFloat(cgImage.width) / image.size.width
    let scaleY = CGFloat(cgImage.height) / image.size.height
    let rect = strip.standardized
    switch orientation {
    case .horizontal:
      let minY = (rect.minY * scaleY).rounded() / scaleY
      let height = (rect.height * scaleY).rounded() / scaleY
      return CGRect(x: rect.minX, y: minY, width: rect.width, height: height)
    case .vertical:
      let minX = (rect.minX * scaleX).rounded() / scaleX
      let width = (rect.width * scaleX).rounded() / scaleX
      return CGRect(x: minX, y: rect.minY, width: width, height: rect.height)
    }
  }

  // MARK: - Geometry (image points)

  /// Builds the full-crossing strip for a free drag rect: along `orientation`
  /// the drag's extent is replaced by the image's full extent; the other
  /// dimension keeps the drag's span. Clamped to the image bounds.
  static func fullCrossingStrip(
    from dragRect: CGRect,
    orientation: CutOutOrientation,
    imageBounds: CGRect
  ) -> CGRect {
    let d = dragRect.standardized
    let bounds = imageBounds.standardized
    switch orientation {
    case .horizontal:
      return bounds.intersection(CGRect(x: bounds.minX, y: d.minY, width: bounds.width, height: d.height))
    case .vertical:
      return bounds.intersection(CGRect(x: d.minX, y: bounds.minY, width: d.width, height: bounds.height))
    }
  }

  /// Translation applied to image-point content on the far side of the strip.
  ///
  /// - remove (horizontal): content at/above `strip.maxY` moves down by the
  ///   strip height; content below `strip.minY` stays.
  /// - remove (vertical): content at/right of `strip.maxX` moves left.
  /// - insert (horizontal): content at/above `strip.minY` moves up; content
  ///   strictly below stays. Insert mirrors remove.
  static func shiftOffset(
    strip: CGRect,
    orientation: CutOutOrientation,
    mode: CutOutMode
  ) -> CGSize {
    let magnitude = orientation == .horizontal ? strip.standardized.height : strip.standardized.width
    return switch (orientation, mode) {
    case (.horizontal, .remove): CGSize(width: 0, height: -magnitude)
    case (.horizontal, .insert): CGSize(width: 0, height: +magnitude)
    case (.vertical, .remove): CGSize(width: -magnitude, height: 0)
    case (.vertical, .insert): CGSize(width: +magnitude, height: 0)
    }
  }

  /// Point-based membership: content at/after the relevant strip boundary
  /// (y = maxY for horizontal remove, maxX for vertical remove, minY/minX for
  /// insert) belongs to the moving half. Freehand paths and arrows shift per
  /// point so geometry reconstructs faithfully across the removed band.
  static func isFarSidePoint(
    _ point: CGPoint,
    strip: CGRect,
    orientation: CutOutOrientation,
    mode: CutOutMode
  ) -> Bool {
    let s = strip.standardized
    switch (orientation, mode) {
    case (.horizontal, .remove): return point.y >= s.maxY
    case (.horizontal, .insert): return point.y >= s.minY
    case (.vertical, .remove): return point.x >= s.maxX
    case (.vertical, .insert): return point.x >= s.minX
    }
  }

  /// Bounds-based shapes crossing the strip follow the half that owns most of
  /// their area — predictable, no data loss. Pure translation (size kept).
  static func shiftRect(
    _ rect: CGRect,
    strip: CGRect,
    orientation: CutOutOrientation,
    mode: CutOutMode
  ) -> CGRect {
    let r = rect.standardized
    let s = strip.standardized

    let isFarSide: Bool
    switch (orientation, mode) {
    case (.horizontal, .remove):
      let above = max(0, r.maxY - s.maxY)
      let below = max(0, s.minY - r.minY)
      isFarSide = above > below
    case (.horizontal, .insert):
      let above = max(0, r.maxY - s.minY)
      let below = max(0, s.minY - r.minY)
      isFarSide = above > below
    case (.vertical, .remove):
      let right = max(0, r.maxX - s.maxX)
      let left = max(0, s.minX - r.minX)
      isFarSide = right > left
    case (.vertical, .insert):
      let right = max(0, r.maxX - s.minX)
      let left = max(0, s.minX - r.minX)
      isFarSide = right > left
    }

    guard isFarSide else { return rect }
    let offset = shiftOffset(strip: strip, orientation: orientation, mode: mode)
    return CGRect(
      x: r.origin.x + offset.width,
      y: r.origin.y + offset.height,
      width: r.width,
      height: r.height
    )
  }
}
