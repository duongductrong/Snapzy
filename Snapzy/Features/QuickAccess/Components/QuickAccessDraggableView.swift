//
//  QuickAccessDraggableView.swift
//  Snapzy
//
//  NSView wrapper for proper drag-to-external-app support
//  Uses NSDraggingSession for reliable file drag operations
//

import AppKit
import SwiftUI

/// NSViewRepresentable that enables proper drag-to-external-app with NSDraggingSession
struct QuickAccessDraggableView<Content: View>: NSViewRepresentable {
  let content: Content
  let fileURL: URL
  let isVideo: Bool
  let thumbnail: NSImage
  let onDragStarted: () -> Void
  let onDragEnded: (Bool) -> Void

  func makeNSView(context: Context) -> DraggableHostingView<Content> {
    let view = DraggableHostingView(
      rootView: content,
      fileURL: fileURL,
      isVideo: isVideo,
      thumbnail: thumbnail,
      onDragStarted: onDragStarted,
      onDragEnded: onDragEnded
    )
    return view
  }

  func updateNSView(_ nsView: DraggableHostingView<Content>, context: Context) {
    nsView.rootView = content
    nsView.fileURL = fileURL
    nsView.isVideo = isVideo
    nsView.thumbnail = thumbnail
  }
}

/// Custom NSView that hosts SwiftUI content and handles drag operations
final class DraggableHostingView<Content: View>: NSView, NSDraggingSource {
  var rootView: Content {
    didSet {
      hostingView.rootView = rootView
    }
  }
  var fileURL: URL
  var isVideo: Bool
  var thumbnail: NSImage
  var onDragStarted: () -> Void
  var onDragEnded: (Bool) -> Void

  private var hostingView: NSHostingView<Content>!
  private var isDragging = false
  private var dragStartLocation: NSPoint?

  init(
    rootView: Content,
    fileURL: URL,
    isVideo: Bool,
    thumbnail: NSImage,
    onDragStarted: @escaping () -> Void,
    onDragEnded: @escaping (Bool) -> Void
  ) {
    self.rootView = rootView
    self.fileURL = fileURL
    self.isVideo = isVideo
    self.thumbnail = thumbnail
    self.onDragStarted = onDragStarted
    self.onDragEnded = onDragEnded

    super.init(frame: .zero)

    hostingView = NSHostingView(rootView: rootView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hostingView)

    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: topAnchor),
      hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
      hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Drag Initiation (called from SwiftUI)

  func startDrag(at location: NSPoint) {
    guard !isDragging else { return }
    isDragging = true
    onDragStarted()

    // Create drag item
    let dragItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

    // Create drag image from thumbnail
    let imageSize = NSSize(width: 120, height: 75)
    let dragImage = NSImage(size: imageSize)
    dragImage.lockFocus()
    thumbnail.draw(
      in: NSRect(origin: .zero, size: imageSize),
      from: .zero,
      operation: .sourceOver,
      fraction: 0.8
    )
    dragImage.unlockFocus()

    dragItem.setDraggingFrame(
      NSRect(origin: NSPoint(x: -60, y: -37), size: imageSize),
      contents: dragImage
    )

    // Start drag session
    let session = beginDraggingSession(with: [dragItem], event: NSApp.currentEvent!, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    return context == .outsideApplication ? .copy : .copy
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    isDragging = false
    let success = operation != []
    onDragEnded(success)
  }
}

// MARK: - Coordinator for accessing NSView from SwiftUI

extension QuickAccessDraggableView {
  class Coordinator {
    var nsView: DraggableHostingView<Content>?

    func startDrag(at location: CGPoint) {
      nsView?.startDrag(at: NSPoint(x: location.x, y: location.y))
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }
}
