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

extension AnnotateState {
  /// Bases above this pixel count publish a downscaled preview before the full render.
  private static let adjustmentPreviewPixelThreshold = 12_000_000
  /// Pixel budget for that preview (still sharp at the canvas' fit scale).
  private static let adjustmentPreviewPixelBudget = 4_000_000
  /// While a slider drags on a large base, wait this long without changes before the
  /// full-resolution render.
  private static let adjustmentFullRenderDebounceNanoseconds: UInt64 = 200_000_000
  private static let filterPresetThumbnailMaxDimension: CGFloat = 160

  /// Adjustments apply to the single base image; combine layouts have no single source, so
  /// the controls hide there unless adjustments made earlier still need a way to be reset.
  var canAdjustImage: Bool {
    hasImage && (!isCombineMode || !imageAdjustments.isIdentity)
  }

  /// Adjusted image for `base` when one was rendered from it (live preview may lag a few
  /// frames behind the sliders), else nil.
  func currentAdjustedImage(for base: NSImage?) -> NSImage? {
    guard let base,
          !imageAdjustments.isIdentity,
          let render = adjustedSourceRender,
          render.base === base else { return nil }
    return render.image
  }

  /// Full-resolution image for export: renders synchronously when the cached render is a
  /// preview, stale, or still in flight.
  func exportSourceImage() -> NSImage? {
    guard let base = adjustmentBaseImage else { return nil }
    let adjustments = imageAdjustments
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
  }

  /// Live slider value: re-render the preview without touching the undo stack.
  func updateImageAdjustmentGesture(_ adjustments: ImageAdjustments) {
    if imageAdjustmentGestureStart == nil {
      beginImageAdjustmentGesture()
    }
    let clamped = adjustments.clamped
    guard clamped != imageAdjustments else { return }
    imageAdjustments = clamped
    scheduleImageAdjustmentRender()
  }

  func endImageAdjustmentGesture() {
    guard let start = imageAdjustmentGestureStart else { return }
    imageAdjustmentGestureStart = nil
    if start != imageAdjustments {
      pushImageAdjustmentsUndo(start)
    }
    // A large base may be waiting out the drag debounce; render full resolution now.
    scheduleImageAdjustmentRender()
  }

  /// Undo/redo target (the caller already moved the current value to the other stack).
  func applyImageAdjustmentsFromUndo(_ adjustments: ImageAdjustments) {
    imageAdjustmentGestureStart = nil
    imageAdjustments = adjustments
    hasUnsavedChanges = true
    scheduleImageAdjustmentRender()
  }

  /// Session restore (QuickAccess cache, sidecar): no undo step, not an unsaved change.
  /// Small images render synchronously so the editor never opens on the original pixels.
  func restoreImageAdjustments(_ adjustments: ImageAdjustments) {
    imageAdjustmentGestureStart = nil
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
    imageAdjustmentGestureStart = nil
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
    guard !imageAdjustments.isIdentity || adjustedSourceRender != nil else { return }
    scheduleImageAdjustmentRender()
  }

  // MARK: - Rendering

  /// Renders the adjusted image off the main actor. Renders are chained (one in flight)
  /// and only the newest request renders, so fast slider drags coalesce.
  func scheduleImageAdjustmentRender() {
    imageAdjustmentRenderGeneration &+= 1
    let generation = imageAdjustmentRenderGeneration
    let adjustments = imageAdjustments

    guard let base = adjustmentBaseImage, !adjustments.isIdentity else {
      imageAdjustmentRenderTask?.cancel()
      imageAdjustmentRenderTask = nil
      if adjustedSourceRender != nil {
        adjustedSourceRender = nil
      }
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
    let debounce = Self.adjustmentFullRenderDebounceNanoseconds
    let previous = imageAdjustmentRenderTask
    previous?.cancel()

    imageAdjustmentRenderTask = Task { [weak self] in
      // Large bases: the cheap preview never waits behind an in-flight full render (the
      // detached Core Image work can't be interrupted); only the full render is chained.
      if !usesPreview {
        await previous?.value
      }
      guard let self, self.imageAdjustmentRenderGeneration == generation else { return }

      if usesPreview {
        let preview = await Task.detached(priority: .userInitiated) {
          AnnotateImageAdjustmentRenderer.render(cgImage, adjustments: adjustments, maxPixelCount: previewBudget)
        }.value
        guard self.imageAdjustmentRenderGeneration == generation else { return }
        if let preview {
          self.adjustedSourceRender = AnnotateAdjustedImageRender(
            base: base,
            adjustments: adjustments,
            image: AnnotateImageAdjustmentRenderer.makeImage(preview, pointSize: pointSize),
            isFullResolution: false
          )
        }
        if self.imageAdjustmentGestureStart != nil {
          try? await Task.sleep(nanoseconds: debounce)
          guard !Task.isCancelled, self.imageAdjustmentRenderGeneration == generation else { return }
        }
        await previous?.value
        guard self.imageAdjustmentRenderGeneration == generation else { return }
      }

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
