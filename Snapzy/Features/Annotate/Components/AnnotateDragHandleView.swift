//
//  AnnotateDragHandleView.swift
//  Snapzy
//
//  NSViewRepresentable drag handle that initiates NSDraggingSession
//  for dragging the annotated image to external apps.
//
//  Performance: Uses NSFilePromiseProvider so the drag session starts
//  INSTANTLY with zero upfront work. Rendering only happens when the
//  drop target actually requests the file (after user releases the mouse).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper for drag handle that uses NSDraggingSession + NSFilePromiseProvider
struct AnnotateDragHandleView: NSViewRepresentable {
  let state: AnnotateState

  func makeNSView(context: Context) -> DragHandleNSView {
    DragHandleNSView(state: state)
  }

  func updateNSView(_ nsView: DragHandleNSView, context: Context) {
    nsView.state = state
  }
}

/// AppKit view that initiates NSDraggingSession with a lazy NSFilePromiseProvider.
///
/// The key insight: NSDraggingItem(pasteboardWriter: NSFilePromiseProvider) starts
/// the drag IMMEDIATELY — no file needs to exist yet. The provider's delegate
/// `filePromiseProvider(_:writePromiseTo:completionHandler:)` is only called
/// AFTER the user drops onto a target app, at which point we render + write the PNG.
///
/// This matches how modern macOS apps (Photos, Finder previews) handle drags.
final class DragHandleNSView: NSView {
  var state: AnnotateState
  private var isDragging = false

  /// Dedicated queue for rendering + writing on drop (off main thread)
  private static let writeQueue = OperationQueue()

  init(state: AnnotateState) {
    self.state = state
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { false }

  // MARK: - Mouse Down → Start Drag Instantly

  override func mouseDown(with event: NSEvent) {
    guard state.hasImage, !isDragging else { return }
    isDragging = true

    // Create a lazy file promise — NO rendering happens here.
    // The provider asks for the file only after the user actually drops.
    let resolvedUTType = Self.preferredUTType()
    let provider = AnnotateDragFilePromiseProvider(
      fileType: resolvedUTType.identifier,
      delegate: self
    )
    provider.annotateState = state

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

    // Notify window controller to hide the window
    NotificationCenter.default.post(name: .annotateDragStarted, object: nil)

    // Start drag session — instant, nothing blocked
    let session = beginDraggingSession(with: [dragItem], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true

    print("[AnnotateDrag] Session started (instant — lazy promise)")
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
    print("[AnnotateDrag] Drag ended — success=\(success), op=\(operation.rawValue)")
    Task { @MainActor in
      NotificationCenter.default.post(
        name: .annotateDragEnded,
        object: nil,
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

    // Render happens on main thread (AppKit requirement)
    DispatchQueue.main.async {
      let image = AnnotateExporter.renderFinalImage(state: state)
      guard let image = image else {
        completionHandler(DragError.renderFailed)
        return
      }

      // Encode in the user's configured format + write on the promise queue (background)
      let ext = Self.preferredFormatExtension()
      DragHandleNSView.writeQueue.addOperation {
        guard let data = AnnotateExporter.imageData(from: image, for: ext) else {
          completionHandler(DragError.encodeFailed)
          return
        }

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
  /// Weak reference to avoid retain cycles; state lives in the window controller
  weak var annotateState: AnnotateState?

  // MARK: - Broad Compatibility: Also Provide File URL

  override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    var types = super.writableTypes(for: pasteboard)
    // Also advertise as a file URL so non-promise apps can accept the drag
    types.append(.fileURL)
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
    // Provide source file URL for apps that ask for NSFilenamesPboardType / public.file-url
    if type == .fileURL {
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
