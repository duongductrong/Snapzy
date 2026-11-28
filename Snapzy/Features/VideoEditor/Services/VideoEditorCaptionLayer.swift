//
//  VideoEditorCaptionLayer.swift
//  Snapzy
//
//  Canvas-space Studio layer burning captions into the export, on top of the camera.
//  Uses the exact same CoreText layout, custom/Google Fonts, per-word cascades,
//  directional `CIMotionBlur`, and specular sheen as the live SwiftUI preview.
//

import CoreImage
import Foundation

nonisolated struct VideoEditorCaptionLayer: VideoEditorStudioLayer, @unchecked Sendable {
  let resolver: VideoEditorCaptionResolver
  let mapping: VideoEditorSourceTimeMapping
  let sequenceMap: TimelineSequenceMap
  private let cache = VideoEditorCaptionImageCache(capacity: 64)

  init(captions: VideoEditorCaptions, mapping: VideoEditorSourceTimeMapping, sequenceMap: TimelineSequenceMap) {
    resolver = VideoEditorCaptionResolver(captions: captions)
    self.mapping = mapping
    self.sequenceMap = sequenceMap
  }

  var space: VideoEditorStudioLayerSpace {
    .canvas
  }

  var isActive: Bool {
    resolver.settings.isEnabled && !resolver.segments.isEmpty
  }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard let sourceTime = mapping.sourceTime(output: context.outputTime) else { return image }
    let rate = sequenceMap.rate(atSequence: sequenceMap.toSequence(context.outputTime))
    guard let segment = resolver.segment(atSource: sourceTime, rate: rate) else { return image }
    let videoRect = context.videoRect
    let settings = resolver.settings

    let motion = VideoEditorCaptionMotion.evaluate(
      atSource: sourceTime,
      in: segment,
      settings: settings
    )
    guard motion.opacity > 0.002, motion.wipeProgress > 0.002, motion.verticalRevealProgress > 0.002 else {
      return image
    }

    guard let entry = cache.entry(
      text: segment.text,
      segment: segment,
      sourceTime: sourceTime,
      settings: settings,
      videoSize: videoRect.size,
      subwordKind: motion.subwordKind,
      subwordProgress: motion.subwordProgress
    ) else {
      return image
    }

    let topLeft = entry.layout.bitmapFrame(in: CGRect(origin: .zero, size: videoRect.size), settings: settings)
    var caption = CIImage(cgImage: entry.image)

    if let sheenProgress = motion.shimmerProgress {
      caption = applySpecularSheen(to: caption, progress: sheenProgress)
    }

    if motion.wipeProgress < 0.999 || motion.verticalRevealProgress < 0.999 {
      let ext = caption.extent
      let revealedW = max(1, ext.width * motion.wipeProgress)
      let revealedH = max(1, ext.height * motion.verticalRevealProgress)
      caption = caption.cropped(to: CGRect(
        x: ext.minX,
        y: ext.maxY - revealedH,
        width: revealedW,
        height: revealedH
      ))
    }

    let baseOriginX = videoRect.minX + topLeft.minX
    let baseOriginY = videoRect.maxY - topLeft.maxY
    let dx = motion.offsetXFraction * videoRect.height
    let dy = -motion.offsetYFraction * videoRect.height

    let bmpW = topLeft.width
    let bmpH = topLeft.height
    let centerX = baseOriginX + bmpW / 2 + dx
    let centerY = baseOriginY + bmpH / 2 + dy
    let sx = motion.scale * motion.scaleX
    let sy = motion.scale * motion.scaleY

    if abs(sx - 1.0) > 0.001 || abs(sy - 1.0) > 0.001 {
      var t = CGAffineTransform(translationX: -bmpW / 2, y: -bmpH / 2)
      t = t.concatenating(CGAffineTransform(scaleX: sx, y: sy))
      t = t.concatenating(CGAffineTransform(translationX: centerX, y: centerY))
      caption = caption.transformed(by: t)
    } else {
      caption = caption.transformed(by: CGAffineTransform(
        translationX: (baseOriginX + dx).rounded(),
        y: (baseOriginY + dy).rounded()
      ))
    }

    let blurPx = motion.blurRadiusFraction * videoRect.height
    if blurPx > 0.25 {
      let padded = caption.extent.insetBy(dx: -ceil(blurPx * 3), dy: -ceil(blurPx * 3))
      if let angleDeg = motion.directionalBlurAngleDegrees {
        caption = caption
          .applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: blurPx,
            kCIInputAngleKey: angleDeg * .pi / 180.0,
          ])
          .cropped(to: padded)
      } else {
        caption = caption
          .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurPx])
          .cropped(to: padded)
      }
    }

    if motion.opacity < 0.999 {
      caption = caption.applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: motion.opacity),
      ])
    }

    return caption.composited(over: image).cropped(to: context.extent)
  }

  private func applySpecularSheen(to base: CIImage, progress: CGFloat) -> CIImage {
    let ext = base.extent
    guard ext.width > 4, ext.height > 4 else { return base }
    let bandHalfW = max(16, ext.width * 0.18)
    let centerX = ext.minX - bandHalfW + (ext.width + 2 * bandHalfW) * progress
    let clear = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
    let bright = CIColor(red: 1, green: 1, blue: 1, alpha: 0.62)

    guard let gradA = CIFilter(name: "CILinearGradient", parameters: [
      "inputPoint0": CIVector(x: centerX - bandHalfW, y: ext.midY + bandHalfW * 0.25),
      "inputPoint1": CIVector(x: centerX, y: ext.midY),
      "inputColor0": clear,
      "inputColor1": bright,
    ])?.outputImage?.cropped(to: CGRect(
      x: ext.minX,
      y: ext.minY,
      width: max(0, centerX - ext.minX),
      height: ext.height
    )),
      let gradB = CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: centerX, y: ext.midY),
        "inputPoint1": CIVector(x: centerX + bandHalfW, y: ext.midY - bandHalfW * 0.25),
        "inputColor0": bright,
        "inputColor1": clear,
      ])?.outputImage?.cropped(to: CGRect(
        x: centerX,
        y: ext.minY,
        width: max(0, ext.maxX - centerX),
        height: ext.height
      ))
    else {
      return base
    }

    let band = gradA.composited(over: gradB).cropped(to: ext)
    let maskedSheen = band.applyingFilter("CISourceInCompositing", parameters: [
      kCIInputBackgroundImageKey: base,
    ])
    return maskedSheen
      .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: base])
      .cropped(to: ext)
  }
}
