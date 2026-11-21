//
//  VideoEditorCursorLayer.swift
//  Snapzy
//
//  Source-space Studio layer drawing the resolved cursor and click effects with Core
//  Image. Used by editor export (output time mapped through the clip sequence) and by
//  the Studio recording flatten pass (identity mapping).
//

import CoreImage
import Foundation

/// Output (composition) time → recording source time of the primary asset.
nonisolated struct VideoEditorSourceTimeMapping: @unchecked Sendable {
  struct Span: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let sourceStart: TimeInterval
  }

  static let identity = VideoEditorSourceTimeMapping(sequenceMap: nil, spans: nil)

  private let sequenceMap: TimelineSequenceMap?
  /// Primary-clip spans of the playable sequence; `nil` = identity.
  private let spans: [Span]?

  private init(sequenceMap: TimelineSequenceMap?, spans: [Span]?) {
    self.sequenceMap = sequenceMap
    self.spans = spans
  }

  init(sequenceMap: TimelineSequenceMap, playbackPlacements: [TimelineSequence.Placement]) {
    self.sequenceMap = sequenceMap
    spans = playbackPlacements.filter { $0.clip.isPrimary }.map {
      Span(start: $0.start, end: $0.end, sourceStart: $0.sourceAxisStart)
    }
  }

  /// `nil` while an inserted clip (another file) plays: no cursor data there.
  func sourceTime(output: TimeInterval) -> TimeInterval? {
    guard let spans else { return output }
    let sequence = sequenceMap?.toSequence(output) ?? output
    guard let span = spans.first(where: { sequence >= $0.start - 0.0001 && sequence < $0.end + 0.0001 }) else {
      return nil
    }
    return span.sourceStart + min(max(sequence - span.start, 0), span.end - span.start)
  }
}

/// Cursor sprite drawn when no captured image applies (arrow).
nonisolated struct VideoEditorCursorSprite: @unchecked Sendable {
  let image: CIImage
  /// Points from the image's top-left.
  let hotspot: CGPoint
  let pointSize: CGSize
}

nonisolated struct VideoEditorCursorLayer: VideoEditorStudioLayer, @unchecked Sendable {
  /// Click effect geometry in points (matches the live click highlight defaults).
  static let rippleDiameter: CGFloat = 50
  static let holdDiameter: CGFloat = 36
  static let ringWidth: CGFloat = 2

  let resolver: VideoEditorCursorResolver
  let mapping: VideoEditorSourceTimeMapping
  /// Capture rect size in points; source pixels per point = frame width / this width.
  let captureSize: CGSize
  let sprites: [Int: VideoEditorCursorSprite]
  let arrow: VideoEditorCursorSprite?

  var space: VideoEditorStudioLayerSpace { .source }
  var isActive: Bool {
    resolver.settings.isVisible && !resolver.samples.isEmpty && captureSize.width > 0 && captureSize.height > 0
  }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard let sourceTime = mapping.sourceTime(output: context.outputTime),
          let frame = resolver.resolve(sourceTime: sourceTime)
    else { return image }
    let extent = context.extent
    let pixelsPerPoint = extent.width / captureSize.width
    let color = resolver.settings.clickColor
    var result = image

    for pulse in frame.pulses {
      let radius = (0.2 + 0.8 * pulse.progress) * Self.rippleDiameter / 2 * pixelsPerPoint
      result = ring(at: pulse.point, radius: radius, alpha: color.alpha * (1 - pulse.progress),
                    color: color, extent: extent, pixelsPerPoint: pixelsPerPoint).composited(over: result)
    }
    for point in frame.held {
      result = ring(at: point, radius: Self.holdDiameter / 2 * pixelsPerPoint, alpha: color.alpha,
                    color: color, extent: extent, pixelsPerPoint: pixelsPerPoint).composited(over: result)
    }

    guard frame.opacity > 0,
          let sprite = frame.imageID.flatMap({ sprites[$0] }) ?? arrow,
          sprite.image.extent.width > 0, sprite.image.extent.height > 0
    else { return result }

    let scale = resolver.settings.scale * pixelsPerPoint
    let width = sprite.pointSize.width * scale
    let height = sprite.pointSize.height * scale
    // Core Image is bottom-left; positions and hotspot are top-left.
    let pointX = extent.minX + frame.position.x * extent.width
    let pointY = extent.minY + (1 - frame.position.y) * extent.height
    var drawn = sprite.image
      .transformed(by: CGAffineTransform(translationX: -sprite.image.extent.minX, y: -sprite.image.extent.minY))
      .transformed(by: CGAffineTransform(scaleX: width / sprite.image.extent.width, y: height / sprite.image.extent.height))
      .transformed(by: CGAffineTransform(
        translationX: pointX - sprite.hotspot.x * scale,
        y: pointY + sprite.hotspot.y * scale - height
      ))
    if frame.opacity < 1 {
      drawn = drawn.applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: frame.opacity),
      ])
    }
    return drawn.composited(over: result)
  }

  private func ring(
    at normalized: CGPoint,
    radius: CGFloat,
    alpha: CGFloat,
    color: VideoEditorRGBAColor,
    extent: CGRect,
    pixelsPerPoint: CGFloat
  ) -> CIImage {
    let center = CIVector(
      x: extent.minX + normalized.x * extent.width,
      y: extent.minY + (1 - normalized.y) * extent.height
    )
    let width = max(Self.ringWidth * pixelsPerPoint, 1)
    let fill = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
    guard
      let outer = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center, "inputRadius0": max(radius - 1, 0), "inputRadius1": radius,
        "inputColor0": fill, "inputColor1": CIColor.clear,
      ])?.outputImage,
      let inner = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center, "inputRadius0": max(radius - width - 1, 0), "inputRadius1": max(radius - width, 0),
        "inputColor0": CIColor.white, "inputColor1": CIColor.clear,
      ])?.outputImage
    else { return CIImage.empty() }
    let bounds = CGRect(x: center.x - radius - 1, y: center.y - radius - 1, width: radius * 2 + 2, height: radius * 2 + 2)
    return outer
      .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
      .cropped(to: bounds)
  }
}
