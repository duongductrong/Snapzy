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

  private let fileAccessManager = SandboxFileAccessManager.shared
  private var sourceFileAccess: SandboxFileAccessManager.ScopedAccess?
  private let state: AnnotateState
  private let quickAccessItemId: UUID?
  private var cancellables = Set<AnyCancellable>()

  init(item: QuickAccessItem) {
    self.quickAccessItemId = item.id
    self.sourceFileAccess = fileAccessManager.beginAccessingURL(item.url)

    // Load full image from URL and adjust for Retina scaling
    let image = Self.loadImageWithCorrectScale(from: item.url) ?? item.thumbnail

    self.state = AnnotateState(image: image, url: item.url, quickAccessItemId: item.id)

    // Fixed window size for consistent experience
    let windowWidth: CGFloat = 1200
    let windowHeight: CGFloat = 768

    let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = NSPoint(
      x: (screenFrame.width - windowWidth) / 2,
      y: (screenFrame.height - windowHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )

    super.init(window: window)

    window.delegate = self
    setupContent()
    setupKeyboardShortcutObservers()
    setupSourceURLObservation()
  }

  /// Empty initializer for drag-drop workflow
  init() {
    self.quickAccessItemId = nil
    self.state = AnnotateState()

    // Default window size for empty canvas
    let defaultWidth: CGFloat = 1200
    let defaultHeight: CGFloat = 768

    let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = NSPoint(
      x: (screenFrame.width - defaultWidth) / 2,
      y: (screenFrame.height - defaultHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: defaultWidth, height: defaultHeight))
    )

    super.init(window: window)

    window.delegate = self
    setupContent()
    setupKeyboardShortcutObservers()
    setupSourceURLObservation()
  }

  /// URL-only initializer for post-capture auto-open flow
  init(url: URL) {
    self.quickAccessItemId = nil
    self.sourceFileAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)

    let image = Self.loadImageWithCorrectScale(from: url)
      ?? NSImage(size: NSSize(width: 400, height: 300))

    self.state = AnnotateState(image: image, url: url)

    let windowWidth: CGFloat = 1200
    let windowHeight: CGFloat = 768

    let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = NSPoint(
      x: (screenFrame.width - windowWidth) / 2,
      y: (screenFrame.height - windowHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )

    super.init(window: window)

    window.delegate = self
    setupContent()
    setupKeyboardShortcutObservers()
    setupSourceURLObservation()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    sourceFileAccess?.stop()
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
    guard let image = SandboxFileAccessManager.shared.withScopedAccess(to: url, {
      NSImage(contentsOf: url)
    }) else { return nil }

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

  private func setupSourceURLObservation() {
    state.$sourceURL
      .sink { [weak self] url in
        self?.refreshSourceAccess(for: url)
      }
      .store(in: &cancellables)
  }

  private func refreshSourceAccess(for url: URL?) {
    sourceFileAccess?.stop()
    sourceFileAccess = nil

    guard let url = url else { return }
    sourceFileAccess = fileAccessManager.beginAccessingURL(url)
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
        if AnnotateExporter.saveToOriginal(state: self.state) {
          self.state.markAsSaved()
          self.forceClose()
        } else {
          self.showSaveErrorAlert()
        }

      case .alertSecondButtonReturn:
        let copyURL = AnnotateExporter.generateCopyURL(from: sourceURL)
        if AnnotateExporter.save(state: self.state, to: copyURL) {
          self.state.markAsSaved()
          self.forceClose()
        } else {
          self.showSaveErrorAlert()
        }

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
      MainActor.assumeIsolated {
        self?.performSave()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateSaveAs,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.performSaveAs()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateCopyAndClose,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.performCopyAndClose()
      }
    }

    // Drag-to-app: hide window when drag starts
    NotificationCenter.default.addObserver(
      forName: .annotateDragStarted,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleDragStarted()
      }
    }

    // Drag-to-app: restore or close window when drag ends
    NotificationCenter.default.addObserver(
      forName: .annotateDragEnded,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      MainActor.assumeIsolated {
        let success = (notification.userInfo?["success"] as? Bool) ?? false
        self?.handleDragEnded(success: success)
      }
    }
  }

  // MARK: - Drag-to-App Window Management

  private var savedWindowFrame: NSRect?

  private func handleDragStarted() {
    guard let window = self.window else { return }
    savedWindowFrame = window.frame
    window.orderOut(nil) // Hide without closing
    print("[AnnotateDrag] Window hidden for drag session")
  }

  private func handleDragEnded(success: Bool) {
    if success {
      // Successful drop — close the window
      state.hasUnsavedChanges = false
      window?.close()
      print("[AnnotateDrag] Drag succeeded — window closed")
    } else {
      // Cancelled/failed — restore window
      guard let window = self.window else { return }
      if let frame = savedWindowFrame {
        window.setFrame(frame, display: true)
      }
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      print("[AnnotateDrag] Drag cancelled — window restored")
    }
    savedWindowFrame = nil
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
      if AnnotateExporter.save(state: self.state, to: url) {
        self.state.markAsSaved()
      } else {
        self.showSaveErrorAlert()
      }
    }
  }

  private func showSaveErrorAlert() {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Save Failed"
    alert.informativeText = "Snapzy couldn't write to the selected location. Please choose another folder."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: window)
  }

  private func generateFileName() -> String {
    guard let url = state.sourceURL else { return "annotated_image" }
    let baseName = url.deletingPathExtension().lastPathComponent
    return "\(baseName)_annotated"
  }

  /// Copy annotated image to clipboard and close window
  private func performCopyAndClose() {
    guard state.hasImage else { return }
    AnnotateExporter.copyToClipboard(state: state)
    state.hasUnsavedChanges = false
    window?.close()
  }
}
