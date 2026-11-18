//
//  RecordingStudioFlattenJob.swift
//  Snapzy
//
//  Runs the flatten pass for one Studio recording: keeps the cursor-less original as a
//  `StudioSources` sidecar (the editor's source), renders the cursor back in, then swaps
//  the shared file in place. On any failure the cursor-less recording stays where it
//  was, so a recording is never lost.
//

import AppKit
import Foundation

@MainActor
enum RecordingStudioFlattenJob {
  enum Outcome {
    case flattened
    /// The shared file still lacks the cursor; the editor can still draw it.
    case keptOriginal(Error)
  }

  static func needsFlatten(_ metadata: RecordingMetadata?) -> Bool {
    guard let metadata else { return false }
    return (!metadata.isCursorBaked && metadata.cursorCapture != nil) || metadata.cameraSource != nil
  }

  static func run(
    url: URL,
    frameRate: Int,
    progress: @escaping @MainActor (Double) -> Void
  ) async -> Outcome {
    guard var metadata = RecordingMetadataStore.load(for: url), needsFlatten(metadata) else {
      return .flattened
    }
    let started = Date()
    let directoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(url.deletingLastPathComponent())
    defer { directoryAccess.stop() }
    let tempURL = url.deletingLastPathComponent()
      .appendingPathComponent(".snapzy-flatten-\(UUID().uuidString)")
      .appendingPathExtension(url.pathExtension)

    do {
      // The editor keeps editing the cursor-less original (APFS clone: no extra space).
      if metadata.studioSourceFileName == nil, metadata.audioSourceURL == nil {
        let stored = try RecordingMetadataStore.storeSidecar(from: url, kind: .studioSource)
        metadata.studioSourceFileName = stored.lastPathComponent
        try RecordingMetadataStore.save(metadata, for: url)
      }

      let recipe = makeRecipe(metadata: metadata)
      let cameraURL = metadata.cameraSource.flatMap { try? RecordingMetadataStore.sidecarURL(named: $0.fileName, kind: .camera) }
        .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
      try await Task.detached(priority: .utility) {
        try await RecordingStudioFlattenExporter.flatten(
          sourceURL: url,
          outputURL: tempURL,
          recipe: recipe,
          frameRate: frameRate,
          cameraURL: cameraURL,
          progress: { value in Task { @MainActor in progress(value) } }
        )
      }.value

      _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
      // Re-associate: replacing the file can invalidate the bookmark.
      try RecordingMetadataStore.save(metadata, for: url)
      DiagnosticLogger.shared.log(.info, .recording, "Studio flatten finished", context: [
        "file": url.lastPathComponent,
        "seconds": String(format: "%.2f", Date().timeIntervalSince(started)),
      ])
      return .flattened
    } catch {
      try? FileManager.default.removeItem(at: tempURL)
      DiagnosticLogger.shared.logError(.recording, error, "Studio flatten failed; keeping cursor-less recording", context: [
        "file": url.lastPathComponent,
      ])
      return .keptOriginal(error)
    }
  }

  /// The recording's Studio layers as they were while recording.
  static func makeRecipe(metadata: RecordingMetadata) -> VideoEditorStudioRecipe {
    let settings = VideoEditorCursorSettings.recorded(
      clickEffect: RecordingToolbarPreferences.highlightClicks() ? .ripple : .none,
      clickColor: highlightColor()
    )
    var layers: [any VideoEditorStudioLayer] = []
    if let cursor = VideoEditorCursorSpriteStore.load(capture: metadata.cursorCapture)
      .makeLayer(metadata: metadata, settings: settings, mapping: .identity) {
      layers.append(cursor)
    }
    if let camera = metadata.cameraSource {
      layers.append(RecordingStudioCameraLayer(source: camera, captureSize: metadata.captureSize))
    }
    return VideoEditorStudioRecipe(layers: layers)
  }

  private static func highlightColor() -> VideoEditorRGBAColor {
    let config = MouseHighlightConfiguration()
    let color = config.highlightColor.usingColorSpace(.sRGB) ?? .systemBlue
    return VideoEditorRGBAColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
                                alpha: CGFloat(config.highlightOpacity))
  }
}
