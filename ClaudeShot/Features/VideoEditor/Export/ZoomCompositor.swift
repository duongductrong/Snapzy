//
//  ZoomCompositor.swift
//  ClaudeShot
//
//  Applies zoom effects to video during export using AVVideoComposition
//

import AVFoundation
import CoreImage

/// Compositor that applies zoom effects during video export
class ZoomCompositor {

  // MARK: - Properties

  private let zooms: [ZoomSegment]
  private let renderSize: CGSize
  private let transitionDuration: TimeInterval

  // MARK: - Initialization

  init(
    zooms: [ZoomSegment],
    renderSize: CGSize,
    transitionDuration: TimeInterval = 0.3
  ) {
    self.zooms = zooms.filter { $0.isEnabled }
    self.renderSize = renderSize
    self.transitionDuration = transitionDuration
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
      transitionDuration: transitionDuration
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

    var errorDescription: String? {
      switch self {
      case .noVideoTrack:
        return "No video track found in asset"
      case .compositionFailed:
        return "Failed to create zoom composition"
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
    transitionDuration: TimeInterval
  ) {
    self.timeRange = timeRange
    self.zooms = zooms
    self.trackID = trackID
    self.renderSize = renderSize
    self.transitionDuration = transitionDuration
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

  // MARK: - AVVideoCompositing Protocol

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    queue.sync {
      renderContext = newRenderContext
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
      print("❌ [Compositor] Frame \(frameCount): No source frame for trackID \(instruction.trackID)")
      print("❌ [Compositor] Available track IDs: \(request.sourceTrackIDs)")
      request.finish(with: ZoomCompositor.ZoomCompositorError.compositionFailed)
      return
    }

    if frameCount == 1 || frameCount % 30 == 0 {
      print("🎥 [Compositor] Processing frame \(frameCount) at time \(String(format: "%.2f", currentTime))s")
    }

    // Find active zoom at current time
    let activeZoom = instruction.zooms.first { $0.contains(time: currentTime) }

    // If no zoom active, pass through original frame
    guard let zoom = activeZoom else {
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    if frameCount == 1 || frameCount % 30 == 0 {
      print("🎥 [Compositor] Frame \(frameCount): Applying zoom level \(zoom.zoomLevel)x")
    }

    // Calculate zoom parameters
    let interpolated = ZoomCalculator.interpolateZoom(
      segment: zoom,
      currentTime: currentTime,
      transitionDuration: instruction.transitionDuration
    )

    // If effectively no zoom, pass through
    if interpolated.level < 1.01 {
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    // Apply zoom effect
    guard let outputBuffer = applyZoom(
      to: sourceBuffer,
      zoomLevel: interpolated.level,
      center: interpolated.center,
      renderSize: instruction.renderSize
    ) else {
      print("❌ [Compositor] Frame \(frameCount): applyZoom returned nil, passing through")
      request.finish(withComposedVideoFrame: sourceBuffer)
      return
    }

    request.finish(withComposedVideoFrame: outputBuffer)
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
