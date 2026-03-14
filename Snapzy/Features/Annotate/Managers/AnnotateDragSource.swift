//
//  AnnotateDragSource.swift
//  Snapzy
//
//  NSDraggingSource for dragging annotated images to external apps
//

import AppKit

/// Drag source handler for annotate window drag-to-external-app sessions.
final class AnnotateDragSource: NSObject, NSDraggingSource {
  let dragID: UUID
  private let onEnded: (Bool) -> Void

  init(
    dragID: UUID,
    onEnded: @escaping (Bool) -> Void
  ) {
    self.dragID = dragID
    self.onEnded = onEnded
    super.init()
  }

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
    AnnotateDragRegistry.release(for: dragID)
    let success = operation != []
    print("[AnnotateDrag] Drag ended — success=\(success), operation=\(operation.rawValue)")
    onEnded(success)
  }
}

// MARK: - Drag Registry

/// Retains drag source objects during active drag sessions to prevent deallocation.
enum AnnotateDragRegistry {
  private static let lock = NSLock()
  private static var activeSources: [UUID: AnnotateDragSource] = [:]

  static func retain(_ source: AnnotateDragSource, for id: UUID) {
    lock.lock()
    activeSources[id] = source
    lock.unlock()
  }

  static func release(for id: UUID) {
    lock.lock()
    activeSources[id] = nil
    lock.unlock()
  }
}
