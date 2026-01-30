//
//  AnnotateWindowController.swift
//  Snapzy
//
//  Controller managing annotation window lifecycle
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Manages annotation window lifecycle and content
@MainActor
final class AnnotateWindowController: NSWindowController, NSWindowDelegate {

  private let state: AnnotateState
  private let quickAccessItemId: UUID?
  private var cancellables = Set<AnyCancellable>()

  init(item: QuickAccessItem) {
    self.quickAccessItemId = item.id

    // Load full image from URL and adjust for Retina scaling
    let image = Self.loadImageWithCorrectScale(from: item.url) ?? item.thumbnail

    self.state = AnnotateState(image: image, url: item.url)

    // Fixed window size for consistent experience
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let windowWidth: CGFloat = 1200
    let windowHeight: CGFloat = 768

    // Keep this for future use
    // let maxWidth = screen.frame.width * 0.8
    // let maxHeight = screen.frame.height * 0.8
    // let imageSize = image.size

    // // Scale to fit screen while maintaining aspect ratio
    // let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1.0)
    // let windowWidth = max(800, imageSize.width * scale + 280) // 280 for sidebar + padding
    // let windowHeight = max(600, imageSize.height * scale + 120) // 120 for toolbar + bottom
    // Keep this for future use

    let origin = NSPoint(
      x: (screen.frame.width - windowWidth) / 2,
      y: (screen.frame.height - windowHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )

    super.init(window: window)

    window.delegate = self
    setupContent()
    setupKeyboardShortcutObservers()
  }

  /// Empty initializer for drag-drop workflow
  init() {
    self.quickAccessItemId = nil
    self.state = AnnotateState()

    // Default window size for empty canvas
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let defaultWidth: CGFloat = 1200
    let defaultHeight: CGFloat = 768

    let origin = NSPoint(
      x: (screen.frame.width - defaultWidth) / 2,
      y: (screen.frame.height - defaultHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: defaultWidth, height: defaultHeight))
    )

    super.init(window: window)

    window.delegate = self
    setupContent()
    setupKeyboardShortcutObservers()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    cancellables.removeAll()
  }

  private func setupContent() {
    let capturedState = self.state
    let mainView = AnnotateMainView(state: capturedState)
    window?.contentView = NSHostingView(rootView: mainView)
  }



  func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    window?.makeMain()
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - Image Loading

  /// Load image and adjust size for Retina displays
  private static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }

    guard let bitmapRep = image.representations.first as? NSBitmapImageRep else {
      if let rep = image.representations.first {
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh
        if pixelWidth > 0 && pixelHeight > 0 {
          let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
          image.size = NSSize(
            width: CGFloat(pixelWidth) / scaleFactor,
            height: CGFloat(pixelHeight) / scaleFactor
          )
        }
      }
      return image
    }

    let pixelWidth = bitmapRep.pixelsWide
    let pixelHeight = bitmapRep.pixelsHigh
    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0

    image.size = NSSize(
      width: CGFloat(pixelWidth) / scaleFactor,
      height: CGFloat(pixelHeight) / scaleFactor
    )

    return image
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard state.hasUnsavedChanges else {
      return true
    }

    showUnsavedChangesAlert(for: sender)
    return false
  }

  private func showUnsavedChangesAlert(for window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = "Unsaved Changes"
    alert.informativeText = "You have unsaved changes. Do you want to save before closing?"
    alert.alertStyle = .warning

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don't Save")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.performSaveAndClose()

      case .alertSecondButtonReturn:
        self.forceClose()

      default:
        break
      }
    }
  }

  private func performSaveAndClose() {
    if let sourceURL = state.sourceURL {
      showSaveConfirmation(for: sourceURL)
    } else {
      AnnotateExporter.saveAs(state: state, closeWindow: true)
    }
  }

  private func showSaveConfirmation(for sourceURL: URL) {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Save Changes"
    alert.informativeText = "How would you like to save your changes to \"\(sourceURL.lastPathComponent)\"?"
    alert.alertStyle = .informational

    alert.addButton(withTitle: "Replace Original")
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        AnnotateExporter.saveToOriginal(state: self.state)
        self.state.markAsSaved()
        self.forceClose()

      case .alertSecondButtonReturn:
        let copyURL = AnnotateExporter.generateCopyURL(from: sourceURL)
        AnnotateExporter.save(state: self.state, to: copyURL)
        self.state.markAsSaved()
        self.forceClose()

      default:
        break
      }
    }
  }

  private func forceClose() {
    state.hasUnsavedChanges = false

    // Remove associated QuickAccess card if opened from QuickAccess
    if let itemId = quickAccessItemId {
      QuickAccessManager.shared.removeItem(id: itemId)
    }

    window?.close()
  }

  // MARK: - Keyboard Shortcuts

  private func setupKeyboardShortcutObservers() {
    guard let window = self.window else { return }

    NotificationCenter.default.addObserver(
      forName: .annotateSave,
      object: window,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.performSave()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateSaveAs,
      object: window,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.performSaveAs()
      }
    }
  }

  private func performSave() {
    guard state.hasImage else { return }

    if let sourceURL = state.sourceURL {
      showSaveConfirmation(for: sourceURL)
    } else {
      performSaveAs()
    }
  }

  private func performSaveAs() {
    guard state.hasImage else { return }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png, .jpeg]
    panel.nameFieldStringValue = generateFileName()
    panel.canCreateDirectories = true

    guard let window = self.window else { return }

    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self = self, response == .OK, let url = panel.url else { return }
      AnnotateExporter.save(state: self.state, to: url)
      self.state.markAsSaved()
    }
  }

  private func generateFileName() -> String {
    guard let url = state.sourceURL else { return "annotated_image" }
    let baseName = url.deletingPathExtension().lastPathComponent
    return "\(baseName)_annotated"
  }
}
