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

/// The file ownership boundary used by the Video Editor Save action.
///
/// A temporary Quick Access capture is committed at its current URL. A capture
/// that is already saved can be replaced at its existing destination or
/// explicitly exported as a copy through the existing confirmation flow.
enum VideoEditorSaveTarget: Equatable {
  case quickAccessTemp
  case destination

  static func resolve(isTempCapture: Bool) -> Self {
    isTempCapture ? .quickAccessTemp : .destination
  }
}

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
  private var sessionData: VideoEditorSessionData?
  private var documentEditedCancellable: AnyCancellable?
  private var isEmptyState: Bool = false

  /// Callback when video is loaded in empty state - (workingURL, originalURL)
  var onVideoLoaded: ((URL, URL?) -> Void)?

  /// Initialize with QuickAccessItem (existing behavior)
  init(item: QuickAccessItem, sessionData: VideoEditorSessionData? = nil) {
    quickAccessItemID = item.id
    sourceFileAccess = fileAccessManager.beginAccessingURL(item.url)
    sourceURL = item.url
    self.sessionData = sessionData
    let state = VideoEditorState(url: item.url, sessionData: sessionData)
    state.quickAccessItemId = item.id
    // A stale Quick Access cloud link must not make the edited file look
    // uploaded again when the editor is reopened. Keep the key so the next
    // upload can still overwrite the existing cloud object.
    state.cloudURL = item.isCloudStale ? nil : item.cloudURL
    state.cloudKey = item.cloudKey
    self.state = state
    isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL directly (for drag & drop from external sources)
  init(url: URL, sessionData: VideoEditorSessionData? = nil) {
    quickAccessItemID = nil
    sourceFileAccess = fileAccessManager.beginAccessingURL(url)
    sourceURL = url
    self.sessionData = sessionData
    state = VideoEditorState(url: url, sessionData: sessionData)
    isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL and optional original URL (for drag & drop with temp copy)
  init(
    url: URL,
    originalURL: URL?,
    sessionData: VideoEditorSessionData? = nil
  ) {
    quickAccessItemID = nil
    sourceFileAccess = fileAccessManager.beginAccessingURL(url)
    if let originalURL, originalURL != url {
      originalFileAccess = fileAccessManager.beginAccessingURL(originalURL)
    }
    sourceURL = url
    self.sessionData = sessionData
    state = VideoEditorState(
      url: url,
      originalURL: originalURL,
      sessionData: sessionData
    )
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
    sessionData = nil
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
    return tempCaptureManager.isTempFile(state.originalURL)
  }

  private var saveTarget: VideoEditorSaveTarget {
    VideoEditorSaveTarget.resolve(isTempCapture: isTempCaptureSource)
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

    // A temporary capture stays under Quick Access ownership. Save commits
    // the edit to that same file; Quick Access Save handles promotion later.
    if saveTarget == .quickAccessTemp {
      if state.isGIF {
        showGIFSaveConfirmation()
      } else {
        performReplaceOriginal(offerPostExportUpload: false)
      }
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

    // Temporary GIF captures follow the same Quick Access session contract as
    // videos: resize into staging, then replace the current temp file.
    if saveTarget == .quickAccessTemp {
      performGIFReplaceOriginal()
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

    let progressOperation: VideoEditorProgressOperation = .saveGIF
    state.progressOperation = progressOperation
    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = progressOperation.initialStatusMessage

    Task {
      var preparedSource: VideoEditorSessionStore.PreparedSourceSnapshot?
      defer {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
      }

      do {
        preparedSource = try await prepareSessionSourceIfNeeded(for: state)
        try GIFResizer.resize(
          sourceURL: state.editingSourceURL,
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
        let targetURL = originalAccess.url
        let backupURL = targetURL.deletingLastPathComponent()
          .appendingPathComponent(".\(targetURL.lastPathComponent).backup")

        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: targetURL, to: backupURL)
        do {
          try FileManager.default.copyItem(at: tempURL, to: targetURL)
          try? FileManager.default.removeItem(at: backupURL)
        } catch {
          try? FileManager.default.removeItem(at: targetURL)
          try? FileManager.default.moveItem(at: backupURL, to: targetURL)
          throw error
        }

        state.isExporting = false
        invalidateEditedCloudState()
        guard await persistSessionAfterCommit(for: state, preparedSource: preparedSource) else {
          showExportError(VideoEditorSessionStore.StoreError.packageUnavailable)
          return
        }
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
        if let preparedSource {
          VideoEditorSessionStore.shared.discardPreparedSourceSnapshot(preparedSource)
        }
        DiagnosticLogger.shared.logError(.export, error, "GIF replace original failed")
        state.isExporting = false
        showExportError(error)
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

    let progressOperation: VideoEditorProgressOperation = .exportGIF
    state.progressOperation = progressOperation
    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = progressOperation.initialStatusMessage

    Task {
      do {
        try GIFResizer.resize(
          sourceURL: state.editingSourceURL,
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

  private func performReplaceOriginal(offerPostExportUpload: Bool = true) {
    guard let state else { return }

    let progressOperation: VideoEditorProgressOperation = .saveVideo
    state.progressOperation = progressOperation
    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = progressOperation.initialStatusMessage

    Task {
      var preparedSource: VideoEditorSessionStore.PreparedSourceSnapshot?
      do {
        preparedSource = try await prepareSessionSourceIfNeeded(for: state)
        try await VideoEditorExporter.replaceOriginal(state: state) { [weak self] progress in
          Task { @MainActor in
            self?.state?.exportProgress = progress
            self?.state?.exportStatusMessage = self?.progressMessage(
              for: progress,
              operation: progressOperation
            ) ?? progressOperation.initialStatusMessage
          }
        }
        state.isExporting = false
        invalidateEditedCloudState()
        guard await persistSessionAfterCommit(for: state, preparedSource: preparedSource) else {
          showExportError(VideoEditorSessionStore.StoreError.packageUnavailable)
          return
        }
        state.markAsSaved()
        if let quickAccessItemID {
          await QuickAccessManager.shared.refreshItemThumbnail(id: quickAccessItemID)
        }
        await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: .recording,
          url: state.originalURL
        )
        if offerPostExportUpload {
          self.offerPostExportUpload(for: state.originalURL) { [weak self] in
            self?.forceClose()
          }
        } else {
          self.forceClose()
        }
      } catch {
        if let preparedSource {
          VideoEditorSessionStore.shared.discardPreparedSourceSnapshot(preparedSource)
        }
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

    let progressOperation: VideoEditorProgressOperation = .exportVideo
    state.progressOperation = progressOperation
    state.isExporting = true
    state.exportProgress = 0
    state.exportStatusMessage = progressOperation.initialStatusMessage

    Task {
      do {
        try await VideoEditorExporter.exportTrimmed(state: state, to: outputURL) { [weak self] progress in
          Task { @MainActor in
            self?.state?.exportProgress = progress
            self?.state?.exportStatusMessage = self?.progressMessage(
              for: progress,
              operation: progressOperation
            ) ?? progressOperation.initialStatusMessage
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

  private func prepareSessionSourceIfNeeded(
    for state: VideoEditorState
  ) async throws -> VideoEditorSessionStore.PreparedSourceSnapshot? {
    // A restored session already owns an immutable master source. Reuse it for
    // every later save so the recipe is never applied to a rendered output.
    guard sessionData == nil else { return nil }

    return try await VideoEditorSessionStore.shared.prepareSourceSnapshot(
      from: state.editingSourceURL,
      for: state.originalURL
    )
  }

  /// Cache and persist the recipe after the rendered file has been replaced.
  /// Caching happens even if the disk manifest fails, so the current Quick Access
  /// session can still be reopened and promoted in this app process.
  @discardableResult
  private func persistSessionAfterCommit(
    for state: VideoEditorState,
    preparedSource: VideoEditorSessionStore.PreparedSourceSnapshot?
  ) async -> Bool {
    guard let sourceSnapshotURL = sessionData?.sourceSnapshotURL ?? preparedSource?.sourceURL else {
      DiagnosticLogger.shared.log(
        .warning,
        .editor,
        "Video Editor session cache skipped; source snapshot missing"
      )
      return false
    }

    let snapshot = VideoEditorSessionData.snapshot(
      from: state,
      sourceSnapshotURL: sourceSnapshotURL
    )
    if let quickAccessItemID {
      VideoEditorManager.shared.saveSessionData(snapshot, for: quickAccessItemID)
    } else {
      VideoEditorManager.shared.saveSessionData(snapshot, for: state.originalURL)
    }
    sessionData = snapshot

    let didPersist = await VideoEditorSessionStore.shared.persistOffMain(
      snapshot,
      for: state.originalURL,
      preparedSourceDirectory: preparedSource?.directoryURL
    )
    guard didPersist else {
      DiagnosticLogger.shared.log(
        .warning,
        .editor,
        "Video Editor session disk persistence failed; in-memory session retained",
        context: ["fileName": state.originalURL.lastPathComponent]
      )
      return false
    }

    if let reloaded = VideoEditorSessionStore.shared.load(for: state.originalURL) {
      sessionData = reloaded
      if let quickAccessItemID {
        VideoEditorManager.shared.saveSessionData(reloaded, for: quickAccessItemID)
      } else {
        VideoEditorManager.shared.saveSessionData(reloaded, for: state.originalURL)
      }
    } else if preparedSource != nil {
      // The pending source directory has been moved into its stable package.
      // Keep the in-memory fallback usable even if the immediate signature
      // re-read races with a filesystem timestamp update.
      let committedSourceURL = VideoEditorSessionStore.shared.committedSourceSnapshotURL(
        for: state.originalURL,
        fileName: sourceSnapshotURL.lastPathComponent
      )
      let committedSnapshot = VideoEditorSessionData.snapshot(
        from: state,
        sourceSnapshotURL: committedSourceURL
      )
      sessionData = committedSnapshot
      if let quickAccessItemID {
        VideoEditorManager.shared.saveSessionData(committedSnapshot, for: quickAccessItemID)
      } else {
        VideoEditorManager.shared.saveSessionData(committedSnapshot, for: state.originalURL)
      }
    }
    return true
  }

  private func progressMessage(
    for progress: Float,
    operation: VideoEditorProgressOperation = .exportVideo
  ) -> String {
    switch progress {
    case 0 ..< 0.1:
      operation.initialStatusMessage
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

    let progressOperation: VideoEditorProgressOperation = .uploadToCloud
    state.progressOperation = progressOperation
    state.isExporting = true
    state.exportProgress = 0.8
    state.exportStatusMessage = progressOperation.initialStatusMessage

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

  private func invalidateEditedCloudState() {
    state?.cloudURL = nil
    if let quickAccessItemID {
      QuickAccessManager.shared.markCloudStale(id: quickAccessItemID)
    }
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
