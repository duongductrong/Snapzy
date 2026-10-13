//
//  AnnotateBlurCacheManager.swift
//  Snapzy
//
//  Manages cached blur images for performance optimization
//

import AppKit
import CoreGraphics

/// Manages cached blur images for annotation items.
///
/// Interactive rendering must never block the canvas draw pass. Callers can ask for a
/// non-blocking lookup that returns an existing exact/approximate image immediately and
/// schedules a bounded background render when the cache is stale.
final class BlurCacheManager {
  var onRenderCompleted: ((UUID, CGRect) -> Void)?

  private var cache: [UUID: CacheEntry] = [:]
  private var inFlightRenders: [UUID: InFlightRender] = [:]
  private var pendingRenders: [UUID: RenderRequest] = [:]
  private var accessCounter: UInt64 = 0

  private let maxCachedPixelsPerBlur: CGFloat = 1_600_000
  private let maxTotalCachedPixels: Int = 8_000_000

  // Keep: nonisolated on purpose, like `CanvasInteractionBridge.deinit`; the
  // synthesized MainActor deinit can abort on macOS 15.4+ runtimes.
  deinit {}

  private struct CacheEntry {
    let image: CGImage
    let bounds: CGRect
    let blurType: BlurType
    let effectValue: CGFloat
    let sourceSignature: SourceSignature
    let cacheScale: CGFloat
    let cost: Int
    var lastAccess: UInt64
  }

  private struct InFlightRender {
    let token: UUID
    let descriptor: RenderDescriptor
  }

  private struct RenderRequest {
    let annotationId: UUID
    let descriptor: RenderDescriptor
    let sourceCGImage: CGImage
    let sourceSize: CGSize
    let quality: BlurRenderQuality
  }

  private struct RenderDescriptor {
    let bounds: CGRect
    let blurType: BlurType
    let effectValue: CGFloat
    let sourceSignature: SourceSignature
    let cacheScale: CGFloat

    func matches(_ other: RenderDescriptor) -> Bool {
      bounds.equalTo(other.bounds) &&
        blurType == other.blurType &&
        effectValue == other.effectValue &&
        sourceSignature == other.sourceSignature &&
        cacheScale == other.cacheScale
    }
  }

  private struct CachedLookup {
    let image: CGImage
    let isExact: Bool
  }

  private struct SourceSignature: Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let pointWidth: Int
    let pointHeight: Int
  }

  /// Get or create cached blur image for annotation.
  /// - Parameters:
  ///   - renderSynchronously: Keep true for export/tests. The editor should pass false.
  /// - Returns: Cached CGImage if available, a sync-rendered image if requested, or nil after scheduling async work.
  func getCachedBlur(
    for annotationId: UUID,
    bounds: CGRect,
    sourceImage: NSImage,
    blurType: BlurType = .pixelated,
    effectValue: CGFloat = BlurEffectRenderer.defaultPixelSize,
    allowApproximateReuse: Bool = false,
    renderSynchronously: Bool = true,
    quality: BlurRenderQuality = .settled,
    resolvedSourceCGImage: CGImage? = nil
  ) -> CGImage? {
    let normalizedBounds = bounds.standardized
    guard let sourceCGImage = resolvedSourceCGImage ?? sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

    let sourceSignature = makeSourceSignature(for: sourceImage, cgImage: sourceCGImage)
    let cacheScale = renderScale(for: sourceImage, cgImage: sourceCGImage, bounds: normalizedBounds)

    let descriptor = RenderDescriptor(
      bounds: normalizedBounds,
      blurType: blurType,
      effectValue: effectValue,
      sourceSignature: sourceSignature,
      cacheScale: cacheScale
    )
    let request = RenderRequest(
      annotationId: annotationId,
      descriptor: descriptor,
      sourceCGImage: sourceCGImage,
      sourceSize: sourceImage.size,
      quality: quality
    )

    if let lookup = cachedImage(
      for: annotationId,
      descriptor: descriptor,
      allowApproximateReuse: allowApproximateReuse
    ) {
      if !lookup.isExact, !renderSynchronously {
        scheduleAsyncRender(request)
      }
      return lookup.image
    }

    if renderSynchronously {
      guard let rendered = Self.renderBlurToImage(
        bounds: descriptor.bounds,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceImage.size,
        blurType: descriptor.blurType,
        effectValue: descriptor.effectValue,
        cacheScale: descriptor.cacheScale,
        quality: quality
      ) else { return nil }

      store(
        rendered,
        for: annotationId,
        descriptor: descriptor
      )
      return rendered
    }

    scheduleAsyncRender(request)
    return nil
  }

  /// Invalidate cache for annotation (call on bounds/source/effect change).
  func invalidate(id: UUID) {
    cache.removeValue(forKey: id)
    inFlightRenders.removeValue(forKey: id)
    pendingRenders.removeValue(forKey: id)
  }

  /// Clear all cache (call on image change).
  func clearAll() {
    cache.removeAll()
    inFlightRenders.removeAll()
    pendingRenders.removeAll()
  }

  /// Check if cache exists for annotation.
  func hasCachedBlur(for annotationId: UUID) -> Bool {
    cache[annotationId] != nil
  }

  private func cachedImage(
    for annotationId: UUID,
    descriptor: RenderDescriptor,
    allowApproximateReuse: Bool
  ) -> CachedLookup? {
    guard var entry = cache[annotationId],
          entry.blurType == descriptor.blurType,
          entry.effectValue == descriptor.effectValue,
          entry.sourceSignature == descriptor.sourceSignature else {
      return nil
    }

    let exactScale = entry.cacheScale == descriptor.cacheScale
    let exactBounds = entry.bounds.equalTo(descriptor.bounds)
    let isExact = exactScale && exactBounds
    guard isExact || allowApproximateReuse else { return nil }

    accessCounter &+= 1
    entry.lastAccess = accessCounter
    cache[annotationId] = entry
    return CachedLookup(image: entry.image, isExact: isExact)
  }

  private func scheduleAsyncRender(_ request: RenderRequest) {
    if let inFlight = inFlightRenders[request.annotationId] {
      guard !inFlight.descriptor.matches(request.descriptor) else { return }
      pendingRenders[request.annotationId] = request
      return
    }

    startAsyncRender(request)
  }

  private func startAsyncRender(_ request: RenderRequest) {
    let token = UUID()
    inFlightRenders[request.annotationId] = InFlightRender(
      token: token,
      descriptor: request.descriptor
    )

    DispatchQueue.global(qos: .userInitiated).async { [request] in
      let rendered = Self.renderBlurToImage(
        bounds: request.descriptor.bounds,
        sourceCGImage: request.sourceCGImage,
        sourceSize: request.sourceSize,
        blurType: request.descriptor.blurType,
        effectValue: request.descriptor.effectValue,
        cacheScale: request.descriptor.cacheScale,
        quality: request.quality
      )

      DispatchQueue.main.async { [weak self] in
        guard let self,
              let current = inFlightRenders[request.annotationId],
              current.token == token else { return }
        inFlightRenders.removeValue(forKey: request.annotationId)

        if let rendered {
          store(
            rendered,
            for: request.annotationId,
            descriptor: request.descriptor
          )
          onRenderCompleted?(request.annotationId, request.descriptor.bounds)
        }

        if let pendingRequest = pendingRenders.removeValue(forKey: request.annotationId) {
          startAsyncRender(pendingRequest)
        }
      }
    }
  }

  private static func renderBlurToImage(
    bounds: CGRect,
    sourceCGImage: CGImage,
    sourceSize: CGSize,
    blurType: BlurType,
    effectValue: CGFloat,
    cacheScale: CGFloat,
    quality: BlurRenderQuality
  ) -> CGImage? {
    let width = Int(ceil(bounds.width * cacheScale))
    let height = Int(ceil(bounds.height * cacheScale))
    guard width > 0, height > 0 else { return nil }

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.scaleBy(x: cacheScale, y: cacheScale)
    let localRegion = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

    switch blurType {
    case .pixelated:
      BlurEffectRenderer.drawPixelatedRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        pixelSize: effectValue
      )
    case .gaussian:
      BlurEffectRenderer.drawGaussianRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        radius: Double(effectValue),
        quality: quality
      )
    case .hexagonal:
      BlurEffectRenderer.drawHexagonalRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        scale: Double(effectValue),
        quality: quality
      )
    case .crystallized:
      BlurEffectRenderer.drawCrystallizedRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        radius: Double(effectValue),
        quality: quality
      )
    case .pointillism:
      BlurEffectRenderer.drawPointillismRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        radius: Double(effectValue),
        quality: quality
      )
    case .halftone:
      BlurEffectRenderer.drawHalftoneRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        width: Double(effectValue),
        quality: quality
      )
    case .tape:
      BlurEffectRenderer.drawTapeRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        patternSpacing: Double(effectValue),
        quality: quality
      )
    case .washi:
      BlurEffectRenderer.drawWashiRegion(
        in: context,
        sourceCGImage: sourceCGImage,
        sourceSize: sourceSize,
        sourceRegion: bounds,
        destRegion: localRegion,
        patternSpacing: Double(effectValue),
        quality: quality
      )
    }

    return context.makeImage()
  }

  private func store(
    _ image: CGImage,
    for annotationId: UUID,
    descriptor: RenderDescriptor
  ) {
    accessCounter &+= 1
    let cost = max(1, image.width * image.height)
    cache[annotationId] = CacheEntry(
      image: image,
      bounds: descriptor.bounds,
      blurType: descriptor.blurType,
      effectValue: descriptor.effectValue,
      sourceSignature: descriptor.sourceSignature,
      cacheScale: descriptor.cacheScale,
      cost: cost,
      lastAccess: accessCounter
    )
    trimCacheIfNeeded(protectedId: annotationId)
  }

  private func trimCacheIfNeeded(protectedId: UUID) {
    while totalCacheCost > maxTotalCachedPixels,
          let victim = cache
          .filter({ $0.key != protectedId })
          .min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
      cache.removeValue(forKey: victim)
    }
  }

  private var totalCacheCost: Int {
    cache.values.reduce(0) { $0 + $1.cost }
  }

  private func makeSourceSignature(for sourceImage: NSImage, cgImage: CGImage) -> SourceSignature {
    SourceSignature(
      pixelWidth: cgImage.width,
      pixelHeight: cgImage.height,
      pointWidth: Int(sourceImage.size.width.rounded(.toNearestOrAwayFromZero)),
      pointHeight: Int(sourceImage.size.height.rounded(.toNearestOrAwayFromZero))
    )
  }

  private func renderScale(for sourceImage: NSImage, cgImage: CGImage, bounds: CGRect) -> CGFloat {
    guard sourceImage.size.width > 0 else { return 1 }

    let baseScale = max(1, CGFloat(cgImage.width) / sourceImage.size.width)
    let requestedPixelArea = bounds.width * bounds.height * baseScale * baseScale
    guard requestedPixelArea > maxCachedPixelsPerBlur else { return baseScale }

    let areaScale = sqrt(maxCachedPixelsPerBlur / requestedPixelArea)
    let adaptiveScale = baseScale * areaScale
    return max(1, min(baseScale, adaptiveScale))
  }
}
