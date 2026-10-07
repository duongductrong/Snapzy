//
//  AnnotateDragHandleView.swift
//  Snapzy
//
//  NSViewRepresentable drag handle that initiates NSDraggingSession
//  for dragging the annotated image to external apps.
//
//  Performance: Uses NSFilePromiseProvider plus a warmed concrete file fallback
//  for apps that only accept public.file-url.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper for drag handle that uses NSDraggingSession + NSFilePromiseProvider
struct AnnotateDragHandleView: NSViewRepresentable {
  let state: AnnotateState

  func makeNSView(context: Context) -> DragHandleNSView {
    let view = DragHandleNSView(state: state)
    view.updateState(state)
    return view
  }

  func updateNSView(_ nsView: DragHandleNSView, context: Context) {
    nsView.updateState(state)
  }
}

/// AppKit view that initiates NSDraggingSession with a lazy NSFilePromiseProvider.
///
/// The key insight: NSDraggingItem(pasteboardWriter: NSFilePromiseProvider) lets
/// modern apps receive a lazy file. A pre-rendered fallback file URL is also
/// attached so apps that only accept concrete files can accept the first drag.
///
/// This matches how modern macOS apps (Photos, Finder previews) handle drags.
final class DragHandleNSView: NSView {
  var state: AnnotateState
  private var isDragging = false
  private weak var draggingWindow: NSWindow?
  private var generatedFallbackFileURL: URL?
  private var currentFallbackSignature: DragFallbackSignature?
  private var preparedFallbackSignature: DragFallbackSignature?
  private var fallbackPreparationTask: Task<Void, Never>?
  private var fallbackGenerationSequence: UInt64 = 0
  private var activeDragFallbackFileURL: URL?
  private var shouldRetainGeneratedFallbackFile = false

  /// Dedicated queue for file writes on drop (off main thread)
  private static let writeQueue = OperationQueue()

  init(state: AnnotateState) {
    self.state = state
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    fallbackPreparationTask?.cancel()
    if !shouldRetainGeneratedFallbackFile {
      cleanupGeneratedFallbackFileIfNeeded()
    }
  }

  override var acceptsFirstResponder: Bool { false }

  func updateState(_ newState: AnnotateState) {
    state = newState
    let nextSignature = DragFallbackSignature(state: newState)
    guard nextSignature != currentFallbackSignature else { return }
    currentFallbackSignature = nextSignature
    scheduleFallbackPreparationIfNeeded()
  }

  // MARK: - Mouse Down → Start Drag Instantly

  override func mouseDown(with event: NSEvent) {
    guard state.hasImage, !isDragging else { return }
    state.commitTextEditing()
    updateState(state)

    let preparedFallbackFileURL = fallbackFileURLForDragStart()
    let canUseSourceFileURL = state.sourceURL != nil && !state.requiresRenderedOutputForSharing
    guard canUseSourceFileURL || preparedFallbackFileURL != nil else {
      state.setDragToAppPreparationState(.preparing)
      scheduleFallbackPreparationIfNeeded()
      return
    }
    isDragging = true
    activeDragFallbackFileURL = preparedFallbackFileURL

    // Create a lazy file promise plus a guaranteed concrete file-url fallback
    // for apps that do not accept file promises.
    let resolvedUTType = Self.preferredUTType()
    let provider = AnnotateDragFilePromiseProvider(
      fileType: resolvedUTType.identifier,
      delegate: self
    )
    provider.annotateState = state
    provider.fallbackFileURL = preparedFallbackFileURL

    let dragItem = NSDraggingItem(pasteboardWriter: provider)

    // Create drag thumbnail (cheap — small rescale of existing sourceImage)
    let imageSize = NSSize(width: 120, height: 80)
    let dragImage = NSImage(size: imageSize)
    if let sourceImage = state.sourceImage {
      dragImage.lockFocus()
      sourceImage.draw(
        in: NSRect(origin: .zero, size: imageSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.8
      )
      dragImage.unlockFocus()
    }

    let mouseLocation = convert(event.locationInWindow, from: nil)
    dragItem.setDraggingFrame(
      NSRect(
        x: mouseLocation.x - imageSize.width / 2,
        y: mouseLocation.y - imageSize.height / 2,
        width: imageSize.width,
        height: imageSize.height
      ),
      contents: dragImage
    )

    // Notify only this window controller to hide the source window.
    draggingWindow = window
    NotificationCenter.default.post(name: .annotateDragStarted, object: draggingWindow)

    // Start drag session once the pasteboard writer can satisfy both promises and file URLs.
    let session = beginDraggingSession(with: [dragItem], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true

    print("[AnnotateDrag] Session started (promise + file-url fallback)")
  }
}

// MARK: - NSDraggingSource

extension DragHandleNSView: NSDraggingSource {
  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    return .copy
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    isDragging = false
    let success = operation != []
    if success, activeDragFallbackFileURL != nil {
      shouldRetainGeneratedFallbackFile = true
    }
    activeDragFallbackFileURL = nil
    if !success {
      scheduleFallbackPreparationIfNeeded()
    }
    let sourceWindow = draggingWindow
    draggingWindow = nil
    print("[AnnotateDrag] Drag ended — success=\(success), op=\(operation.rawValue)")
    Task { @MainActor in
      NotificationCenter.default.post(
        name: .annotateDragEnded,
        object: sourceWindow,
        userInfo: ["success": success]
      )
    }
  }
}

// MARK: - NSFilePromiseProviderDelegate

extension DragHandleNSView: NSFilePromiseProviderDelegate {
  /// Called on drag start to get the promised filename (cheap, no rendering)
  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    fileNameForType fileType: String
  ) -> String {
    let provider = filePromiseProvider as? AnnotateDragFilePromiseProvider
    let baseName = provider?.annotateState?.sourceURL?
      .deletingPathExtension().lastPathComponent ?? "annotated_image"
    let ext = Self.preferredFormatExtension()
    return "\(baseName)_annotated.\(ext)"
  }

  /// Called on the writeQueue AFTER user drops — render + write happens here
  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    writePromiseTo url: URL,
    completionHandler: @escaping (Error?) -> Void
  ) {
    guard let provider = filePromiseProvider as? AnnotateDragFilePromiseProvider,
          let state = provider.annotateState else {
      completionHandler(DragError.noState)
      return
    }

    if let fallbackFileURL = provider.fallbackFileURL {
      DragHandleNSView.writeQueue.addOperation {
        do {
          let data = try Data(contentsOf: fallbackFileURL)
          try data.write(to: url, options: .atomic)
          completionHandler(nil)
          print("[AnnotateDrag] Promise fulfilled from fallback: \(url.lastPathComponent)")
        } catch {
          completionHandler(error)
        }
      }
      return
    }

    // Render and encode on MainActor because the exporter touches AppKit image APIs.
    Task { @MainActor in
      let image = AnnotateExporter.renderFinalImage(state: state)
      guard let image = image else {
        completionHandler(DragError.renderFailed)
        return
      }

      let ext = Self.preferredFormatExtension()
      guard let data = AnnotateExporter.imageData(from: image, for: ext) else {
        completionHandler(DragError.encodeFailed)
        return
      }

      // Write on the promise queue so the drop target is not blocked by disk IO.
      DragHandleNSView.writeQueue.addOperation {
        do {
          try data.write(to: url, options: .atomic)
          completionHandler(nil)
          print("[AnnotateDrag] Promise fulfilled: \(url.lastPathComponent) (\(ext))")
        } catch {
          completionHandler(error)
        }
      }
    }
  }

  /// Provide a background queue for writing (Apple recommended)
  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    DragHandleNSView.writeQueue
  }
}

// MARK: - AnnotateDragFilePromiseProvider

/// Subclass of NSFilePromiseProvider that carries AnnotateState reference.
///
/// Provides BOTH:
/// 1. NSFilePromiseProvider — for modern apps that support file promises (lazy, instant drag)
/// 2. Source file URL — fallback for apps that only accept concrete file URLs
///    (browsers, Slack, older Electron apps, etc.)
///
/// This matches the pattern used by Photos.app and Finder.
final class AnnotateDragFilePromiseProvider: NSFilePromiseProvider {
  /// Keep the state alive until the file promise finishes, since a successful
  /// drop closes the source Annotate window immediately after the drag session.
  var annotateState: AnnotateState?
  var fallbackFileURL: URL?

  // MARK: - Broad Compatibility: Also Provide File URL

  override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    var types = super.writableTypes(for: pasteboard)
    // Also advertise as a file URL so non-promise apps can accept the drag.
    // Dirty source-backed edits must use the rendered fallback file; exposing
    // sourceURL here would let apps read stale pixels from disk.
    let canUseSourceFileURL = annotateState?.sourceURL != nil && annotateState?.requiresRenderedOutputForSharing != true
    if fallbackFileURL != nil || canUseSourceFileURL {
      types.append(.fileURL)
    }
    return types
  }

  override func writingOptions(
    forType type: NSPasteboard.PasteboardType,
    pasteboard: NSPasteboard
  ) -> NSPasteboard.WritingOptions {
    // Promised types should be lazy; file URL can be written immediately
    if type == .fileURL { return [] }
    return super.writingOptions(forType: type, pasteboard: pasteboard)
  }

  override func pasteboardPropertyList(
    forType type: NSPasteboard.PasteboardType
  ) -> Any? {
    // Provide a concrete file URL for apps that ask for NSFilenamesPboardType / public.file-url.
    if type == .fileURL {
      if let fallbackFileURL {
        return (fallbackFileURL as NSURL).pasteboardPropertyList(forType: type)
      }
      guard annotateState?.requiresRenderedOutputForSharing != true else { return nil }
      let url = annotateState?.sourceURL
      return (url as NSURL?)?.pasteboardPropertyList(forType: type)
    }
    return super.pasteboardPropertyList(forType: type)
  }
}


// MARK: - Error

private enum DragError: Error {
  case noState
  case renderFailed
  case encodeFailed
}

// MARK: - Format Helpers

extension DragHandleNSView {
  private func preparedFallbackFileURLForCurrentState() -> URL? {
    guard preparedFallbackSignature == currentFallbackSignature else { return nil }
    return generatedFallbackFileURL
  }

  private func fallbackFileURLForDragStart() -> URL? {
    guard state.sourceURL == nil || state.requiresRenderedOutputForSharing else {
      return nil
    }

    if let preparedFallbackFileURL = preparedFallbackFileURLForCurrentState() {
      return preparedFallbackFileURL
    }

    guard let signature = currentFallbackSignature else { return nil }
    cancelFallbackPreparationTask()
    return prepareConcreteFallbackFileIfNeeded(for: signature)
  }

  private func scheduleFallbackPreparationIfNeeded() {
    fallbackGenerationSequence &+= 1
    let generation = fallbackGenerationSequence
    cancelFallbackPreparationTask()
    preparedFallbackSignature = nil

    guard !isDragging else { return }

    guard state.hasImage else {
      cleanupGeneratedFallbackFileIfNeeded()
      state.setDragToAppPreparationState(.unavailable)
      return
    }

    guard state.sourceURL == nil || state.requiresRenderedOutputForSharing else {
      cleanupGeneratedFallbackFileIfNeeded()
      state.setDragToAppPreparationState(.ready)
      return
    }

    guard let signature = currentFallbackSignature else {
      cleanupGeneratedFallbackFileIfNeeded()
      state.setDragToAppPreparationState(.unavailable)
      return
    }

    state.setDragToAppPreparationState(.preparing)
    fallbackPreparationTask = Task(priority: .utility) { @MainActor [weak self] in
      await Task.yield()

      guard let self,
            !Task.isCancelled,
            self.fallbackGenerationSequence == generation,
            self.currentFallbackSignature == signature else { return }
      _ = self.prepareConcreteFallbackFileIfNeeded(for: signature)
    }
  }

  private func cancelFallbackPreparationTask() {
    fallbackPreparationTask?.cancel()
    fallbackPreparationTask = nil
  }

  private func cleanupGeneratedFallbackFileIfNeeded() {
    guard let existing = generatedFallbackFileURL else {
      preparedFallbackSignature = nil
      return
    }
    try? FileManager.default.removeItem(at: existing.deletingLastPathComponent())
    generatedFallbackFileURL = nil
    preparedFallbackSignature = nil
  }

  @MainActor
  private func prepareConcreteFallbackFileIfNeeded(for signature: DragFallbackSignature) -> URL? {
    guard let image = AnnotateExporter.renderFinalImage(state: state) else {
      state.setDragToAppPreparationState(.unavailable)
      return nil
    }

    let ext = Self.preferredFormatExtension()
    guard let data = AnnotateExporter.imageData(from: image, for: ext) else {
      state.setDragToAppPreparationState(.unavailable)
      return nil
    }

    let rootDirectory = Self.dragFallbackRootDirectory()
    let sessionDirectory = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let baseName = state.sourceURL?.deletingPathExtension().lastPathComponent ?? "annotated_image"
    let fileURL = sessionDirectory.appendingPathComponent("\(baseName)_annotated.\(ext)")
    let previousFallbackFileURL = generatedFallbackFileURL

    do {
      try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
      try data.write(to: fileURL, options: .atomic)
      generatedFallbackFileURL = fileURL
      preparedFallbackSignature = signature
      state.setDragToAppPreparationState(.ready)
      if let previousFallbackFileURL {
        try? FileManager.default.removeItem(at: previousFallbackFileURL.deletingLastPathComponent())
      }
      return fileURL
    } catch {
      try? FileManager.default.removeItem(at: sessionDirectory)
      state.setDragToAppPreparationState(.unavailable)
      DiagnosticLogger.shared.logError(.annotate, error, "Annotate drag fallback export failed")
      return nil
    }
  }

  private static func dragFallbackRootDirectory() -> URL {
    let fileManager = FileManager.default
    if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let url = appSupport
        .appendingPathComponent("Snapzy", isDirectory: true)
        .appendingPathComponent("Captures", isDirectory: true)
        .appendingPathComponent("AnnotateDrag", isDirectory: true)
      try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }

    let fallback = fileManager.temporaryDirectory
      .appendingPathComponent("Snapzy_Captures", isDirectory: true)
      .appendingPathComponent("AnnotateDrag", isDirectory: true)
    try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
    return fallback
  }

  /// Resolve the user's preferred screenshot format as UTType
  static func preferredUTType() -> UTType {
    guard let raw = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
          let option = ImageFormatOption(rawValue: raw) else { return .png }
    switch option {
    case .png:  return .png
    case .jpeg: return .jpeg
    case .webp: return .webP
    }
  }

  /// Resolve the user's preferred screenshot format file extension
  static func preferredFormatExtension() -> String {
    guard let raw = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
          let option = ImageFormatOption(rawValue: raw) else { return "png" }
    return option.format.fileExtension
  }
}

private struct DragFallbackSignature: Equatable {
  let sourceIdentity: String
  let editorMode: String
  let cropRect: String?
  let backgroundStyle: String
  let isBlurredBackgroundEnabled: Bool
  let blurredBackgroundEffect: String
  let padding: Int64
  let inset: Int64
  let autoBalance: Bool
  let shadowIntensity: Int64
  let cornerRadius: Int64
  let imageAlignment: String
  let aspectRatio: String
  let mockupRotationX: Int64
  let mockupRotationY: Int64
  let mockupRotationZ: Int64
  let mockupPerspective: Int64
  let mockupShadowIntensity: Int64
  let mockupCornerRadius: Int64
  let mockupPadding: Int64
  let annotations: [String]
  let embeddedAssets: [String]

  init?(state: AnnotateState) {
    guard state.hasImage else { return nil }

    sourceIdentity = Self.sourceIdentity(for: state)
    editorMode = state.editorMode.rawValue
    cropRect = state.cropRect.map(Self.rectSignature)
    backgroundStyle = Self.backgroundStyleSignature(state.backgroundStyle)
    isBlurredBackgroundEnabled = state.isBlurredBackgroundEnabled
    blurredBackgroundEffect = state.blurredBackgroundEffect.rawValue
    padding = Self.quantize(state.padding)
    inset = Self.quantize(state.inset)
    autoBalance = state.autoBalance
    shadowIntensity = Self.quantize(state.shadowIntensity)
    cornerRadius = Self.quantize(state.cornerRadius)
    imageAlignment = state.imageAlignment.rawValue
    aspectRatio = state.aspectRatio.rawValue
    mockupRotationX = Self.quantize(state.mockupRotationX)
    mockupRotationY = Self.quantize(state.mockupRotationY)
    mockupRotationZ = Self.quantize(state.mockupRotationZ)
    mockupPerspective = Self.quantize(state.mockupPerspective)
    mockupShadowIntensity = Self.quantize(state.mockupShadowIntensity)
    mockupCornerRadius = Self.quantize(state.mockupCornerRadius)
    mockupPadding = Self.quantize(state.mockupPadding)
    annotations = state.annotations.map(Self.annotationSignature)
    embeddedAssets = state.annotations.compactMap { annotation in
      guard case .embeddedImage(let assetId) = annotation.type else { return nil }
      return "\(assetId.uuidString)|\(Self.imageIdentity(state.embeddedImage(for: assetId)) ?? "nil")"
    }
  }

  private static func sourceIdentity(for state: AnnotateState) -> String {
    let sourceURL = state.sourceURL?.absoluteString ?? "nil"
    let sourceImage = imageIdentity(state.sourceImage) ?? "nil"
    let effectiveImage = imageIdentity(state.effectiveSourceImage) ?? "nil"
    return "\(sourceURL)|\(sourceImage)|\(effectiveImage)|cutout=\(state.isCutoutApplied)"
  }

  private static func backgroundStyleSignature(_ style: BackgroundStyle) -> String {
    switch style {
    case .none:
      return "none"
    case .gradient(let preset):
      return "gradient|\(preset.rawValue)"
    case .wallpaper(let url):
      return "wallpaper|\(url.absoluteString)"
    case .blurred(let url):
      return "blurred|\(url.absoluteString)"
    case .solidColor(let color):
      return "solid|\(colorSignature(color))"
    }
  }

  private nonisolated static func annotationSignature(_ annotation: AnnotationItem) -> String {
    let properties = annotation.properties
    return [
      annotation.id.uuidString,
      annotationTypeSignature(annotation.type),
      rectSignature(annotation.bounds),
      colorSignature(properties.strokeColor),
      colorSignature(properties.fillColor),
      String(quantize(properties.strokeWidth)),
      String(quantize(properties.cornerRadius)),
      String(quantize(properties.fontSize)),
      properties.fontName,
      String(quantize(properties.opacity)),
      String(quantize(properties.rotationDegrees)),
      properties.watermarkStyle.rawValue
    ].joined(separator: "|")
  }

  private nonisolated static func annotationTypeSignature(_ type: AnnotationType) -> String {
    switch type {
    case .path(let points):
      return "path|\(points.map(pointSignature).joined(separator: ";"))"
    case .rectangle:
      return "rectangle"
    case .filledRectangle:
      return "filledRectangle"
    case .oval:
      return "oval"
    case .arrow(let geometry):
      let controlPoint = geometry.resolvedControlPoint.map(pointSignature) ?? "nil"
      return "arrow|\(pointSignature(geometry.start))|\(pointSignature(geometry.end))|\(geometry.style.rawValue)|\(controlPoint)"
    case .line(let start, let end):
      return "line|\(pointSignature(start))|\(pointSignature(end))"
    case .text(let value):
      return "text|\(value)"
    case .highlight(let points):
      return "highlight|\(points.map(pointSignature).joined(separator: ";"))"
    case .blur(let blurType):
      return "blur|\(blurType.rawValue)"
    case .counter(let value):
      return "counter|\(value)"
    case .watermark(let text):
      return "watermark|\(text)"
    case .embeddedImage(let assetId):
      return "embeddedImage|\(assetId.uuidString)"
    case .spotlight:
      return "spotlight"
    }
  }

  private nonisolated static func rectSignature(_ rect: CGRect) -> String {
    let standardized = rect.standardized
    return "\(quantize(standardized.origin.x)),\(quantize(standardized.origin.y)),\(quantize(standardized.size.width)),\(quantize(standardized.size.height))"
  }

  private nonisolated static func pointSignature(_ point: CGPoint) -> String {
    "\(quantize(point.x)),\(quantize(point.y))"
  }

  private nonisolated static func colorSignature(_ color: Color) -> String {
    guard let rgba = RGBAColor(color: color) else {
      return String(reflecting: color)
    }
    return "\(quantize(rgba.red)),\(quantize(rgba.green)),\(quantize(rgba.blue)),\(quantize(rgba.alpha))"
  }

  private static func imageIdentity(_ image: NSImage?) -> String? {
    guard let image else { return nil }
    let pointer = UInt(bitPattern: Unmanaged.passUnretained(image).toOpaque())
    return "\(pointer)|\(quantize(image.size.width))x\(quantize(image.size.height))"
  }

  private nonisolated static func quantize(_ value: CGFloat) -> Int64 {
    Int64((value * 10_000).rounded())
  }

  private nonisolated static func quantize(_ value: Double) -> Int64 {
    Int64((value * 10_000).rounded())
  }
}
