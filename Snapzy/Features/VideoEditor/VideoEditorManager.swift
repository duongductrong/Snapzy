//
//  VideoEditorManager.swift
//  Snapzy
//
//  Singleton manager for video editor windows (placeholder)
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Manages video editor window instances
@MainActor
final class VideoEditorManager {

  static let shared = VideoEditorManager()

  private var windowControllers: [UUID: VideoEditorWindowController] = [:]
  private var urlWindowControllers: [URL: VideoEditorWindowController] = [:]
  private var emptyWindowController: VideoEditorWindowController?
  private var observers: [UUID: NSObjectProtocol] = [:]
  private var urlObservers: [URL: NSObjectProtocol] = [:]

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

  /// Open video editor for a video URL directly
  func openEditor(for url: URL, originalURL: URL? = nil) {
    // Validate it's a video file
    guard isVideoFile(url) else { return }

    // Reuse existing window if open
    if let existing = urlWindowControllers[url] {
      existing.showWindow()
      return
    }

    let controller = VideoEditorWindowController(url: url, originalURL: originalURL)
    urlWindowControllers[url] = controller

    // Remove from tracking when window closes
    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.cleanupURLWindow(for: url)
        }
      }
      urlObservers[url] = observer
    }

    controller.showWindow()
  }

  /// Open video editor with empty state for drag & drop
  func openEmptyEditor() {
    // Reuse existing empty window if open
    if let existing = emptyWindowController {
      existing.showWindow()
      return
    }

    let controller = VideoEditorWindowController()
    controller.onVideoLoaded = { [weak self] url, originalURL in
      self?.handleVideoLoaded(url: url, originalURL: originalURL, from: controller)
    }
    emptyWindowController = controller

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

  /// Validate if URL is a video file
  private func isVideoFile(_ url: URL) -> Bool {
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
      return false
    }
    return type.conforms(to: .movie) || type.conforms(to: .video)
  }

  /// Handle video loaded in empty editor
  private func handleVideoLoaded(url: URL, originalURL: URL?, from controller: VideoEditorWindowController) {
    // Close empty window and open proper editor
    emptyWindowController = nil
    controller.window?.close()
    openEditor(for: url, originalURL: originalURL)
  }

  private func cleanupURLWindow(for url: URL) {
    if let observer = urlObservers[url] {
      NotificationCenter.default.removeObserver(observer)
      urlObservers.removeValue(forKey: url)
    }
    urlWindowControllers.removeValue(forKey: url)
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
