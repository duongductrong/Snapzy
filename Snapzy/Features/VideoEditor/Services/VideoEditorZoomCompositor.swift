//
//  ZoomCompositor.swift
//  Snapzy
//
//  Applies zoom effects to video during export using AVVideoComposition
//

import AVFoundation
import CoreImage
import SwiftUI

/// Compositor that applies zoom effects during video export
class ZoomCompositor {

  // MARK: - Properties

  private let zooms: [ZoomSegment]
  private let renderSize: CGSize
  private let transitionDuration: TimeInterval

  // Background properties
  private let backgroundStyle: BackgroundStyle
  private let backgroundPadding: CGFloat
  private let cornerRadius: CGFloat
  let paddedRenderSize: CGSize

  // MARK: - Initialization

  init(
    zooms: [ZoomSegment],
    renderSize: CGSize,
    transitionDuration: TimeInterval = 0.3,
    backgroundStyle: BackgroundStyle = .none,
    backgroundPadding: CGFloat = 0,
    cornerRadius: CGFloat = 0
  ) {
    self.zooms = zooms.filter { $0.isEnabled }
    self.renderSize = renderSize
    self.transitionDuration = transitionDuration
    self.backgroundStyle = backgroundStyle
    self.backgroundPadding = backgroundPadding
    self.cornerRadius = cornerRadius

    // Calculate padded render size
    if backgroundStyle != .none && backgroundPadding > 0 {
      self.paddedRenderSize = CGSize(
        width: renderSize.width + (backgroundPadding * 2),
        height: renderSize.height + (backgroundPadding * 2)
      )
    } else {
      self.paddedRenderSize = renderSize
    }
  }

  // MARK: - Video Composition Creation

  /// Create a video composition that applies zoom effects
  func createVideoComposition(
    for asset: AVAsset,
    timeRange: CMTimeRange
  ) async throws -> AVMutableVideoComposition {
    print("🎬 [ZoomCompositor] Creating video composition")
    print("🎬 [ZoomCompositor] Render size: \(renderSize)")
    print("🎬 [ZoomCompositor] Time range: \(CMTimeGetSeconds(timeRange.start))s - \(CMTimeGetSeconds(timeRange.end))s")
    print("🎬 [ZoomCompositor] Zooms to apply: \(zooms.count)")

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps

    // Get video track
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      print("❌ [ZoomCompositor] ERROR: No video track found")
      throw ZoomCompositorError.noVideoTrack
    }
    print("🎬 [ZoomCompositor] Video track ID: \(videoTrack.trackID)")

    // Create instruction covering the entire time range
    let instruction = ZoomVideoCompositionInstruction(
      timeRange: timeRange,
      zooms: zooms,
      trackID: videoTrack.trackID,
      renderSize: renderSize,
      transitionDuration: transitionDuration,
      backgroundStyle: backgroundStyle,
      backgroundPadding: backgroundPadding,
      cornerRadius: cornerRadius,
      paddedRenderSize: paddedRenderSize
    )
    print("🎬 [ZoomCompositor] Created instruction with trackID: \(videoTrack.trackID)")

    videoComposition.instructions = [instruction]
    videoComposition.customVideoCompositorClass = ZoomVideoCompositorClass.self
    print("🎬 [ZoomCompositor] Set custom compositor class: ZoomVideoCompositorClass")

    return videoComposition
  }

  // MARK: - Errors

  enum ZoomCompositorError: Error, LocalizedError {
    case noVideoTrack
    case compositionFailed
    case trackMismatch(expected: CMPersistentTrackID, available: [CMPersistentTrackID])

    var errorDescription: String? {
      switch self {
      case .noVideoTrack:
        return "Video file format is incompatible or corrupted. Please try re-recording."
      case .compositionFailed:
        return "Failed to apply zoom effects. The video may be corrupted or in an unsupported format."
      case .trackMismatch(let expected, let available):
        return "Track ID mismatch: expected \(expected), available: \(available). Please try re-exporting."
      }
    }
  }
}

// MARK: - Custom Video Composition Instruction

class ZoomVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
  let timeRange: CMTimeRange
  let zooms: [ZoomSegment]
  let trackID: CMPersistentTrackID
  let renderSize: CGSize
  let transitionDuration: TimeInterval
  let backgroundStyle: BackgroundStyle
  let backgroundPadding: CGFloat
  let cornerRadius: CGFloat
  let paddedRenderSize: CGSize

  var enablePostProcessing: Bool { true }
  var containsTweening: Bool { true }
  var requiredSourceTrackIDs: [NSValue]? {
    // Must return NSNumber (which is a subclass of NSValue) for track IDs
    // AVFoundation calls intValue on these objects
    return [NSNumber(value: trackID)]
  }
  var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

  init(
    timeRange: CMTimeRange,
    zooms: [ZoomSegment],
    trackID: CMPersistentTrackID,
    renderSize: CGSize,
    transitionDuration: TimeInterval,
    backgroundStyle: BackgroundStyle = .none,
    backgroundPadding: CGFloat = 0,
    cornerRadius: CGFloat = 0,
    paddedRenderSize: CGSize? = nil
  ) {
    self.timeRange = timeRange
    self.zooms = zooms
    self.trackID = trackID
    self.renderSize = renderSize
    self.transitionDuration = transitionDuration
    self.backgroundStyle = backgroundStyle
    self.backgroundPadding = backgroundPadding
    self.cornerRadius = cornerRadius
    self.paddedRenderSize = paddedRenderSize ?? renderSize
    super.init()
  }
}

// MARK: - Custom Video Compositor

class ZoomVideoCompositorClass: NSObject, AVVideoCompositing {

  // Required properties
  var sourcePixelBufferAttributes: [String: Any]? {
    [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true
    ]
  }

  var requiredPixelBufferAttributesForRenderContext: [String: Any] {
    [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true
    ]
  }

  var supportsWideColorSourceFrames: Bool { false }
  var supportsHDRSourceFrames: Bool { false }

  private var renderContext: AVVideoCompositionRenderContext?
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  private let queue = DispatchQueue(label: "com.claudeshot.zoomcompositor")

  // Wallpaper cache to avoid loading from disk on every frame
  private var cachedWallpaperURL: URL?
  private var cachedWallpaperSize: CGSize?
  private var cachedScaledWallpaper: CIImage?

  // Blurred wallpaper cache
  private var cachedBlurredURL: URL?
  private var cachedBlurredSize: CGSize?
  private var cachedBlurredWallpaper: CIImage?

  // MARK: - AVVideoCompositing Protocol

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    queue.sync {
      renderContext = newRenderContext
      // Clear wallpaper cache if size changed to ensure correct scaling
      if cachedWallpaperSize != newRenderContext.size {
        cachedScaledWallpaper = nil
        cachedBlurredWallpaper = nil
      }
      print("🎥 [Compositor] Render context changed - size: \(newRenderContext.size)")
    }
  }

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    queue.async { [weak self] in
      self?.processRequest(request)
    }
  }

  func cancelAllPendingVideoCompositionRequests() {
    // No pending requests to cancel
  }

  // MARK: - Frame Processing

  private var frameCount = 0

  private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    frameCount += 1
    let currentTime = CMTimeGetSeconds(request.compositionTime)

    guard let instruction = request.videoCompositionInstruction as? ZoomVideoCompositionInstruction else {
      print("❌ [Compositor] Frame \(frameCount): Invalid instruction type")
      request.finish(with: ZoomCompositor.ZoomCompositorError.compositionFailed)
      return
    }

    guard let sourceBuffer = request.sourceFrame(byTrackID: instruction.trackID) else {
      // Try to find any available source frame as fallback
      let availableTrackIDs = request.sourceTrackIDs.compactMap { ($0 as? NSNumber)?.int32Value }
      print("❌ [Compositor] Frame \(frameCount): No source frame for trackID \(instruction.trackID)")
      print("❌ [Compositor] Available track IDs: \(availableTrackIDs)")

      // Try fallback: use first available track
      if let firstTrackID = availableTrackIDs.first,
         let fallbackBuffer = request.sourceFrame(byTrackID: firstTrackID) {
        print("🔄 [Compositor] Frame \(frameCount): Using fallback trackID \(firstTrackID)")
        request.finish(withComposedVideoFrame: fallbackBuffer)
        return
      }

      request.finish(with: ZoomCompositor.ZoomCompositorError.trackMismatch(
        expected: instruction.trackID,
        available: availableTrackIDs
      ))
      return
    }

    if frameCount == 1 || frameCount % 30 == 0 {
      print("🎥 [Compositor] Processing frame \(frameCount) at time \(String(format: "%.2f", currentTime))s")
    }

    // Find active zoom at current time
    let activeZoom = instruction.zooms.first { $0.contains(time: currentTime) }
    let hasBackground = instruction.backgroundStyle != .none && instruction.backgroundPadding > 0

    // Calculate zoom parameters if zoom is active
    var zoomLevel: CGFloat = 1.0
    var zoomCenter = CGPoint(x: 0.5, y: 0.5)
    if let zoom = activeZoom {
      let interpolated = ZoomCalculator.interpolateZoom(
        segment: zoom,
        currentTime: currentTime,
        transitionDuration: instruction.transitionDuration
      )
      zoomLevel = interpolated.level
      zoomCenter = interpolated.center
    }

    // If no zoom and no background, pass through original frame
    if zoomLevel < 1.01 && !hasBackground {
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    // Apply zoom and/or background effect
    guard let outputBuffer = applyEffects(
      to: sourceBuffer,
      zoomLevel: zoomLevel,
      center: zoomCenter,
      instruction: instruction
    ) else {
      print("❌ [Compositor] Frame \(frameCount): applyEffects returned nil, passing through")
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    request.finish(withComposedVideoFrame: outputBuffer)
  }

  private func applyEffects(
    to sourceBuffer: CVPixelBuffer,
    zoomLevel: CGFloat,
    center: CGPoint,
    instruction: ZoomVideoCompositionInstruction
  ) -> CVPixelBuffer? {
    // Create CIImage from source buffer
    var processedImage = CIImage(cvPixelBuffer: sourceBuffer)
    let sourceExtent = processedImage.extent

    // Apply zoom if needed
    if zoomLevel > 1.01 {
      let cropRect = ZoomCalculator.calculateCropRect(
        center: center,
        zoomLevel: zoomLevel,
        frameSize: CGSize(width: sourceExtent.width, height: sourceExtent.height)
      )
      let croppedImage = processedImage.cropped(to: cropRect)
      let scaleX = sourceExtent.width / cropRect.width
      let scaleY = sourceExtent.height / cropRect.height
      processedImage = croppedImage
        .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    // Apply background if needed
    let hasBackground = instruction.backgroundStyle != .none && instruction.backgroundPadding > 0
    if hasBackground {
      // Apply corner radius to video frame if specified
      if instruction.cornerRadius > 0 {
        processedImage = applyCornerRadius(
          to: processedImage,
          cornerRadius: instruction.cornerRadius,
          size: instruction.renderSize
        )
      }

      // Position video in center with padding
      let translatedVideo = processedImage.transformed(
        by: CGAffineTransform(translationX: instruction.backgroundPadding, y: instruction.backgroundPadding)
      )

      // Create background
      let background = createBackgroundImage(
        style: instruction.backgroundStyle,
        size: instruction.paddedRenderSize
      )

      // Composite video over background
      processedImage = translatedVideo.composited(over: background)
    }

    // Create output buffer
    guard let renderContext = renderContext else { return nil }
    guard let outputBuffer = renderContext.newPixelBuffer() else { return nil }

    // Render to output buffer
    ciContext.render(processedImage, to: outputBuffer)

    return outputBuffer
  }

  /// Apply corner radius mask to a CIImage
  private func applyCornerRadius(to image: CIImage, cornerRadius: CGFloat, size: CGSize) -> CIImage {
    let extent = image.extent

    // Create a rounded rectangle mask using CGContext
    let maskSize = CGSize(width: extent.width, height: extent.height)
    guard let cgContext = CGContext(
      data: nil,
      width: Int(maskSize.width),
      height: Int(maskSize.height),
      bitsPerComponent: 8,
      bytesPerRow: Int(maskSize.width) * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return image
    }

    // Scale corner radius proportionally to video size
    // Use the smaller dimension as reference for consistent appearance
    let scaleFactor = min(extent.width, extent.height) / min(size.width, size.height)
    let scaledCornerRadius = cornerRadius * scaleFactor

    // Clamp corner radius to prevent visual artifacts (max = half of smaller dimension)
    let maxRadius = min(maskSize.width, maskSize.height) / 2
    let clampedCornerRadius = min(scaledCornerRadius, maxRadius)

    // Draw white rounded rectangle (mask)
    cgContext.setFillColor(CGColor.white)
    let maskRect = CGRect(origin: .zero, size: maskSize)
    let path = CGPath(roundedRect: maskRect, cornerWidth: clampedCornerRadius, cornerHeight: clampedCornerRadius, transform: nil)
    cgContext.addPath(path)
    cgContext.fillPath()

    guard let maskCGImage = cgContext.makeImage() else {
      return image
    }

    let maskImage = CIImage(cgImage: maskCGImage)

    // Use CIBlendWithAlphaMask to apply the rounded corner mask
    guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else {
      return image
    }

    // Create transparent background for masking
    let transparentBackground = CIImage(color: .clear).cropped(to: extent)

    blendFilter.setValue(image, forKey: kCIInputImageKey)
    blendFilter.setValue(transparentBackground, forKey: kCIInputBackgroundImageKey)
    blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

    return blendFilter.outputImage ?? image
  }

  private func createBackgroundImage(style: BackgroundStyle, size: CGSize) -> CIImage {
    let rect = CGRect(origin: .zero, size: size)

    switch style {
    case .none:
      return CIImage(color: .clear).cropped(to: rect)

    case .gradient(let preset):
      // Create gradient using CILinearGradient filter
      guard let filter = CIFilter(name: "CILinearGradient") else {
        return CIImage(color: .black).cropped(to: rect)
      }
      filter.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint0")
      filter.setValue(CIVector(x: size.width, y: 0), forKey: "inputPoint1")

      // Convert SwiftUI colors to CIColor
      let color0 = CIColor(color: NSColor(preset.colors[0])) ?? CIColor.black
      let color1 = CIColor(color: NSColor(preset.colors[1])) ?? CIColor.white
      filter.setValue(color0, forKey: "inputColor0")
      filter.setValue(color1, forKey: "inputColor1")

      return filter.outputImage?.cropped(to: rect) ?? CIImage(color: .black).cropped(to: rect)

    case .solidColor(let color):
      let ciColor = CIColor(color: NSColor(color)) ?? CIColor.white
      return CIImage(color: ciColor).cropped(to: rect)

    case .wallpaper(let url):
      // Check if we have a cached version for this URL and size
      if let cached = cachedScaledWallpaper,
         cachedWallpaperURL == url,
         cachedWallpaperSize == size {
        return cached
      }

      // Load and cache the wallpaper
      guard let image = CIImage(contentsOf: url) else {
        return CIImage(color: .black).cropped(to: rect)
      }
      let scaled = scaleToFill(image: image, targetSize: size)

      // Store in cache
      cachedWallpaperURL = url
      cachedWallpaperSize = size
      cachedScaledWallpaper = scaled

      return scaled

    case .blurred(let url):
      // Check if we have a cached version for this URL and size
      if let cached = cachedBlurredWallpaper,
         cachedBlurredURL == url,
         cachedBlurredSize == size {
        return cached
      }

      // Load and cache the blurred wallpaper
      guard let image = CIImage(contentsOf: url) else {
        return CIImage(color: .black).cropped(to: rect)
      }
      let scaled = scaleToFill(image: image, targetSize: size)
      let blurred = scaled.applyingGaussianBlur(sigma: 20).cropped(to: rect)

      // Store in cache
      cachedBlurredURL = url
      cachedBlurredSize = size
      cachedBlurredWallpaper = blurred

      return blurred
    }
  }

  private func scaleToFill(image: CIImage, targetSize: CGSize) -> CIImage {
    let scaleX = targetSize.width / image.extent.width
    let scaleY = targetSize.height / image.extent.height
    let scale = max(scaleX, scaleY)
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let offsetX = (scaled.extent.width - targetSize.width) / 2
    let offsetY = (scaled.extent.height - targetSize.height) / 2
    return scaled.cropped(to: CGRect(x: offsetX, y: offsetY, width: targetSize.width, height: targetSize.height))
      .transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))
  }

  private func applyZoom(
    to sourceBuffer: CVPixelBuffer,
    zoomLevel: CGFloat,
    center: CGPoint,
    renderSize: CGSize
  ) -> CVPixelBuffer? {
    // Create CIImage from source buffer
    let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
    let sourceExtent = sourceImage.extent

    // Calculate crop rect
    let cropRect = ZoomCalculator.calculateCropRect(
      center: center,
      zoomLevel: zoomLevel,
      frameSize: CGSize(width: sourceExtent.width, height: sourceExtent.height)
    )

    // Crop the image
    let croppedImage = sourceImage.cropped(to: cropRect)

    // Scale back to original size
    let scaleX = sourceExtent.width / cropRect.width
    let scaleY = sourceExtent.height / cropRect.height
    let scaledImage = croppedImage
      .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
      .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    // Create output buffer
    guard let renderContext = renderContext else { return nil }
    guard let outputBuffer = renderContext.newPixelBuffer() else { return nil }

    // Render to output buffer
    ciContext.render(scaledImage, to: outputBuffer)

    return outputBuffer
  }
}
