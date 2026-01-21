//
//  VideoEditorManager.swift
//  ClaudeShot
//
//  Singleton manager for video editor windows (placeholder)
//

import AppKit
import Foundation

/// Manages video editor window instances
@MainActor
final class VideoEditorManager {

  static let shared = VideoEditorManager()

  private var windowControllers: [UUID: VideoEditorWindowController] = [:]
  private var observers: [UUID: NSObjectProtocol] = [:]

  private init() {}

  /// Open video editor for a quick access item
  func openEditor(for item: QuickAccessItem) {
    guard item.isVideo else { return }

    // Reuse existing window if open
    if let existing = windowControllers[item.id] {
      existing.showWindow()
      return
    }

    let controller = VideoEditorWindowController(item: item)
    windowControllers[item.id] = controller

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.cleanupWindow(for: itemId)
        }
      }
      observers[itemId] = observer
    }

    controller.showWindow()
  }

  /// Close all video editor windows
  func closeAll() {
    // Remove all observers
    for (_, observer) in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()

    // Close all windows
    for controller in windowControllers.values {
      controller.window?.close()
    }
    windowControllers.removeAll()
  }

  private func cleanupWindow(for itemId: UUID) {
    if let observer = observers[itemId] {
      NotificationCenter.default.removeObserver(observer)
      observers.removeValue(forKey: itemId)
    }
    windowControllers.removeValue(forKey: itemId)
  }
}
