//
//  AnnotateExporter.swift
//  Snapzy
//
//  Export functionality for annotated images
//

import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Handles exporting annotated images
@MainActor
final class AnnotateExporter {

  static func saveAs(state: AnnotateState, closeWindow: Bool = true) {
    DiagnosticLogger.shared.log(.info, .annotate, "Save As dialog opened")
    guard state.hasImage else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png, .jpeg, .webP]
    panel.nameFieldStringValue = generateFileName(from: state.sourceURL, isCombine: state.isCombineMode)
    panel.canCreateDirectories = true

    if panel.runModal() == .OK, let url = panel.url {
      guard confirmTransparencyLossIfNeeded(state: state, targetURL: url) else { return }
      let didSave = save(state: state, to: url)
      if didSave && closeWindow {
        NSApp.keyWindow?.close()
      }
    }
  }

  /// Save annotated image to original file location (overwrite)
  @discardableResult
  static func saveToOriginal(state: AnnotateState) -> Bool {
    guard let sourceURL = state.sourceURL else { return false }
    guard confirmTransparencyLossIfNeeded(state: state, targetURL: sourceURL) else { return false }
    DiagnosticLogger.shared.log(.info, .annotate, "Save to original", context: ["file": sourceURL.lastPathComponent])
    return save(state: state, to: sourceURL)
  }

  @discardableResult
  static func save(state: AnnotateState, to url: URL) -> Bool {
    DiagnosticLogger.shared.log(.info, .annotate, "Save started", context: [
      "file": url.lastPathComponent,
      "format": url.pathExtension,
      "annotations": "\(state.annotations.count)"
    ])
    guard let image = renderFinalImage(state: state) else {
      DiagnosticLogger.shared.log(.error, .annotate, "Save failed: render returned nil")
      return false
    }

    guard let data = imageData(from: image, for: url.pathExtension) else { return false }

    do {
      try SandboxFileAccessManager.shared.withScopedAccess(to: url.deletingLastPathComponent()) {
        try data.write(to: url, options: .atomic)
      }
      CaptureHistoryStore.shared.markFileChanged(at: url)
      SoundManager.play("Pop")
      return true
    } catch {
      SoundManager.play("Basso")
      DiagnosticLogger.shared.logError(.annotate, error, "Save failed")
      return false
    }
  }

  /// Write a pre-rendered image to the source URL (for background save after instant close)
  @MainActor
  @discardableResult
  static func saveToFile(image: NSImage?, state: AnnotateState) -> Bool {
    guard let image = image, let sourceURL = state.sourceURL else { return false }
    DiagnosticLogger.shared.log(.info, .annotate, "Background save", context: ["file": sourceURL.lastPathComponent])

    guard let data = imageData(from: image, for: sourceURL.pathExtension) else { return false }

    do {
      try SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL.deletingLastPathComponent()) {
        try data.write(to: sourceURL, options: .atomic)
      }
      CaptureHistoryStore.shared.markFileChanged(at: sourceURL)
      return true
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Background save failed")
      return false
    }
  }

  /// Off-main variant of `saveToFile`: the full-res encode runs on the calling (background)
  /// queue — it is the most expensive step — while only the sandbox-scoped write and
  /// history bookkeeping hop to main (both main-bound APIs, ~ms).
  nonisolated static func saveToFileOffMain(image: NSImage, sourceURL: URL) async -> Bool {
    DiagnosticLogger.shared.log(.info, .annotate, "Background save", context: ["file": sourceURL.lastPathComponent])

    guard let data = imageData(from: image, for: sourceURL.pathExtension) else { return false }

    do {
      try await MainActor.run {
        try SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL.deletingLastPathComponent()) {
          try data.write(to: sourceURL, options: .atomic)
        }
        CaptureHistoryStore.shared.markFileChanged(at: sourceURL)
      }
      return true
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Background save failed")
      return false
    }
  }

  static func copyToClipboard(state: AnnotateState) {
    DiagnosticLogger.shared.log(.info, .annotate, "Copy to clipboard", context: ["annotations": "\(state.annotations.count)"])
    guard let image = renderFinalImage(state: state) else {
      DiagnosticLogger.shared.log(.error, .annotate, "Copy failed: render returned nil")
      return
    }

    ClipboardHelper.copyImage(image)
    SoundManager.play("Pop")
  }

  static func share(state: AnnotateState, from view: NSView) {
    DiagnosticLogger.shared.log(.info, .annotate, "Share started")
    guard let image = renderFinalImage(state: state) else {
      DiagnosticLogger.shared.log(.error, .annotate, "Share failed: render returned nil")
      return
    }

    let picker = NSSharingServicePicker(items: [image])
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
  }


  // MARK: - Private

  private static func generateFileName(from url: URL?, isCombine: Bool = false) -> String {
    if isCombine {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyyMMdd-HHmmss"
      return "combined-\(formatter.string(from: Date())).png"
    }
    guard let url = url else { return L10n.AnnotateUI.defaultAnnotatedFileName }
    let baseName = url.deletingPathExtension().lastPathComponent
    return "\(baseName)_annotated"
  }

  /// JPEG does not support alpha. Confirm before flattening a cutout result.
  static func confirmTransparencyLossIfNeeded(state: AnnotateState, targetURL: URL) -> Bool {
    guard state.isCutoutApplied else { return true }

    let ext = targetURL.pathExtension.lowercased()
    guard ext == "jpg" || ext == "jpeg" else { return true }

    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.jpegRemovesTransparencyTitle
    alert.informativeText = L10n.AnnotateUI.jpegRemovesTransparencyMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.AnnotateUI.saveAsJPEG)
    alert.addButton(withTitle: L10n.Common.cancel)
    return alert.runModal() == .alertFirstButtonReturn
  }

  /// Determine the pixel-to-point scale factor from the source image.
  /// Falls back to 1.0 when bitmap metadata is unavailable.
  nonisolated private static func sourceImageScale(_ sourceImage: NSImage) -> CGFloat {
    let pointWidth = sourceImage.size.width
    let pointHeight = sourceImage.size.height
    guard pointWidth > 0, pointHeight > 0 else { return 1.0 }

    if let rep = bestBitmapRepresentation(in: sourceImage) {
      let pixelWidth = CGFloat(rep.pixelsWide)
      let pixelHeight = CGFloat(rep.pixelsHigh)
      if pixelWidth > 0 && pixelHeight > 0 {
        let widthScale = pixelWidth / pointWidth
        let heightScale = pixelHeight / pointHeight
        return max(widthScale, heightScale, 1.0)
      }
    }

    if let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      let widthScale = CGFloat(cgImage.width) / pointWidth
      let heightScale = CGFloat(cgImage.height) / pointHeight
      return max(widthScale, heightScale, 1.0)
    }

    return 1.0
  }

  nonisolated private static func bestBitmapRepresentation(in image: NSImage) -> NSBitmapImageRep? {
    image.representations
      .compactMap { $0 as? NSBitmapImageRep }
      .max { lhs, rhs in
        lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
      }
  }

  nonisolated static func bestCGImage(from image: NSImage) -> CGImage? {
    if let cgImage = bestBitmapRepresentation(in: image)?.cgImage {
      return cgImage
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  /// Convert NSImage to Data for any supported format (PNG, JPEG, WebP)
  /// Uses CGImageDestination for WebP support (macOS 14+)
  nonisolated static func imageData(from image: NSImage, for fileExtension: String) -> Data? {
    guard let cgImage = bestCGImage(from: image) else {
      return nil
    }

    let scale = sourceImageScale(image)
    let ext = fileExtension.lowercased()

    // WebP: use WebPEncoder (cwebp CLI) since ImageIO doesn't support WebP encoding
    if ext == "webp" {
      return WebPEncoderService.encode(cgImage)
    }

    // PNG/JPEG: use CGImageDestination
    let utType: CFString
    switch ext {
    case "jpg", "jpeg":
      utType = "public.jpeg" as CFString
    default:
      utType = "public.png" as CFString
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, utType, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, cgImage, imageDestinationProperties(for: ext, scaleFactor: scale))
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }

  nonisolated private static func imageDestinationProperties(
    for fileExtension: String,
    scaleFactor: CGFloat
  ) -> CFDictionary? {
    let resolvedScale = max(Double(scaleFactor), 1.0)
    let dpi = resolvedScale * 72.0
    var properties: [CFString: Any] = [
      kCGImagePropertyDPIWidth: dpi,
      kCGImagePropertyDPIHeight: dpi
    ]

    switch fileExtension {
    case "png":
      let pixelsPerMeter = Int((dpi / 0.0254).rounded())
      properties[kCGImagePropertyPNGDictionary] = [
        kCGImagePropertyPNGXPixelsPerMeter: pixelsPerMeter,
        kCGImagePropertyPNGYPixelsPerMeter: pixelsPerMeter
      ] as CFDictionary
    case "jpg", "jpeg":
      properties[kCGImageDestinationLossyCompressionQuality] = 0.9
    default:
      break
    }

    return properties as CFDictionary
  }

  /// Generate unique copy URL from original file path
  static func generateCopyURL(from originalURL: URL) -> URL {
    let directory = originalURL.deletingLastPathComponent()
    let baseName = originalURL.deletingPathExtension().lastPathComponent
    let ext = originalURL.pathExtension

    var copyNumber = 1
    var newURL = directory.appendingPathComponent("\(baseName)_copy.\(ext)")

    while FileManager.default.fileExists(atPath: newURL.path) {
      copyNumber += 1
      newURL = directory.appendingPathComponent("\(baseName)_copy\(copyNumber).\(ext)")
    }

    return newURL
  }

  static func renderCanvasEffects(
    sourceImage: NSImage,
    effects: AnnotationCanvasEffects
  ) -> NSImage? {
    let startedAt = CFAbsoluteTimeGetCurrent()
    var outputSizeDescription = "nil"
    defer {
      let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
      DiagnosticLogger.shared.log(.debug, .annotate, "Render canvas effects completed", context: [
        "background": "\(effects.backgroundStyle)",
        "outputSize": outputSizeDescription,
        "durationMs": "\(durationMs)"
      ])
    }

    let effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    let padding = effects.backgroundStyle != .none ? effects.padding : 0
    let alignmentSpace: CGFloat = effects.imageAlignment != .center ? 40 : 0

    let totalSize: NSSize = effects.aspectRatio.canvasSize(
      for: effectiveBounds.size,
      padding: padding,
      alignmentSpace: alignmentSpace,
      orientation: effects.aspectRatioOrientation
    )
    outputSizeDescription = "\(Int(totalSize.width))x\(Int(totalSize.height))"

    let scale = sourceImageScale(sourceImage)
    let pixelWidth = max(1, Int(ceil(totalSize.width * scale)))
    let pixelHeight = max(1, Int(ceil(totalSize.height * scale)))

    guard let bitmapRep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelWidth,
      pixelsHigh: pixelHeight,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }
    bitmapRep.size = totalSize

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphicsContext

    let context = graphicsContext.cgContext
    drawBackground(effects: effects, in: context, size: totalSize)

    let destinationOrigin = destinationOrigin(
      imageSize: effectiveBounds.size,
      totalSize: totalSize,
      alignment: effects.imageAlignment
    )
    let imageRect = CGRect(origin: destinationOrigin, size: effectiveBounds.size)

    drawCanvasShadow(
      imageRect: imageRect,
      canvasRect: CGRect(origin: .zero, size: totalSize),
      cornerRadius: effects.cornerRadius,
      intensity: effects.backgroundStyle != .none ? effects.shadowIntensity : 0,
      in: context
    )

    if effects.cornerRadius > 0 {
      let path = NSBezierPath(
        roundedRect: imageRect,
        xRadius: effects.cornerRadius,
        yRadius: effects.cornerRadius
      )
      path.addClip()
    }

    drawSourceImage(
      sourceImage,
      effectiveBounds: effectiveBounds,
      destinationOrigin: destinationOrigin,
      in: context
    )
    context.resetClip()

    let image = NSImage(size: totalSize)
    image.addRepresentation(bitmapRep)
    return image
  }

  /// Main-actor render entry point (Save As / Copy / Share). Freezes state into a
  /// snapshot first so every render path shares one implementation.
  static func renderFinalImage(state: AnnotateState) -> NSImage? {
    guard let snapshot = state.makeRenderSnapshot() else { return nil }
    if snapshot.editorMode == .mockup {
      DiagnosticLogger.shared.log(.debug, .annotate, "Rendering mockup image")
      guard let flatImage = renderMockupFlatImage(snapshot: snapshot) else { return nil }
      return compositeMockupImage(flatImage: flatImage, snapshot: snapshot)
    }
    return renderFlatFinalImage(snapshot: snapshot)
  }

  /// Off-main render entry point for the save-and-close background path.
  /// Mockup mode renders the flat image off-main, then composites 3D transforms on main
  /// (SwiftUI `ImageRenderer` is a main-only API).
  nonisolated static func renderFinalImage(snapshot: AnnotateRenderSnapshot) async -> NSImage? {
    if snapshot.editorMode == .mockup {
      DiagnosticLogger.shared.log(.debug, .annotate, "Rendering mockup image")
      guard let flatImage = renderMockupFlatImage(snapshot: snapshot) else { return nil }
      return await compositeMockupImage(flatImage: flatImage, snapshot: snapshot)
    }
    return renderFlatFinalImage(snapshot: snapshot)
  }

  /// Flat render pipeline (no mockup transforms). Pure CoreGraphics/AppKit drawing into a
  /// private bitmap context — safe on any queue, reads only the frozen snapshot.
  nonisolated static func renderFlatFinalImage(snapshot: AnnotateRenderSnapshot) -> NSImage? {
    let startedAt = CFAbsoluteTimeGetCurrent()
    let embeddedLayerCount = snapshot.annotations.reduce(into: 0) { count, annotation in
      if case .embeddedImage = annotation.type {
        count += 1
      }
    }
    var outputSizeDescription = "nil"
    defer {
      let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
      DiagnosticLogger.shared.log(.debug, .annotate, "Render final image completed", context: [
        "mode": snapshot.editorMode.rawValue,
        "annotations": "\(snapshot.annotations.count)",
        "embeddedLayers": "\(embeddedLayerCount)",
        "outputSize": outputSizeDescription,
        "durationMs": "\(durationMs)"
      ])
    }

    let sourceImage = snapshot.sourceImage

    DiagnosticLogger.shared.log(.debug, .annotate, "Rendering final image", context: [
      "annotations": "\(snapshot.annotations.count)",
      "hasCrop": "\(snapshot.cropRect != nil)",
      "background": "\(snapshot.backgroundStyle)"
    ])

    // Determine effective bounds (crop or full image)
    let effectiveBounds: CGRect
    if snapshot.isCombineMode {
      effectiveBounds = snapshot.effectiveContentBounds
    } else if let cropRect = snapshot.cropRect {
      effectiveBounds = cropRect
    } else {
      effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    }

    let padding = snapshot.isCombineMode ? snapshot.padding : (snapshot.backgroundStyle != .none ? snapshot.padding : 0)

    // Add alignment space for non-center alignments (matches preview)
    let alignmentSpace: CGFloat = snapshot.imageAlignment != .center ? 40 : 0

    let totalSize: NSSize = snapshot.isCombineMode
      ? NSSize(width: effectiveBounds.width + padding * 2, height: effectiveBounds.height + padding * 2)
      : snapshot.aspectRatio.canvasSize(
        for: effectiveBounds.size,
        padding: padding,
        alignmentSpace: alignmentSpace,
        orientation: snapshot.aspectRatioOrientation
      )
    outputSizeDescription = "\(Int(totalSize.width))x\(Int(totalSize.height))"

    // Render at pixel resolution using NSBitmapImageRep for Retina quality
    let scale = sourceImageScale(sourceImage)
    let pixelWidth = max(1, Int(ceil(totalSize.width * scale)))
    let pixelHeight = max(1, Int(ceil(totalSize.height * scale)))

    guard let bitmapRep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelWidth,
      pixelsHigh: pixelHeight,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }
    bitmapRep.size = totalSize  // Point size — CG context will scale drawings to pixel dimensions

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    let context = graphicsContext.cgContext

    // Draw background
    drawBackground(snapshot: snapshot, in: context, size: totalSize)

    // Calculate image position based on alignment
    let imageWidth = effectiveBounds.width
    let imageHeight = effectiveBounds.height
    let totalExtraWidth = totalSize.width - imageWidth
    let totalExtraHeight = totalSize.height - imageHeight

    // Calculate destRect origin based on alignment
    // Note: CoreGraphics Y=0 is at bottom, so top alignment needs higher Y value
    let destX: CGFloat
    let destY: CGFloat

    switch snapshot.isCombineMode ? ImageAlignment.center : snapshot.imageAlignment {
    case .center:
      destX = totalExtraWidth / 2
      destY = totalExtraHeight / 2
    case .topLeft:
      destX = 0
      destY = totalExtraHeight  // Top in CG = max Y
    case .top:
      destX = totalExtraWidth / 2
      destY = totalExtraHeight
    case .topRight:
      destX = totalExtraWidth
      destY = totalExtraHeight
    case .left:
      destX = 0
      destY = totalExtraHeight / 2
    case .right:
      destX = totalExtraWidth
      destY = totalExtraHeight / 2
    case .bottomLeft:
      destX = 0
      destY = 0  // Bottom in CG = Y=0
    case .bottom:
      destX = totalExtraWidth / 2
      destY = 0
    case .bottomRight:
      destX = totalExtraWidth
      destY = 0
    }

    let imageRect = CGRect(
      x: destX,
      y: destY,
      width: effectiveBounds.width,
      height: effectiveBounds.height
    )
    drawCanvasShadow(
      imageRect: imageRect,
      canvasRect: CGRect(origin: .zero, size: totalSize),
      cornerRadius: snapshot.cornerRadius,
      intensity: snapshot.backgroundStyle != .none ? snapshot.shadowIntensity : 0,
      in: context
    )

    if snapshot.cornerRadius > 0 {
      let path = NSBezierPath(
        roundedRect: imageRect,
        xRadius: snapshot.cornerRadius,
        yRadius: snapshot.cornerRadius
      )
      path.addClip()
    }

    drawSourceImage(
      sourceImage,
      effectiveBounds: effectiveBounds,
      destinationOrigin: CGPoint(x: destX, y: destY),
      in: context
    )

    if !snapshot.isCombineMode {
      context.resetClip()
    }

    // Unified Spotlight overlay pass (drawn below other annotations, above base image).
    // Opacity sourced from per-item properties so exported image matches the on-screen appearance.
    let spotlightRegions: [SpotlightRegion] = snapshot.annotations.compactMap { a in
      guard case .spotlight = a.type else { return nil }
      let offset = offsetAnnotationForExport(
        a,
        cropOrigin: effectiveBounds.origin,
        imageX: destX,
        imageY: destY
      )
      return SpotlightRegion(rect: offset.bounds, cornerRadius: offset.properties.cornerRadius, opacity: offset.properties.spotlightOpacity)
    }
    SpotlightCompositor.drawOverlay(
      regions: spotlightRegions,
      previewRegion: nil,
      canvasRect: CGRect(x: destX, y: destY, width: effectiveBounds.width, height: effectiveBounds.height),
      in: context
    )

    // Draw annotations (offset by crop origin and image position based on alignment)
    let renderer = AnnotationRenderer(
      context: context,
      sourceImage: sourceImage,
      embeddedImageProvider: { assetId in
        snapshot.embeddedImages[assetId]
      },
      embeddedCGImageProvider: { assetId in
        snapshot.embeddedCGImages[assetId]
      }
    )
    for annotation in snapshot.annotations.renderOrdered {
      if case .spotlight = annotation.type { continue }
      // Only include annotations that intersect with crop bounds
      if let cropRect = snapshot.cropRect {
        guard annotation.bounds.intersects(cropRect) else { continue }
      }
      let offsetAnnotation = offsetAnnotationForExport(
        annotation,
        cropOrigin: effectiveBounds.origin,
        imageX: destX,
        imageY: destY
      )
      renderer.draw(offsetAnnotation)
    }

    if snapshot.isCombineMode {
      context.resetClip()
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: totalSize)
    image.addRepresentation(bitmapRep)
    return image
  }

  /// Draw the flat-canvas screenshot shadow without painting beneath the source image.
  /// The even-odd clip keeps only the blurred pixels outside the rounded silhouette,
  /// so transparent source pixels and native-resolution screenshot pixels stay untouched.
  nonisolated private static func drawCanvasShadow(
    imageRect: CGRect,
    canvasRect: CGRect,
    cornerRadius: CGFloat,
    intensity: CGFloat,
    in context: CGContext
  ) {
    let opacity = min(max(intensity, 0), 1)
    guard opacity > 0, imageRect.width > 0, imageRect.height > 0 else { return }

    let radius = min(
      max(cornerRadius, 0),
      min(imageRect.width, imageRect.height) / 2
    )
    let silhouette = CGPath(
      roundedRect: imageRect,
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )

    context.saveGState()
    let outsideSilhouette = CGMutablePath()
    outsideSilhouette.addRect(canvasRect)
    outsideSilhouette.addPath(silhouette)
    context.addPath(outsideSilhouette)
    context.clip(using: .evenOdd)

    context.setShadow(
      offset: CGSize(
        width: AnnotateCanvasDefaults.shadowOffsetX,
        height: -AnnotateCanvasDefaults.shadowOffsetY
      ),
      blur: AnnotateCanvasDefaults.shadowRadius,
      color: NSColor.black.withAlphaComponent(opacity).cgColor
    )
    context.addPath(silhouette)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()
  }

  /// Draw only the source-image portion that intersects the requested canvas bounds.
  /// Expanded crop areas outside the source image intentionally stay transparent/background-filled.
  nonisolated private static func drawSourceImage(
    _ sourceImage: NSImage,
    effectiveBounds: CGRect,
    destinationOrigin: CGPoint,
    in context: CGContext
  ) {
    let sourceImageBounds = CGRect(origin: .zero, size: sourceImage.size)
    let visibleSourceBounds = effectiveBounds.intersection(sourceImageBounds)
    guard !visibleSourceBounds.isNull, !visibleSourceBounds.isEmpty else { return }

    let destinationRect = NSRect(
      x: destinationOrigin.x + visibleSourceBounds.minX - effectiveBounds.minX,
      y: destinationOrigin.y + visibleSourceBounds.minY - effectiveBounds.minY,
      width: visibleSourceBounds.width,
      height: visibleSourceBounds.height
    )
    guard
      let sourceCGImage = bestCGImage(from: sourceImage),
      let sourcePixelRect = sourcePixelCropRect(
        for: visibleSourceBounds,
        imageSize: sourceImage.size,
        pixelSize: CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
      ),
      let croppedImage = sourceCGImage.cropping(to: sourcePixelRect)
    else {
      let sourceRect = NSRect(
        x: visibleSourceBounds.minX,
        y: visibleSourceBounds.minY,
        width: visibleSourceBounds.width,
        height: visibleSourceBounds.height
      )
      sourceImage.draw(in: destinationRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)
      return
    }

    let sourceScale = sourceImageScale(sourceImage)
    let destinationPixelSize = CGSize(
      width: destinationRect.width * sourceScale,
      height: destinationRect.height * sourceScale
    )
    let drawsOneToOne = abs(destinationPixelSize.width - CGFloat(croppedImage.width)) < 0.5
      && abs(destinationPixelSize.height - CGFloat(croppedImage.height)) < 0.5

    context.saveGState()
    context.interpolationQuality = drawsOneToOne ? .none : .high
    context.draw(croppedImage, in: destinationRect)
    context.restoreGState()
  }

  nonisolated private static func sourcePixelCropRect(
    for bounds: CGRect,
    imageSize: CGSize,
    pixelSize: CGSize
  ) -> CGRect? {
    guard imageSize.width > 0, imageSize.height > 0, pixelSize.width > 0, pixelSize.height > 0 else {
      return nil
    }

    let scaleX = pixelSize.width / imageSize.width
    let scaleY = pixelSize.height / imageSize.height
    let minX = floor(bounds.minX * scaleX)
    let maxX = ceil(bounds.maxX * scaleX)
    let minY = floor((imageSize.height - bounds.maxY) * scaleY)
    let maxY = ceil((imageSize.height - bounds.minY) * scaleY)
    let imagePixelBounds = CGRect(origin: .zero, size: pixelSize)
    let cropRect = CGRect(
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    )
    .intersection(imagePixelBounds)
    .integral

    guard !cropRect.isNull, !cropRect.isEmpty else { return nil }
    return cropRect
  }

  /// Offset annotation for export, accounting for crop origin and alignment-based image position
  nonisolated private static func offsetAnnotationForExport(
    _ annotation: AnnotationItem,
    cropOrigin: CGPoint,
    imageX: CGFloat,
    imageY: CGFloat
  ) -> AnnotationItem {
    var result = annotation
    result.bounds = CGRect(
      x: annotation.bounds.origin.x - cropOrigin.x + imageX,
      y: annotation.bounds.origin.y - cropOrigin.y + imageY,
      width: annotation.bounds.width,
      height: annotation.bounds.height
    )

    // Offset internal points for types that store coordinates
    switch annotation.type {
    case .arrow(let geometry):
      result.type = .arrow(
        geometry.translatedBy(
          dx: -cropOrigin.x + imageX,
          dy: -cropOrigin.y + imageY
        )
      )
    case .line(let start, let end):
      result.type = .line(
        start: CGPoint(x: start.x - cropOrigin.x + imageX, y: start.y - cropOrigin.y + imageY),
        end: CGPoint(x: end.x - cropOrigin.x + imageX, y: end.y - cropOrigin.y + imageY)
      )
    case .path(let points):
      result.type = .path(points.map {
        CGPoint(x: $0.x - cropOrigin.x + imageX, y: $0.y - cropOrigin.y + imageY)
      })
    case .highlight(let points):
      result.type = .highlight(points.map {
        CGPoint(x: $0.x - cropOrigin.x + imageX, y: $0.y - cropOrigin.y + imageY)
      })
    default:
      break
    }

    return result
  }

  /// Offset annotation for crop, accounting for crop origin and padding
  nonisolated private static func offsetAnnotationForCrop(
    _ annotation: AnnotationItem,
    cropOrigin: CGPoint,
    padding: CGFloat
  ) -> AnnotationItem {
    var result = annotation
    result.bounds = CGRect(
      x: annotation.bounds.origin.x - cropOrigin.x + padding,
      y: annotation.bounds.origin.y - cropOrigin.y + padding,
      width: annotation.bounds.width,
      height: annotation.bounds.height
    )

    // Offset internal points for types that store coordinates
    switch annotation.type {
    case .arrow(let geometry):
      result.type = .arrow(
        geometry.translatedBy(
          dx: -cropOrigin.x + padding,
          dy: -cropOrigin.y + padding
        )
      )
    case .line(let start, let end):
      result.type = .line(
        start: CGPoint(x: start.x - cropOrigin.x + padding, y: start.y - cropOrigin.y + padding),
        end: CGPoint(x: end.x - cropOrigin.x + padding, y: end.y - cropOrigin.y + padding)
      )
    case .path(let points):
      result.type = .path(points.map {
        CGPoint(x: $0.x - cropOrigin.x + padding, y: $0.y - cropOrigin.y + padding)
      })
    case .highlight(let points):
      result.type = .highlight(points.map {
        CGPoint(x: $0.x - cropOrigin.x + padding, y: $0.y - cropOrigin.y + padding)
      })
    default:
      break
    }

    return result
  }

  /// Offset an annotation by padding, including internal points for lines/arrows
  nonisolated private static func offsetAnnotation(_ annotation: AnnotationItem, by padding: CGFloat) -> AnnotationItem {
    var result = annotation
    result.bounds = annotation.bounds.offsetBy(dx: padding, dy: padding)

    // Also offset internal points for types that store coordinates
    switch annotation.type {
    case .arrow(let geometry):
      result.type = .arrow(geometry.translatedBy(dx: padding, dy: padding))
    case .line(let start, let end):
      result.type = .line(
        start: CGPoint(x: start.x + padding, y: start.y + padding),
        end: CGPoint(x: end.x + padding, y: end.y + padding)
      )
    case .path(let points):
      result.type = .path(points.map { CGPoint(x: $0.x + padding, y: $0.y + padding) })
    case .highlight(let points):
      result.type = .highlight(points.map { CGPoint(x: $0.x + padding, y: $0.y + padding) })
    default:
      break
    }

    return result
  }

  /// Snapshot-based background draw. The wallpaper/blurred image arrives pre-resolved
  /// (main-bound sandbox access + CI blur happen when the snapshot is built).
  nonisolated private static func drawBackground(snapshot: AnnotateRenderSnapshot, in context: CGContext, size: NSSize) {
    let rect = CGRect(origin: .zero, size: size)

    switch snapshot.backgroundStyle {
    case .none:
      break

    case .gradient(let preset):
      drawLinearGradient(colors: preset.colors, in: context, size: size)

    case .solidColor(let color):
      context.setFillColor(NSColor(color).cgColor)
      context.fill(rect)
      if snapshot.isBlurredBackgroundEffectActive {
        drawBlurredBackgroundTint(effect: snapshot.blurredBackgroundEffect, in: context, rect: rect)
      }

    case .wallpaper(let url):
      if url.scheme == "preset",
         let presetName = url.host,
         let preset = WallpaperPreset(rawValue: presetName) {
        drawLinearGradient(colors: preset.colors, in: context, size: size)
        return
      }
      if let wallpaper = snapshot.resolvedBackgroundImage {
        wallpaper.draw(in: rect)
        if snapshot.isBlurredBackgroundEffectActive {
          drawBlurredBackgroundTint(effect: snapshot.blurredBackgroundEffect, in: context, rect: rect)
        }
      }

    case .blurred:
      if let wallpaper = snapshot.resolvedBackgroundImage {
        wallpaper.draw(in: rect)
        drawBlurredBackgroundTint(effect: snapshot.blurredBackgroundEffect, in: context, rect: rect)
      }
    }
  }

  private static func drawBackground(effects: AnnotationCanvasEffects, in context: CGContext, size: NSSize) {
    let rect = CGRect(origin: .zero, size: size)

    switch effects.backgroundStyle {
    case .none:
      break

    case .gradient(let preset):
      drawLinearGradient(colors: preset.colors, in: context, size: size)

    case .solidColor(let color):
      context.setFillColor(NSColor(color).cgColor)
      context.fill(rect)
      if isBlurredBackgroundEffectActive(effects) {
        drawBlurredBackgroundTint(effect: effects.blurredBackgroundEffect, in: context, rect: rect)
      }

    case .wallpaper(let url):
      if url.scheme == "preset",
         let presetName = url.host,
         let preset = WallpaperPreset(rawValue: presetName) {
        drawLinearGradient(colors: preset.colors, in: context, size: size)
        return
      }
      let preferBlurred = isBlurredBackgroundEffectActive(effects)
      if let wallpaper = resolveWallpaperImage(
        for: url,
        blurredEffect: effects.blurredBackgroundEffect,
        preferBlurred: preferBlurred
      ) {
        wallpaper.draw(in: rect)
        if preferBlurred {
          drawBlurredBackgroundTint(effect: effects.blurredBackgroundEffect, in: context, rect: rect)
        }
      }

    case .blurred(let url):
      if let wallpaper = resolveWallpaperImage(
        for: url,
        blurredEffect: effects.blurredBackgroundEffect,
        preferBlurred: true
      ) {
        wallpaper.draw(in: rect)
        drawBlurredBackgroundTint(effect: effects.blurredBackgroundEffect, in: context, rect: rect)
      }
    }
  }

  private static func isBlurredBackgroundEffectActive(_ effects: AnnotationCanvasEffects) -> Bool {
    guard effects.backgroundStyle.supportsBlurredBackgroundEffect else { return false }
    if case .blurred = effects.backgroundStyle {
      return true
    }
    return effects.isBlurredBackgroundEnabled
  }

  nonisolated private static func drawLinearGradient(colors: [Color], in context: CGContext, size: NSSize) {
    let cgColors = colors.map { NSColor($0).cgColor }
    let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: cgColors as CFArray,
      locations: nil
    )
    if let gradient = gradient {
      context.drawLinearGradient(
        gradient,
        start: .zero,
        end: CGPoint(x: size.width, y: size.height),
        options: []
      )
    }
  }

  private static func resolveWallpaperImage(
    for url: URL,
    blurredEffect: BlurredBackgroundEffect,
    preferBlurred: Bool
  ) -> NSImage? {
    let image = SandboxFileAccessManager.shared.withScopedAccess(to: url) {
      NSImage(contentsOf: url)
    }
    guard preferBlurred else { return image }
    return makeBlurredBackgroundImage(from: image, effect: blurredEffect)
  }

  nonisolated private static func drawBlurredBackgroundTint(
    effect: BlurredBackgroundEffect,
    in context: CGContext,
    rect: CGRect
  ) {
    guard effect.tintOpacity > 0 else { return }

    context.saveGState()
    context.setFillColor(NSColor(effect.tintColor).withAlphaComponent(CGFloat(effect.tintOpacity)).cgColor)
    context.fill(rect)
    context.restoreGState()
  }

  nonisolated private static func makeBlurredBackgroundImage(
    from image: NSImage?,
    effect: BlurredBackgroundEffect
  ) -> NSImage? {
    guard let image,
          let tiffData = image.tiffRepresentation,
          let ciImage = CIImage(data: tiffData) else { return nil }

    let blurFilter = CIFilter(name: "CIGaussianBlur")
    blurFilter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
    blurFilter?.setValue(effect.blurRadius, forKey: kCIInputRadiusKey)

    guard let blurredOutput = blurFilter?.outputImage else { return nil }

    let colorFilter = CIFilter(name: "CIColorControls")
    colorFilter?.setValue(blurredOutput, forKey: kCIInputImageKey)
    colorFilter?.setValue(effect.saturation, forKey: kCIInputSaturationKey)
    colorFilter?.setValue(effect.brightness, forKey: kCIInputBrightnessKey)

    guard let output = colorFilter?.outputImage else { return nil }

    let croppedOutput = output.cropped(to: ciImage.extent)
    let rep = NSCIImageRep(ciImage: croppedOutput)
    let blurred = NSImage(size: rep.size)
    blurred.addRepresentation(rep)
    return blurred
  }

  nonisolated private static func destinationOrigin(
    imageSize: CGSize,
    totalSize: CGSize,
    alignment: ImageAlignment
  ) -> CGPoint {
    let totalExtraWidth = totalSize.width - imageSize.width
    let totalExtraHeight = totalSize.height - imageSize.height

    switch alignment {
    case .center:
      return CGPoint(x: totalExtraWidth / 2, y: totalExtraHeight / 2)
    case .topLeft:
      return CGPoint(x: 0, y: totalExtraHeight)
    case .top:
      return CGPoint(x: totalExtraWidth / 2, y: totalExtraHeight)
    case .topRight:
      return CGPoint(x: totalExtraWidth, y: totalExtraHeight)
    case .left:
      return CGPoint(x: 0, y: totalExtraHeight / 2)
    case .right:
      return CGPoint(x: totalExtraWidth, y: totalExtraHeight / 2)
    case .bottomLeft:
      return .zero
    case .bottom:
      return CGPoint(x: totalExtraWidth / 2, y: 0)
    case .bottomRight:
      return CGPoint(x: totalExtraWidth, y: 0)
    }
  }



  // MARK: - Mockup Rendering

  /// Render the flattened image + annotations that mockup transforms are applied to.
  /// Pure bitmap drawing from the frozen snapshot — safe on any queue.
  nonisolated static func renderMockupFlatImage(snapshot: AnnotateRenderSnapshot) -> NSImage? {
    let sourceImage = snapshot.sourceImage

    // Determine effective bounds (crop or full image)
    let effectiveBounds: CGRect
    if let cropRect = snapshot.cropRect {
      effectiveBounds = cropRect
    } else {
      effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    }

    // Render at pixel resolution using NSBitmapImageRep for Retina quality
    let scale = sourceImageScale(sourceImage)
    let pixelWidth = max(1, Int(ceil(effectiveBounds.width * scale)))
    let pixelHeight = max(1, Int(ceil(effectiveBounds.height * scale)))

    guard let bitmapRep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelWidth,
      pixelsHigh: pixelHeight,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }
    bitmapRep.size = effectiveBounds.size  // Point size

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    let context = graphicsContext.cgContext

    drawSourceImage(sourceImage, effectiveBounds: effectiveBounds, destinationOrigin: .zero, in: context)

    // Draw annotations offset by crop origin
    let renderer = AnnotationRenderer(
      context: context,
      sourceImage: sourceImage,
      embeddedImageProvider: { assetId in
        snapshot.embeddedImages[assetId]
      },
      embeddedCGImageProvider: { assetId in
        snapshot.embeddedCGImages[assetId]
      }
    )
    for annotation in snapshot.annotations.renderOrdered {
      if let cropRect = snapshot.cropRect {
        guard annotation.bounds.intersects(cropRect) else { continue }
      }
      let offsetAnnotation = offsetAnnotationForCrop(
        annotation,
        cropOrigin: effectiveBounds.origin,
        padding: 0
      )
      renderer.draw(offsetAnnotation)
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: effectiveBounds.size)
    image.addRepresentation(bitmapRep)
    return image
  }

  /// Apply mockup 3D transforms to the flattened image via SwiftUI ImageRenderer.
  /// ImageRenderer is main-only — this is the sole main-actor step of mockup export.
  @MainActor static func compositeMockupImage(flatImage: NSImage, snapshot: AnnotateRenderSnapshot) -> NSImage? {
    let mockupView = MockupExportViewForAnnotate(flatImage: flatImage, snapshot: snapshot)
    let renderer = ImageRenderer(content: mockupView)
    renderer.scale = 2.0

    return renderer.nsImage
  }
}

// MARK: - Mockup Export View for Annotate

/// SwiftUI view for exporting mockup with 3D transforms
struct MockupExportViewForAnnotate: View {
  let flatImage: NSImage  // Pre-rendered image with annotations
  let snapshot: AnnotateRenderSnapshot

  var body: some View {
    ZStack {
      backgroundLayer
        .frame(width: canvasSize.width, height: canvasSize.height)

      Image(nsImage: flatImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: imageSize.width, maxHeight: imageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: snapshot.cornerRadius, style: .continuous))
        .rotation3DEffect(
          .degrees(snapshot.mockupRotationY),
          axis: (x: 0, y: 1, z: 0),
          anchor: .center,
          anchorZ: 0,
          perspective: snapshot.mockupPerspective
        )
        .rotation3DEffect(
          .degrees(snapshot.mockupRotationX),
          axis: (x: 1, y: 0, z: 0),
          anchor: .center,
          anchorZ: 0,
          perspective: snapshot.mockupPerspective
        )
        .rotation3DEffect(
          .degrees(snapshot.mockupRotationZ),
          axis: (x: 0, y: 0, z: 1),
          anchor: .center
        )
        .shadow(
          color: .black.opacity(snapshot.shadowIntensity),
          radius: snapshot.mockupShadowRadius,
          x: snapshot.mockupShadowOffsetX,
          y: snapshot.mockupShadowOffsetY
        )
    }
  }

  // MARK: - Size Calculations

  private var imageSize: CGSize {
    flatImage.size
  }

  private var canvasSize: CGSize {
    let padding = snapshot.backgroundStyle != .none ? snapshot.padding : 0
    let extraSpace = padding * 2 + 100 // Extra for shadow and rotation
    return CGSize(
      width: imageSize.width + extraSpace,
      height: imageSize.height + extraSpace
    )
  }

  // MARK: - Background

  @ViewBuilder
  private var backgroundLayer: some View {
    switch snapshot.backgroundStyle {
    case .none:
      Color.clear
    case .gradient(let preset):
      LinearGradient(
        colors: preset.colors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .solidColor(let color):
      color
        .brightness(snapshot.isBlurredBackgroundEffectActive ? snapshot.blurredBackgroundEffect.brightness : 0)
        .overlay(
          (snapshot.isBlurredBackgroundEffectActive ? snapshot.blurredBackgroundEffect.tintColor : .clear)
            .opacity(snapshot.isBlurredBackgroundEffectActive ? snapshot.blurredBackgroundEffect.tintOpacity : 0)
        )
    case .wallpaper(let url):
      // Check if this is a preset wallpaper
      if url.scheme == "preset", let presetName = url.host,
         let preset = WallpaperPreset(rawValue: presetName) {
        preset.gradient
      } else if let image = snapshot.resolvedBackgroundImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .overlay(
            snapshot.isBlurredBackgroundEffectActive
              ? snapshot.blurredBackgroundEffect.tintColor.opacity(snapshot.blurredBackgroundEffect.tintOpacity)
              : .clear
          )
      } else {
        Color.gray.opacity(0.3)
      }
    case .blurred:
      if let image = snapshot.resolvedBackgroundImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .overlay(snapshot.blurredBackgroundEffect.tintColor.opacity(snapshot.blurredBackgroundEffect.tintOpacity))
      } else {
        Color.gray.opacity(0.3)
      }
    }
  }
}
