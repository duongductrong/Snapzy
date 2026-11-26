//
//  ScreenshotPresetAutoApplier.swift
//  Snapzy
//
//  Applies the configured Annotate canvas preset to captured screenshots.
//

import AppKit
import Foundation

@MainActor
final class ScreenshotPresetAutoApplier {
  static let shared = ScreenshotPresetAutoApplier(
    presetStore: AnnotateCanvasPresetStore.shared,
    fileAccess: SandboxFileAccessManager.shared
  )

  private static let emptyCanvasPresetPayload = AnnotateCanvasPresetPayload(
    backgroundStyle: CodableBackgroundStyle(from: .none)!,
    isBlurredBackgroundEnabled: false,
    blurredBackgroundEffect: .soft,
    padding: 0,
    shadowIntensity: 0.3,
    cornerRadius: AnnotateCanvasDefaults.cornerRadius,
    aspectRatio: .auto,
    aspectRatioOrientation: .horizontal
  )

  private let presetStore: AnnotateCanvasPresetStore
  private let fileAccess: SandboxFileAccessManager

  init(presetStore: AnnotateCanvasPresetStore, fileAccess: SandboxFileAccessManager) {
    self.presetStore = presetStore
    self.fileAccess = fileAccess
  }

  convenience init(presetStore: AnnotateCanvasPresetStore) {
    self.init(presetStore: presetStore, fileAccess: SandboxFileAccessManager.shared)
  }

  func applyDefaultPresetIfNeeded(to url: URL) -> AnnotationSessionData? {
    let presets = presetStore.loadPresets()
    guard let defaultPresetId = presetStore.loadDefaultPresetId(validating: presets),
          let preset = presets.first(where: { $0.id == defaultPresetId }) else {
      return nil
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      DiagnosticLogger.shared.log(
        .warning,
        .annotate,
        "Screenshot preset auto-apply skipped; file missing",
        context: ["fileName": url.lastPathComponent]
      )
      return nil
    }

    let originalImageData: Data
    do {
      originalImageData = try fileAccess.withScopedAccess(to: url) {
        try Data(contentsOf: url)
      }
    } catch {
      DiagnosticLogger.shared.logError(
        .annotate,
        error,
        "Screenshot preset auto-apply skipped; original read failed",
        context: ["fileName": url.lastPathComponent]
      )
      return nil
    }

    guard let sourceImage = AnnotateState.loadImageWithCorrectScale(from: url) else {
      DiagnosticLogger.shared.log(
        .warning,
        .annotate,
        "Screenshot preset auto-apply skipped; image load failed",
        context: ["fileName": url.lastPathComponent]
      )
      return nil
    }

    let effects = Self.canvasEffects(from: preset.payload)

    guard Self.defaultPresetChangesCanvas(preset.payload) else {
      DiagnosticLogger.shared.log(
        .debug,
        .annotate,
        "Screenshot preset auto-apply skipped; preset leaves image unchanged",
        context: ["fileName": url.lastPathComponent, "preset": preset.name]
      )
      return nil
    }

    guard let renderedImage = AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effects),
          let renderedData = AnnotateExporter.imageData(from: renderedImage, for: url.pathExtension) else {
      DiagnosticLogger.shared.log(
        .error,
        .annotate,
        "Screenshot preset auto-apply failed; render returned no data",
        context: ["fileName": url.lastPathComponent, "preset": preset.name]
      )
      return nil
    }

    do {
      try fileAccess.withScopedAccess(to: url.deletingLastPathComponent()) {
        try renderedData.write(to: url, options: .atomic)
      }
    } catch {
      DiagnosticLogger.shared.logError(
        .annotate,
        error,
        "Screenshot preset auto-apply failed; write failed",
        context: ["fileName": url.lastPathComponent, "preset": preset.name]
      )
      return nil
    }

    DiagnosticLogger.shared.log(
      .info,
      .annotate,
      "Screenshot preset auto-applied",
      context: ["fileName": url.lastPathComponent, "preset": preset.name]
    )

    return AnnotationSessionData(
      originalImageData: originalImageData,
      annotations: [],
      canvasEffects: effects,
      selectedCanvasPresetId: preset.id,
      isSelectedCanvasPresetDirty: false,
      cropRect: nil
    )
  }

  // MARK: - Automation steps

  /// The preset with `id`, or the default preset when `id` is nil.
  func preset(id: UUID?) -> AnnotateCanvasPreset? {
    let presets = presetStore.loadPresets()
    let wanted = id ?? presetStore.loadDefaultPresetId(validating: presets)
    guard let wanted else { return nil }
    return presets.first { $0.id == wanted }
  }

  /// Renders `preset` over `source` into `destination` (the source is untouched).
  /// Returns `nil` without writing when the preset leaves the image unchanged.
  func apply(_ preset: AnnotateCanvasPreset, from source: URL, writingTo destination: URL) throws -> AnnotationSessionData? {
    guard Self.defaultPresetChangesCanvas(preset.payload) else { return nil }
    let originalImageData = try fileAccess.withScopedAccess(to: source) {
      try Data(contentsOf: source)
    }
    guard let sourceImage = AnnotateState.loadImageWithCorrectScale(from: source) else {
      throw AutomationStepError.noFile
    }
    let effects = Self.canvasEffects(from: preset.payload)
    guard let renderedImage = AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effects),
          let renderedData = AnnotateExporter.imageData(from: renderedImage, for: destination.pathExtension)
    else {
      throw AutomationStepError.renderFailed
    }
    try renderedData.write(to: destination, options: .atomic)
    DiagnosticLogger.shared.log(
      .info,
      .annotate,
      "Automation canvas preset applied",
      context: ["fileName": source.lastPathComponent, "preset": preset.name]
    )
    return AnnotationSessionData(
      originalImageData: originalImageData,
      annotations: [],
      canvasEffects: effects,
      selectedCanvasPresetId: preset.id,
      isSelectedCanvasPresetDirty: false,
      cropRect: nil
    )
  }

  private static func defaultPresetChangesCanvas(_ payload: AnnotateCanvasPresetPayload) -> Bool {
    emptyCanvasPresetPayload.approximatelyEquals(payload) == false
  }

  private static func canvasEffects(from payload: AnnotateCanvasPresetPayload) -> AnnotationCanvasEffects {
    let backgroundStyle = payload.backgroundStyle.toBackgroundStyle()
    return AnnotationCanvasEffects(
      backgroundStyle: backgroundStyle,
      isBlurredBackgroundEnabled: payload.isBlurredBackgroundEnabled && backgroundStyle.supportsBlurredBackgroundEffect,
      blurredBackgroundEffect: payload.blurredBackgroundEffect,
      padding: payload.padding,
      inset: 0,
      autoBalance: true,
      shadowIntensity: payload.shadowIntensity,
      cornerRadius: payload.cornerRadius,
      imageAlignment: .center,
      aspectRatio: payload.aspectRatio,
      aspectRatioOrientation: payload.aspectRatioOrientation
    )
  }
}
