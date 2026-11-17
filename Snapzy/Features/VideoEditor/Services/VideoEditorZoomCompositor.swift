//
//  VideoEditorZoomCompositor.swift
//  Snapzy
//
//  Applies zoom effects to video during export using AVVideoComposition
//

import AVFoundation
import CoreImage
import CoreVideo
import SwiftUI

/// Compositor that applies zoom effects during video export
class ZoomCompositor {
  // MARK: - Properties

  private let zooms: [ZoomSegment]
  private let autoFocusPaths: [UUID: [AutoFocusCameraSample]]
  private let renderSize: CGSize
  private let frameDuration: CMTime
  private let transitionDuration: TimeInterval

  // Background properties
  private let backgroundStyle: BackgroundStyle
  private let backgroundPadding: CGFloat
  private let cornerRadius: CGFloat
  private let studioRecipe: VideoEditorStudioRecipe
  let paddedRenderSize: CGSize

  // MARK: - Initialization

  init(
    zooms: [ZoomSegment],
    autoFocusPaths: [UUID: [AutoFocusCameraSample]] = [:],
    renderSize: CGSize,
    frameDuration: CMTime = CMTime(value: 1, timescale: 30),
    transitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration,
    backgroundStyle: BackgroundStyle = .none,
    backgroundPadding: CGFloat = 0,
    cornerRadius: CGFloat = 0,
    studioRecipe: VideoEditorStudioRecipe = .empty
  ) {
    self.zooms = zooms.filter(\.isEnabled)
    self.autoFocusPaths = autoFocusPaths
    self.renderSize = renderSize
    self.frameDuration = frameDuration
    self.transitionDuration = ZoomCalculator.clampTransitionDuration(transitionDuration)
    self.backgroundStyle = backgroundStyle
    self.backgroundPadding = backgroundPadding
    self.cornerRadius = cornerRadius
    self.studioRecipe = studioRecipe

    // Calculate padded render size
    if backgroundStyle != .none, backgroundPadding > 0 {
      paddedRenderSize = CGSize(
        width: renderSize.width + (backgroundPadding * 2),
        height: renderSize.height + (backgroundPadding * 2)
      )
    } else {
      paddedRenderSize = renderSize
    }
  }

  // MARK: - Video Composition Creation

  /// Create a video composition that applies zoom effects.
  /// - Parameters:
  ///   - screenTrackID: The screen-recording track. Required whenever the asset carries
  ///     more than one video track (e.g. a camera sidecar), so the compositor never
  ///     mistakes an auxiliary track for the screen. `nil` keeps the legacy
  ///     single-track behaviour (first video track).
  ///   - auxiliaryTrackIDs: Extra video tracks Studio layers read, keyed by role.
  func createVideoComposition(
    for asset: AVAsset,
    timeRange: CMTimeRange,
    screenTrackID: CMPersistentTrackID? = nil,
    auxiliaryTrackIDs: [VideoEditorStudioAuxiliaryTrack: CMPersistentTrackID] = [:]
  ) async throws -> AVMutableVideoComposition {
    print("🎬 [ZoomCompositor] Creating video composition")
    print("🎬 [ZoomCompositor] Render size: \(renderSize)")
    print("🎬 [ZoomCompositor] Time range: \(CMTimeGetSeconds(timeRange.start))s - \(CMTimeGetSeconds(timeRange.end))s")
    print("🎬 [ZoomCompositor] Zooms to apply: \(zooms.count)")

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = frameDuration

    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    let resolvedScreenTrackID = try Self.resolveScreenTrackID(
      explicit: screenTrackID,
      available: videoTracks.map(\.trackID),
      auxiliary: Array(auxiliaryTrackIDs.values)
    )
    print("🎬 [ZoomCompositor] Video track ID: \(resolvedScreenTrackID)")

    // Create instruction covering the entire time range
    let instruction = ZoomVideoCompositionInstruction(
      timeRange: timeRange,
      zooms: zooms,
      autoFocusPaths: autoFocusPaths,
      trackID: resolvedScreenTrackID,
      renderSize: renderSize,
      transitionDuration: transitionDuration,
      backgroundStyle: backgroundStyle,
      backgroundPadding: backgroundPadding,
      cornerRadius: cornerRadius,
      paddedRenderSize: paddedRenderSize,
      studioRecipe: studioRecipe,
      auxiliaryTrackIDs: auxiliaryTrackIDs
    )
    print("🎬 [ZoomCompositor] Created instruction with trackID: \(resolvedScreenTrackID)")

    videoComposition.instructions = [instruction]
    videoComposition.customVideoCompositorClass = ZoomVideoCompositorClass.self
    print("🎬 [ZoomCompositor] Set custom compositor class: ZoomVideoCompositorClass")

    return videoComposition
  }

  /// Picks the screen track. With auxiliary tracks present the caller must name the
  /// screen track explicitly; "first video track" is only safe for single-track assets.
  nonisolated static func resolveScreenTrackID(
    explicit: CMPersistentTrackID?,
    available: [CMPersistentTrackID],
    auxiliary: [CMPersistentTrackID]
  ) throws -> CMPersistentTrackID {
    if let explicit {
      guard available.contains(explicit), !auxiliary.contains(explicit) else {
        DiagnosticLogger.shared.log(.error, .export, "Zoom compositor screen track missing", context: [
          "expectedTrackID": "\(explicit)",
          "availableTrackCount": "\(available.count)",
        ])
        throw ZoomCompositorError.trackMismatch(expected: explicit, available: available)
      }
      return explicit
    }
    guard auxiliary.isEmpty else {
      throw ZoomCompositorError.trackMismatch(expected: kCMPersistentTrackID_Invalid, available: available)
    }
    guard let first = available.first else {
      print("❌ [ZoomCompositor] ERROR: No video track found")
      DiagnosticLogger.shared.log(.error, .export, "Zoom compositor failed; source video track missing")
      throw ZoomCompositorError.noVideoTrack
    }
    return first
  }

  // MARK: - Errors

  enum ZoomCompositorError: Error, LocalizedError {
    case noVideoTrack
    case compositionFailed
    case trackMismatch(expected: CMPersistentTrackID, available: [CMPersistentTrackID])

    var errorDescription: String? {
      switch self {
      case .noVideoTrack:
        L10n.ZoomCompositor.noVideoTrack
      case .compositionFailed:
        L10n.ZoomCompositor.compositionFailed
      case .trackMismatch(let expected, let available):
        L10n.ZoomCompositor.trackMismatch(
          String(expected),
          available.map(String.init(describing:)).joined(separator: ", ")
        )
      }
    }
  }
}

// MARK: - Custom Video Composition Instruction

class ZoomVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
  let timeRange: CMTimeRange
  let zooms: [ZoomSegment]
  let autoFocusPaths: [UUID: [AutoFocusCameraSample]]
  let trackID: CMPersistentTrackID
  let renderSize: CGSize
  let transitionDuration: TimeInterval
  let backgroundStyle: BackgroundStyle
  let hasBackground: Bool
  let backgroundPadding: CGFloat
  let cornerRadius: CGFloat
  let paddedRenderSize: CGSize
  let studioRecipe: VideoEditorStudioRecipe
  /// Auxiliary video tracks (camera sidecar, ...) Studio layers read. Never used as a
  /// stand-in for the screen track.
  let auxiliaryTrackIDs: [VideoEditorStudioAuxiliaryTrack: CMPersistentTrackID]

  var enablePostProcessing: Bool {
    true
  }

  var containsTweening: Bool {
    true
  }

  var requiredSourceTrackIDs: [NSValue]? {
    // Must return NSNumber (which is a subclass of NSValue) for track IDs
    // AVFoundation calls intValue on these objects. Screen track first.
    let auxiliary = auxiliaryTrackIDs
      .sorted { $0.key.rawValue < $1.key.rawValue }
      .map(\.value)
      .filter { $0 != trackID }
    return ([trackID] + auxiliary).map { NSNumber(value: $0) }
  }

  /// Layers draw something, so the compositor must not pass frames through untouched.
  var hasStudioLayers: Bool { studioRecipe.hasActiveLayers }

  var passthroughTrackID: CMPersistentTrackID {
    kCMPersistentTrackID_Invalid
  }

  init(
    timeRange: CMTimeRange,
    zooms: [ZoomSegment],
    autoFocusPaths: [UUID: [AutoFocusCameraSample]],
    trackID: CMPersistentTrackID,
    renderSize: CGSize,
    transitionDuration: TimeInterval,
    backgroundStyle: BackgroundStyle = .none,
    backgroundPadding: CGFloat = 0,
    cornerRadius: CGFloat = 0,
    paddedRenderSize: CGSize? = nil,
    studioRecipe: VideoEditorStudioRecipe = .empty,
    auxiliaryTrackIDs: [VideoEditorStudioAuxiliaryTrack: CMPersistentTrackID] = [:]
  ) {
    self.timeRange = timeRange
    self.zooms = zooms
    self.autoFocusPaths = autoFocusPaths
    self.trackID = trackID
    self.renderSize = renderSize
    self.transitionDuration = transitionDuration
    self.backgroundStyle = backgroundStyle
    switch backgroundStyle {
    case .none:
      hasBackground = false
    default:
      hasBackground = backgroundPadding > 0
    }
    self.backgroundPadding = backgroundPadding
    self.cornerRadius = cornerRadius
    self.paddedRenderSize = paddedRenderSize ?? renderSize
    self.studioRecipe = studioRecipe
    self.auxiliaryTrackIDs = auxiliaryTrackIDs
    super.init()
  }
}

// MARK: - Custom Video Compositor

class ZoomVideoCompositorClass: NSObject, AVVideoCompositing {
  private let minimumRenderableZoomLevel: CGFloat = 1.0001

  /// Required properties
  var sourcePixelBufferAttributes: [String: any Sendable]? {
    [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
  }

  var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
    [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
  }

  var supportsWideColorSourceFrames: Bool {
    false
  }

  var supportsHDRSourceFrames: Bool {
    false
  }

  private var renderContext: AVVideoCompositionRenderContext?
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  private let queue = DispatchQueue(label: "com.trongduong.snapzy.zoomcompositor")

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
      DiagnosticLogger.shared.log(
        .error,
        .export,
        "Zoom compositor request failed; invalid instruction type",
        context: ["frame": "\(frameCount)"]
      )
      request.finish(with: ZoomCompositor.ZoomCompositorError.compositionFailed)
      return
    }

    guard let sourceBuffer = request.sourceFrame(byTrackID: instruction.trackID) else {
      // Try to find any available source frame as fallback
      let availableTrackIDs = request.sourceTrackIDs.map(\.int32Value)
      print("❌ [Compositor] Frame \(frameCount): No source frame for trackID \(instruction.trackID)")
      print("❌ [Compositor] Available track IDs: \(availableTrackIDs)")
      DiagnosticLogger.shared.log(
        .error,
        .export,
        "Zoom compositor source frame missing",
        context: [
          "frame": "\(frameCount)",
          "expectedTrackID": "\(instruction.trackID)",
          "availableTrackCount": "\(availableTrackIDs.count)",
        ]
      )

      // Try fallback: use first available track that is not an auxiliary (camera, ...)
      // track — passing a camera frame through as the screen would be worse than failing.
      let auxiliaryIDs = Set(instruction.auxiliaryTrackIDs.values)
      if let firstTrackID = availableTrackIDs.first(where: { !auxiliaryIDs.contains($0) }),
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

    let cameraState = VideoEditorAutoFocusEngine.resolvedCameraState(
      at: currentTime,
      segments: instruction.zooms,
      autoFocusPaths: instruction.autoFocusPaths,
      transitionDuration: instruction.transitionDuration
    )
    let zoomLevel = cameraState.zoomLevel
    let zoomCenter = cameraState.center
    let sourceSize = CGSize(
      width: CVPixelBufferGetWidth(sourceBuffer),
      height: CVPixelBufferGetHeight(sourceBuffer)
    )
    let needsCanvasFit = abs(sourceSize.width - instruction.renderSize.width) > 0.5
      || abs(sourceSize.height - instruction.renderSize.height) > 0.5

    // If no zoom, no background and no Studio layer, pass through original frame
    if zoomLevel <= minimumRenderableZoomLevel,
       !instruction.hasBackground,
       !needsCanvasFit,
       !instruction.hasStudioLayers {
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    // Apply zoom and/or background effect
    guard let outputBuffer = applyEffects(
      to: sourceBuffer,
      zoomLevel: zoomLevel,
      center: zoomCenter,
      instruction: instruction,
      outputTime: currentTime,
      auxiliaryFrames: auxiliaryFrames(for: instruction, request: request)
    ) else {
      print("❌ [Compositor] Frame \(frameCount): applyEffects returned nil, passing through")
      if frameCount == 1 || frameCount % 30 == 0 {
        DiagnosticLogger.shared.log(
          .warning,
          .export,
          "Zoom compositor effects failed; passed through source frame",
          context: ["frame": "\(frameCount)"]
        )
      }
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    request.finish(withComposedVideoFrame: outputBuffer)
  }

  private func applyEffects(
    to sourceBuffer: CVPixelBuffer,
    zoomLevel: CGFloat,
    center: CGPoint,
    instruction: ZoomVideoCompositionInstruction,
    outputTime: TimeInterval,
    auxiliaryFrames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer]
  ) -> CVPixelBuffer? {
    // Create CIImage from source buffer
    var processedImage = CIImage(cvPixelBuffer: sourceBuffer)
    let sourceExtent = processedImage.extent

    // Studio source-space layers (cursor, clicks) ride along with the screen into zoom.
    processedImage = compositeSourceSpaceLayers(
      processedImage,
      outputTime: outputTime,
      instruction: instruction,
      auxiliaryFrames: auxiliaryFrames
    )

    // Apply zoom if needed
    if zoomLevel > minimumRenderableZoomLevel {
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

    let fittedRect = VideoEditorExportLayout.aspectFitRect(
      sourceSize: processedImage.extent.size,
      in: instruction.renderSize
    )
    let needsCanvasFit = abs(fittedRect.origin.x) > 0.5
      || abs(fittedRect.origin.y) > 0.5
      || abs(fittedRect.width - processedImage.extent.width) > 0.5
      || abs(fittedRect.height - processedImage.extent.height) > 0.5

    if needsCanvasFit || instruction.cornerRadius > 0 {
      processedImage = placeImageOnCanvas(
        processedImage,
        canvasSize: instruction.renderSize,
        fittedRect: fittedRect
      )
    }

    // Apply background if needed
    if instruction.hasBackground {
      // Apply corner radius to video frame if specified
      if instruction.cornerRadius > 0 {
        processedImage = applyCornerRadius(
          to: processedImage,
          cornerRadius: instruction.cornerRadius,
          roundedRect: fittedRect,
          canvasSize: instruction.renderSize
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

    // Studio canvas-space layers (camera, captions) are never zoomed.
    processedImage = compositeCanvasSpaceLayers(
      processedImage,
      outputTime: outputTime,
      instruction: instruction,
      auxiliaryFrames: auxiliaryFrames
    )

    // Create output buffer
    guard let renderContext else { return nil }
    guard let outputBuffer = renderContext.newPixelBuffer() else { return nil }

    // Render to output buffer
    ciContext.render(processedImage, to: outputBuffer)

    return outputBuffer
  }

  // MARK: - Studio Layer Hooks

  /// Draws `.source` layers on the untouched source frame, before the zoom crop.
  private func compositeSourceSpaceLayers(
    _ image: CIImage,
    outputTime: TimeInterval,
    instruction: ZoomVideoCompositionInstruction,
    auxiliaryFrames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer]
  ) -> CIImage {
    guard instruction.hasStudioLayers else { return image }
    return instruction.studioRecipe
      .composite(image, space: .source, outputTime: outputTime, auxiliaryFrames: auxiliaryFrames)
      .cropped(to: image.extent)
  }

  /// Draws `.canvas` layers on the final canvas, after background and padding.
  private func compositeCanvasSpaceLayers(
    _ image: CIImage,
    outputTime: TimeInterval,
    instruction: ZoomVideoCompositionInstruction,
    auxiliaryFrames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer]
  ) -> CIImage {
    guard instruction.hasStudioLayers else { return image }
    let canvasRect = CGRect(origin: .zero, size: instruction.paddedRenderSize)
    let base = image.extent.isInfinite ? image.cropped(to: canvasRect) : image
    return instruction.studioRecipe
      .composite(base, space: .canvas, outputTime: outputTime, auxiliaryFrames: auxiliaryFrames)
      .cropped(to: canvasRect)
  }

  /// Auxiliary frames only for tracks the active layers actually need.
  private func auxiliaryFrames(
    for instruction: ZoomVideoCompositionInstruction,
    request: AVAsynchronousVideoCompositionRequest
  ) -> [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer] {
    guard instruction.hasStudioLayers else { return [:] }
    var frames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer] = [:]
    for role in instruction.studioRecipe.requiredAuxiliaryTracks {
      guard let trackID = instruction.auxiliaryTrackIDs[role],
            let frame = request.sourceFrame(byTrackID: trackID) else { continue }
      frames[role] = frame
    }
    return frames
  }

  /// Apply corner radius mask to a CIImage
  private func applyCornerRadius(
    to image: CIImage,
    cornerRadius: CGFloat,
    roundedRect: CGRect,
    canvasSize: CGSize
  ) -> CIImage {
    let extent = CGRect(origin: .zero, size: canvasSize)

    // Create a rounded rectangle mask using CGContext
    let maskSize = canvasSize
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

    // Scale corner radius to the displayed video frame, not the whole canvas.
    let scaleFactor = min(roundedRect.width, roundedRect.height) / min(canvasSize.width, canvasSize.height)
    let scaledCornerRadius = cornerRadius * scaleFactor

    // Clamp corner radius to prevent visual artifacts (max = half of smaller dimension)
    let maxRadius = min(roundedRect.width, roundedRect.height) / 2
    let clampedCornerRadius = min(scaledCornerRadius, maxRadius)

    // Draw white rounded rectangle (mask)
    cgContext.setFillColor(CGColor.white)
    let path = CGPath(
      roundedRect: roundedRect,
      cornerWidth: clampedCornerRadius,
      cornerHeight: clampedCornerRadius,
      transform: nil
    )
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

  private func placeImageOnCanvas(_ image: CIImage, canvasSize: CGSize, fittedRect: CGRect) -> CIImage {
    let normalized = image.transformed(
      by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y)
    )
    let scale = min(
      fittedRect.width / max(image.extent.width, 1),
      fittedRect.height / max(image.extent.height, 1)
    )
    let transformed = normalized
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .transformed(by: CGAffineTransform(translationX: fittedRect.origin.x, y: fittedRect.origin.y))

    let canvasRect = CGRect(origin: .zero, size: canvasSize)
    let clearCanvas = CIImage(color: .clear).cropped(to: canvasRect)
    return transformed.composited(over: clearCanvas).cropped(to: canvasRect)
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
      guard let image = loadWallpaperImage(from: url) else {
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
      guard let image = loadWallpaperImage(from: url) else {
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

  private func loadWallpaperImage(from url: URL) -> CIImage? {
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return CIImage(contentsOf: url)
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
    renderSize _: CGSize
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
    guard let renderContext else { return nil }
    guard let outputBuffer = renderContext.newPixelBuffer() else { return nil }

    // Render to output buffer
    ciContext.render(scaledImage, to: outputBuffer)

    return outputBuffer
  }
}
