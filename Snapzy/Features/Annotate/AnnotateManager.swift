//
//  AnnotateManager.swift
//  Snapzy
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

  /// Track if we switched to regular app mode
  private var isRegularAppMode = false

  private init() {}

  // MARK: - Activation Policy Management

  /// Switch to regular app mode (visible in Dock + Cmd+Tab)
  private func becomeRegularApp() {
    guard !isRegularAppMode else { return }
    isRegularAppMode = true
    NSApp.setActivationPolicy(.regular)
  }

  /// Switch back to accessory mode (menu bar only) if no windows open
  private func becomeAccessoryAppIfNeeded() {
    guard isRegularAppMode else { return }
    guard windowControllers.isEmpty && emptyWindowController == nil else { return }
    isRegularAppMode = false
    NSApp.setActivationPolicy(.accessory)
  }

  /// Check if any annotate windows are open
  var hasOpenWindows: Bool {
    !windowControllers.isEmpty || emptyWindowController != nil
  }

  /// Open annotation window for a quick access item
  func openAnnotation(for item: QuickAccessItem) {
    // Check if already open for this item
    if let existing = windowControllers[item.id] {
      existing.showWindow()
      DiagnosticLogger.shared.log(.info, .action, "Annotate window reused for item \(item.id)")
      return
    }

    guard NSScreen.screens.isEmpty == false else {
      DiagnosticLogger.shared.log(.error, .action, "Annotate open failed: no screens available")
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    let controller = AnnotateWindowController(item: item)
    windowControllers[item.id] = controller
    DiagnosticLogger.shared.log(.info, .action, "Annotate window opened for item \(item.id)")

    // Pause Quick Access countdown for this item + newer items
    QuickAccessManager.shared.pauseCountdownForEditingItem(item.id)

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.windowControllers.removeValue(forKey: itemId)
          self?.becomeAccessoryAppIfNeeded()

          // Resume Quick Access countdown
          QuickAccessManager.shared.resumeCountdownForEditingItem(itemId)
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

    becomeAccessoryAppIfNeeded()
  }

  /// Check if annotation window is open for item
  func isOpen(for itemId: UUID) -> Bool {
    windowControllers[itemId] != nil
  }

  /// Open annotation window directly from a file URL (used by post-capture auto-open)
  func openAnnotation(url: URL) {
    guard NSScreen.screens.isEmpty == false else {
      DiagnosticLogger.shared.log(.error, .action, "Annotate open failed: no screens available")
      return
    }

    // If Quick Access has this item, reuse it to link the annotation window
    if let existingItem = QuickAccessManager.shared.items.first(where: { $0.url == url }) {
      openAnnotation(for: existingItem)
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    let controller = AnnotateWindowController(url: url)
    let controllerId = UUID()
    windowControllers[controllerId] = controller
    DiagnosticLogger.shared.log(.info, .action, "Annotate window opened for URL \(url.lastPathComponent)")

    // Remove from tracking when window closes
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.windowControllers.removeValue(forKey: controllerId)
          self?.becomeAccessoryAppIfNeeded()
        }
      }
    }

    controller.showWindow()
  }

  /// Open empty annotation window for drag-drop workflow
  func openEmptyAnnotation() {
    // Reuse existing empty window if open
    if let existing = emptyWindowController {
      existing.showWindow()
      DiagnosticLogger.shared.log(.info, .action, "Annotate empty window reused")
      return
    }

    guard NSScreen.screens.isEmpty == false else {
      DiagnosticLogger.shared.log(.error, .action, "Annotate open failed: no screens available")
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    let controller = AnnotateWindowController()
    emptyWindowController = controller
    DiagnosticLogger.shared.log(.info, .action, "Annotate empty window opened")

    // Clear reference when window closes
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
}
