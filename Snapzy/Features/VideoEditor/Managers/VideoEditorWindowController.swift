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
  private let tempCaptureManager = TempCaptureManager.shared
  private let quickAccessItemID: UUID?
  private var sourceFileAccess: SandboxFileAccessManager.ScopedAccess?
  private var originalFileAccess: SandboxFileAccessManager.ScopedAccess?
  private var sourceURL: URL?
  private var state: VideoEditorState?
  private var isEmptyState: Bool = false

  /// Callback when video is loaded in empty state - (workingURL, originalURL)
  var onVideoLoaded: ((URL, URL?) -> Void)?

  /// Initialize with QuickAccessItem (existing behavior)
  init(item: QuickAccessItem) {
    self.quickAccessItemID = item.id
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
    self.quickAccessItemID = nil
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
    self.quickAccessItemID = nil
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
    self.quickAccessItemID = nil
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
      primaryActionTitle: primaryActionTitle,
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

  private var isTempCaptureSource: Bool {
    guard let state = state else { return false }
    return tempCaptureManager.isTempFile(state.sourceURL)
  }

  private var primaryActionTitle: String {
    isTempCaptureSource ? "Save" : "Convert"
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
    alert.informativeText = "You have unsaved video edits. Do you want to save before closing?"
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

    // Temp capture flow: save directly to destination location.
    if isTempCaptureSource {
      saveTempCaptureToDestination()
      return
    }

    // GIF mode: resize export
    if state.isGIF {
      showGIFSaveConfirmation()
      return
    }

    let alert = NSAlert()
    alert.messageText = "Save Edited Video"
    alert.informativeText = "How would you like to save the edited video \"\(state.filename)\"?"
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

  // MARK: - Temp Capture Save Flow

  private func saveTempCaptureToDestination() {
    guard let state = state else { return }
    guard let exportDirectory = fileAccessManager.ensureExportDirectoryForOperation(
      promptMessage: "Choose where Snapzy should save screenshots and recordings")
    else {
      return
    }

    let exportAccess = fileAccessManager.beginAccessingURL(exportDirectory)
    defer { exportAccess.stop() }

    let destinationURL = exportAccess.url.appendingPathComponent(state.sourceURL.lastPathComponent)
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      showTempSaveCollisionAlert(destinationURL: destinationURL)
      return
    }

    exportTempCapture(to: destinationURL)
  }

  private func showTempSaveCollisionAlert(destinationURL: URL) {
    guard let window = window else { return }

    let alert = NSAlert()
    alert.messageText = "File Already Exists"
    alert.informativeText =
      "A file named \"\(destinationURL.lastPathComponent)\" already exists in the destination folder."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Overwrite")
    alert.addButton(withTitle: "Save As")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.exportTempCapture(to: destinationURL, overwriteIfNeeded: true)
      case .alertSecondButtonReturn:
        self.showTempSaveAsPanel(
          defaultDirectory: destinationURL.deletingLastPathComponent(),
          suggestedFilename: self.defaultSaveAsFilename(for: destinationURL)
        )
      default:
        break
      }
    }
  }

  private func showTempSaveAsPanel(defaultDirectory: URL, suggestedFilename: String) {
    guard let window = window, let state = state else { return }

    let savePanel = NSSavePanel()
    savePanel.title = state.isGIF ? "Save GIF" : "Save Video"
    savePanel.message = "Choose where to save the file"
    savePanel.nameFieldLabel = "File Name:"
    savePanel.nameFieldStringValue = suggestedFilename
    savePanel.allowedContentTypes =
      state.isGIF ? [.gif] : [.movie, .mpeg4Movie, .quickTimeMovie]
    savePanel.canCreateDirectories = true
    savePanel.directoryURL = defaultDirectory

    savePanel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let outputURL = savePanel.url else { return }
      self?.exportTempCapture(to: outputURL, overwriteIfNeeded: true)
    }
  }

  private func defaultSaveAsFilename(for destinationURL: URL) -> String {
    guard let state = state else { return destinationURL.lastPathComponent }
    if state.isGIF {
      let baseName = destinationURL.deletingPathExtension().lastPathComponent
      return "\(baseName)_copy.gif"
    }
    return VideoEditorExporter.generateCopyFilename(from: destinationURL)
  }

  private func exportTempCapture(to destinationURL: URL, overwriteIfNeeded: Bool = false) {
    guard let state = state else { return }
    let sourceURL = state.sourceURL

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = state.isGIF ? "Preparing save..." : "Preparing export..."

    Task {
      do {
        if overwriteIfNeeded && destinationURL.standardizedFileURL != sourceURL.standardizedFileURL {
          try removeFileIfExists(at: destinationURL)
        }

        if state.isGIF {
          try await saveTempGIF(state: state, to: destinationURL)
        } else {
          try await VideoEditorExporter.exportTrimmed(state: state, to: destinationURL) { [weak self] progress in
            Task { @MainActor in
              self?.state?.exportProgress = progress
              self?.state?.exportStatusMessage = self?.progressMessage(for: progress) ?? "Exporting..."
            }
          }
        }

        finalizeTempSave(destinationURL: destinationURL, sourceURL: sourceURL)
      } catch {
        DiagnosticLogger.shared.logError(.export, error, "Temp capture save failed")
        state.isExporting = false
        showExportError(error)
      }
    }
  }

  private func saveTempGIF(state: VideoEditorState, to outputURL: URL) async throws {
    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)
    let isResizing = Int(targetSize.width) != Int(state.naturalSize.width)
      || Int(targetSize.height) != Int(state.naturalSize.height)
    let outputDirectoryAccess = fileAccessManager.beginAccessingURL(outputURL.deletingLastPathComponent())
    defer { outputDirectoryAccess.stop() }
    let scopedOutputURL = outputDirectoryAccess.url.appendingPathComponent(outputURL.lastPathComponent)

    if isResizing {
      try GIFResizer.resize(
        sourceURL: state.sourceURL,
        targetSize: targetSize,
        outputURL: scopedOutputURL
      ) { progress in
        Task { @MainActor in
          state.exportProgress = Float(progress)
          state.exportStatusMessage = progress < 0.95 ? "Resizing frames..." : "Finalizing..."
        }
      }
      return
    }

    state.exportProgress = 0.95
    state.exportStatusMessage = "Finalizing..."

    let sourceAccess = fileAccessManager.beginAccessingURL(state.sourceURL)
    defer { sourceAccess.stop() }
    try FileManager.default.copyItem(at: sourceAccess.url, to: scopedOutputURL)
  }

  private func removeFileIfExists(at url: URL) throws {
    let directoryAccess = fileAccessManager.beginAccessingURL(url.deletingLastPathComponent())
    defer { directoryAccess.stop() }
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private func finalizeTempSave(destinationURL: URL, sourceURL: URL) {
    state?.isExporting = false
    state?.markAsSaved()

    cleanupTempSourceFile(at: sourceURL)
    if let quickAccessItemID {
      QuickAccessManager.shared.dismissCard(id: quickAccessItemID)
    }

    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    forceClose()
  }

  private func cleanupTempSourceFile(at sourceURL: URL) {
    guard tempCaptureManager.isTempFile(sourceURL) else { return }
    let directoryAccess = fileAccessManager.beginAccessingURL(sourceURL.deletingLastPathComponent())
    defer { directoryAccess.stop() }

    if FileManager.default.fileExists(atPath: sourceURL.path) {
      try? FileManager.default.removeItem(at: sourceURL)
    }
    try? RecordingMetadataStore.delete(for: sourceURL)
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
        DiagnosticLogger.shared.logError(.export, error, "GIF replace original failed")
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
        DiagnosticLogger.shared.logError(.export, error, "GIF save as copy failed")
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
        DiagnosticLogger.shared.logError(.export, error, "Video replace original failed")
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
    savePanel.message = "Choose where to save the edited video"
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
        DiagnosticLogger.shared.logError(.export, error, "Video save as copy failed")
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
    DiagnosticLogger.shared.logError(.export, error, "Export error shown to user")
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
