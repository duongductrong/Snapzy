//
//  VideoEditorCameraLayer.swift
//  Snapzy
//
//  Canvas-space Studio layer drawing the camera sidecar with the editor's camera
//  settings (export), plus the Core Image drawing shared with the flatten pass.
//

import CoreImage
import Foundation

nonisolated enum VideoEditorCameraRenderer {
  /// Draws `buffer` aspect-filled into `target` (Core Image coordinates), optionally
  /// mirrored, masked to a rounded rect with `cornerRadius`, at `opacity` (fades).
  static func draw(
    _ buffer: CVPixelBuffer,
    in target: CGRect,
    cornerRadius: CGFloat,
    mirrored: Bool,
    opacity: CGFloat = 1,
    onto image: CIImage
  ) -> CIImage {
    var camera = CIImage(cvPixelBuffer: buffer)
    let extent = camera.extent
    guard target.width > 1, target.height > 1, extent.width > 0, extent.height > 0 else { return image }
    if mirrored {
      camera = camera.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -extent.width, y: 0))
    }
    let scale = max(target.width / extent.width, target.height / extent.height)
    camera = camera
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .transformed(by: CGAffineTransform(
        translationX: target.midX - extent.width * scale / 2,
        y: target.midY - extent.height * scale / 2
      ))
      .cropped(to: target)
    if cornerRadius > 0, let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
      "inputExtent": CIVector(cgRect: target),
      "inputRadius": cornerRadius,
      "inputColor": CIColor.white,
    ])?.outputImage {
      camera = camera.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
    }
    if opacity < 1 {
      camera = camera.applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(opacity, 0)),
      ])
    }
    return camera.composited(over: image)
  }
}

nonisolated struct VideoEditorCameraLayer: VideoEditorStudioLayer, @unchecked Sendable {
  let settings: VideoEditorCameraSettings
  let source: RecordingCameraSource
  let mapping: VideoEditorSourceTimeMapping

  var space: VideoEditorStudioLayerSpace { .canvas }
  var auxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> { [.camera] }
  var isActive: Bool { settings.isVisible }

  /// Camera rect in Core Image coordinates for a video placed at `videoRect`.
  func targetRect(videoRect: CGRect) -> CGRect {
    let topLeft = settings.rect(in: CGRect(origin: .zero, size: videoRect.size), aspect: source.overlayAspect, edgeInset: source.edgeInsetFraction)
    return CGRect(
      x: videoRect.minX + topLeft.minX,
      y: videoRect.maxY - topLeft.maxY,
      width: topLeft.width,
      height: topLeft.height
    ).integral
  }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard let buffer = context.auxiliaryFrames[.camera],
          let sourceTime = mapping.sourceTime(output: context.outputTime),
          !source.isInGap(sourceTime)
    else { return image }
    let opacity = settings.visibility(atSource: sourceTime)
    guard opacity > 0 else { return image }
    let target = targetRect(videoRect: context.videoRect)
    return VideoEditorCameraRenderer.draw(
      buffer,
      in: target,
      cornerRadius: settings.cornerRadius(for: target, referencePointWidth: source.pointSize.width),
      mirrored: settings.isMirrored,
      opacity: CGFloat(opacity),
      onto: image
    )
  }
}
