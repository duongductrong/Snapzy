//
//  VideoEditorWindowController.swift
//  Snapzy
//
//  Controller managing video editor window lifecycle
//

import AppKit
import Combine
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
  private var documentEditedCancellable: AnyCancellable?
  private var isEmptyState: Bool = false

  /// Callback when video is loaded in empty state - (workingURL, originalURL)
  var onVideoLoaded: ((URL, URL?) -> Void)?

  /// Initialize with QuickAccessItem (existing behavior)
  init(item: QuickAccessItem) {
    quickAccessItemID = item.id
    sourceFileAccess = fileAccessManager.beginAccessingURL(item.url)
    sourceURL = item.url
    let state = VideoEditorState(url: item.url)
    state.quickAccessItemId = item.id
    state.cloudURL = item.cloudURL
    state.cloudKey = item.cloudKey
    self.state = state
    isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL directly (for drag & drop from external sources)
  init(url: URL) {
    quickAccessItemID = nil
    sourceFileAccess = fileAccessManager.beginAccessingURL(url)
    sourceURL = url
    state = VideoEditorState(url: url)
    isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL and optional original URL (for drag & drop with temp copy)
  init(url: URL, originalURL: URL?) {
    quickAccessItemID = nil
    sourceFileAccess = fileAccessManager.beginAccessingURL(url)
    if let originalURL, originalURL != url {
      originalFileAccess = fileAccessManager.beginAccessingURL(originalURL)
    }
    sourceURL = url
    state = VideoEditorState(url: url, originalURL: originalURL)
    isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with empty state (for drag & drop workflow)
  override init(window _: NSWindow?) {
    quickAccessItemID = nil
    sourceURL = nil
    state = nil
    isEmptyState = true

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupEmptyContent()
  }

  deinit {
    sourceFileAccess?.stop()
    originalFileAccess?.stop()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
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
    guard let state else {
      setupEmptyContent()
      return
    }

    let mainView = VideoEditorMainView(
      state: state,
      primaryActionTitle: primaryActionTitle,
      onSave: { [weak self] in self?.showSaveConfirmation() },
      onCancel: { [weak self] in self?.handleCancel() }
    )
    bindDocumentEditedState(to: state)
    window?.contentView = NSHostingView(rootView: mainView)
  }

  private func setupEmptyContent() {
    bindDocumentEditedState(to: nil)
    let emptyView = VideoEditorEmptyStateView { [weak self] url, originalURL in
      self?.onVideoLoaded?(url, originalURL)
    }
    window?.contentView = NSHostingView(rootView: emptyView)
  }

  private func bindDocumentEditedState(to state: VideoEditorState?) {
    documentEditedCancellable = nil
    window?.isDocumentEdited = state?.hasUnsavedChanges ?? false

    guard let state else { return }

    documentEditedCancellable = state.$hasUnsavedChanges
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] hasUnsavedChanges in
        self?.window?.isDocumentEdited = hasUnsavedChanges
      }
  }

  func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    window?.makeMain()
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    (notification.object as? VideoEditorWindow)?.syncLevelWithFocusState()
  }

  func windowDidResignKey(_ notification: Notification) {
    (notification.object as? VideoEditorWindow)?.syncLevelWithFocusState()
  }

  func windowDidBecomeMain(_ notification: Notification) {
    (notification.object as? VideoEditorWindow)?.syncLevelWithFocusState()
  }

  func windowDidResignMain(_ notification: Notification) {
    (notification.object as? VideoEditorWindow)?.syncLevelWithFocusState()
  }

  private var isTempCaptureSource: Bool {
    guard let state else { return false }
    return tempCaptureManager.isTempFile(state.sourceURL)
  }

  private var primaryActionTitle: String {
    isTempCaptureSource ? L10n.VideoEditor.save : L10n.VideoEditor.convert
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Empty state can always close
    guard let state else { return true }

    guard state.hasUnsavedChanges else {
      state.pause()
      return true
    }

    showUnsavedChangesAlert(for: sender)
    return false
  }

  func windowWillClose(_: Notification) {
    window?.alphaValue = 0
    if let itemId = quickAccessItemID {
      QuickAccessManager.shared.setWindowOpen(id: itemId, isOpen: false)
    }
  }

  // MARK: - Unsaved Changes Alert

  private func showUnsavedChangesAlert(for window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.unsavedChangesTitle
    alert.informativeText = L10n.VideoEditor.unsavedChangesMessage
    alert.alertStyle = .warning

    alert.addButton(withTitle: L10n.VideoEditor.save)
    alert.addButton(withTitle: L10n.VideoEditor.dontSave)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }

      switch response {
      case .alertFirstButtonReturn:
        showSaveConfirmation()

      case .alertSecondButtonReturn:
        forceClose()

      default:
        break
      }
    }
  }

  // MARK: - Save Confirmation

  private func showSaveConfirmation() {
    guard let window, let state else { return }

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
    alert.messageText = L10n.VideoEditor.saveEditedVideoTitle
    alert.informativeText = L10n.VideoEditor.saveEditedVideoMessage(state.filename)
    alert.alertStyle = .informational

    alert.addButton(withTitle: L10n.VideoEditor.replaceOriginal)
    alert.addButton(withTitle: L10n.VideoEditor.saveAsCopy)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }

      switch response {
      case .alertFirstButtonReturn:
        performReplaceOriginal()

      case .alertSecondButtonReturn:
        performSaveAsCopy()

      default:
        break
      }
    }
  }

  // MARK: - Temp Capture Save Flow

  private func saveTempCaptureToDestination() {
    guard let state else { return }
    guard let exportDirectory = fileAccessManager.ensureExportDirectoryForOperation(
      promptMessage: L10n.Recording.chooseSaveLocationMessage
    )
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
    guard let window else { return }

    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.fileAlreadyExistsTitle
    alert.informativeText = L10n.VideoEditor.fileAlreadyExistsMessage(destinationURL.lastPathComponent)
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.overwrite)
    alert.addButton(withTitle: L10n.Common.saveAs)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }

      switch response {
      case .alertFirstButtonReturn:
        exportTempCapture(to: destinationURL, overwriteIfNeeded: true)
      case .alertSecondButtonReturn:
        showTempSaveAsPanel(
          defaultDirectory: destinationURL.deletingLastPathComponent(),
          suggestedFilename: defaultSaveAsFilename(for: destinationURL)
        )
      default:
        break
      }
    }
  }

  private func showTempSaveAsPanel(defaultDirectory: URL, suggestedFilename: String) {
    guard let window, let state else { return }

    let savePanel = NSSavePanel()
    savePanel.title = state.isGIF ? L10n.VideoEditor.saveGIFTitle : L10n.VideoEditor.saveVideoTitle
    savePanel.message = L10n.VideoEditor.chooseWhereToSaveFile
    savePanel.nameFieldLabel = L10n.VideoEditor.fileNameLabel
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
    guard let state else { return destinationURL.lastPathComponent }
    if state.isGIF {
      let baseName = destinationURL.deletingPathExtension().lastPathComponent
      return "\(baseName)_copy.gif"
    }
    return VideoEditorExporter.generateCopyFilename(from: destinationURL)
  }

  private func exportTempCapture(to destinationURL: URL, overwriteIfNeeded: Bool = false) {
    guard let state else { return }
    let sourceURL = state.sourceURL

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = state.isGIF ? L10n.VideoEditor.preparingSave : L10n.VideoEditor.preparingExport

    Task {
      do {
        if overwriteIfNeeded, destinationURL.standardizedFileURL != sourceURL.standardizedFileURL {
          try removeFileIfExists(at: destinationURL)
        }

        if state.isGIF {
          try await saveTempGIF(state: state, to: destinationURL)
        } else {
          try await VideoEditorExporter.exportTrimmed(state: state, to: destinationURL) { [weak self] progress in
            Task { @MainActor in
              self?.state?.exportProgress = progress
              self?.state?.exportStatusMessage = self?.progressMessage(for: progress) ?? L10n.VideoEditor.exporting
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
    state?.cloudURL = nil
    state?.cloudKey = nil
    state?.markAsSaved()

    CaptureHistoryStore.shared.updateFilePath(
      from: sourceURL.path,
      to: destinationURL.path
    )

    PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
      for: .recording,
      url: destinationURL
    )

    cleanupTempSourceFile(at: sourceURL)
    if let quickAccessItemID {
      QuickAccessManager.shared.dismissCard(id: quickAccessItemID)
    }

    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    offerPostExportUpload(for: destinationURL) { [weak self] in
      self?.forceClose()
    }
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
    guard let window, let state else { return }

    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)
    let isResizing = Int(targetSize.width) != Int(state.naturalSize.width)
      || Int(targetSize.height) != Int(state.naturalSize.height)

    guard isResizing else {
      let alert = NSAlert()
      alert.messageText = L10n.VideoEditor.noChangesTitle
      alert.informativeText = L10n.VideoEditor.gifDimensionsNotChanged
      alert.alertStyle = .informational
      alert.addButton(withTitle: L10n.Common.ok)
      alert.beginSheetModal(for: window)
      return
    }

    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.saveResizedGIFTitle
    alert.informativeText = L10n.VideoEditor.resizeGifMessage(
      state.filename,
      Int(state.naturalSize.width),
      Int(state.naturalSize.height),
      Int(targetSize.width),
      Int(targetSize.height)
    )
    alert.alertStyle = .informational

    alert.addButton(withTitle: L10n.VideoEditor.replaceOriginal)
    alert.addButton(withTitle: L10n.VideoEditor.saveAsCopy)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      switch response {
      case .alertFirstButtonReturn:
        performGIFReplaceOriginal()
      case .alertSecondButtonReturn:
        performGIFSaveAsCopy()
      default:
        break
      }
    }
  }

  private func performGIFReplaceOriginal() {
    guard let state else { return }

    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("GIFResize_\(UUID().uuidString)")
      .appendingPathComponent(state.sourceURL.lastPathComponent)

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = L10n.VideoEditor.resizingGIF

    Task {
      do {
        try GIFResizer.resize(
          sourceURL: state.sourceURL,
          targetSize: targetSize,
          outputURL: tempURL
        ) { progress in
          Task { @MainActor in
            state.exportProgress = Float(progress)
            state.exportStatusMessage = progress < 0.95 ? L10n.VideoEditor.resizingFrames : L10n.VideoEditor.finalizing
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
        if let quickAccessItemID {
          await QuickAccessManager.shared.refreshItemThumbnail(id: quickAccessItemID)
        }
        await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: .recording,
          url: originalAccess.url
        )
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
    guard let state, let window else { return }

    let savePanel = NSSavePanel()
    savePanel.title = L10n.VideoEditor.saveResizedGIFTitle
    savePanel.message = L10n.VideoEditor.chooseWhereToSaveFile
    savePanel.nameFieldLabel = L10n.VideoEditor.fileNameLabel

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
    guard let state else { return }

    let targetSize = state.exportSettings.exportSize(from: state.naturalSize)

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = L10n.VideoEditor.resizingGIF

    Task {
      do {
        try GIFResizer.resize(
          sourceURL: state.sourceURL,
          targetSize: targetSize,
          outputURL: outputURL
        ) { progress in
          Task { @MainActor in
            state.exportProgress = Float(progress)
            state.exportStatusMessage = progress < 0.95 ? L10n.VideoEditor.resizingFrames : L10n.VideoEditor.finalizing
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
    guard let state else { return }

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = L10n.VideoEditor.preparingExport

    Task {
      do {
        try await VideoEditorExporter.replaceOriginal(state: state) { [weak self] progress in
          Task { @MainActor in
            self?.state?.exportProgress = progress
            self?.state?.exportStatusMessage = self?.progressMessage(for: progress) ?? L10n.VideoEditor.exporting
          }
        }
        state.isExporting = false
        state.cloudURL = nil
        state.cloudKey = nil
        state.markAsSaved()
        if let quickAccessItemID {
          await QuickAccessManager.shared.refreshItemThumbnail(id: quickAccessItemID)
        }
        await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: .recording,
          url: state.originalURL
        )
        self.offerPostExportUpload(for: state.originalURL) { [weak self] in
          self?.forceClose()
        }
      } catch {
        DiagnosticLogger.shared.logError(.export, error, "Video replace original failed")
        state.isExporting = false
        if error.isPermissionDenied {
          showReplaceOriginalPermissionFallback(error)
        } else {
          showExportError(error)
        }
      }
    }
  }

  private func performSaveAsCopy() {
    guard let state, let window else { return }

    // Show save panel to let user choose destination
    let savePanel = NSSavePanel()
    savePanel.title = L10n.VideoEditor.saveVideoCopyTitle
    savePanel.message = L10n.VideoEditor.chooseWhereToSaveEditedVideo
    savePanel.nameFieldLabel = L10n.VideoEditor.fileNameLabel
    savePanel.nameFieldStringValue = VideoEditorExporter.generateCopyFilename(from: state.sourceURL)
    savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
    savePanel.canCreateDirectories = true

    savePanel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let outputURL = savePanel.url else { return }
      self?.exportToCopy(outputURL: outputURL)
    }
  }

  private func exportToCopy(outputURL: URL) {
    guard let state else { return }

    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = L10n.VideoEditor.preparingExport

    Task {
      do {
        try await VideoEditorExporter.exportTrimmed(state: state, to: outputURL) { [weak self] progress in
          Task { @MainActor in
            self?.state?.exportProgress = progress
            self?.state?.exportStatusMessage = self?.progressMessage(for: progress) ?? L10n.VideoEditor.exporting
          }
        }
        state.isExporting = false
        state.cloudURL = nil
        state.cloudKey = nil
        state.markAsSaved()

        // Show exported file in Finder
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        self.offerPostExportUpload(for: outputURL) {}
      } catch {
        DiagnosticLogger.shared.logError(.export, error, "Video save as copy failed")
        state.isExporting = false
        showExportError(error)
      }
    }
  }

  private func progressMessage(for progress: Float) -> String {
    switch progress {
    case 0 ..< 0.1:
      L10n.VideoEditor.preparingExport
    case 0.1 ..< 0.3:
      L10n.VideoEditor.processingVideo
    case 0.3 ..< 0.7:
      L10n.VideoEditor.applyingEffects
    case 0.7 ..< 0.9:
      L10n.VideoEditor.encodingFrames
    case 0.9 ..< 1.0:
      L10n.VideoEditor.finalizing
    default:
      L10n.VideoEditor.completing
    }
  }

  private func showExportError(_ error: Error) {
    DiagnosticLogger.shared.logError(.export, error, "Export error shown to user")
    guard let window else { return }

    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.exportFailedTitle
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .critical
    alert.addButton(withTitle: L10n.Common.ok)
    alert.beginSheetModal(for: window)
  }

  private func showReplaceOriginalPermissionFallback(_ error: Error) {
    guard let window else { return }

    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.cannotReplaceOriginalTitle
    alert.informativeText = L10n.VideoEditor.cannotReplaceOriginalMessage(error.localizedDescription)
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.VideoEditor.saveAsCopy)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      if response == .alertFirstButtonReturn {
        performSaveAsCopy()
      }
    }
  }

  // MARK: - Post-Export Cloud Upload Offer

  private func offerPostExportUpload(for fileURL: URL, completion: @escaping () -> Void) {
    guard CloudManager.shared.isConfigured,
          QuickAccessActionConfigurationStore.shared.isEnabled(.uploadToCloud),
          let window,
          let state
    else {
      completion()
      return
    }

    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.uploadToCloud
    alert.informativeText = L10n.VideoEditor.uploadToCloudMessage
    alert.alertStyle = .informational
    alert.addButton(withTitle: L10n.AnnotateUI.uploadToCloud)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else {
        completion()
        return
      }

      if response == .alertFirstButtonReturn {
        performPostExportUpload(fileURL: fileURL, completion: completion)
      } else {
        completion()
      }
    }
  }

  private func performPostExportUpload(fileURL: URL, completion: @escaping () -> Void) {
    guard let state else {
      completion()
      return
    }

    state.isExporting = true
    state.exportProgress = 0.8
    state.exportStatusMessage = "Uploading to cloud..."

    Task {
      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(fileURL)
        defer { fileAccess.stop() }

        let result = try await CloudManager.shared.upload(fileURL: fileURL)

        // Store cloud link on pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        SoundManager.play("Pop")

        // Sync with Quick Access item if linked
        if let itemId = self.quickAccessItemID {
          QuickAccessManager.shared.setCloudURL(id: itemId, url: result.publicURL, key: result.key)
        }

        state.isExporting = false
        completion()
      } catch {
        state.isExporting = false
        self.showExportError(error)
        completion()
      }
    }
  }

  private func forceClose() {
    state?.pause()
    state?.hasUnsavedChanges = false
    window?.close()
  }

  // MARK: - Cancel Action

  private func handleCancel() {
    guard let window else { return }

    if let state, state.hasUnsavedChanges {
      showUnsavedChangesAlert(for: window)
    } else {
      forceClose()
    }
  }
}
