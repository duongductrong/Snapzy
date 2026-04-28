//
//  RecordingCoordinator.swift
//  Snapzy
//
//  Coordinates the recording flow between UI components and recording manager
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingCoordinator: ObservableObject {

  static let shared = RecordingCoordinator()

  @Published private(set) var isActive = false

  private var toolbarWindow: RecordingToolbarWindow?
  private var regionOverlayWindows: [RecordingRegionOverlayWindow] = []
  private var selectedRect: CGRect?
  private var selectedWindowTarget: WindowCaptureTarget?
  private let captureManager = ScreenCaptureManager.shared
  private let recorder = ScreenRecordingManager.shared
  private var isStartingRecording = false
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  private var onSessionEnded: (@MainActor () -> Void)?

  // Annotation overlay
  private var annotationToolbarWindow: RecordingAnnotationToolbarWindow?
  private var annotationOverlayWindow: RecordingAnnotationOverlayWindow?

  // Click highlight overlay
  private var clickHighlightWindow: MouseClickHighlightWindow?
  private var clickHighlightService: MouseClickHighlightService?

  // Keystroke overlay
  private var keystrokeOverlayWindow: KeystrokeOverlayWindow?
  private var keystrokeMonitorService: KeystrokeMonitorService?

  private struct ToolbarConfiguration {
    let format: VideoFormat
    let quality: VideoQuality
    let captureAudio: Bool
    let captureMicrophone: Bool
    let outputMode: RecordingOutputMode
    let highlightClicks: Bool
    let showKeystrokes: Bool
  }

  private init() {}

  private let tempCaptureManager = TempCaptureManager.shared

  private var includeOwnAppInScreenshots: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.screenshotIncludeOwnApp)
  }

  private var showsCursorInScreenshots: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.screenshotShowCursor) as? Bool ?? false
  }

  private var includeOwnAppInRecordings: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.recordingIncludeOwnApp)
  }

  private func recordingCaptureExclusionConfiguration() -> (excludeOwnApplication: Bool, excludedWindowIDs: [CGWindowID]) {
    let excludeOwnApplication = !includeOwnAppInRecordings
    if excludeOwnApplication {
      return (true, [])
    }

    var windowIDs = regionOverlayWindows.map { CGWindowID($0.windowNumber) }
    if let toolbarWindow {
      windowIDs.append(CGWindowID(toolbarWindow.windowNumber))
    }
    return (false, windowIDs)
  }

  // MARK: - Recording Area Persistence

  /// Save recording area rect to UserDefaults
  private func saveLastAreaRect(_ rect: CGRect) {
    let rectDict: [String: CGFloat] = [
      "x": rect.origin.x,
      "y": rect.origin.y,
      "width": rect.width,
      "height": rect.height
    ]
    UserDefaults.standard.set(rectDict, forKey: PreferencesKeys.recordingLastAreaRect)
  }

  /// Load last recording area rect from UserDefaults
  func loadLastAreaRect() -> CGRect? {
    guard let rectDict = UserDefaults.standard.dictionary(forKey: PreferencesKeys.recordingLastAreaRect),
          let x = rectDict["x"] as? CGFloat,
          let y = rectDict["y"] as? CGFloat,
          let width = rectDict["width"] as? CGFloat,
          let height = rectDict["height"] as? CGFloat else {
      return nil
    }

    let rect = CGRect(x: x, y: y, width: width, height: height)

    // Validate rect is still visible on current screens
    guard isRectVisibleOnScreen(rect) else {
      return nil
    }

    return rect
  }

  /// Check if rect is visible on any connected screen
  private func isRectVisibleOnScreen(_ rect: CGRect) -> Bool {
    for screen in NSScreen.screens {
      if screen.frame.intersects(rect) {
        return true
      }
    }
    return false
  }

  // MARK: - Public API

  func stopFromStatusItem() {
    DiagnosticLogger.shared.log(.debug, .recording, "Stop requested from status item", context: [
      "recorderState": "\(recorder.state)"
    ])
    switch recorder.state {
    case .recording, .paused:
      stopRecording()
    case .preparing:
      cancel()
    case .idle, .stopping:
      break
    }
  }

  /// Start recording flow after area selection
  func showToolbar(
    for rect: CGRect,
    captureMode: RecordingCaptureMode = .area,
    windowTarget: WindowCaptureTarget? = nil,
    onSessionEnded: (@MainActor () -> Void)? = nil
  ) {
    guard !isActive else {
      DiagnosticLogger.shared.log(.debug, .recording, "Recording toolbar request ignored: coordinator active")
      onSessionEnded?()
      return
    }
    isActive = true
    self.onSessionEnded = onSessionEnded
    presentToolbar(
      for: rect,
      captureMode: captureMode,
      windowTarget: windowTarget,
      configuration: nil
    )
  }

  private func setupEscapeMonitors() {
    removeEscapeMonitors()

    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if self?.handlePreRecordKeyEvent(event) == true {
        return nil
      }
      return event
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard self?.isPreRecordKeyEvent(event) == true else { return }
      DispatchQueue.main.async {
        _ = self?.handlePreRecordKeyEvent(event)
      }
    }
  }

  private func isPreRecordKeyEvent(_ event: NSEvent) -> Bool {
    event.keyCode == 53 || isApplicationToggleEvent(event)
  }

  @discardableResult
  private func handlePreRecordKeyEvent(_ event: NSEvent) -> Bool {
    if event.keyCode == 53 {  // Escape key
      handleEscapeKey()
      return true
    }

    guard isApplicationToggleEvent(event) else { return false }
    toggleApplicationCaptureMode()
    return true
  }

  private func isApplicationToggleEvent(_ event: NSEvent) -> Bool {
    guard recorder.state == .idle, !isStartingRecording else { return false }
    guard toolbarWindow != nil else { return false }
    return CaptureOverlayShortcutSettings.matchesRecordingApplicationCaptureShortcut(event)
  }

  private func toggleApplicationCaptureMode() {
    guard let toolbarWindow else { return }
    let nextMode: RecordingCaptureMode = toolbarWindow.captureMode == .application ? .area : .application
    toolbarWindow.captureMode = nextMode
    handleCaptureModeChange(nextMode)
  }

  /// Handle ESC key before recording starts.
  private func handleEscapeKey() {
    cancel()
  }

  private func removeEscapeMonitors() {
    if let monitor = localEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      localEscapeMonitor = nil
    }
    if let monitor = globalEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      globalEscapeMonitor = nil
    }
  }

  func cancel() {
    DiagnosticLogger.shared.log(.info, .recording, "Recording coordinator cancel requested", context: [
      "isActive": "\(isActive)",
      "recorderState": "\(recorder.state)",
    ])
    Task {
      await recorder.cancelRecording()
      cleanup()
    }
  }

  private func presentToolbar(
    for rect: CGRect,
    captureMode: RecordingCaptureMode,
    windowTarget: WindowCaptureTarget?,
    configuration: ToolbarConfiguration?
  ) {
    DiagnosticLogger.shared.log(.info, .recording, "Recording toolbar shown", context: [
      "mode": captureMode.rawValue,
      "rect": "\(Int(rect.width))x\(Int(rect.height))",
      "origin": "\(Int(rect.origin.x)),\(Int(rect.origin.y))",
      "windowTarget": windowTarget == nil ? "false" : "true",
    ])

    updateSelectedTarget(
      rect: rect,
      captureMode: captureMode,
      windowTarget: windowTarget,
      syncToolbarMode: false
    )

    let toolbar = RecordingToolbarWindow(anchorRect: rect)
    configureToolbarCallbacks(toolbar)
    applyToolbarConfiguration(configuration, to: toolbar)
    toolbar.captureMode = captureMode
    toolbarWindow = toolbar

    showRegionOverlay(for: rect, interactionEnabled: captureMode != .application)
    setupEscapeMonitors()
  }

  private func configureToolbarCallbacks(_ toolbar: RecordingToolbarWindow) {
    toolbar.onRecord = { [weak self] in
      self?.startRecording()
    }
    toolbar.onCapture = { [weak self] in
      self?.captureScreenshot()
    }
    toolbar.onCancel = { [weak self] in
      self?.cancel()
    }
    toolbar.onDelete = { [weak self] in
      self?.deleteRecording()
    }
    toolbar.onRestart = { [weak self] in
      self?.restartRecording()
    }
    toolbar.onStop = { [weak self] in
      self?.stopRecording()
    }
    toolbar.onCaptureModeChanged = { [weak self] mode in
      self?.handleCaptureModeChange(mode)
    }
  }

  private func currentToolbarConfiguration() -> ToolbarConfiguration? {
    guard let toolbarWindow else { return nil }
    return ToolbarConfiguration(
      format: toolbarWindow.selectedFormat,
      quality: toolbarWindow.selectedQuality,
      captureAudio: toolbarWindow.captureAudio,
      captureMicrophone: toolbarWindow.captureMicrophone,
      outputMode: toolbarWindow.outputMode,
      highlightClicks: toolbarWindow.state.highlightClicks,
      showKeystrokes: toolbarWindow.state.showKeystrokes
    )
  }

  private func applyToolbarConfiguration(
    _ configuration: ToolbarConfiguration?,
    to toolbar: RecordingToolbarWindow
  ) {
    if let configuration {
      toolbar.selectedFormat = configuration.format
      toolbar.selectedQuality = configuration.quality
      toolbar.captureAudio = configuration.captureAudio
      toolbar.captureMicrophone = configuration.captureMicrophone
      toolbar.outputMode = configuration.outputMode
      toolbar.state.highlightClicks = configuration.highlightClicks
      toolbar.state.showKeystrokes = configuration.showKeystrokes
      return
    }

    if let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingFormat),
       let format = VideoFormat(rawValue: formatString) {
      toolbar.selectedFormat = format
    }
  }

  private func updateSelectedTarget(
    rect: CGRect,
    captureMode: RecordingCaptureMode,
    windowTarget: WindowCaptureTarget?,
    syncToolbarMode: Bool = true
  ) {
    selectedRect = rect
    selectedWindowTarget = windowTarget
    saveLastAreaRect(rect)

    for overlay in regionOverlayWindows {
      overlay.updateHighlightRect(rect)
      overlay.setInteractionEnabled(captureMode != .application)
    }

    if syncToolbarMode {
      toolbarWindow?.captureMode = captureMode
      toolbarWindow?.updateAnchorRect(rect)
    }
  }

  private func handleSelectionResult(
    _ selection: AreaSelectionResult?,
    configuration: ToolbarConfiguration?,
    cancellationLog: String
  ) {
    guard let selection else {
      DiagnosticLogger.shared.log(.info, .recording, cancellationLog)
      cleanup()
      return
    }

    let captureMode: RecordingCaptureMode
    let windowTarget: WindowCaptureTarget?
    switch selection.target {
    case .rect:
      captureMode = .area
      windowTarget = nil
    case .window(let target):
      captureMode = .application
      windowTarget = target
    }

    presentToolbar(
      for: selection.rect,
      captureMode: captureMode,
      windowTarget: windowTarget,
      configuration: configuration
    )
  }

  private func restartSelection(for mode: RecordingCaptureMode) {
    let configuration = currentToolbarConfiguration()
    DiagnosticLogger.shared.log(.info, .recording, "Recording selection restart requested", context: [
      "mode": mode.rawValue,
      "hasToolbar": "\(toolbarWindow != nil)"
    ])

    removeEscapeMonitors()
    closePreRecordUI()

    let applicationConfiguration = AreaSelectionApplicationConfiguration(
      prefetchedContentTask: captureManager.prefetchShareableContent(),
      excludeOwnApplication: !includeOwnAppInRecordings
    )

    if mode == .fullscreen {
      let fullscreenRect = ScreenUtility.activeScreen().frame
      presentToolbar(
        for: fullscreenRect,
        captureMode: .fullscreen,
        windowTarget: nil,
        configuration: configuration
      )
      return
    }

    AreaSelectionController.shared.startSelection(
      mode: .recording,
      backdrops: [:],
      applicationConfiguration: applicationConfiguration,
      initialInteractionMode: mode == .application ? .applicationWindow : .manualRegion
    ) { [weak self] selection in
      guard let self else { return }
      self.handleSelectionResult(
        selection,
        configuration: configuration,
        cancellationLog: "Recording reselection cancelled"
      )
    }
  }

  private func closePreRecordUI() {
    for overlay in regionOverlayWindows {
      overlay.close()
    }
    regionOverlayWindows.removeAll()

    toolbarWindow?.onRecord = nil
    toolbarWindow?.onCapture = nil
    toolbarWindow?.onCancel = nil
    toolbarWindow?.onDelete = nil
    toolbarWindow?.onRestart = nil
    toolbarWindow?.onStop = nil
    toolbarWindow?.onCaptureModeChanged = nil
    toolbarWindow?.onAnnotateButtonOffsetChanged = nil
    toolbarWindow?.close()
    toolbarWindow = nil
  }

  /// Handle capture mode toggle between area and fullscreen
  private func handleCaptureModeChange(_ mode: RecordingCaptureMode) {
    DiagnosticLogger.shared.log(.info, .recording, "Recording capture mode changed", context: [
      "mode": "\(mode)"
    ])

    switch mode {
    case .fullscreen:
      restartSelection(for: .fullscreen)
    case .area:
      restartSelection(for: .area)
    case .application:
      restartSelection(for: .application)
    }
  }

  /// Delete current recording and close
  private func deleteRecording() {
    DiagnosticLogger.shared.log(.info, .recording, "Recording delete requested", context: [
      "recorderState": "\(recorder.state)"
    ])
    Task {
      await recorder.cancelRecording()
      SoundManager.play("Funk")
      cleanup()
    }
  }

  /// Restart recording from scratch (cancel current and start new)
  private func restartRecording() {
    guard let rect = selectedRect, let window = toolbarWindow else {
      DiagnosticLogger.shared.log(.warning, .recording, "Recording restart ignored: missing selection or toolbar")
      return
    }

    let savedFormat = window.selectedFormat
    let savedQuality = window.selectedQuality
    let savedCaptureAudio = window.captureAudio
    let savedCaptureMicrophone = window.captureMicrophone
    DiagnosticLogger.shared.log(.info, .recording, "Recording restart requested", context: [
      "format": savedFormat.rawValue,
      "quality": savedQuality.rawValue,
      "systemAudio": "\(savedCaptureAudio)",
      "microphone": "\(savedCaptureMicrophone)",
      "rect": "\(Int(rect.width))x\(Int(rect.height))",
    ])

    Task {
      // Cancel current recording
      await recorder.cancelRecording()

      // Small delay to ensure cleanup completes
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

      // Re-prepare and start recording with same settings
      do {
        var fps = UserDefaults.standard.integer(forKey: PreferencesKeys.recordingFPS)
        if fps == 0 { fps = 30 }

        guard let saveDirectory = self.resolveSaveDirectoryForOperation() else {
          DiagnosticLogger.shared.log(.warning, .recording, "Recording restart blocked: no save directory access")
          self.showSaveLocationPermissionAlert()
          return
        }

        let exclusionConfig = self.recordingCaptureExclusionConfiguration()

        // Resolve save directory based on auto-save toggle
        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .recording,
          exportDirectory: saveDirectory
        )

        try await recorder.prepareRecording(
          rect: rect,
          windowTarget: self.selectedWindowTarget,
          format: savedFormat,
          quality: savedQuality,
          fps: fps,
          captureSystemAudio: savedCaptureAudio,
          captureMicrophone: savedCaptureMicrophone,
          saveDirectory: actualSaveDirectory,
          excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
          excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
          excludeOwnApplication: exclusionConfig.excludeOwnApplication,
          excludedWindowIDs: exclusionConfig.excludedWindowIDs
        )

        try await recorder.startRecording()
        removeEscapeMonitors()
        DiagnosticLogger.shared.log(.info, .recording, "Recording restart completed")

        // Play sound to indicate restart
        SoundManager.play("Purr")

      } catch let error as RecordingError {
        DiagnosticLogger.shared.logError(.recording, error, "Recording restart failed")
        if !showErrorAlert(error) {
          cancel()
        }
      } catch {
        DiagnosticLogger.shared.logError(.recording, error, "Recording restart failed (generic)")
        if !showErrorAlert(.setupFailed(error.localizedDescription)) {
          cancel()
        }
      }
    }
  }

  // MARK: - Private

  private func showRegionOverlay(for rect: CGRect, interactionEnabled: Bool) {
    for screen in NSScreen.screens {
      let overlay = RecordingRegionOverlayWindow(screen: screen, highlightRect: rect)
      overlay.interactionDelegate = self
      overlay.setInteractionEnabled(interactionEnabled)
      overlay.orderFrontRegardless()
      regionOverlayWindows.append(overlay)
    }
  }

  private func startRecording() {
    guard let rect = selectedRect, let window = toolbarWindow else {
      DiagnosticLogger.shared.log(.warning, .recording, "Start recording ignored: missing selection or toolbar")
      return
    }
    guard beginRecordingStartAttempt(source: "toolbar") else { return }

    let format = window.selectedFormat
    DiagnosticLogger.shared.log(.info, .recording, "Start recording", context: [
      "format": format.rawValue,
      "rect": "\(Int(rect.width))x\(Int(rect.height))"
    ])

    // Get FPS from preferences (default 30)
    var fps = UserDefaults.standard.integer(forKey: PreferencesKeys.recordingFPS)
    if fps == 0 { fps = 30 }

    // Get quality from preferences (default high)
    let qualityString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingQuality) ?? "high"
    let quality = VideoQuality(rawValue: qualityString) ?? .high

    let captureSystemAudio = window.captureAudio

    // Get microphone setting from toolbar
    let captureMicrophone = window.captureMicrophone
    DiagnosticLogger.shared.log(.debug, .recording, "Recording options resolved", context: [
      "quality": quality.rawValue,
      "fps": "\(fps)",
      "systemAudio": "\(captureSystemAudio)",
      "microphone": "\(captureMicrophone)",
    ])

    guard let saveDirectory = resolveSaveDirectoryForOperation() else {
      DiagnosticLogger.shared.log(.warning, .recording, "Recording start blocked: no save directory access")
      finishRecordingStartAttempt()
      showSaveLocationPermissionAlert()
      return
    }

    // Save selected format to preferences
    UserDefaults.standard.set(format.rawValue, forKey: PreferencesKeys.recordingFormat)

    Task {
      do {
        let exclusionConfig = self.recordingCaptureExclusionConfiguration()
        DiagnosticLogger.shared.log(.debug, .recording, "Recording capture exclusion resolved", context: [
          "excludeOwnApp": "\(exclusionConfig.excludeOwnApplication)",
          "excludedWindows": "\(exclusionConfig.excludedWindowIDs.count)",
        ])

        // Resolve save directory based on auto-save toggle
        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .recording,
          exportDirectory: saveDirectory
        )

        try await recorder.prepareRecording(
          rect: rect,
          windowTarget: self.selectedWindowTarget,
          format: format,
          quality: quality,
          fps: fps,
          captureSystemAudio: captureSystemAudio,
          captureMicrophone: captureMicrophone,
          saveDirectory: actualSaveDirectory,
          excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
          excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
          excludeOwnApplication: exclusionConfig.excludeOwnApplication,
          excludedWindowIDs: exclusionConfig.excludedWindowIDs
        )

        try await recorder.startRecording()
        removeEscapeMonitors()

        // Hide border on overlay (would appear in video)
        // Disable interaction during recording
        for overlay in regionOverlayWindows {
          overlay.hideBorder()
          overlay.setInteractionEnabled(false)
        }

        // Setup annotation overlay (must be after recording starts so window exists)
        setupAnnotationOverlay(for: rect)

        // Setup click highlight overlay (must be after recording starts)
        setupClickHighlightOverlay(for: rect)

        // Setup keystroke overlay (must be after recording starts)
        setupKeystrokeOverlay(for: rect)

        // Switch to status bar
        window.showRecordingStatusBar(recorder: recorder)
        finishRecordingStartAttempt()

      } catch let error as RecordingError {
        DiagnosticLogger.shared.logError(.recording, error, "Recording setup failed")
        finishRecordingStartAttempt()
        if case .alreadyActive = error { return }
        if !showErrorAlert(error) {
          cancel()
        }
      } catch {
        DiagnosticLogger.shared.logError(.recording, error, "Recording setup failed (generic)")
        finishRecordingStartAttempt()
        if !showErrorAlert(.setupFailed(error.localizedDescription)) {
          cancel()
        }
      }
    }
  }

  @discardableResult
  private func showErrorAlert(_ error: RecordingError) -> Bool {
    DiagnosticLogger.shared.log(.error, .recording, "Error alert shown", context: ["error": error.localizedDescription])
    let alert = NSAlert()
    alert.messageText = L10n.Recording.failedTitle
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning

    // Special handling for microphone permission denied
    if case .microphonePermissionDenied = error {
      alert.messageText = L10n.Microphone.accessRequiredTitle
      alert.informativeText = L10n.Microphone.recordingMessage
      alert.addButton(withTitle: L10n.Common.openSystemSettings)
      alert.addButton(withTitle: L10n.Microphone.continueWithoutMic)
      alert.addButton(withTitle: L10n.Common.cancel)

      let response = alert.runModal()
      switch response {
      case .alertFirstButtonReturn:
        // Open System Settings > Privacy & Security > Microphone
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
          NSWorkspace.shared.open(url)
        }
        return false
      case .alertSecondButtonReturn:
        // Continue recording without microphone
        startRecordingWithoutMicrophone()
        return true
      default:
        return false
      }
    } else {
      alert.addButton(withTitle: L10n.Common.ok)
      alert.runModal()
      return false
    }
  }

  private func startRecordingWithoutMicrophone() {
    guard let rect = selectedRect, let window = toolbarWindow else {
      DiagnosticLogger.shared.log(.warning, .recording, "Microphone retry ignored: missing selection or toolbar")
      return
    }
    guard beginRecordingStartAttempt(source: "microphone-retry") else { return }

    // Disable microphone and retry
    window.captureMicrophone = false
    DiagnosticLogger.shared.log(.info, .recording, "Retrying recording without microphone")

    let format = window.selectedFormat
    var fps = UserDefaults.standard.integer(forKey: PreferencesKeys.recordingFPS)
    if fps == 0 { fps = 30 }
    let qualityString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingQuality) ?? "high"
    let quality = VideoQuality(rawValue: qualityString) ?? .high
    let captureSystemAudio = window.captureAudio

    guard let saveDirectory = resolveSaveDirectoryForOperation() else {
      DiagnosticLogger.shared.log(.warning, .recording, "Microphone retry blocked: no save directory access")
      finishRecordingStartAttempt()
      showSaveLocationPermissionAlert()
      return
    }

    Task {
      do {
        let exclusionConfig = self.recordingCaptureExclusionConfiguration()

        // Resolve save directory based on auto-save toggle
        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .recording,
          exportDirectory: saveDirectory
        )

        try await recorder.prepareRecording(
          rect: rect,
          windowTarget: self.selectedWindowTarget,
          format: format,
          quality: quality,
          fps: fps,
          captureSystemAudio: captureSystemAudio,
          captureMicrophone: false,
          saveDirectory: actualSaveDirectory,
          excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
          excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
          excludeOwnApplication: exclusionConfig.excludeOwnApplication,
          excludedWindowIDs: exclusionConfig.excludedWindowIDs
        )
        try await recorder.startRecording()
        removeEscapeMonitors()

        for overlay in regionOverlayWindows {
          overlay.hideBorder()
          overlay.setInteractionEnabled(false)
        }
        window.showRecordingStatusBar(recorder: recorder)
        finishRecordingStartAttempt()
        DiagnosticLogger.shared.log(.info, .recording, "Microphone retry recording started")
      } catch let error as RecordingError {
        DiagnosticLogger.shared.logError(.recording, error, "Microphone retry recording failed")
        finishRecordingStartAttempt()
        if case .alreadyActive = error { return }
        if !showErrorAlert(error) {
          cancel()
        }
      } catch {
        DiagnosticLogger.shared.logError(.recording, error, "Microphone retry recording failed (generic)")
        finishRecordingStartAttempt()
        if !showErrorAlert(.setupFailed(error.localizedDescription)) {
          cancel()
        }
      }
    }
  }

  private func stopRecording() {
    // Capture output mode before cleanup closes the toolbar
    let outputMode = toolbarWindow?.state.outputMode ?? .video

    Task {
      let url = await recorder.stopRecording()
      DiagnosticLogger.shared.log(.info, .recording, "Recording stopped", context: [
        "hasOutput": "\(url != nil)",
        "outputMode": "\(outputMode)"
      ])
      if url == nil {
        DiagnosticLogger.shared.log(.warning, .recording, "Recording stop completed without output URL")
      }

      // Dismiss recording UI immediately (status bar, area overlay, etc.)
      cleanup()

      if let url = url {
        // Play sound
        SoundManager.play("Glass")

        if outputMode == .gif {
          // GIF mode: add to QuickAccess immediately with processing state
          await handleGIFConversion(videoURL: url)
        } else {
          // Video mode: normal post-capture flow
          await PostCaptureActionHandler.shared.handleVideoCapture(url: url)
        }
      }
    }
  }

  /// Handle GIF conversion: add to QuickAccess with progress, convert, and update
  private func handleGIFConversion(videoURL: URL) async {
    DiagnosticLogger.shared.log(.info, .recording, "GIF conversion started", context: ["file": videoURL.lastPathComponent])
    let quickAccess = QuickAccessManager.shared
    let sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(videoURL)
    let outputDirectoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(
      videoURL.deletingLastPathComponent())
    defer {
      sourceAccess.stop()
      outputDirectoryAccess.stop()
    }

    // Add video to QuickAccess immediately with processing state
    await quickAccess.addVideo(url: videoURL)

    // Find the item we just added (should be first)
    guard let item = quickAccess.items.first else {
      DiagnosticLogger.shared.log(.error, .recording, "GIF conversion aborted: Quick Access item missing", context: [
        "file": videoURL.lastPathComponent
      ])
      return
    }
    let itemId = item.id

    // Set initial processing state
    quickAccess.updateProcessingState(id: itemId, state: .processing(progress: 0))

    // Run GIF conversion
    do {
      let gifURL = try await GIFConverter.convert(
        videoURL: videoURL,
        onProgress: { progress in
          quickAccess.updateProcessingState(id: itemId, state: .processing(progress: progress))
        }
      )

      // Generate thumbnail from GIF
      let thumbnail = SandboxFileAccessManager.shared.withScopedAccess(to: gifURL) {
        NSImage(contentsOf: gifURL)
      }

      // Update the QuickAccess item with GIF URL
      quickAccess.updateItemURL(id: itemId, newURL: gifURL, newThumbnail: thumbnail)
      quickAccess.updateProcessingState(id: itemId, state: .idle)

      // Run remaining post-capture actions (clipboard copy, etc.) on the final GIF
      // skipQuickAccess: item is already in QuickAccess from addVideo() above
      await PostCaptureActionHandler.shared.handleVideoCapture(url: gifURL, skipQuickAccess: true)

      // Delete the original video file
      SandboxFileAccessManager.shared.withScopedAccess(to: videoURL.deletingLastPathComponent()) {
        do {
          try FileManager.default.removeItem(at: videoURL)
          DiagnosticLogger.shared.log(.debug, .recording, "GIF source video deleted", context: [
            "file": videoURL.lastPathComponent
          ])
        } catch {
          DiagnosticLogger.shared.logError(.recording, error, "Failed to delete GIF source video", context: [
            "file": videoURL.lastPathComponent
          ])
        }
        try? RecordingMetadataStore.delete(for: videoURL)
      }

    } catch {
      DiagnosticLogger.shared.logError(.recording, error, "GIF conversion failed")
      // On failure, keep the video as-is and clear processing state
      quickAccess.updateProcessingState(id: itemId, state: .failed)

      // Auto-clear failure state after 2 seconds
      Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        quickAccess.updateProcessingState(id: itemId, state: .idle)
      }
    }
  }

  /// Capture a screenshot of the selected area and close the toolbar
  private func captureScreenshot() {
    guard let rect = selectedRect else { return }
    DiagnosticLogger.shared.log(.info, .recording, "Screenshot during recording", context: [
      "rect": "\(Int(rect.width))x\(Int(rect.height))"
    ])

    guard let saveDirectory = resolveSaveDirectoryForOperation() else {
      DiagnosticLogger.shared.log(.warning, .recording, "Screenshot during recording blocked: no save directory access")
      showSaveLocationPermissionAlert()
      return
    }

    // Hide overlay windows and toolbar so they don't appear in the screenshot
    for overlay in regionOverlayWindows {
      overlay.orderOut(nil)
    }
    toolbarWindow?.orderOut(nil)

    let captureManager = ScreenCaptureManager.shared
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )

    // Resolve save directory based on auto-save toggle
    let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
      for: .screenshot,
      exportDirectory: saveDirectory
    )

    Task {
      await Task.yield()

      let result: CaptureResult
      if let selectedWindowTarget {
        result = await captureManager.captureWindow(
          target: selectedWindowTarget,
          saveDirectory: actualSaveDirectory,
          showCursor: showsCursorInScreenshots,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: !includeOwnAppInScreenshots,
          prefetchedContentTask: prefetchedContentTask
        )
      } else {
        result = await captureManager.captureArea(
          rect: rect,
          saveDirectory: actualSaveDirectory,
          showCursor: showsCursorInScreenshots,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: !includeOwnAppInScreenshots,
          prefetchedContentTask: prefetchedContentTask
        )
      }

      switch result {
      case .success:
        DiagnosticLogger.shared.log(.info, .recording, "Screenshot during recording captured")
        SoundManager.playScreenshotCapture()
        // PostCaptureActionHandler is triggered automatically via
        // ScreenCaptureManager.captureCompletedPublisher → ScreenCaptureViewModel
      case .failure(let error):
        DiagnosticLogger.shared.logError(.recording, error, "Screenshot during recording failed")
        let alert = NSAlert()
        alert.messageText = L10n.Recording.screenshotFailedTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Common.ok)
        alert.runModal()
      }

      cleanup()
    }
  }

  private func cleanup() {
    DiagnosticLogger.shared.log(.debug, .recording, "Recording cleanup", context: [
      "regionOverlays": "\(regionOverlayWindows.count)",
      "hasToolbar": "\(toolbarWindow != nil)",
      "hasAnnotationOverlay": "\(annotationOverlayWindow != nil)",
      "hasClickHighlight": "\(clickHighlightWindow != nil)",
      "hasKeystrokeOverlay": "\(keystrokeOverlayWindow != nil)",
    ])
    finishRecordingStartAttempt()
    // Remove escape monitors
    removeEscapeMonitors()

    // Close click highlight overlay
    cleanupClickHighlightOverlay()

    // Close keystroke overlay
    cleanupKeystrokeOverlay()

    // Close annotation windows
    cleanupAnnotationOverlay()

    // Close region overlay windows
    closePreRecordUI()
    selectedRect = nil
    selectedWindowTarget = nil
    isActive = false
    let sessionEndHandler = onSessionEnded
    onSessionEnded = nil
    sessionEndHandler?()
  }

  private func beginRecordingStartAttempt(source: String) -> Bool {
    guard !isStartingRecording, recorder.state == .idle else {
      DiagnosticLogger.shared.log(.debug, .recording, "Recording start blocked: recorder busy", context: [
        "source": source,
        "state": "\(recorder.state)"
      ])
      return false
    }

    isStartingRecording = true
    toolbarWindow?.state.isPreparingToRecord = true
    return true
  }

  private func finishRecordingStartAttempt() {
    isStartingRecording = false
    toolbarWindow?.state.isPreparingToRecord = false
  }

  private func resolveSaveDirectoryForOperation() -> URL? {
    SandboxFileAccessManager.shared.ensureExportDirectoryForOperation(
      promptMessage: L10n.Recording.chooseSaveLocationMessage
    )
  }

  private func showSaveLocationPermissionAlert() {
    let alert = NSAlert()
    alert.messageText = L10n.Recording.saveLocationAccessRequiredTitle
    alert.informativeText = L10n.Recording.saveLocationAccessRequiredMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.ok)
    alert.runModal()
  }

  // MARK: - Annotation Overlay

  private func setupAnnotationOverlay(for rect: CGRect) {
    guard let window = toolbarWindow else {
      DiagnosticLogger.shared.log(.warning, .recording, "Annotation overlay setup skipped: toolbar missing")
      return
    }
    let annotationState = window.annotationState

    // Create overlay window covering recording rect
    let overlayWindow = RecordingAnnotationOverlayWindow(
      recordingRect: rect,
      annotationState: annotationState
    )
    overlayWindow.orderFrontRegardless()
    annotationOverlayWindow = overlayWindow
    DiagnosticLogger.shared.log(.info, .recording, "Annotation overlay created", context: [
      "windowID": "\(overlayWindow.overlayWindowID)",
      "rect": "\(Int(rect.width))x\(Int(rect.height))",
    ])

    // Create popover-style annotation toolbar anchored to the status bar
    let toolbarWin = RecordingAnnotationToolbarWindow(annotationState: annotationState)
    toolbarWin.anchorWindow = window
    toolbarWin.anchorButtonCenterXOffset = window.annotateButtonCenterXOffset
    annotationToolbarWindow = toolbarWin

    // Update popover anchor offset when SwiftUI layout reports button position
    window.onAnnotateButtonOffsetChanged = { [weak toolbarWin] offset in
      toolbarWin?.anchorButtonCenterXOffset = offset
      if annotationState.isAnnotationEnabled {
        toolbarWin?.positionRelativeToAnchor()
      }
    }

    // Start auto-clear timer
    annotationState.startCleanupTimer()

    // Add overlay window to ScreenCaptureKit's exceptingWindows
    // so annotations appear in the recorded video
    Task {
      await recorder.addExceptedWindow(windowID: overlayWindow.overlayWindowID)
    }
  }

  private func cleanupAnnotationOverlay() {
    if annotationOverlayWindow != nil || annotationToolbarWindow != nil {
      DiagnosticLogger.shared.log(.debug, .recording, "Annotation overlay cleanup")
    }
    toolbarWindow?.annotationState.stopCleanupTimer()
    toolbarWindow?.annotationState.isAnnotationEnabled = false

    annotationToolbarWindow?.close()
    annotationToolbarWindow = nil

    annotationOverlayWindow?.close()
    annotationOverlayWindow = nil
  }

  // MARK: - Click Highlight Overlay

  private func setupClickHighlightOverlay(for rect: CGRect) {
    let isEnabled = UserDefaults.standard.object(forKey: PreferencesKeys.recordingHighlightClicks) as? Bool ?? false
    guard isEnabled else {
      DiagnosticLogger.shared.log(.debug, .recording, "Click highlight overlay disabled")
      return
    }

    let config = MouseHighlightConfiguration()
    let highlightWindow = MouseClickHighlightWindow(recordingRect: rect, configuration: config)
    highlightWindow.orderFrontRegardless()
    clickHighlightWindow = highlightWindow

    let service = MouseClickHighlightService()
    service.onMouseDown = { [weak highlightWindow] point in
      highlightWindow?.showClickEffect(at: point)
    }
    service.onMouseUp = { [weak highlightWindow] in
      highlightWindow?.dismissClickEffect()
    }
    service.onMouseDragged = { [weak highlightWindow] point in
      highlightWindow?.moveClickEffect(to: point)
    }
    service.start(recordingRect: rect)
    clickHighlightService = service
    DiagnosticLogger.shared.log(.info, .recording, "Click highlight overlay started", context: [
      "windowID": "\(highlightWindow.overlayWindowID)"
    ])

    // Add to ScreenCaptureKit's exceptingWindows so the effect is captured
    Task {
      await recorder.addExceptedWindow(windowID: highlightWindow.overlayWindowID)
    }
  }

  private func cleanupClickHighlightOverlay() {
    if clickHighlightWindow != nil || clickHighlightService != nil {
      DiagnosticLogger.shared.log(.debug, .recording, "Click highlight overlay cleanup")
    }
    clickHighlightService?.stop()
    clickHighlightService = nil
    clickHighlightWindow?.close()
    clickHighlightWindow = nil
  }

  // MARK: - Keystroke Overlay

  private func setupKeystrokeOverlay(for rect: CGRect) {
    let isEnabled = UserDefaults.standard.object(forKey: PreferencesKeys.recordingShowKeystrokes) as? Bool ?? false
    guard isEnabled else {
      DiagnosticLogger.shared.log(.debug, .recording, "Keystroke overlay disabled")
      return
    }

    let config = KeystrokeOverlayConfiguration()
    let overlayWindow = KeystrokeOverlayWindow(recordingRect: rect, configuration: config)
    overlayWindow.orderFrontRegardless()
    keystrokeOverlayWindow = overlayWindow

    let service = KeystrokeMonitorService()
    service.onKeystroke = { [weak overlayWindow] text in
      overlayWindow?.showKeystroke(text)
    }
    service.start()
    keystrokeMonitorService = service
    DiagnosticLogger.shared.log(.info, .recording, "Keystroke overlay started", context: [
      "windowID": "\(overlayWindow.overlayWindowID)"
    ])

    // Add to ScreenCaptureKit's exceptingWindows so keystrokes are captured
    Task {
      await recorder.addExceptedWindow(windowID: overlayWindow.overlayWindowID)
    }
  }

  private func cleanupKeystrokeOverlay() {
    if keystrokeOverlayWindow != nil || keystrokeMonitorService != nil {
      DiagnosticLogger.shared.log(.debug, .recording, "Keystroke overlay cleanup")
    }
    keystrokeMonitorService?.stop()
    keystrokeMonitorService = nil
    keystrokeOverlayWindow?.close()
    keystrokeOverlayWindow = nil
  }

  /// Update the selected rect and sync all overlays + toolbar
  private func updateSelectedRect(_ rect: CGRect) {
    let captureMode = toolbarWindow?.captureMode == .application ? RecordingCaptureMode.area : (toolbarWindow?.captureMode ?? .area)
    updateSelectedTarget(rect: rect, captureMode: captureMode, windowTarget: nil)
  }
}

// MARK: - RecordingRegionOverlayDelegate

extension RecordingCoordinator: RecordingRegionOverlayDelegate {
  func overlayDidRequestReselection(_ overlay: RecordingRegionOverlayWindow) {
    restartSelection(for: .area)
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didMoveRegionTo rect: CGRect) {
    updateSelectedRect(rect)
  }

  func overlayDidFinishMoving(_ overlay: RecordingRegionOverlayWindow) {
    // No additional action needed - rect is already updated
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didReselectWithRect rect: CGRect) {
    // Update the selected rect in-place without closing windows
    updateSelectedRect(rect)
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didResizeRegionTo rect: CGRect) {
    updateSelectedRect(rect)
  }

  func overlayDidFinishResizing(_ overlay: RecordingRegionOverlayWindow) {
    // No additional action needed - rect is already updated
  }
}
