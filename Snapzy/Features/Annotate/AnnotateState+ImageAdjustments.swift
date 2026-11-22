//
//  AnnotateState+ImageAdjustments.swift
//  Snapzy
//
//  Non-destructive image adjustments (tone sliders + filter presets). The original source
//  (and cutout) stay untouched; the adjusted bitmap is rendered asynchronously and exposed
//  through `effectiveSourceImage`, so canvas, blur, measure, OCR and export all see it.
//

import AppKit

/// One rendered adjusted image and the inputs it was rendered from.
struct AnnotateAdjustedImageRender {
  /// Base image (source or cutout) the render came from; compared by identity.
  let base: NSImage
  let adjustments: ImageAdjustments
  let image: NSImage
  /// False for the downscaled live preview of very large captures.
  let isFullResolution: Bool
}

/// Base image downscaled once for live slider previews.
struct AnnotateAdjustmentPreviewBase {
  let base: NSImage
  let image: CGImage
  /// Scale `image` was rendered at relative to the base's pixels.
  let scale: CGFloat

  typealias Payload = (image: CGImage, scale: CGFloat)
}

extension AnnotateState {
  /// Bases above this pixel count publish a downscaled preview before the full render.
  private static let adjustmentPreviewPixelThreshold = 12_000_000
  /// Pixel budget for that preview (still sharp at the canvas' fit scale).
  private static let adjustmentPreviewPixelBudget = 4_000_000
  /// Pixel budget for live previews while a slider drags (any base size).
  private static let adjustmentGesturePreviewPixelBudget = 2_500_000
  private static let filterPresetThumbnailMaxDimension: CGFloat = 160

  /// Adjustments apply to the single base image; combine layouts have no single source, so
  /// the controls hide there unless adjustments made earlier still need a way to be reset.
  var canAdjustImage: Bool {
    hasImage && (!isCombineMode || !imageAdjustments.isIdentity)
  }

  /// Value the controls and the canvas reflect: the live drag value, else the committed one.
  var liveImageAdjustments: ImageAdjustments {
    imageAdjustmentGestureValue ?? imageAdjustments
  }

  /// Adjusted image for `base` when one was rendered from it (live preview may lag a few
  /// frames behind the sliders), else nil.
  func currentAdjustedImage(for base: NSImage?) -> NSImage? {
    guard let base,
          !liveImageAdjustments.isIdentity,
          let render = adjustedSourceRender,
          render.base === base else { return nil }
    return render.image
  }

  /// Full-resolution image for export: renders synchronously when the cached render is a
  /// preview, stale, or still in flight.
  func exportSourceImage() -> NSImage? {
    guard let base = adjustmentBaseImage else { return nil }
    let adjustments = liveImageAdjustments
    guard !adjustments.isIdentity else { return base }
    if let render = adjustedSourceRender,
       render.base === base,
       render.adjustments == adjustments,
       render.isFullResolution {
      return render.image
    }
    guard let cgImage = AnnotateExporter.bestCGImage(from: base),
          let rendered = AnnotateImageAdjustmentRenderer.render(cgImage, adjustments: adjustments) else {
      DiagnosticLogger.shared.log(.error, .annotate, "Image adjustment export render failed")
      return base
    }
    let image = AnnotateImageAdjustmentRenderer.makeImage(rendered, pointSize: base.size)
    // Supersede any in-flight render with this exact result.
    imageAdjustmentRenderGeneration &+= 1
    imageAdjustmentRenderTask?.cancel()
    imageAdjustmentRenderTask = nil
    adjustedSourceRender = AnnotateAdjustedImageRender(
      base: base, adjustments: adjustments, image: image, isFullResolution: true
    )
    return image
  }

  // MARK: - Editing

  /// Applies a discrete change (preset tap, typed value) as one undo step.
  func setImageAdjustments(_ adjustments: ImageAdjustments) {
    let clamped = adjustments.clamped
    if imageAdjustmentGestureStart != nil {
      // The slider writes its final value right before ending the drag.
      updateImageAdjustmentGesture(clamped)
      return
    }
    guard clamped != imageAdjustments else { return }
    pushImageAdjustmentsUndo(imageAdjustments)
    imageAdjustments = clamped
    scheduleImageAdjustmentRender()
  }

  func selectImageFilterPreset(_ preset: ImageFilterPreset) {
    var adjustments = imageAdjustments
    adjustments.preset = preset
    setImageAdjustments(adjustments)
  }

  func resetImageAdjustments() {
    setImageAdjustments(.identity)
  }

  /// Slider drag began: remember the value so release commits one undo step.
  func beginImageAdjustmentGesture() {
    guard imageAdjustmentGestureStart == nil else { return }
    imageAdjustmentGestureStart = imageAdjustments
    imageAdjustmentGestureValue = imageAdjustments
  }

  /// Live slider value: re-render a low-resolution preview without publishing the value or
  /// touching the undo stack.
  func updateImageAdjustmentGesture(_ adjustments: ImageAdjustments) {
    if imageAdjustmentGestureStart == nil {
      beginImageAdjustmentGesture()
    }
    let clamped = adjustments.clamped
    guard clamped != imageAdjustmentGestureValue else { return }
    imageAdjustmentGestureValue = clamped
    scheduleImageAdjustmentRender()
  }

  /// Drag released: publish the final value once, push one undo step, render full resolution.
  func endImageAdjustmentGesture() {
    guard let start = imageAdjustmentGestureStart else { return }
    let final = imageAdjustmentGestureValue ?? imageAdjustments
    imageAdjustmentGestureStart = nil
    imageAdjustmentGestureValue = nil
    if start != final {
      pushImageAdjustmentsUndo(start)
    }
    if imageAdjustments != final {
      imageAdjustments = final
    }
    scheduleImageAdjustmentRender()
  }

  /// Drops an in-progress drag without committing it (undo, restore, new image).
  private func cancelImageAdjustmentGesture() {
    imageAdjustmentGestureStart = nil
    imageAdjustmentGestureValue = nil
  }

  /// Undo/redo target (the caller already moved the current value to the other stack).
  func applyImageAdjustmentsFromUndo(_ adjustments: ImageAdjustments) {
    cancelImageAdjustmentGesture()
    imageAdjustments = adjustments
    hasUnsavedChanges = true
    scheduleImageAdjustmentRender()
  }

  /// Session restore (QuickAccess cache, sidecar): no undo step, not an unsaved change.
  /// Small images render synchronously so the editor never opens on the original pixels.
  func restoreImageAdjustments(_ adjustments: ImageAdjustments) {
    cancelImageAdjustmentGesture()
    imageAdjustments = adjustments.clamped
    guard !imageAdjustments.isIdentity,
          let base = adjustmentBaseImage,
          let cgImage = AnnotateExporter.bestCGImage(from: base) else {
      scheduleImageAdjustmentRender()
      return
    }
    if cgImage.width * cgImage.height <= Self.adjustmentPreviewPixelThreshold {
      _ = exportSourceImage()
    } else {
      scheduleImageAdjustmentRender()
    }
  }

  /// A different capture was loaded into this editor: adjustments belong to the old one.
  func resetImageAdjustmentsForNewImage() {
    cancelImageAdjustmentGesture()
    imageAdjustmentPreviewBase = nil
    imageAdjustments = .identity
    imageFilterPresetThumbnails = [:]
    imageFilterPresetThumbnailsBase = nil
    scheduleImageAdjustmentRender()
  }

  /// Source, cutout or cutout toggle changed (rotate, flip, cut-out strip, cutout…).
  func imageAdjustmentBaseDidChange() {
    if let thumbnailsBase = imageFilterPresetThumbnailsBase, thumbnailsBase !== adjustmentBaseImage {
      // Thumbnails are in use (sidebar shown): rebuild them for the new base.
      imageFilterPresetThumbnailsBase = nil
      prepareImageFilterPresetThumbnailsIfNeeded()
    }
    imageAdjustmentPreviewBase = nil
    guard !liveImageAdjustments.isIdentity || adjustedSourceRender != nil else { return }
    scheduleImageAdjustmentRender()
  }

  // MARK: - Rendering

  /// Renders the adjusted image off the main actor. While a slider drags only a coalescing
  /// low-resolution preview runs; otherwise renders are chained (one in flight) and only the
  /// newest request renders.
  func scheduleImageAdjustmentRender() {
    imageAdjustmentRenderGeneration &+= 1
    let generation = imageAdjustmentRenderGeneration
    let adjustments = liveImageAdjustments

    guard let base = adjustmentBaseImage, !adjustments.isIdentity else {
      imageAdjustmentRenderTask?.cancel()
      imageAdjustmentRenderTask = nil
      if adjustedSourceRender != nil {
        adjustedSourceRender = nil
      }
      return
    }

    if imageAdjustmentGestureStart != nil {
      // The full render (if any) is stale now; the preview loop picks up the newest value.
      imageAdjustmentRenderTask?.cancel()
      startImageAdjustmentPreviewLoopIfNeeded()
      return
    }

    if let render = adjustedSourceRender,
       render.base === base,
       render.adjustments == adjustments,
       render.isFullResolution {
      return
    }
    guard let cgImage = AnnotateExporter.bestCGImage(from: base) else { return }

    let pointSize = base.size
    let usesPreview = cgImage.width * cgImage.height > Self.adjustmentPreviewPixelThreshold
    let previewBudget = Self.adjustmentPreviewPixelBudget
    let previous = imageAdjustmentRenderTask
    previous?.cancel()

    imageAdjustmentRenderTask = Task { [weak self] in
      // Large bases: publish a cheap preview first so the canvas responds right away.
      if usesPreview {
        let preview = await Task.detached(priority: .userInitiated) {
          AnnotateImageAdjustmentRenderer.render(cgImage, adjustments: adjustments, maxPixelCount: previewBudget)
        }.value
        guard let self, self.imageAdjustmentRenderGeneration == generation else { return }
        if let preview {
          self.adjustedSourceRender = AnnotateAdjustedImageRender(
            base: base,
            adjustments: adjustments,
            image: AnnotateImageAdjustmentRenderer.makeImage(preview, pointSize: pointSize),
            isFullResolution: false
          )
        }
      }
      // Detached Core Image work can't be interrupted: wait for it rather than pile up.
      await previous?.value
      guard let self, self.imageAdjustmentRenderGeneration == generation else { return }

      let rendered = await Task.detached(priority: .userInitiated) {
        AnnotateImageAdjustmentRenderer.render(cgImage, adjustments: adjustments)
      }.value
      guard self.imageAdjustmentRenderGeneration == generation else { return }
      guard let rendered else {
        // Don't leave a preview on screen that export can't reproduce (export falls back to
        // the unadjusted base too).
        DiagnosticLogger.shared.log(.error, .annotate, "Image adjustment render failed")
        self.adjustedSourceRender = nil
        return
      }
      self.adjustedSourceRender = AnnotateAdjustedImageRender(
        base: base,
        adjustments: adjustments,
        image: AnnotateImageAdjustmentRenderer.makeImage(rendered, pointSize: pointSize),
        isFullResolution: true
      )
    }
  }

  /// One render at a time on a downscaled copy of the base; after each frame it renders the
  /// newest slider value if it moved meanwhile, so fast drags never queue renders up.
  private func startImageAdjustmentPreviewLoopIfNeeded() {
    guard imageAdjustmentPreviewTask == nil else { return }
    let budget = Self.adjustmentGesturePreviewPixelBudget

    imageAdjustmentPreviewTask = Task { [weak self] in
      defer { self?.imageAdjustmentPreviewTask = nil }
      var lastRendered: ImageAdjustments?
      while let self, self.imageAdjustmentGestureStart != nil {
        let adjustments = self.liveImageAdjustments
        guard adjustments != lastRendered,
              let base = self.adjustmentBaseImage else { return }
        if adjustments.isIdentity {
          if self.adjustedSourceRender != nil { self.adjustedSourceRender = nil }
          lastRendered = adjustments
          continue
        }

        let cachedBase = self.imageAdjustmentPreviewBase.flatMap { $0.base === base ? $0 : nil }
        let sourceCG = cachedBase == nil ? AnnotateExporter.bestCGImage(from: base) : nil
        if cachedBase == nil && sourceCG == nil { return }

        let result = await Task.detached(priority: .userInitiated) {
          () -> (preview: AnnotateAdjustmentPreviewBase.Payload, image: CGImage?)? in
          let previewBase: AnnotateAdjustmentPreviewBase.Payload
          if let cachedBase {
            previewBase = (cachedBase.image, cachedBase.scale)
          } else if let sourceCG,
                    let made = AnnotateImageAdjustmentRenderer.makePreviewBase(sourceCG, maxPixelCount: budget) {
            previewBase = made
          } else {
            return nil
          }
          let image = AnnotateImageAdjustmentRenderer.renderPreview(
            previewBase.image, adjustments: adjustments, detailScale: previewBase.scale
          )
          return (previewBase, image)
        }.value

        guard let result, self.adjustmentBaseImage === base else { return }
        if cachedBase == nil {
          self.imageAdjustmentPreviewBase = AnnotateAdjustmentPreviewBase(
            base: base, image: result.preview.image, scale: result.preview.scale
          )
        }
        lastRendered = adjustments
        // Released meanwhile: the full-resolution render owns the canvas now.
        guard self.imageAdjustmentGestureStart != nil, let image = result.image else { return }
        self.adjustedSourceRender = AnnotateAdjustedImageRender(
          base: base,
          adjustments: adjustments,
          image: AnnotateImageAdjustmentRenderer.makeImage(image, pointSize: base.size),
          isFullResolution: result.preview.scale >= 1
        )
      }
    }
  }

  /// Renders one small thumbnail per preset for the sidebar (once per base image).
  func prepareImageFilterPresetThumbnailsIfNeeded() {
    guard let base = adjustmentBaseImage else { return }
    if let thumbnailsBase = imageFilterPresetThumbnailsBase, thumbnailsBase === base { return }
    guard let cgImage = AnnotateExporter.bestCGImage(from: base) else { return }
    imageFilterPresetThumbnailsBase = base
    if !imageFilterPresetThumbnails.isEmpty {
      imageFilterPresetThumbnails = [:]
    }
    let maxDimension = Self.filterPresetThumbnailMaxDimension

    Task { [weak self] in
      let thumbnails = await Task.detached(priority: .utility) { () -> [ImageFilterPreset: CGImage] in
        // Downscale once, then run every preset on the small bitmap.
        guard let small = AnnotateImageAdjustmentRenderer.renderThumbnail(
          cgImage, adjustments: .identity, maxDimension: maxDimension
        ) else { return [:] }
        var result: [ImageFilterPreset: CGImage] = [ImageFilterPreset.none: small]
        for preset in ImageFilterPreset.allCases where preset != .none {
          if let rendered = AnnotateImageAdjustmentRenderer.render(small, adjustments: ImageAdjustments(preset: preset)) {
            result[preset] = rendered
          }
        }
        return result
      }.value
      guard let self, self.imageFilterPresetThumbnailsBase === base else { return }
      self.imageFilterPresetThumbnails = thumbnails.mapValues { thumbnail in
        NSImage(cgImage: thumbnail, size: CGSize(width: thumbnail.width, height: thumbnail.height))
      }
    }
  }
}
