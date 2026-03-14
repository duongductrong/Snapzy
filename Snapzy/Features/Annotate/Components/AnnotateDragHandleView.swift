//
//  AnnotateDragHandleView.swift
//  Snapzy
//
//  NSViewRepresentable drag handle that initiates NSDraggingSession
//  for dragging the annotated image to external apps.
//

import AppKit
import SwiftUI

/// SwiftUI wrapper for drag handle that uses NSDraggingSession
struct AnnotateDragHandleView: NSViewRepresentable {
  let state: AnnotateState

  func makeNSView(context: Context) -> DragHandleNSView {
    let view = DragHandleNSView(state: state)
    return view
  }

  func updateNSView(_ nsView: DragHandleNSView, context: Context) {
    nsView.state = state
  }
}

/// AppKit view that handles mouse-drag to start NSDraggingSession
final class DragHandleNSView: NSView, NSDraggingSource {
  var state: AnnotateState
  private var isDragging = false
  private var dragTempFileURL: URL?

  init(state: AnnotateState) {
    self.state = state
    super.init(frame: .zero)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { false }

  // MARK: - Mouse Drag → NSDraggingSession

  override func mouseDown(with event: NSEvent) {
    guard state.hasImage, !isDragging else { return }
    isDragging = true

    // Render annotated image to temp file
    guard let fileURL = AnnotateExporter.renderToTempFile(state: state) else {
      isDragging = false
      return
    }
    dragTempFileURL = fileURL

    // Create drag item
    let dragItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

    // Create drag image (thumbnail)
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

    // Create drag source
    let dragSource = AnnotateDragSource(
      dragID: UUID(),
      onEnded: { [weak self] success in
        Task { @MainActor in
          self?.isDragging = false
          // Post drag ended notification
          NotificationCenter.default.post(
            name: .annotateDragEnded,
            object: nil,
            userInfo: ["success": success]
          )
        }
      }
    )
    AnnotateDragRegistry.retain(dragSource, for: dragSource.dragID)

    // Post drag started notification (window will hide)
    NotificationCenter.default.post(name: .annotateDragStarted, object: nil)

    // Start drag session
    let session = beginDraggingSession(with: [dragItem], event: event, source: dragSource)
    session.animatesToStartingPositionsOnCancelOrFail = true

    print("[AnnotateDrag] Started drag session for annotated image")
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    return .copy
  }
}
