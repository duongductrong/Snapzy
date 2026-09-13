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

  // MARK: - Activation Policy Management

  /// Check if any video editor windows are open
  var hasOpenWindows: Bool {
    !windowControllers.isEmpty || !urlWindowControllers.isEmpty || emptyWindowController != nil
  }

  /// Switch to regular app mode (visible in Dock + Cmd+Tab)
  private func becomeRegularApp() {
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
  }

  /// Switch back to accessory mode (menu bar only) if no windows open
  private func becomeAccessoryAppIfNeeded() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard !hasOpenWindows else { return }
      guard !AnnotateManager.shared.hasOpenWindows else { return }
      NSApp.revertActivationPolicyToAccessoryIfNeeded()
    }
  }

  /// Open video editor for a quick access item
  func openEditor(for item: QuickAccessItem) {
    guard item.isVideo else { return }

    // Reuse existing window if open
    if let existing = windowControllers[item.id] {
      DiagnosticLogger.shared.log(.debug, .editor, "Video editor reused", context: ["itemId": item.id.uuidString])
      existing.showWindow()
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    DiagnosticLogger.shared.log(.info, .editor, "Opening video editor", context: ["itemId": item.id.uuidString])

    let controller = VideoEditorWindowController(item: item)
    windowControllers[item.id] = controller

    // Pause Quick Access countdown for this item + newer items
    QuickAccessManager.shared.pauseCountdownForEditingItem(item.id)

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.cleanupWindow(for: itemId)
          self?.becomeAccessoryAppIfNeeded()

          // Resume Quick Access countdown
          QuickAccessManager.shared.resumeCountdownForEditingItem(itemId)
        }
      }
      observers[itemId] = observer
    }

    controller.showWindow()
    QuickAccessManager.shared.setWindowOpen(id: item.id, isOpen: true)
  }

  /// Open video editor for a video URL directly
  func openEditor(for url: URL, originalURL: URL? = nil) {
    // Validate it's a video file
    guard isVideoFile(url) else { return }

    // If Quick Access has this item, reuse it to link the video editor window
    if let existingItem = QuickAccessManager.shared.items
      .first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) {
      openEditor(for: existingItem)
      return
    }

    // Reuse existing window if open
    if let existing = urlWindowControllers[url] {
      DiagnosticLogger.shared.log(.debug, .editor, "Video editor reused", context: ["file": url.lastPathComponent])
      existing.showWindow()
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Opening video editor for URL",
      context: ["file": url.lastPathComponent]
    )

    let controller = VideoEditorWindowController(url: url, originalURL: originalURL)
    urlWindowControllers[url] = controller

    // Remove from tracking when window closes
    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.cleanupURLWindow(for: url)
          self?.becomeAccessoryAppIfNeeded()
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
      DiagnosticLogger.shared.log(.debug, .editor, "Empty video editor reused")
      existing.showWindow()
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    DiagnosticLogger.shared.log(.info, .editor, "Opening empty video editor")

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
        MainActor.assumeIsolated {
          self?.emptyWindowController = nil
          self?.becomeAccessoryAppIfNeeded()
        }
      }
    }

    controller.showWindow()
  }

  /// Validate if URL is a video or GIF file
  private func isVideoFile(_ url: URL) -> Bool {
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
      // Fallback: check extension directly for GIF
      return url.pathExtension.lowercased() == "gif"
    }
    return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .gif)
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

    for (_, observer) in urlObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    urlObservers.removeAll()

    // Close all windows
    for controller in windowControllers.values {
      controller.window?.close()
    }
    windowControllers.removeAll()

    for controller in urlWindowControllers.values {
      controller.window?.close()
    }
    urlWindowControllers.removeAll()

    emptyWindowController?.window?.close()
    emptyWindowController = nil

    becomeAccessoryAppIfNeeded()
  }

  private func cleanupWindow(for itemId: UUID) {
    if let observer = observers[itemId] {
      NotificationCenter.default.removeObserver(observer)
      observers.removeValue(forKey: itemId)
    }
    windowControllers.removeValue(forKey: itemId)
    DiagnosticLogger.shared.log(.debug, .editor, "Video editor window closed", context: ["itemId": itemId.uuidString])
  }
}
