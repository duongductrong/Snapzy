//
//  VideoEditorWindowController.swift
//  Snapzy
//
//  Controller managing video editor window lifecycle
//

import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

/// Manages video editor window lifecycle
@MainActor
final class VideoEditorWindowController: NSWindowController, NSWindowDelegate {

  private let fileAccessManager = SandboxFileAccessManager.shared
  private var sourceFileAccess: SandboxFileAccessManager.ScopedAccess?
  private var originalFileAccess: SandboxFileAccessManager.ScopedAccess?
  private var sourceURL: URL?
  private var state: VideoEditorState?
  private var isEmptyState: Bool = false

  /// Callback when video is loaded in empty state - (workingURL, originalURL)
  var onVideoLoaded: ((URL, URL?) -> Void)?

  /// Initialize with QuickAccessItem (existing behavior)
  init(item: QuickAccessItem) {
    self.sourceFileAccess = fileAccessManager.beginAccessingURL(item.url)
    self.sourceURL = item.url
    self.state = VideoEditorState(url: item.url)
    self.isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL directly (for drag & drop from external sources)
  init(url: URL) {
    self.sourceFileAccess = fileAccessManager.beginAccessingURL(url)
    self.sourceURL = url
    self.state = VideoEditorState(url: url)
    self.isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL and optional original URL (for drag & drop with temp copy)
  init(url: URL, originalURL: URL?) {
    self.sourceFileAccess = fileAccessManager.beginAccessingURL(url)
    if let originalURL = originalURL, originalURL != url {
      self.originalFileAccess = fileAccessManager.beginAccessingURL(originalURL)
    }
    self.sourceURL = url
    self.state = VideoEditorState(url: url, originalURL: originalURL)
    self.isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with empty state (for drag & drop workflow)
  override init(window: NSWindow?) {
    self.sourceURL = nil
    self.state = nil
    self.isEmptyState = true

    super.init(window: Self.createWindow())
    self.window?.delegate = self
    setupEmptyContent()
  }

  deinit {
    sourceFileAccess?.stop()
    originalFileAccess?.stop()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func createWindow() -> VideoEditorWindow {
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let windowWidth: CGFloat = 1200
    let windowHeight: CGFloat = 800

    let origin = NSPoint(
      x: (screen.frame.width - windowWidth) / 2,
      y: (screen.frame.height - windowHeight) / 2
    )

    return VideoEditorWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )
  }

  private func setupContent() {
    guard let state = state else {
      setupEmptyContent()
      return
    }

    let mainView = VideoEditorMainView(
      state: state,
      onSave: { [weak self] in self?.showSaveConfirmation() },
      onCancel: { [weak self] in self?.handleCancel() }
    )
    window?.contentView = NSHostingView(rootView: mainView)
  }

  private func setupEmptyContent() {
    let emptyView = VideoEditorEmptyStateView { [weak self] url, originalURL in
      self?.onVideoLoaded?(url, originalURL)
    }
    window?.contentView = NSHostingView(rootView: emptyView)
  }

  func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Empty state can always close
    guard let state = state else { return true }

    guard state.hasUnsavedChanges else {
      state.pause()
      return true
    }

    showUnsavedChangesAlert(for: sender)
    return false
  }

  // MARK: - Unsaved Changes Alert

  private func showUnsavedChangesAlert(for window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = "Unsaved Changes"
    alert.informativeText = "You have unsaved trim changes. Do you want to save before closing?"
    alert.alertStyle = .warning

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don't Save")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.showSaveConfirmation()

      case .alertSecondButtonReturn:
        self.forceClose()

      default:
        break
      }
    }
  }

  // MARK: - Save Confirmation

  private func showSaveConfirmation() {
    guard let window = self.window, let state = state else { return }

    // GIF mode: resize export
    if state.isGIF {
      showGIFSaveConfirmation()
      return
    }

    let alert = NSAlert()
    alert.messageText = "Save Trimmed Video"
    alert.informativeText = "How would you like to save the trimmed video \"\(state.filename)\"?"
    alert.alertStyle = .informational

    alert.addButton(withTitle: "Replace Original")
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.performReplaceOriginal()

      case .alertSecondButtonReturn:
        self.performSaveAsCopy()

      default:
        break
      }
    }
  }

  // MARK: - GIF Export

  private func showGIFSaveConfirmation() {
    guard let window = self.window, let state = state else { return }

    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)
    let isResizing = Int(targetSize.width) != Int(state.naturalSize.width)
      || Int(targetSize.height) != Int(state.naturalSize.height)

    guard isResizing else {
      let alert = NSAlert()
      alert.messageText = "No Changes"
      alert.informativeText = "The GIF dimensions haven't changed. Select a different size preset to resize."
      alert.alertStyle = .informational
      alert.addButton(withTitle: "OK")
      alert.beginSheetModal(for: window)
      return
    }

    let alert = NSAlert()
    alert.messageText = "Save Resized GIF"
    alert.informativeText = "Resize \"\(state.filename)\" from \(Int(state.naturalSize.width))×\(Int(state.naturalSize.height)) to \(Int(targetSize.width))×\(Int(targetSize.height))?"
    alert.alertStyle = .informational

    alert.addButton(withTitle: "Replace Original")
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }
      switch response {
      case .alertFirstButtonReturn:
        self.performGIFReplaceOriginal()
      case .alertSecondButtonReturn:
        self.performGIFSaveAsCopy()
      default:
        break
      }
    }
  }

  private func performGIFReplaceOriginal() {
    guard let state = state else { return }

    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("GIFResize_\(UUID().uuidString)")
      .appendingPathComponent(state.sourceURL.lastPathComponent)

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = "Resizing GIF..."

    Task {
      do {
        try GIFResizer.resize(
          sourceURL: state.sourceURL,
          targetSize: targetSize,
          outputURL: tempURL
        ) { progress in
          Task { @MainActor in
            state.exportProgress = Float(progress)
            state.exportStatusMessage = progress < 0.95 ? "Resizing frames..." : "Finalizing..."
          }
        }

        // Replace original
        let originalURL = state.originalURL
        let originalAccess = SandboxFileAccessManager.shared.beginAccessingURL(originalURL)
        defer { originalAccess.stop() }

        try FileManager.default.removeItem(at: originalAccess.url)
        try FileManager.default.copyItem(at: tempURL, to: originalAccess.url)
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())

        state.isExporting = false
        state.markAsSaved()
        forceClose()
      } catch {
        state.isExporting = false
        showExportError(error)
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
      }
    }
  }

  private func performGIFSaveAsCopy() {
    guard let state = state, let window = self.window else { return }

    let savePanel = NSSavePanel()
    savePanel.title = "Save Resized GIF"
    savePanel.message = "Choose where to save the resized GIF"
    savePanel.nameFieldLabel = "File Name:"

    let baseName = state.sourceURL.deletingPathExtension().lastPathComponent
    savePanel.nameFieldStringValue = "\(baseName)_resized.gif"
    savePanel.allowedContentTypes = [.gif]
    savePanel.canCreateDirectories = true

    savePanel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let outputURL = savePanel.url else { return }
      self?.exportGIFToCopy(outputURL: outputURL)
    }
  }

  private func exportGIFToCopy(outputURL: URL) {
    guard let state = state else { return }

    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = "Resizing GIF..."

    Task {
      do {
        try GIFResizer.resize(
          sourceURL: state.sourceURL,
          targetSize: targetSize,
          outputURL: outputURL
        ) { progress in
          Task { @MainActor in
            state.exportProgress = Float(progress)
            state.exportStatusMessage = progress < 0.95 ? "Resizing frames..." : "Finalizing..."
          }
        }

        state.isExporting = false
        state.markAsSaved()
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
      } catch {
        state.isExporting = false
        showExportError(error)
      }
    }
  }

  // MARK: - Export Actions

  private func performReplaceOriginal() {
    guard let state = state else { return }

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = "Preparing export..."

    Task {
      do {
        try await VideoEditorExporter.replaceOriginal(state: state) { [weak self] progress in
          Task { @MainActor in
            self?.state?.exportProgress = progress
            self?.state?.exportStatusMessage = self?.progressMessage(for: progress) ?? "Exporting..."
          }
        }
        state.isExporting = false
        state.markAsSaved()
        forceClose()
      } catch {
        state.isExporting = false
        if isPermissionDeniedError(error) {
          showReplaceOriginalPermissionFallback(error)
        } else {
          showExportError(error)
        }
      }
    }
  }

  private func performSaveAsCopy() {
    guard let state = state, let window = self.window else { return }

    // Show save panel to let user choose destination
    let savePanel = NSSavePanel()
    savePanel.title = "Save Video Copy"
    savePanel.message = "Choose where to save the trimmed video"
    savePanel.nameFieldLabel = "File Name:"
    savePanel.nameFieldStringValue = VideoEditorExporter.generateCopyFilename(from: state.sourceURL)
    savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
    savePanel.canCreateDirectories = true

    savePanel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let outputURL = savePanel.url else { return }
      self?.exportToCopy(outputURL: outputURL)
    }
  }

  private func exportToCopy(outputURL: URL) {
    guard let state = state else { return }

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = "Preparing export..."

    Task {
      do {
        try await VideoEditorExporter.exportTrimmed(state: state, to: outputURL) { [weak self] progress in
          Task { @MainActor in
            self?.state?.exportProgress = progress
            self?.state?.exportStatusMessage = self?.progressMessage(for: progress) ?? "Exporting..."
          }
        }
        state.isExporting = false
        state.markAsSaved()

        // Show exported file in Finder
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
      } catch {
        state.isExporting = false
        showExportError(error)
      }
    }
  }

  private func progressMessage(for progress: Float) -> String {
    switch progress {
    case 0..<0.1:
      return "Preparing export..."
    case 0.1..<0.3:
      return "Processing video..."
    case 0.3..<0.7:
      return "Applying effects..."
    case 0.7..<0.9:
      return "Encoding frames..."
    case 0.9..<1.0:
      return "Finalizing..."
    default:
      return "Completing..."
    }
  }

  private func showExportError(_ error: Error) {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Export Failed"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: window)
  }

  private func showReplaceOriginalPermissionFallback(_ error: Error) {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Cannot Replace Original"
    alert.informativeText =
      "Snapzy doesn't have write access to this file location. Save as a copy instead.\n\n\(error.localizedDescription)"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }
      if response == .alertFirstButtonReturn {
        self.performSaveAsCopy()
      }
    }
  }

  private func isPermissionDeniedError(_ error: Error) -> Bool {
    let nsError = error as NSError

    if nsError.domain == NSCocoaErrorDomain {
      return nsError.code == NSFileReadNoPermissionError
        || nsError.code == NSFileWriteNoPermissionError
    }

    if nsError.domain == NSPOSIXErrorDomain {
      return nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
    }

    return false
  }

  private func forceClose() {
    state?.pause()
    state?.hasUnsavedChanges = false
    window?.close()
  }

  // MARK: - Cancel Action

  private func handleCancel() {
    guard let window = self.window else { return }

    if let state = state, state.hasUnsavedChanges {
      showUnsavedChangesAlert(for: window)
    } else {
      forceClose()
    }
  }
}
