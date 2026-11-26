//
//  VideoEditorWindowController.swift
//  Snapzy
//
//  Controller managing video editor window lifecycle
//

import AppKit
import AVFoundation
import Combine
import CoreMedia
import Darwin
import SwiftUI
import UniformTypeIdentifiers

/// Observable `.snapzy` project metadata shared between `VideoEditorWindowController`
/// and `VideoEditorToolbarView` so saving or renaming a project updates the titlebar live.
@MainActor
final class VideoEditorProjectContext: ObservableObject {
  nonisolated deinit {}

  @Published var packageURL: URL?
  @Published var isSavingProject: Bool = false
  @Published private(set) var showsJustSavedBadge: Bool = false
  var onRenameProject: ((String) throws -> Void)?

  private var resetBadgeTask: Task<Void, Never>?

  var hasProjectPackage: Bool {
    packageURL != nil
  }

  var packageDisplayName: String? {
    packageURL?.lastPathComponent
  }

  var packageStemName: String? {
    packageURL?.deletingPathExtension().lastPathComponent
  }

  func markJustSaved() {
    resetBadgeTask?.cancel()
    showsJustSavedBadge = true
    resetBadgeTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_600_000_000)
      guard !Task.isCancelled else { return }
      self?.showsJustSavedBadge = false
    }
  }

  func revealInFinder() {
    guard let packageURL else { return }
    let access = SandboxFileAccessManager.shared.beginAccessingURL(packageURL)
    defer { access.stop() }
    NSWorkspace.shared.activateFileViewerSelecting([packageURL])
  }
}

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
  let projectContext = VideoEditorProjectContext()
  private(set) var projectPackageURL: URL?
  private(set) var didPresentRestoreFailureAlert: Bool = false
  private var projectPackageAccess: SandboxFileAccessManager.ScopedAccess?
  private var sourceFileAccess: SandboxFileAccessManager.ScopedAccess?
  private var originalFileAccess: SandboxFileAccessManager.ScopedAccess?
  private var sourceURL: URL?
  private var ownedTempDropDirectoryURL: URL?
  private var state: VideoEditorState?
  var editorState: VideoEditorState? {
    state
  }

  private var sessionData: VideoEditorSessionData?
  private var initialPlayheadSeconds: Double?
  private var documentEditedCancellable: AnyCancellable?
  private var autoRecoveryCancellable: AnyCancellable?
  private var autoRecoveryTask: Task<Void, Never>?
  private var activeExportTask: Task<Void, Never>?
  private var activeProjectSaveTask: Task<Void, Never>?
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
    let parentDir = url.deletingLastPathComponent()
    if parentDir.lastPathComponent.hasPrefix("VideoEditor_"),
       parentDir.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
      ownedTempDropDirectoryURL = parentDir
    }
    self.sessionData = sessionData
    if let enclosing = SnapzyProjectPackage.enclosingProjectPackageURL(for: originalURL ?? url)
      ?? SnapzyProjectPackage.enclosingProjectPackageURL(for: url) {
      projectPackageURL = enclosing
      projectContext.packageURL = enclosing
      projectPackageAccess = fileAccessManager.beginAccessingURL(enclosing)
    }
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

  /// Initialize directly from a rehydrated `.snapzy` project package.
  init(project: SnapzyProjectPackage.LoadedProject) {
    quickAccessItemID = nil
    projectPackageURL = project.packageURL
    projectContext.packageURL = project.packageURL
    projectPackageAccess = fileAccessManager.beginAccessingURL(project.packageURL)
    sourceFileAccess = fileAccessManager.beginAccessingURL(project.sessionData.sourceSnapshotURL)
    sourceURL = project.sessionData.sourceSnapshotURL
    sessionData = project.sessionData
    initialPlayheadSeconds = project.playheadSeconds > 0 ? project.playheadSeconds : nil
    state = VideoEditorState(
      url: project.sessionData.sourceSnapshotURL,
      originalURL: project.packageURL,
      sessionData: project.sessionData
    )
    isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    window?.representedURL = project.packageURL
    window?.title = project.packageURL.lastPathComponent
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
    projectPackageAccess?.stop()
    sourceFileAccess?.stop()
    originalFileAccess?.stop()
    if let tempDir = ownedTempDropDirectoryURL {
      try? FileManager.default.removeItem(at: tempDir)
    }
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

    projectContext.onRenameProject = { [weak self] newName in
      try self?.renameProjectPackage(to: newName)
    }

    let mainView = VideoEditorMainView(
      state: state,
      projectContext: projectContext,
      initialPlayheadSeconds: initialPlayheadSeconds,
      primaryActionTitle: primaryActionTitle,
      onSave: { [weak self] in self?.showSaveConfirmation() },
      onCancel: { [weak self] in self?.handleCancel() },
      onSaveProject: { [weak self] in self?.saveProject() },
      onSaveProjectAs: { [weak self] in self?.saveProjectAs() },
      onOpenProjectOrVideo: { [weak self] in self?.openProjectOrVideo() },
      onMetadataLoaded: { [weak self] in self?.handleMetadataLoaded() }
    )
    bindDocumentEditedState(to: state)
    bindAutoRecovery(to: state)
    (window as? VideoEditorWindow)?.onTogglePlayback = { [weak state] in
      guard state?.isExporting != true else { return }
      state?.togglePlayback()
    }
    (window as? VideoEditorWindow)?.onAIPromptShortcut = { [weak state, weak window] in
      guard let state, !state.isExporting else { return false }
      let agent = state.agent
      guard agent.isAvailable else { return false }
      agent.handleShortcut(isFieldEditing: PromptTextField.isEditing(in: window))
      return true
    }
    window?.contentView = NSHostingView(rootView: mainView)
  }

  private func setupEmptyContent() {
    bindDocumentEditedState(to: nil)
    bindAutoRecovery(to: nil)
    (window as? VideoEditorWindow)?.onTogglePlayback = nil
    (window as? VideoEditorWindow)?.onAIPromptShortcut = nil
    let emptyView = VideoEditorEmptyStateView { [weak self] url, originalURL in
      self?.onVideoLoaded?(url, originalURL)
    }
    window?.contentView = NSHostingView(rootView: emptyView)
  }

  private func bindAutoRecovery(to state: VideoEditorState?) {
    autoRecoveryCancellable = nil
    autoRecoveryTask?.cancel()
    autoRecoveryTask = nil
    guard let state else { return }

    autoRecoveryCancellable = state.objectWillChange
      .debounce(for: .milliseconds(1200), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        guard let self,
              let liveState = self.state,
              projectPackageURL == nil,
              !liveState.isExporting,
              liveState.hasUnsavedChanges
        else { return }
        scheduleOffMainAutoRecovery()
      }
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

  /// Surfaces a visible warning alert when a `.snapzy` project's timeline fails validation
  /// against its media, and locks in-place Save so the original package is never clobbered.
  func handleMetadataLoaded() {
    guard let state,
          state.sessionRestoreFailed,
          projectPackageURL != nil,
          !didPresentRestoreFailureAlert
    else {
      return
    }
    didPresentRestoreFailureAlert = true
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
          let window
    else {
      return
    }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.VideoEditor.projectRestoreFailedTitle
    alert.informativeText = L10n.VideoEditor.projectRestoreFailedMessage
    alert.addButton(withTitle: L10n.Common.ok)
    alert.beginSheetModal(for: window)
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

  var canOverwriteProjectInPlace: Bool {
    guard let state, projectPackageURL != nil else { return false }
    return !state.sessionRestoreFailed
  }

  // MARK: - NSWindowDelegate

  static var shouldBypassUnsavedCloseAlert: Bool {
    let env = ProcessInfo.processInfo.environment
    if env["SNAPZY_SKIP_UNSAVED_CLOSE_ALERT"] == "1" {
      return true
    }
    if env["XCTestConfigurationFilePath"] != nil, env["SNAPZY_FORCE_UNSAVED_CLOSE_ALERT"] != "1" {
      return true
    }
    return false
  }

  private func flushActiveTextEditing() {
    window?.makeFirstResponder(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let state else { return true }

    flushActiveTextEditing()

    guard state.hasUnsavedChanges else {
      state.agentIfLoaded?.stop()
      state.pause()
      return true
    }

    if Self.shouldBypassUnsavedCloseAlert {
      scheduleOffMainAutoRecovery()
      state.agentIfLoaded?.stop()
      state.pause()
      return true
    }

    // Do not stop `agentIfLoaded` or pause before the user confirms Save / Don't Save so
    // choosing Cancel leaves an active AI run and playback undisturbed.
    showUnsavedChangesAlert(for: sender)
    return false
  }

  func windowWillClose(_: Notification) {
    activeExportTask?.cancel()
    activeExportTask = nil
    activeProjectSaveTask?.cancel()
    activeProjectSaveTask = nil
    autoRecoveryCancellable = nil
    autoRecoveryTask?.cancel()
    autoRecoveryTask = nil
    state?.agentIfLoaded?.stop()
    state?.cancelPendingPerformanceWork()
    if let tempDir = ownedTempDropDirectoryURL {
      ownedTempDropDirectoryURL = nil
      try? FileManager.default.removeItem(at: tempDir)
    }
    window?.alphaValue = 0
    if let contentView = window?.contentView {
      window?.contentView = nil
      // Release `NSHostingView` on a plain C RunLoop turn outside any active Swift
      // Concurrency `Task` frame so `NSHostingView.deinit` never triggers the macOS 15
      // `swift_task_deinitOnExecutorMainActorBackDeploy` / `StopLookupScope` malloc abort.
      CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
        withExtendedLifetime(contentView) {}
      }
      CFRunLoopWakeUp(CFRunLoopGetMain())
    }
    if let itemId = quickAccessItemID {
      QuickAccessManager.shared.setWindowOpen(id: itemId, isOpen: false)
    }
  }

  // MARK: - Unsaved Changes Alert (.snapzy Zero Data Loss Protection)

  private func showUnsavedChangesAlert(for window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.projectUnsavedCloseTitle
    alert.informativeText = L10n.VideoEditor.projectUnsavedCloseMessage
    alert.alertStyle = .warning

    let saveTitle = canOverwriteProjectInPlace
      ? L10n.VideoEditor.projectMenuSave
      : L10n.VideoEditor.projectMenuSaveEllipsis
    alert.addButton(withTitle: saveTitle)
    alert.addButton(withTitle: L10n.VideoEditor.dontSave)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }

      switch response {
      case .alertFirstButtonReturn:
        state?.agentIfLoaded?.stop()
        state?.pause()
        saveProject { [weak self] didSave in
          if didSave {
            self?.forceClose()
          }
        }

      case .alertSecondButtonReturn:
        scheduleOffMainAutoRecovery()
        forceClose()

      default:
        break
      }
    }
  }

  // MARK: - .snapzy Project Actions (⌘S / ⇧⌘S / ⌘O)

  func saveProject(completion: ((Bool) -> Void)? = nil) {
    guard let state else {
      completion?(false)
      return
    }
    flushActiveTextEditing()
    state.pause()

    // Never overwrite the original `.snapzy` package in place if session restore failed!
    if state.sessionRestoreFailed {
      presentSaveProjectPanel(completion: completion)
      return
    }

    if let existingPackageURL = projectPackageURL
      ?? SnapzyProjectPackage.enclosingProjectPackageURL(for: state.originalURL)
      ?? SnapzyProjectPackage.enclosingProjectPackageURL(for: state.editingSourceURL) {
      projectPackageURL = existingPackageURL
      projectContext.packageURL = existingPackageURL
      performSaveProjectPackage(to: existingPackageURL, completion: completion)
    } else {
      presentSaveProjectPanel(completion: completion)
    }
  }

  func saveProjectAs(completion: ((Bool) -> Void)? = nil) {
    guard state != nil else {
      completion?(false)
      return
    }
    flushActiveTextEditing()
    state?.pause()
    presentSaveProjectPanel(completion: completion)
  }

  func openProjectOrVideo() {
    VideoEditorManager.shared.promptOpenVideoOrProject(from: isEmptyState ? window : nil)
  }

  private func presentSaveProjectPanel(completion: ((Bool) -> Void)? = nil) {
    guard let state, let window else {
      completion?(false)
      return
    }

    let savePanel = NSSavePanel()
    savePanel.title = L10n.VideoEditor.projectSavePanelTitle
    savePanel.message = L10n.VideoEditor.projectSavePanelMessage
    savePanel.nameFieldLabel = L10n.VideoEditor.fileNameLabel
    let baseReferenceURL = projectPackageURL ?? state.originalURL
    if state.sessionRestoreFailed, projectPackageURL != nil {
      let stem = baseReferenceURL.deletingPathExtension().lastPathComponent
      savePanel.nameFieldStringValue = "\(stem)-copy.\(SnapzyProjectPackage.fileExtension)"
    } else {
      savePanel.nameFieldStringValue = SnapzyProjectPackage.suggestedProjectFilename(for: baseReferenceURL)
    }
    savePanel.allowedContentTypes = [SnapzyProjectPackage.projectUTType]
    savePanel.canCreateDirectories = true
    savePanel.isExtensionHidden = false

    savePanel.beginSheetModal(for: window) { [weak self] response in
      guard let self else {
        completion?(false)
        return
      }
      guard response == .OK, let rawURL = savePanel.url else {
        completion?(false)
        return
      }
      let targetURL = SnapzyProjectPackage.normalizedPackageURL(rawURL)
      performSaveProjectPackage(to: targetURL, completion: completion)
    }
  }

  /// Off-main-thread project save used by interactive UI actions.
  func performSaveProjectPackage(
    to destinationURL: URL,
    completion: ((Bool) -> Void)? = nil
  ) {
    guard let state, !projectContext.isSavingProject else {
      completion?(false)
      return
    }

    let previousPackageURL = projectPackageURL
    let preSaveOriginalURL = state.originalURL
    let preSaveSourceURL = sourceURL
    let existingSourceSnapshotURL = sessionData?.sourceSnapshotURL
    projectContext.isSavingProject = true

    activeProjectSaveTask?.cancel()
    activeProjectSaveTask = Task { @MainActor [weak self] in
      guard let self else {
        completion?(false)
        return
      }
      defer {
        projectContext.isSavingProject = false
        activeProjectSaveTask = nil
      }

      do {
        let loaded = try await SnapzyProjectPackage.saveAsync(
          state: state,
          existingSourceSnapshotURL: existingSourceSnapshotURL,
          existingPackageURL: previousPackageURL,
          to: destinationURL
        )
        applySavedProjectState(
          loaded,
          state: state,
          previousPackageURL: previousPackageURL,
          preSaveOriginalURL: preSaveOriginalURL,
          preSaveSourceURL: preSaveSourceURL
        )
        completion?(true)
      } catch {
        DiagnosticLogger.shared.logError(.editor, error, "Failed to save .snapzy project")
        showSaveProjectError(error)
        completion?(false)
      }
    }
  }

  /// Synchronous project save helper for deterministic XCTests; still enforces the restore-failed
  /// in-place overwrite lock (`SnapzyProjectPackageError.restoreFailedSaveBlocked`).
  @discardableResult
  func performSaveProjectPackageSync(to destinationURL: URL) throws -> SnapzyProjectPackage.LoadedProject {
    guard let state else {
      throw SnapzyProjectPackageError.invalidPackageURL(destinationURL)
    }
    let previousPackageURL = projectPackageURL
    let preSaveOriginalURL = state.originalURL
    let preSaveSourceURL = sourceURL
    let loaded = try SnapzyProjectPackage.save(
      state: state,
      existingSourceSnapshotURL: sessionData?.sourceSnapshotURL,
      existingPackageURL: previousPackageURL,
      to: destinationURL
    )
    applySavedProjectState(
      loaded,
      state: state,
      previousPackageURL: previousPackageURL,
      preSaveOriginalURL: preSaveOriginalURL,
      preSaveSourceURL: preSaveSourceURL
    )
    return loaded
  }

  private func applySavedProjectState(
    _ loaded: SnapzyProjectPackage.LoadedProject,
    state: VideoEditorState,
    previousPackageURL: URL?,
    preSaveOriginalURL: URL,
    preSaveSourceURL: URL?
  ) {
    projectPackageAccess?.stop()
    projectPackageAccess = fileAccessManager.beginAccessingURL(loaded.packageURL)
    sourceFileAccess?.stop()
    sourceFileAccess = fileAccessManager.beginAccessingURL(loaded.sessionData.sourceSnapshotURL)
    projectPackageURL = loaded.packageURL
    projectContext.packageURL = loaded.packageURL
    projectContext.markJustSaved()
    sourceURL = loaded.sessionData.sourceSnapshotURL
    sessionData = loaded.sessionData
    state.rebindProjectMediaURLs(from: loaded.sessionData, newPackageURL: loaded.packageURL)
    window?.representedURL = loaded.packageURL
    window?.title = loaded.packageURL.lastPathComponent

    VideoEditorManager.shared.registerProjectAssociation(
      controller: self,
      packageURL: loaded.packageURL,
      previousPackageURL: previousPackageURL
    )

    if previousPackageURL == nil {
      if !SnapzyProjectPackage.isInsideProjectPackage(preSaveOriginalURL) {
        VideoEditorSessionStore.shared.deleteSession(for: preSaveOriginalURL)
        VideoEditorManager.shared.clearSessionData(for: preSaveOriginalURL)
      }
      if let preSaveSourceURL,
         preSaveSourceURL.standardizedFileURL != preSaveOriginalURL.standardizedFileURL,
         !SnapzyProjectPackage.isInsideProjectPackage(preSaveSourceURL) {
        VideoEditorSessionStore.shared.deleteSession(for: preSaveSourceURL)
        VideoEditorManager.shared.clearSessionData(for: preSaveSourceURL)
      }
    }

    state.markAsSaved()
    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Saved .snapzy project package",
      context: ["project": loaded.packageURL.lastPathComponent]
    )
  }

  private func renameProjectPackage(to rawName: String) throws {
    guard let oldPackageURL = projectPackageURL else { return }
    let sanitized = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty,
          sanitized != ".",
          sanitized != "..",
          !sanitized.contains("/"),
          !sanitized.contains("\\")
    else {
      throw NSError(
        domain: "VideoEditor",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid project filename"]
      )
    }

    let parentDir = oldPackageURL.deletingLastPathComponent()
    let oldAccess = fileAccessManager.beginAccessingURL(oldPackageURL)
    let dirAccess = fileAccessManager.beginAccessingURL(parentDir)
    defer {
      oldAccess.stop()
      dirAccess.stop()
    }

    let newPackageURL = SnapzyProjectPackage.normalizedPackageURL(
      dirAccess.url.appendingPathComponent(sanitized)
    )
    guard newPackageURL != oldPackageURL.standardizedFileURL else { return }
    guard !FileManager.default.fileExists(atPath: newPackageURL.path) else {
      throw NSError(
        domain: "VideoEditor",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "A project with this name already exists"]
      )
    }

    try FileManager.default.moveItem(at: oldAccess.url, to: newPackageURL)
    let reloaded = try SnapzyProjectPackage.load(from: newPackageURL)

    projectPackageAccess?.stop()
    projectPackageAccess = fileAccessManager.beginAccessingURL(reloaded.packageURL)
    sourceFileAccess?.stop()
    sourceFileAccess = fileAccessManager.beginAccessingURL(reloaded.sessionData.sourceSnapshotURL)

    projectPackageURL = reloaded.packageURL
    projectContext.packageURL = reloaded.packageURL
    sourceURL = reloaded.sessionData.sourceSnapshotURL
    sessionData = reloaded.sessionData
    state?.rebindProjectMediaURLs(from: reloaded.sessionData, newPackageURL: reloaded.packageURL)
    window?.representedURL = reloaded.packageURL
    window?.title = reloaded.packageURL.lastPathComponent

    VideoEditorManager.shared.registerProjectAssociation(
      controller: self,
      packageURL: reloaded.packageURL,
      previousPackageURL: oldPackageURL
    )
  }

  private func showSaveProjectError(_ error: Error) {
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
          let window
    else { return }
    let alert = NSAlert()
    alert.messageText = L10n.VideoEditor.projectSaveFailedTitle
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .critical
    alert.addButton(withTitle: L10n.Common.ok)
    alert.beginSheetModal(for: window)
  }

  /// Schedules auto-recovery draft persistence off `@MainActor` so large source videos are never
  /// copied synchronously on the main thread.
  private func scheduleOffMainAutoRecovery() {
    guard projectPackageURL == nil,
          let state,
          state.isGIF || !state.clips.isEmpty,
          !SnapzyProjectPackage.isInsideProjectPackage(state.originalURL)
    else {
      return
    }
    let existingSourceURL = sessionData?.sourceSnapshotURL ?? state.editingSourceURL
    let targetOriginalURL = state.originalURL
    let itemID = quickAccessItemID
    let snapshot = VideoEditorSessionData.snapshot(
      from: state,
      sourceSnapshotURL: existingSourceURL
    )

    autoRecoveryTask?.cancel()
    autoRecoveryTask = Task { @MainActor [weak self] in
      let persisted = await VideoEditorSessionStore.shared.persistDraftOffMain(
        snapshot: snapshot,
        existingSourceSnapshotURL: self?.sessionData?.sourceSnapshotURL,
        for: targetOriginalURL
      )
      guard !Task.isCancelled, let persisted else { return }
      self?.sessionData = persisted
      if let itemID {
        VideoEditorManager.shared.saveSessionData(persisted, for: itemID)
      } else {
        VideoEditorManager.shared.saveSessionData(persisted, for: targetOriginalURL)
      }
    }
  }

  // MARK: - Save Confirmation

  private func showSaveConfirmation() {
    guard let window, let state else { return }

    // When editing a `.snapzy` project package, `Convert` always exports a rendered
    // standalone video/GIF copy rather than overwriting internal `Media/primary.*`.
    if projectPackageURL != nil {
      if state.isGIF {
        performGIFSaveAsCopy()
      } else {
        performSaveAsCopy()
      }
      return
    }

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
        try await GIFResizer.resize(
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

        invalidateEditedCloudState()
        guard await persistSessionAfterCommit(for: state, preparedSource: preparedSource) else {
          state.isExporting = false
          showExportError(VideoEditorSessionStore.StoreError.packageUnavailable)
          return
        }
        state.markAsSaved()
        state.isExporting = false
        if let quickAccessItemID {
          await QuickAccessManager.shared.refreshItemThumbnail(id: quickAccessItemID)
        }
        PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
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
        try await GIFResizer.resize(
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
        invalidateEditedCloudState()
        guard await persistSessionAfterCommit(for: state, preparedSource: preparedSource) else {
          state.isExporting = false
          showExportError(VideoEditorSessionStore.StoreError.packageUnavailable)
          return
        }
        state.markAsSaved()
        state.isExporting = false
        if let quickAccessItemID {
          await QuickAccessManager.shared.refreshItemThumbnail(id: quickAccessItemID)
        }
        PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
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
    if let projectStem = projectContext.packageStemName, !projectStem.isEmpty {
      let ext = state.sourceURL.pathExtension.isEmpty ? "mp4" : state.sourceURL.pathExtension
      savePanel.nameFieldStringValue = "\(projectStem).\(ext)"
    } else {
      savePanel.nameFieldStringValue = VideoEditorExporter.generateCopyFilename(from: state.sourceURL)
    }
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

    activeExportTask?.cancel()
    activeExportTask = Task { [weak self] in
      defer { self?.activeExportTask = nil }
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
        guard let self, !Task.isCancelled else { return }
        state.isExporting = false
        state.cloudURL = nil
        state.cloudKey = nil
        scheduleOffMainAutoRecovery()
        if projectPackageURL == nil {
          state.markAsSaved()
        }

        // Show exported file in Finder
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        offerPostExportUpload(for: outputURL) {}
      } catch {
        guard let self, !Task.isCancelled else { return }
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
          let window
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

        let result = try await CloudShareService.shared.upload(fileURL: fileURL)

        // Store cloud link on pasteboard
        ClipboardHelper.copyText(result.publicURL.absoluteString)

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
    flushActiveTextEditing()

    if let state, state.hasUnsavedChanges {
      if Self.shouldBypassUnsavedCloseAlert {
        scheduleOffMainAutoRecovery()
        forceClose()
      } else {
        showUnsavedChangesAlert(for: window)
      }
    } else {
      forceClose()
    }
  }
}
