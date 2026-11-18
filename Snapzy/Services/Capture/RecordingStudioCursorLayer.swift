//
//  RecordingStudioCursorLayer.swift
//  Snapzy
//
//  Source-space Studio layer that redraws a Studio recording's captured cursor (and,
//  optionally, click rings) as it looked while recording. Used by the flatten pass,
//  where output time equals recording time.
//

import AppKit
import CoreImage
import Foundation

nonisolated struct RecordingStudioCursorLayer: VideoEditorStudioLayer, @unchecked Sendable {
  struct ClickStyle: Sendable {
    /// Ripple diameter and hold-circle diameter, in points.
    var rippleDiameter: CGFloat
    var holdDiameter: CGFloat
    var ringWidth: CGFloat
    var duration: TimeInterval
    var color: CIColor
  }

  let samples: [RecordedMouseSample]
  let capture: RecordingCursorCapture
  /// Capture rect size in points; source pixels per point = frame width / this width.
  let captureSize: CGSize
  /// Decoded cursor images by `RecordedCursorImage.id`.
  let images: [Int: CIImage]
  /// Drawn when the captured image is missing (unreadable PNG, unknown id).
  let fallbackImage: RecordingStudioCursorFallback?
  let clickStyle: ClickStyle?

  var space: VideoEditorStudioLayerSpace { .source }
  var isActive: Bool { !samples.isEmpty && captureSize.width > 0 && captureSize.height > 0 }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    let time = context.outputTime
    let extent = context.extent
    let pixelsPerPoint = extent.width / captureSize.width
    var result = image

    if let clickStyle {
      result = drawClicks(onto: result, at: time, extent: extent, pixelsPerPoint: pixelsPerPoint, style: clickStyle)
    }

    guard let sample = RecordedMouseSampleInterpolator.sample(at: time, in: samples),
          sample.isInsideCapture
    else { return result }

    let change = capture.appearance(at: time)
    if change?.isHidden == true { return result }

    let sprite: CIImage
    let hotspot: CGPoint
    let pointSize: CGSize
    if let recorded = capture.image(id: change?.imageID), let decoded = images[recorded.id] {
      sprite = decoded
      hotspot = recorded.hotspot
      pointSize = recorded.pointSize
    } else if let fallbackImage {
      sprite = fallbackImage.image
      hotspot = fallbackImage.hotspot
      pointSize = fallbackImage.pointSize
    } else {
      return result
    }

    let targetWidth = pointSize.width * pixelsPerPoint
    let targetHeight = pointSize.height * pixelsPerPoint
    guard sprite.extent.width > 0, sprite.extent.height > 0, targetWidth > 0 else { return result }
    let scaled = sprite
      .transformed(by: CGAffineTransform(translationX: -sprite.extent.minX, y: -sprite.extent.minY))
      .transformed(by: CGAffineTransform(
        scaleX: targetWidth / sprite.extent.width,
        y: targetHeight / sprite.extent.height
      ))
    // Core Image is bottom-left; samples and hotspot are top-left.
    let pointX = extent.minX + sample.normalizedX * extent.width
    let pointY = extent.minY + (1 - sample.normalizedY) * extent.height
    let originX = pointX - hotspot.x * pixelsPerPoint
    let originY = pointY + hotspot.y * pixelsPerPoint - targetHeight
    return scaled
      .transformed(by: CGAffineTransform(translationX: originX, y: originY))
      .composited(over: result)
  }

  private func drawClicks(
    onto image: CIImage,
    at time: TimeInterval,
    extent: CGRect,
    pixelsPerPoint: CGFloat,
    style: ClickStyle
  ) -> CIImage {
    var result = image
    var openDowns: [RecordedClickButton: RecordedClick] = [:]
    for click in capture.clicks {
      if click.time > time { break }
      switch click.phase {
      case .down: openDowns[click.button] = click
      case .up: openDowns[click.button] = nil
      }
      guard click.phase == .down else { continue }
      let age = time - click.time
      guard age < style.duration else { continue }
      let progress = CGFloat(age / style.duration)
      let radius = (0.2 + 0.8 * progress) * style.rippleDiameter / 2 * pixelsPerPoint
      result = ring(at: click.normalizedPoint, radius: radius, alpha: 1 - progress, style: style,
                    extent: extent, pixelsPerPoint: pixelsPerPoint).composited(over: result)
    }
    for down in openDowns.values {
      result = ring(at: down.normalizedPoint, radius: style.holdDiameter / 2 * pixelsPerPoint, alpha: 1,
                    style: style, extent: extent, pixelsPerPoint: pixelsPerPoint).composited(over: result)
    }
    return result
  }

  private func ring(
    at normalized: CGPoint,
    radius: CGFloat,
    alpha: CGFloat,
    style: ClickStyle,
    extent: CGRect,
    pixelsPerPoint: CGFloat
  ) -> CIImage {
    let center = CIVector(
      x: extent.minX + normalized.x * extent.width,
      y: extent.minY + (1 - normalized.y) * extent.height
    )
    let width = max(style.ringWidth * pixelsPerPoint, 1)
    let color = CIColor(red: style.color.red, green: style.color.green, blue: style.color.blue,
                        alpha: style.color.alpha * alpha)
    let outer = CIFilter(name: "CIRadialGradient", parameters: [
      "inputCenter": center, "inputRadius0": max(radius - 1, 0), "inputRadius1": radius,
      "inputColor0": color, "inputColor1": CIColor.clear,
    ])?.outputImage
    let inner = CIFilter(name: "CIRadialGradient", parameters: [
      "inputCenter": center, "inputRadius0": max(radius - width - 1, 0), "inputRadius1": max(radius - width, 0),
      "inputColor0": CIColor.white, "inputColor1": CIColor.clear,
    ])?.outputImage
    guard let outer, let inner else { return CIImage.empty() }
    let bounds = CGRect(x: center.x - radius - 1, y: center.y - radius - 1, width: radius * 2 + 2, height: radius * 2 + 2)
    return outer
      .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
      .cropped(to: bounds)
  }
}

nonisolated struct RecordingStudioCursorFallback: @unchecked Sendable {
  let image: CIImage
  let hotspot: CGPoint
  let pointSize: CGSize
}
