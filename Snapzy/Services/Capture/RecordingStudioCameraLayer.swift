//
//  RecordingStudioCameraLayer.swift
//  Snapzy
//
//  Canvas-space Studio layer that draws a Studio recording's camera sidecar where the
//  overlay sat while recording (shape, mirroring, aspect fill), as the flatten pass
//  needs it. Output time equals recording time; gaps (no camera) draw nothing.
//

import CoreImage
import Foundation

nonisolated struct RecordingStudioCameraLayer: VideoEditorStudioLayer {
  let source: RecordingCameraSource
  /// Capture rect size in points; canvas pixels per point = canvas width / this width.
  let captureSize: CGSize

  var space: VideoEditorStudioLayerSpace { .canvas }
  var auxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> { [.camera] }
  var isActive: Bool {
    source.normalizedFrame.width > 0 && source.normalizedFrame.height > 0 && captureSize.width > 0
  }

  func isInGap(_ time: TimeInterval) -> Bool {
    source.gaps.contains { time >= $0.start && time < $0.end }
  }

  /// Target rect in Core Image (bottom-left) coordinates of `extent`.
  func targetRect(in extent: CGRect) -> CGRect {
    let frame = source.normalizedFrame
    return CGRect(
      x: extent.minX + frame.minX * extent.width,
      y: extent.minY + (1 - frame.maxY) * extent.height,
      width: frame.width * extent.width,
      height: frame.height * extent.height
    ).integral
  }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard !isInGap(context.outputTime), let buffer = context.auxiliaryFrames[.camera] else { return image }
    let target = targetRect(in: context.extent)
    var camera = CIImage(cvPixelBuffer: buffer)
    let cameraExtent = camera.extent
    guard target.width > 1, target.height > 1, cameraExtent.width > 0, cameraExtent.height > 0 else { return image }

    if source.isMirrored {
      camera = camera.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -cameraExtent.width, y: 0))
    }
    // Aspect fill, centered on the target.
    let scale = max(target.width / cameraExtent.width, target.height / cameraExtent.height)
    let scaledWidth = cameraExtent.width * scale
    let scaledHeight = cameraExtent.height * scale
    camera = camera
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .transformed(by: CGAffineTransform(
        translationX: target.midX - scaledWidth / 2,
        y: target.midY - scaledHeight / 2
      ))
      .cropped(to: target)

    let shape = RecordingCameraShape(rawValue: source.shape) ?? .rectangle
    let pixelsPerPoint = context.extent.width / captureSize.width
    let pointSize = source.pointSize.width > 0 ? source.pointSize : CGSize(
      width: target.width / pixelsPerPoint, height: target.height / pixelsPerPoint
    )
    let radius = min(shape.cornerRadius(for: pointSize) * pixelsPerPoint, min(target.width, target.height) / 2)
    guard let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
      "inputExtent": CIVector(cgRect: target),
      "inputRadius": radius,
      "inputColor": CIColor.white,
    ])?.outputImage else {
      return camera.composited(over: image)
    }
    return camera
      .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
      .composited(over: image)
  }
}
