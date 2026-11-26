//
//  VideoEditorTextOverlayRenderer.swift
//  Snapzy
//
//  Thread-safe CoreText + CoreImage export renderer for `VideoEditorTextOverlay`.
//  Supports system/installed/imported fonts, per-word cascades, typewriter cursor,
//  X-axis shutter flip, directional `CIMotionBlur`, and specular light sheen.
//

import CoreGraphics
import CoreImage
import Foundation

nonisolated enum VideoEditorTextOverlayRenderer {
  struct LayoutCacheKey: Hashable, Sendable {
    let id: UUID
    let text: String
    let style: VideoEditorCaptionSettings
    let canvasWidth: Int
    let canvasHeight: Int

    init(overlay: VideoEditorTextOverlay, canvasSize: CGSize) {
      id = overlay.id
      text = overlay.text
      style = overlay.style
      canvasWidth = Int(canvasSize.width.rounded())
      canvasHeight = Int(canvasSize.height.rounded())
    }
  }

  struct CacheKey: Hashable, Sendable {
    let layoutKey: LayoutCacheKey
    let activeWordBucket: Int
    let activeWordArrivalBucket: Int
    let subwordKind: VideoEditorCaptionMotionState.SubwordAnimationKind?
    let subwordBucket: Int

    init(
      layoutKey: LayoutCacheKey,
      activeWordBucket: Int,
      activeWordArrivalBucket: Int,
      subwordKind: VideoEditorCaptionMotionState.SubwordAnimationKind?,
      subwordBucket: Int
    ) {
      self.layoutKey = layoutKey
      self.activeWordBucket = activeWordBucket
      self.activeWordArrivalBucket = activeWordArrivalBucket
      self.subwordKind = subwordKind
      self.subwordBucket = subwordBucket
    }

    init(
      layoutKey: LayoutCacheKey,
      overlay: VideoEditorTextOverlay,
      layout: VideoEditorCaptionLayout,
      motion: VideoEditorCaptionMotionState,
      outputTime: TimeInterval?
    ) {
      self.layoutKey = layoutKey

      if let sk = motion.subwordKind, let sp = motion.subwordProgress, sp < 0.999 {
        subwordKind = sk
        subwordBucket = Int((min(1, max(0, sp)) * 24).rounded())
      } else {
        subwordKind = nil
        subwordBucket = -1
      }

      if overlay.style.wordMode != .fullLine, let t = outputTime {
        let seg = CaptionSegment(id: overlay.id, sourceRange: overlay.safeTimeRange, text: overlay.text)
        let timing = VideoEditorCaptionMotion.activeWordTiming(
          atSource: t,
          in: seg,
          wordsInLayout: layout.flatWords,
          settings: overlay.style
        )
        activeWordBucket = timing?.index ?? -1
        if overlay.style.wordAnimation != .none, let arr = timing?.arrivalProgress {
          activeWordArrivalBucket = arr < 0.999 ? Int((min(1, max(0, arr)) * 8).rounded()) : 8
        } else {
          activeWordArrivalBucket = -1
        }
      } else {
        activeWordBucket = -1
        activeWordArrivalBucket = -1
      }
    }

    init(overlay: VideoEditorTextOverlay, canvasSize: CGSize, outputTime: TimeInterval? = nil) {
      let lKey = LayoutCacheKey(overlay: overlay, canvasSize: canvasSize)
      let trimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let motion = outputTime.map { overlay.motionState(at: $0) } ?? .identity
      if let layout = VideoEditorCaptionLayout.make(text: trimmed, settings: overlay.style, videoSize: canvasSize) {
        self.init(layoutKey: lKey, overlay: overlay, layout: layout, motion: motion, outputTime: outputTime)
      } else {
        self.init(
          layoutKey: lKey,
          activeWordBucket: -1,
          activeWordArrivalBucket: -1,
          subwordKind: nil,
          subwordBucket: -1
        )
      }
    }
  }

  static func renderPillImage(
    for overlay: VideoEditorTextOverlay,
    layout: VideoEditorCaptionLayout,
    motion: VideoEditorCaptionMotionState,
    outputTime: TimeInterval? = nil
  ) -> CIImage? {
    let trimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let wordTiming: VideoEditorActiveWordTiming? = if overlay.style.wordMode != .fullLine, let t = outputTime {
      VideoEditorCaptionMotion.activeWordTiming(
        atSource: t,
        in: CaptionSegment(id: overlay.id, sourceRange: overlay.safeTimeRange, text: trimmed),
        wordsInLayout: layout.flatWords,
        settings: overlay.style
      )
    } else {
      nil
    }

    let activeIdx = wordTiming?.index
    let activeWordArrival: CGFloat? = if overlay.style.wordAnimation != .none, let arr = wordTiming?.arrivalProgress {
      arr < 0.999 ? (CGFloat(Int((min(1, max(0, arr)) * 8).rounded())) / 8.0) : 1.0
    } else {
      nil
    }

    var subwordKind: VideoEditorCaptionMotionState.SubwordAnimationKind?
    var subwordProgress: CGFloat?
    if let sk = motion.subwordKind, let sp = motion.subwordProgress, sp < 0.999 {
      subwordKind = sk
      let bucket = Int((min(1, max(0, sp)) * 24).rounded())
      subwordProgress = CGFloat(bucket) / 24.0
    }

    guard let cgImage = VideoEditorCaptionRenderer.image(
      layout,
      settings: overlay.style,
      activeWordIndex: activeIdx,
      activeWordArrivalProgress: activeWordArrival,
      subwordKind: subwordKind,
      subwordProgress: subwordProgress,
      scale: 1
    ) else { return nil }
    return CIImage(cgImage: cgImage)
  }

  static func renderPillImage(
    for overlay: VideoEditorTextOverlay,
    canvasSize: CGSize,
    outputTime: TimeInterval? = nil
  ) -> CIImage? {
    let trimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, canvasSize.width > 16, canvasSize.height > 16,
          let layout = VideoEditorCaptionLayout.make(text: trimmed, settings: overlay.style, videoSize: canvasSize)
    else { return nil }
    let motion = outputTime.map { overlay.motionState(at: $0) } ?? .identity
    return renderPillImage(for: overlay, layout: layout, motion: motion, outputTime: outputTime)
  }

  static func composite(
    pillImage: CIImage,
    onto canvasImage: CIImage,
    overlay: VideoEditorTextOverlay,
    canvasSize: CGSize,
    motion: VideoEditorCaptionMotionState
  ) -> CIImage {
    guard motion.opacity > 0.002,
          motion.wipeProgress > 0.002,
          motion.verticalRevealProgress > 0.002
    else { return canvasImage }

    var layer = pillImage

    if let sheen = motion.shimmerProgress {
      layer = applySpecularSheen(to: layer, progress: sheen)
    }

    if motion.wipeProgress < 0.999 || motion.verticalRevealProgress < 0.999 {
      let ext = layer.extent
      let revealedW = max(1, ext.width * motion.wipeProgress)
      let revealedH = max(1, ext.height * motion.verticalRevealProgress)
      layer = layer.cropped(to: CGRect(
        x: ext.minX,
        y: ext.maxY - revealedH,
        width: revealedW,
        height: revealedH
      ))
    }

    let bmpW = pillImage.extent.width
    let bmpH = pillImage.extent.height
    let dx = motion.offsetXFraction * canvasSize.height
    let dy = -motion.offsetYFraction * canvasSize.height
    let targetCenterX = overlay.normalizedX * canvasSize.width + dx
    let targetCenterY = (1.0 - overlay.normalizedY) * canvasSize.height + dy
    let sx = motion.scale * motion.scaleX
    let sy = motion.scale * motion.scaleY

    var transform = CGAffineTransform(translationX: -bmpW / 2, y: -bmpH / 2)
    if abs(sx - 1.0) > 0.001 || abs(sy - 1.0) > 0.001 {
      transform = transform.concatenating(CGAffineTransform(scaleX: sx, y: sy))
    }
    transform = transform.concatenating(CGAffineTransform(translationX: targetCenterX, y: targetCenterY))
    layer = layer.transformed(by: transform)

    let blurPx = motion.blurRadiusFraction * canvasSize.height
    if blurPx > 0.25 {
      let padded = layer.extent.insetBy(dx: -ceil(blurPx * 3), dy: -ceil(blurPx * 3))
      if let angleDeg = motion.directionalBlurAngleDegrees {
        layer = layer
          .applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: blurPx,
            kCIInputAngleKey: angleDeg * .pi / 180.0,
          ])
          .cropped(to: padded)
      } else {
        layer = layer
          .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurPx])
          .cropped(to: padded)
      }
    }

    if motion.opacity < 0.999 {
      layer = layer.applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: motion.opacity),
      ])
    }

    return layer.composited(over: canvasImage).cropped(to: CGRect(origin: .zero, size: canvasSize))
  }

  static func composite(
    pillImage: CIImage,
    onto canvasImage: CIImage,
    overlay: VideoEditorTextOverlay,
    canvasSize: CGSize,
    opacity: Double,
    scale: CGFloat
  ) -> CIImage {
    var m = VideoEditorCaptionMotionState.identity
    m.opacity = CGFloat(opacity)
    m.scale = scale
    return composite(pillImage: pillImage, onto: canvasImage, overlay: overlay, canvasSize: canvasSize, motion: m)
  }

  private static func applySpecularSheen(to base: CIImage, progress: CGFloat) -> CIImage {
    let ext = base.extent
    guard ext.width > 4, ext.height > 4 else { return base }
    let bandHalfW = max(16, ext.width * 0.18)
    let centerX = ext.minX - bandHalfW + (ext.width + 2 * bandHalfW) * progress
    let clear = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
    let bright = CIColor(red: 1, green: 1, blue: 1, alpha: 0.60)

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
