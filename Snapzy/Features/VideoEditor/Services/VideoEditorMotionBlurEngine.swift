//
//  VideoEditorMotionBlurEngine.swift
//  Snapzy
//
//  True physical shutter-angle motion blur powered by a single-pass Metal compute
//  `CIImageProcessorKernel` (temporal sub-frame accumulation along the exact camera
//  zoom/pan/arc trajectory with raised-cosine shutter weighting).
//  Also provides zero-flicker analytical preview parameters and curved cursor shutter taps.
//

import CoreGraphics
import CoreImage
import Foundation
import Metal
import simd

nonisolated enum VideoEditorMotionBlurEngine {
  /// One normalized top-left UV viewport sample inside the camera shutter exposure window.
  struct ShutterTap: Equatable, Sendable {
    /// `(uvMinX, uvMinY, uvSpanX, uvSpanY)` in top-left normalized texture UV coordinates.
    let uvMinX: Float
    let uvMinY: Float
    let uvSpanX: Float
    let uvSpanY: Float
    /// Raised-cosine shutter weight (all tap weights sum to 1.0).
    let weight: Float
  }

  /// Complete physical shutter integration plan for one rendered frame.
  struct ShutterPlan: Equatable, Sendable {
    static let inactive = ShutterPlan(
      taps: [],
      maxCornerTravelPx: 0,
      panVelocityPx: .zero,
      panAngleRadians: 0,
      zoomDeltaRatio: 0,
      zoomCenterNormalized: CGPoint(x: 0.5, y: 0.5)
    )

    let taps: [ShutterTap]
    let maxCornerTravelPx: CGFloat
    let panVelocityPx: CGVector
    let panAngleRadians: CGFloat
    let zoomDeltaRatio: CGFloat
    /// Top-left normalized optical focus point inside the rendered viewport.
    let zoomCenterNormalized: CGPoint

    var isActive: Bool {
      taps.count > 1 && maxCornerTravelPx >= 1.8
    }
  }

  /// Analytical, jitter-free Core Animation filter parameters for 60fps live preview.
  struct PreviewFilterParams: Equatable, Sendable {
    static let none = PreviewFilterParams(
      panRadius: 0,
      panAngleRadians: 0,
      zoomAmount: 0,
      zoomCenterNormalized: CGPoint(x: 0.5, y: 0.5)
    )

    let panRadius: CGFloat
    let panAngleRadians: CGFloat
    let zoomAmount: CGFloat
    /// Normalized top-left optical focus point in the preview frame.
    let zoomCenterNormalized: CGPoint

    var isActive: Bool {
      panRadius > 0.35 || zoomAmount > 0.35
    }
  }

  /// Backwards-compatible summary vector for diagnostics and tests.
  struct CameraMotionVector: Equatable, Sendable {
    static let zero = CameraMotionVector(
      panVelocityPx: .zero,
      panRadius: 0,
      panAngleRadians: 0,
      zoomBlurAmount: 0,
      zoomCenterCI: .zero
    )

    let panVelocityPx: CGVector
    let panRadius: CGFloat
    let panAngleRadians: CGFloat
    let zoomBlurAmount: CGFloat
    let zoomCenterCI: CGPoint

    var isActive: Bool {
      panRadius > 0.01 || zoomBlurAmount > 0.01
    }
  }

  /// Instantaneous cursor velocity motion blur parameters.
  struct CursorMotionVector: Equatable, Sendable {
    let radius: CGFloat
    let angleRadians: CGFloat
  }

  private static let minCornerTravelPx: CGFloat = 1.8
  private static let cursorDeadZonePx: CGFloat = 2.2
  private static let referenceDimension: CGFloat = 1080.0
  private static let maxShutterTaps = 35

  // MARK: - True Physical Shutter Plan

  /// Samples the continuous camera trajectory across the physical shutter window
  /// `[time - shutterHalf ... time + shutterHalf]` to compute exact sub-frame UV viewports
  /// and raised-cosine shutter weights.
  static func shutterPlan(
    at time: TimeInterval,
    frameDuration: TimeInterval,
    frameSize: CGSize,
    segments: [ZoomSegment],
    autoFocusPaths: [UUID: [AutoFocusCameraSample]],
    transitionDuration: TimeInterval,
    settings: VideoEditorMotionBlurSettings
  ) -> ShutterPlan {
    let strength = settings.effectiveCameraStrength
    guard strength > 0.001,
          frameSize.width > 1,
          frameSize.height > 1,
          !segments.isEmpty
    else {
      return .inactive
    }

    let dt = min(max(frameDuration, 1.0 / 120.0), 1.0 / 15.0)
    // 0.25*dt (90° crisp) → 0.58*dt (210° silky cinema) → 0.90*dt (324° liquid shutter).
    let shutterHalf = dt * (0.25 + 0.65 * strength)

    let tPrev = max(0, time - shutterHalf)
    let tNext = time + shutterHalf

    let prevState = VideoEditorAutoFocusEngine.resolvedCameraState(
      at: tPrev,
      segments: segments,
      autoFocusPaths: autoFocusPaths,
      transitionDuration: transitionDuration
    )
    let nowState = VideoEditorAutoFocusEngine.resolvedCameraState(
      at: time,
      segments: segments,
      autoFocusPaths: autoFocusPaths,
      transitionDuration: transitionDuration
    )
    let nextState = VideoEditorAutoFocusEngine.resolvedCameraState(
      at: tNext,
      segments: segments,
      autoFocusPaths: autoFocusPaths,
      transitionDuration: transitionDuration
    )

    if prevState.zoomLevel <= 1.0001, nowState.zoomLevel <= 1.0001, nextState.zoomLevel <= 1.0001 {
      return .inactive
    }

    let cropPrev = ZoomCalculator.calculateCropRect(
      center: prevState.center,
      zoomLevel: prevState.zoomLevel,
      frameSize: frameSize
    )
    let cropNow = ZoomCalculator.calculateCropRect(
      center: nowState.center,
      zoomLevel: nowState.zoomLevel,
      frameSize: frameSize
    )
    let cropNext = ZoomCalculator.calculateCropRect(
      center: nextState.center,
      zoomLevel: nextState.zoomLevel,
      frameSize: frameSize
    )

    // Measure exact maximum corner pixel displacement across the full shutter exposure.
    let effectiveZoom = max(nowState.zoomLevel, 1.0)
    let dLeft = abs(cropNext.minX - cropPrev.minX) * effectiveZoom
    let dRight = abs(cropNext.maxX - cropPrev.maxX) * effectiveZoom
    let dBottom = abs(cropNext.minY - cropPrev.minY) * effectiveZoom
    let dTop = abs(cropNext.maxY - cropPrev.maxY) * effectiveZoom
    let maxCornerTravel = max(hypot(dLeft, dBottom), hypot(dRight, dTop), hypot(dLeft, dTop), hypot(dRight, dBottom))

    let dxCenter = (cropNext.midX - cropPrev.midX) * effectiveZoom
    let dyCenter = (cropNext.midY - cropPrev.midY) * effectiveZoom
    let panAngle = atan2(dyCenter, dxCenter)
    let zoomRatio = abs(nextState.zoomLevel - prevState.zoomLevel) / max(nowState.zoomLevel, 1.0)

    let focusSourceX = nowState.center.x * frameSize.width
    let focusSourceY = (1.0 - nowState.center.y) * frameSize.height
    let normFocusX = ((focusSourceX - cropNow.minX) / max(cropNow.width, 1)).clampedUnit
    let normFocusYTopLeft = (1.0 - ((focusSourceY - cropNow.minY) / max(cropNow.height, 1))).clampedUnit

    let resolutionScale = max(0.5, min(frameSize.width, frameSize.height) / referenceDimension)
    guard maxCornerTravel >= minCornerTravelPx * resolutionScale else {
      return ShutterPlan(
        taps: [],
        maxCornerTravelPx: maxCornerTravel,
        panVelocityPx: CGVector(dx: dxCenter, dy: dyCenter),
        panAngleRadians: panAngle,
        zoomDeltaRatio: zoomRatio,
        zoomCenterNormalized: CGPoint(x: normFocusX, y: normFocusYTopLeft)
      )
    }

    // Adaptive odd tap count (9...35): dense continuous shutter sampling eliminates all stepping/ghosting.
    let rawTaps = Int(ceil(maxCornerTravel / (1.35 * resolutionScale))) | 1
    let tapCount = min(maxShutterTaps, max(9, rawTaps))

    var weights: [Float] = []
    weights.reserveCapacity(tapCount)
    var weightSum: Float = 0
    for i in 0 ..< tapCount {
      let u = (Double(i) / Double(tapCount - 1)) - 0.5 // -0.5 ... +0.5
      // Smooth raised-cosine shutter profile: liquid motion trails with zero hard step edges.
      let w = Float(0.35 + 0.65 * cos(Double.pi * u))
      weights.append(w)
      weightSum += w
    }

    var taps: [ShutterTap] = []
    taps.reserveCapacity(tapCount)
    let invW = 1.0 / max(frameSize.width, 1)
    let invH = 1.0 / max(frameSize.height, 1)

    for i in 0 ..< tapCount {
      let u = (Double(i) / Double(tapCount - 1)) - 0.5
      let sampleTime = max(0, time + u * 2.0 * shutterHalf)
      let state = VideoEditorAutoFocusEngine.resolvedCameraState(
        at: sampleTime,
        segments: segments,
        autoFocusPaths: autoFocusPaths,
        transitionDuration: transitionDuration
      )
      let crop = ZoomCalculator.calculateCropRect(
        center: state.center,
        zoomLevel: state.zoomLevel,
        frameSize: frameSize
      )

      // Convert Core Image bottom-left crop rect into Metal top-left normalized UV rect.
      let uvMinX = Float(crop.minX * invW)
      let uvSpanX = Float(crop.width * invW)
      let uvMinY = Float(1.0 - (crop.maxY * invH))
      let uvSpanY = Float(crop.height * invH)

      taps.append(
        ShutterTap(
          uvMinX: uvMinX,
          uvMinY: uvMinY,
          uvSpanX: uvSpanX,
          uvSpanY: uvSpanY,
          weight: weights[i] / max(weightSum, 0.0001)
        )
      )
    }

    return ShutterPlan(
      taps: taps,
      maxCornerTravelPx: maxCornerTravel,
      panVelocityPx: CGVector(dx: dxCenter, dy: dyCenter),
      panAngleRadians: panAngle,
      zoomDeltaRatio: zoomRatio,
      zoomCenterNormalized: CGPoint(x: normFocusX, y: normFocusYTopLeft)
    )
  }

  /// Renders the zoomed frame WITH true physical shutter-angle temporal accumulation in ONE Metal GPU pass.
  /// Falls back cleanly to multi-tap Core Image accumulation if Metal is unavailable.
  static func renderZoomedWithShutterMotionBlur(
    sourceImage: CIImage,
    shutterPlan: ShutterPlan
  ) -> CIImage {
    guard shutterPlan.isActive else { return sourceImage }
    let extent = sourceImage.extent
    guard !extent.isEmpty, !extent.isInfinite else { return sourceImage }

    // Primary path: single-pass Metal compute shader (up to 35 stochastic taps in < 0.5ms at 4K, tile-safe).
    if let metalOutput = try? ShutterMotionBlurProcessor.apply(
      withExtent: extent,
      inputs: [sourceImage],
      arguments: [
        ShutterMotionBlurProcessor.tapsKey: shutterPlan.taps,
        ShutterMotionBlurProcessor.fullExtentKey: extent,
      ]
    ) {
      return metalOutput.cropped(to: extent)
    }

    // Fallback path: exact Core Image weighted sub-frame affine accumulation.
    let clamped = sourceImage.clampedToExtent()
    let w = extent.width
    let h = extent.height
    var accumulated: CIImage?

    for tap in shutterPlan.taps {
      let cropW = max(CGFloat(tap.uvSpanX) * w, 1)
      let cropH = max(CGFloat(tap.uvSpanY) * h, 1)
      let cropOriginX = extent.minX + CGFloat(tap.uvMinX) * w
      // Convert top-left uvMinY back to Core Image bottom-left originY.
      let cropOriginY = extent.minY + (1.0 - CGFloat(tap.uvMinY) - CGFloat(tap.uvSpanY)) * h

      let sx = w / cropW
      let sy = h / cropH
      let tx = extent.minX - cropOriginX * sx
      let ty = extent.minY - cropOriginY * sy
      let weight = CGFloat(tap.weight)

      let transformed = clamped
        .transformed(by: CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty))
        .cropped(to: extent)
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: weight, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: weight, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: weight, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight),
        ])

      if let existing = accumulated {
        accumulated = transformed.applyingFilter("CIAdditionCompositing", parameters: [
          kCIInputBackgroundImageKey: existing,
        ])
      } else {
        accumulated = transformed
      }
    }

    return (accumulated ?? sourceImage).cropped(to: extent)
  }

  // MARK: - Analytical Camera Vector & Zero-Flicker Preview Params

  static func cameraMotion(
    at time: TimeInterval,
    frameDuration: TimeInterval,
    frameSize: CGSize,
    segments: [ZoomSegment],
    autoFocusPaths: [UUID: [AutoFocusCameraSample]],
    transitionDuration: TimeInterval,
    settings: VideoEditorMotionBlurSettings
  ) -> CameraMotionVector {
    let plan = shutterPlan(
      at: time,
      frameDuration: frameDuration,
      frameSize: frameSize,
      segments: segments,
      autoFocusPaths: autoFocusPaths,
      transitionDuration: transitionDuration,
      settings: settings
    )
    guard plan.isActive else { return .zero }

    let strength = settings.effectiveCameraStrength
    let resolutionScale = max(0.5, min(frameSize.width, frameSize.height) / referenceDimension)
    let panSpeed = hypot(plan.panVelocityPx.dx, plan.panVelocityPx.dy)
    let panRadius: CGFloat = panSpeed > 1.2 * resolutionScale
      ? min(24.0 * resolutionScale, (panSpeed - 1.2 * resolutionScale) * 0.45 * CGFloat(strength))
      : 0

    let rawZoom = plan.zoomDeltaRatio * min(frameSize.width, frameSize.height) * 0.22 * CGFloat(strength)
    let zoomAmount: CGFloat = rawZoom > 0.75 * resolutionScale
      ? min(16.0 * resolutionScale, rawZoom - 0.75 * resolutionScale)
      : 0

    let zoomCenterCI = CGPoint(
      x: plan.zoomCenterNormalized.x * frameSize.width,
      y: (1.0 - plan.zoomCenterNormalized.y) * frameSize.height
    )

    return CameraMotionVector(
      panVelocityPx: plan.panVelocityPx,
      panRadius: panRadius,
      panAngleRadians: plan.panAngleRadians,
      zoomBlurAmount: zoomAmount,
      zoomCenterCI: zoomCenterCI
    )
  }

  /// Analytical, 100% flicker-free directional + radial preview motion blur parameters.
  /// Computed purely from the smooth camera spline `t ± shutterHalf` (never from jittery playback tick deltas!).
  static func previewFilterParams(
    at time: TimeInterval,
    viewSize: CGSize,
    segments: [ZoomSegment],
    autoFocusPaths: [UUID: [AutoFocusCameraSample]],
    transitionDuration: TimeInterval,
    settings: VideoEditorMotionBlurSettings
  ) -> PreviewFilterParams {
    guard settings.effectiveCameraStrength > 0.001,
          viewSize.width > 1,
          viewSize.height > 1,
          !segments.isEmpty
    else {
      return .none
    }

    let plan = shutterPlan(
      at: time,
      frameDuration: 1.0 / 30.0,
      frameSize: viewSize,
      segments: segments,
      autoFocusPaths: autoFocusPaths,
      transitionDuration: transitionDuration,
      settings: settings
    )
    guard plan.isActive else { return .none }

    let strength = CGFloat(settings.effectiveCameraStrength)
    let panSpeed = hypot(plan.panVelocityPx.dx, plan.panVelocityPx.dy)
    let rawPan = max(0, panSpeed - 1.5) * 0.34 * strength
    let panRadius = 14.0 * CGFloat(tanh(Double(rawPan / 14.0)))

    let rawZoom = max(0, plan.zoomDeltaRatio * min(viewSize.width, viewSize.height) * 0.22 * strength - 0.8)
    let zoomAmount = 10.0 * CGFloat(tanh(Double(rawZoom / 10.0)))

    return PreviewFilterParams(
      panRadius: panRadius > 0.35 ? panRadius : 0,
      panAngleRadians: plan.panAngleRadians,
      zoomAmount: zoomAmount > 0.35 ? zoomAmount : 0,
      zoomCenterNormalized: plan.zoomCenterNormalized
    )
  }

  /// Edge-safe Core Image directional + radial blur helper (kept for diagnostics & unit tests).
  static func applyCameraMotionBlur(
    to image: CIImage,
    motion: CameraMotionVector
  ) -> CIImage {
    guard motion.isActive else { return image }
    let extent = image.extent
    guard !extent.isEmpty, !extent.isInfinite else { return image }

    var result = image
    if motion.panRadius > 0.01 {
      result = result
        .clampedToExtent()
        .applyingFilter("CIMotionBlur", parameters: [
          kCIInputRadiusKey: motion.panRadius,
          kCIInputAngleKey: motion.panAngleRadians,
        ])
        .cropped(to: extent)
    }
    if motion.zoomBlurAmount > 0.01 {
      let center = CIVector(
        x: extent.minX + motion.zoomCenterCI.x,
        y: extent.minY + motion.zoomCenterCI.y
      )
      result = result
        .clampedToExtent()
        .applyingFilter("CIZoomBlur", parameters: [
          kCIInputCenterKey: center,
          "inputAmount": motion.zoomBlurAmount,
        ])
        .cropped(to: extent)
    }
    return result
  }

  // MARK: - Cursor Shutter Motion Blur

  /// Computes directional blur parameters for a moving cursor sprite (used by tests and diagnostics).
  static func cursorMotion(
    velocityNormalizedPerSec velocity: CGVector,
    frameDuration: TimeInterval,
    frameSize: CGSize,
    settings: VideoEditorMotionBlurSettings
  ) -> CursorMotionVector? {
    let strength = settings.effectiveCursorStrength
    guard strength > 0.001, frameSize.width > 1, frameSize.height > 1 else { return nil }

    let dt = min(max(frameDuration, 1.0 / 120.0), 1.0 / 15.0)
    let dxPx = velocity.dx * frameSize.width * CGFloat(dt)
    let dyPx = -velocity.dy * frameSize.height * CGFloat(dt)
    let speedPx = hypot(dxPx, dyPx)

    let resolutionScale = max(0.5, min(frameSize.width, frameSize.height) / referenceDimension)
    let threshold = cursorDeadZonePx * resolutionScale
    guard speedPx > threshold else { return nil }

    let rawRadius = (speedPx - threshold) * CGFloat(strength) * 0.42
    let maxRadius: CGFloat = 15.0 * resolutionScale
    let radius = maxRadius * CGFloat(tanh(Double(rawRadius / maxRadius)))
    guard radius > 0.35 else { return nil }

    return CursorMotionVector(
      radius: radius,
      angleRadians: atan2(dyPx, dxPx)
    )
  }

  /// Computes exact temporal sub-frame offsets & raised-cosine weights along the cursor's
  /// actual curved path inside `[sourceTime - shutterHalf ... sourceTime + shutterHalf]`.
  static func cursorShutterTaps(
    at sourceTime: TimeInterval,
    frameDuration: TimeInterval,
    frameSize: CGSize,
    resolver: VideoEditorCursorResolver,
    settings: VideoEditorMotionBlurSettings
  ) -> [(position: CGPoint, weight: CGFloat)] {
    let strength = settings.effectiveCursorStrength
    guard strength > 0.001, frameSize.width > 1, frameSize.height > 1 else { return [] }

    let dt = min(max(frameDuration, 1.0 / 120.0), 1.0 / 15.0)
    let shutterHalf = dt * (0.22 + 0.56 * strength)
    let t0 = max(0, sourceTime - shutterHalf)
    let t1 = sourceTime + shutterHalf

    guard let f0 = resolver.resolve(sourceTime: t0),
          let f1 = resolver.resolve(sourceTime: t1),
          f0.opacity > 0, f1.opacity > 0
    else {
      return []
    }

    let travelPx = hypot(
      (f1.position.x - f0.position.x) * frameSize.width,
      (f1.position.y - f0.position.y) * frameSize.height
    )
    let resolutionScale = max(0.5, min(frameSize.width, frameSize.height) / referenceDimension)
    guard travelPx >= cursorDeadZonePx * resolutionScale else { return [] }

    let count = min(13, max(5, Int(ceil(travelPx / (2.5 * resolutionScale))) | 1))
    var raw: [(position: CGPoint, weight: CGFloat)] = []
    raw.reserveCapacity(count)
    var sum: CGFloat = 0

    for i in 0 ..< count {
      let u = (Double(i) / Double(count - 1)) - 0.5
      let sampleT = max(0, sourceTime + u * 2.0 * shutterHalf)
      guard let frame = resolver.resolve(sourceTime: sampleT), frame.opacity > 0 else { continue }
      let w = CGFloat(0.35 + 0.65 * cos(Double.pi * u))
      raw.append((frame.position, w))
      sum += w
    }

    guard raw.count >= 2, sum > 0.0001 else { return [] }
    return raw.map { ($0.position, $0.weight / sum) }
  }
  // MARK: - Shared Metal Shutter Compute Dispatch (Export + Live Preview)

  /// Encodes the single-pass physical shutter-angle Metal compute kernel directly onto `encoder`.
  /// Used by BOTH Export (`ShutterMotionBlurProcessor`) and Full-Retina Live Preview (`MetalShutterPreviewView`).
  @discardableResult
  static func encodeShutterCompute(
    encoder: MTLComputeCommandEncoder,
    device: MTLDevice,
    sourceTexture: MTLTexture,
    outputTexture: MTLTexture,
    taps: [ShutterTap],
    outOrigin: SIMD2<Float> = .zero,
    fullSize: SIMD2<Float>? = nil,
    flipY: Bool = false
  ) -> Bool {
    ShutterMotionBlurProcessor.encode(
      encoder: encoder,
      device: device,
      sourceTexture: sourceTexture,
      outputTexture: outputTexture,
      taps: taps,
      outOrigin: outOrigin,
      fullSize: fullSize ?? SIMD2<Float>(Float(outputTexture.width), Float(outputTexture.height)),
      flipY: flipY
    )
  }
}

// MARK: - Single-Pass Metal Compute Shutter Motion Blur Processor

private nonisolated final class ShutterMotionBlurProcessor: CIImageProcessorKernel {
  nonisolated static let tapsKey = "shutterTaps"
  nonisolated static let fullExtentKey = "fullExtent"

  private struct MetalTap {
    var uvRect: SIMD4<Float>
    var weight: Float
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
  }

  private struct MetalUniforms {
    var tapCount: UInt32
    var flipY: UInt32
    var outOrigin: SIMD2<Float>
    var fullSize: SIMD2<Float>
    var pad0: Float = 0
    var pad1: Float = 0
  }

  private static let metalSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct MetalTap {
    float4 uvRect;
    float weight;
    float pad0;
    float pad1;
    float pad2;
  };

  struct MetalUniforms {
    uint tapCount;
    uint flipY;
    float2 outOrigin;
    float2 fullSize;
    float pad0;
    float pad1;
  };

  // Interleaved Gradient Noise (Jimenez 2014): decorrelates discrete shutter taps into
  // a 100% continuous, ghost-free optical streak without visible banding on Retina UI text.
  inline float ign(float2 p) {
    return fract(52.9829189f * fract(dot(p, float2(0.06711056f, 0.00583715f))));
  }

  kernel void shutterMotionBlurKernel(
    texture2d<float, access::sample> sourceTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant MetalUniforms &uniforms [[buffer(0)]],
    constant MetalTap *taps [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
  ) {
    uint outW = outTex.get_width();
    uint outH = outTex.get_height();
    if (gid.x >= outW || gid.y >= outH) { return; }

    constexpr sampler linearClamp(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 globalPos = uniforms.outOrigin + float2(gid) + 0.5f;
    float2 uvOut = globalPos / max(uniforms.fullSize, float2(1.0f));
    if (uniforms.flipY != 0u) {
      uvOut.y = 1.0f - uvOut.y;
    }

    uint n = uniforms.tapCount;
    float jitter = (n > 2u) ? (ign(globalPos) - 0.5f) : 0.0f;
    float maxIdx = float(n - 1u);

    float4 accum = float4(0.0f);
    float weightSum = 0.0f;
    for (uint i = 0; i < n; ++i) {
      float f = clamp(float(i) + jitter, 0.0f, maxIdx);
      uint i0 = uint(floor(f));
      uint i1 = min(i0 + 1u, n - 1u);
      float frac = f - float(i0);

      float4 r = mix(taps[i0].uvRect, taps[i1].uvRect, frac);
      float w = mix(taps[i0].weight, taps[i1].weight, frac);

      float2 uvSrc = float2(r.x + uvOut.x * r.z, r.y + uvOut.y * r.w);
      if (uniforms.flipY != 0u) {
        uvSrc.y = 1.0f - uvSrc.y;
      }
      accum += sourceTex.sample(linearClamp, uvSrc) * w;
      weightSum += w;
    }

    outTex.write(accum / max(weightSum, 0.0001f), gid);
  }
  """

  private static let pipelineLock = NSLock()
  private static var cachedDeviceID: UInt64 = 0
  private static var cachedPipeline: MTLComputePipelineState?

  private static func pipeline(for device: MTLDevice) -> MTLComputePipelineState? {
    pipelineLock.lock()
    defer { pipelineLock.unlock() }
    if cachedDeviceID == device.registryID, let existing = cachedPipeline {
      return existing
    }
    guard let library = try? device.makeLibrary(source: metalSource, options: nil),
          let function = library.makeFunction(name: "shutterMotionBlurKernel"),
          let state = try? device.makeComputePipelineState(function: function)
    else {
      return nil
    }
    cachedDeviceID = device.registryID
    cachedPipeline = state
    return state
  }

  static func encode(
    encoder: MTLComputeCommandEncoder,
    device: MTLDevice,
    sourceTexture: MTLTexture,
    outputTexture: MTLTexture,
    taps: [VideoEditorMotionBlurEngine.ShutterTap],
    outOrigin: SIMD2<Float>,
    fullSize: SIMD2<Float>,
    flipY: Bool
  ) -> Bool {
    guard !taps.isEmpty,
          let computePipeline = pipeline(for: device)
    else {
      return false
    }

    var uniforms = MetalUniforms(
      tapCount: UInt32(taps.count),
      flipY: flipY ? 1 : 0,
      outOrigin: outOrigin,
      fullSize: fullSize
    )
    let metalTaps = taps.map { tap in
      MetalTap(
        uvRect: SIMD4<Float>(tap.uvMinX, tap.uvMinY, tap.uvSpanX, tap.uvSpanY),
        weight: tap.weight
      )
    }

    encoder.setComputePipelineState(computePipeline)
    encoder.setTexture(sourceTexture, index: 0)
    encoder.setTexture(outputTexture, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 0)
    metalTaps.withUnsafeBytes { rawBuffer in
      if let base = rawBuffer.baseAddress {
        encoder.setBytes(base, length: rawBuffer.count, index: 1)
      }
    }

    let w = max(1, computePipeline.threadExecutionWidth)
    let h = max(1, computePipeline.maxTotalThreadsPerThreadgroup / w)
    let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
    let threadsPerGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
    return true
  }

  override class var synchronizeInputs: Bool { false }
  override class var outputFormat: CIFormat { .RGBAh }
  override class func formatForInput(at _: Int32) -> CIFormat { .RGBAh }

  override class func roi(
    forInput _: Int32,
    arguments: [String: Any]?,
    outputRect: CGRect
  ) -> CGRect {
    // Always request the full un-tiled source frame so every shutter tap UV is resident even when
    // Core Image tiles 3360x2100 / 4K outputs into sub-regions!
    if let fullExtent = arguments?[fullExtentKey] as? CGRect, !fullExtent.isEmpty {
      return fullExtent
    }
    return outputRect
  }

  override class func process(
    with inputs: [CIImageProcessorInput]?,
    arguments: [String: Any]?,
    output: CIImageProcessorOutput
  ) throws {
    guard let input = inputs?.first,
          let sourceTex = input.metalTexture,
          let outTex = output.metalTexture,
          let commandBuffer = output.metalCommandBuffer,
          let taps = arguments?[tapsKey] as? [VideoEditorMotionBlurEngine.ShutterTap],
          !taps.isEmpty,
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw NSError(domain: "Snapzy.MotionBlur", code: 1)
    }

    let fullExtent = (arguments?[fullExtentKey] as? CGRect) ?? input.region
    // Core Image Metal processor textures are top-down (`gid.y == 0` is `region.maxY`),
    // matching `CVPixelBuffer` and `MTKView` top-left UV coordinates directly (`flipY: false`).
    let outOrigin = SIMD2<Float>(
      Float(output.region.minX - fullExtent.minX),
      Float(fullExtent.maxY - output.region.maxY)
    )
    let fullSize = SIMD2<Float>(
      Float(max(fullExtent.width, 1)),
      Float(max(fullExtent.height, 1))
    )

    let ok = encode(
      encoder: encoder,
      device: commandBuffer.device,
      sourceTexture: sourceTex,
      outputTexture: outTex,
      taps: taps,
      outOrigin: outOrigin,
      fullSize: fullSize,
      flipY: false
    )
    encoder.endEncoding()
    if !ok {
      throw NSError(domain: "Snapzy.MotionBlur", code: 2)
    }
  }
}

private nonisolated extension CGFloat {
  var clampedUnit: CGFloat {
    Swift.min(Swift.max(self, 0), 1)
  }
}
