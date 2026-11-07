//
//  AnnotateMeasureMapper.swift
//  Snapzy
//
//  Bridges Annotate's image space (points, bottom-left origin) and the measurement engine's
//  raster (pixels, top-left origin): scans spans and snaps boxes on the source pixels and
//  turns the result into Measure annotation geometry.
//

import CoreGraphics
import Foundation
import SnapzyMeasureCore

nonisolated struct AnnotateMeasureMapper {
  let raster: MeasureRaster
  /// The source image's size in points; the raster covers it exactly.
  let imageSize: CGSize

  init?(raster: MeasureRaster, imageSize: CGSize) {
    guard imageSize.width > 0, imageSize.height > 0 else { return nil }
    self.raster = raster
    self.imageSize = imageSize
  }

  var scaleX: CGFloat { CGFloat(raster.width) / imageSize.width }
  var scaleY: CGFloat { CGFloat(raster.height) / imageSize.height }
  var pixelScale: CGSize { CGSize(width: scaleX, height: scaleY) }

  /// The source pixel under `point`, or nil outside the image.
  func pixel(at point: CGPoint) -> MeasurePixel? {
    let x = Int(floor(point.x * scaleX))
    let y = Int(floor((imageSize.height - point.y) * scaleY))
    let pixel = MeasurePixel(x: x, y: y)
    return raster.contains(pixel) ? pixel : nil
  }

  /// The pixel under `point`, clamped into the image.
  func clampedPixel(at point: CGPoint) -> MeasurePixel {
    MeasurePixel(
      x: min(max(Int(floor(point.x * scaleX)), 0), raster.width - 1),
      y: min(max(Int(floor((imageSize.height - point.y) * scaleY)), 0), raster.height - 1)
    )
  }

  /// Image-space rectangle covering whole pixels `rect`.
  func bounds(of rect: MeasurePixelRect) -> CGRect {
    let minX = CGFloat(rect.minX) / scaleX
    let maxX = CGFloat(rect.maxX + 1) / scaleX
    let top = imageSize.height - CGFloat(rect.minY) / scaleY
    let bottom = imageSize.height - CGFloat(rect.maxY + 1) / scaleY
    return CGRect(x: minX, y: bottom, width: maxX - minX, height: top - bottom)
  }

  /// The span around the pixel under `point`, as Measure geometry plus its bounds.
  func span(at point: CGPoint, axis: MeasureAxis, tolerance: Int, unit: MeasureUnit) -> (geometry: MeasureGeometry, bounds: CGRect)? {
    guard let origin = pixel(at: point) else { return nil }
    let span = MeasureEdgeScanner.span(in: raster, from: origin, axis: axis, tolerance: tolerance)
    let extent = bounds(of: MeasurePixelRect(minX: span.left, minY: span.top, maxX: span.right, maxY: span.bottom))
    let center = CGPoint(
      x: (CGFloat(span.origin.x) + 0.5) / scaleX,
      y: imageSize.height - (CGFloat(span.origin.y) + 0.5) / scaleY
    )
    let spanBounds = MeasureGeometry.spanBounds(
      axis: axis,
      origin: center,
      horizontal: extent.minX...extent.maxX,
      vertical: extent.minY...extent.maxY
    )
    return (.span(axis: axis, origin: center, pixelScale: pixelScale, unit: unit), spanBounds)
  }

  /// The box dragged from `start` to `end`, shrunk to the content inside unless `snaps` is off.
  func box(from start: CGPoint, to end: CGPoint, snaps: Bool, tolerance: Int, unit: MeasureUnit) -> (geometry: MeasureGeometry, bounds: CGRect) {
    var rect = MeasurePixelRect(corner: clampedPixel(at: start), clampedPixel(at: end))
    if snaps {
      rect = MeasureEdgeScanner.snap(rect, in: raster, tolerance: tolerance)
    }
    return (.box(pixelScale: pixelScale, unit: unit), bounds(of: rect))
  }
}
