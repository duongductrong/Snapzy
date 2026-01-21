//
//  AnnotateManager.swift
//  ClaudeShot
//
//  Singleton manager for opening and tracking annotation windows
//

import AppKit
import Foundation

/// Manages annotation window instances
@MainActor
final class AnnotateManager {

  static let shared = AnnotateManager()

  private var windowControllers: [UUID: AnnotateWindowController] = [:]
  private var emptyWindowController: AnnotateWindowController?

  private init() {}

  /// Open annotation window for a quick access item
  func openAnnotation(for item: QuickAccessItem) {
    // Check if already open for this item
    if let existing = windowControllers[item.id] {
      existing.showWindow()
      return
    }

    let controller = AnnotateWindowController(item: item)
    windowControllers[item.id] = controller

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.windowControllers.removeValue(forKey: itemId)
        }
      }
    }

    controller.showWindow()
  }

  /// Close all annotation windows
  func closeAll() {
    for controller in windowControllers.values {
      controller.window?.close()
    }
    windowControllers.removeAll()

    emptyWindowController?.window?.close()
    emptyWindowController = nil
  }

  /// Check if annotation window is open for item
  func isOpen(for itemId: UUID) -> Bool {
    windowControllers[itemId] != nil
  }

  /// Open empty annotation window for drag-drop workflow
  func openEmptyAnnotation() {
    // Reuse existing empty window if open
    if let existing = emptyWindowController {
      existing.showWindow()
      return
    }

    let controller = AnnotateWindowController()
    emptyWindowController = controller

    // Clear reference when window closes
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.emptyWindowController = nil
        }
      }
    }

    controller.showWindow()
  }
}
