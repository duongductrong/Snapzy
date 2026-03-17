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
  private let recorder = ScreenRecordingManager.shared
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?

  // Annotation overlay
  private var annotationToolbarWindow: RecordingAnnotationToolbarWindow?
  private var annotationOverlayWindow: RecordingAnnotationOverlayWindow?

  // Click highlight overlay
  private var clickHighlightWindow: MouseClickHighlightWindow?
  private var clickHighlightService: MouseClickHighlightService?

  // Keystroke overlay
  private var keystrokeOverlayWindow: KeystrokeOverlayWindow?
  private var keystrokeMonitorService: KeystrokeMonitorService?

  private init() {}

  private let tempCaptureManager = TempCaptureManager.shared

  private var includeOwnAppInScreenshots: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.screenshotIncludeOwnApp)
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

  /// Start recording flow after area selection
  func showToolbar(for rect: CGRect) {
    guard !isActive else { return }
    isActive = true
    selectedRect = rect

    // Save rect for next time
    saveLastAreaRect(rect)

    toolbarWindow = RecordingToolbarWindow(anchorRect: rect)
    toolbarWindow?.onRecord = { [weak self] in
      self?.startRecording()
    }
    toolbarWindow?.onCapture = { [weak self] in
      self?.captureScreenshot()
    }
    toolbarWindow?.onCancel = { [weak self] in
      self?.cancel()
    }
    toolbarWindow?.onDelete = { [weak self] in
      self?.deleteRecording()
    }
    toolbarWindow?.onRestart = { [weak self] in
      self?.restartRecording()
    }
    toolbarWindow?.onStop = { [weak self] in
      self?.stopRecording()
    }
    toolbarWindow?.onCaptureModeChanged = { [weak self] mode in
      self?.handleCaptureModeChange(mode)
    }

    // Load format from preferences
    if let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingFormat),
      let format = VideoFormat(rawValue: formatString)
    {
      toolbarWindow?.selectedFormat = format
    }

    // Show region overlay to highlight recording area
    showRegionOverlay(for: rect)

    // Set up escape key monitoring for cancel during prepare phase
    setupEscapeMonitors()
  }

  private func setupEscapeMonitors() {
    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {  // Escape key
        self?.handleEscapeKey()
        return nil
      }
      return event
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        DispatchQueue.main.async {
          self?.handleEscapeKey()
        }
      }
    }
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
    Task {
      await recorder.cancelRecording()
      cleanup()
    }
  }

  /// Handle capture mode toggle between area and fullscreen
  private func handleCaptureModeChange(_ mode: RecordingCaptureMode) {
    guard let screen = NSScreen.main else { return }

    switch mode {
    case .fullscreen:
      // Switch to fullscreen - use entire screen frame
      let fullscreenRect = screen.frame
      updateSelectedRect(fullscreenRect)
    case .area:
      // Switch back to area selection - restart area selection flow
      restartAreaSelection()
    }
  }

  /// Delete current recording and close
  private func deleteRecording() {
    Task {
      await recorder.cancelRecording()
      SoundManager.play("Funk")
      cleanup()
    }
  }

  /// Restart recording from scratch (cancel current and start new)
  private func restartRecording() {
    guard let rect = selectedRect, let window = toolbarWindow else { return }

    let savedFormat = window.selectedFormat
    let savedQuality = window.selectedQuality
    let savedCaptureAudio = window.captureAudio
    let savedCaptureMicrophone = window.captureMicrophone

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

        // Play sound to indicate restart
        SoundManager.play("Purr")

      } catch let error as RecordingError {
        showErrorAlert(error)
        cancel()
      } catch {
        showErrorAlert(.setupFailed(error.localizedDescription))
        cancel()
      }
    }
  }

  // MARK: - Private

  private func showRegionOverlay(for rect: CGRect) {
    for screen in NSScreen.screens {
      let overlay = RecordingRegionOverlayWindow(screen: screen, highlightRect: rect)
      overlay.interactionDelegate = self
      overlay.setInteractionEnabled(true)
      overlay.orderFrontRegardless()
      regionOverlayWindows.append(overlay)
    }
  }

  private func startRecording() {
    guard let rect = selectedRect, let window = toolbarWindow else { return }

    let format = window.selectedFormat

    // Get FPS from preferences (default 30)
    var fps = UserDefaults.standard.integer(forKey: PreferencesKeys.recordingFPS)
    if fps == 0 { fps = 30 }

    // Get quality from preferences (default high)
    let qualityString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingQuality) ?? "high"
    let quality = VideoQuality(rawValue: qualityString) ?? .high

    // Get audio setting (default true)
    let captureSystemAudio: Bool
    if UserDefaults.standard.object(forKey: PreferencesKeys.recordingCaptureAudio) != nil {
      captureSystemAudio = UserDefaults.standard.bool(forKey: PreferencesKeys.recordingCaptureAudio)
    } else {
      captureSystemAudio = true
    }

    // Get microphone setting from toolbar
    let captureMicrophone = window.captureMicrophone

    guard let saveDirectory = resolveSaveDirectoryForOperation() else {
      showSaveLocationPermissionAlert()
      return
    }

    // Save selected format to preferences
    UserDefaults.standard.set(format.rawValue, forKey: PreferencesKeys.recordingFormat)

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

      } catch let error as RecordingError {
        showErrorAlert(error)
        cancel()
      } catch {
        showErrorAlert(.setupFailed(error.localizedDescription))
        cancel()
      }
    }
  }

  private func showErrorAlert(_ error: RecordingError) {
    let alert = NSAlert()
    alert.messageText = "Recording Failed"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning

    // Special handling for microphone permission denied
    if case .microphonePermissionDenied = error {
      alert.messageText = "Microphone Access Required"
      alert.informativeText = "Snapzy needs microphone permission to record audio. Please grant access in System Settings."
      alert.addButton(withTitle: "Open System Settings")
      alert.addButton(withTitle: "Continue Without Mic")
      alert.addButton(withTitle: "Cancel")

      let response = alert.runModal()
      switch response {
      case .alertFirstButtonReturn:
        // Open System Settings > Privacy & Security > Microphone
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
          NSWorkspace.shared.open(url)
        }
      case .alertSecondButtonReturn:
        // Continue recording without microphone
        startRecordingWithoutMicrophone()
        return
      default:
        break
      }
    } else {
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  private func startRecordingWithoutMicrophone() {
    guard let rect = selectedRect, let window = toolbarWindow else { return }

    // Disable microphone and retry
    window.captureMicrophone = false

    let format = window.selectedFormat
    var fps = UserDefaults.standard.integer(forKey: PreferencesKeys.recordingFPS)
    if fps == 0 { fps = 30 }
    let qualityString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingQuality) ?? "high"
    let quality = VideoQuality(rawValue: qualityString) ?? .high
    let captureSystemAudio: Bool
    if UserDefaults.standard.object(forKey: PreferencesKeys.recordingCaptureAudio) != nil {
      captureSystemAudio = UserDefaults.standard.bool(forKey: PreferencesKeys.recordingCaptureAudio)
    } else {
      captureSystemAudio = true
    }

    guard let saveDirectory = resolveSaveDirectoryForOperation() else {
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
      } catch let error as RecordingError {
        showErrorAlert(error)
        cancel()
      } catch {
        showErrorAlert(.setupFailed(error.localizedDescription))
        cancel()
      }
    }
  }

  private func stopRecording() {
    // Capture output mode before cleanup closes the toolbar
    let outputMode = toolbarWindow?.state.outputMode ?? .video

    Task {
      let url = await recorder.stopRecording()

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
    guard let item = quickAccess.items.first else { return }
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
        try? FileManager.default.removeItem(at: videoURL)
        try? RecordingMetadataStore.delete(for: videoURL)
      }

    } catch {
      print("GIF conversion failed: \(error.localizedDescription)")
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

    guard let saveDirectory = resolveSaveDirectoryForOperation() else {
      showSaveLocationPermissionAlert()
      return
    }

    // Hide overlay windows and toolbar so they don't appear in the screenshot
    for overlay in regionOverlayWindows {
      overlay.orderOut(nil)
    }
    toolbarWindow?.orderOut(nil)

    let captureManager = ScreenCaptureManager.shared
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    // Resolve save directory based on auto-save toggle
    let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
      for: .screenshot,
      exportDirectory: saveDirectory
    )

    Task {
      await Task.yield()

      let result = await captureManager.captureArea(
        rect: rect,
        saveDirectory: actualSaveDirectory,
        excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
        excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
        excludeOwnApplication: !includeOwnAppInScreenshots,
        prefetchedContentTask: prefetchedContentTask
      )

      switch result {
      case .success:
        SoundManager.play("Glass")
        // PostCaptureActionHandler is triggered automatically via
        // ScreenCaptureManager.captureCompletedPublisher → ScreenCaptureViewModel
      case .failure(let error):
        let alert = NSAlert()
        alert.messageText = "Screenshot Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }

      cleanup()
    }
  }

  private func cleanup() {
    // Remove escape monitors
    removeEscapeMonitors()

    // Close click highlight overlay
    cleanupClickHighlightOverlay()

    // Close keystroke overlay
    cleanupKeystrokeOverlay()

    // Close annotation windows
    cleanupAnnotationOverlay()

    // Close region overlay windows
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
    selectedRect = nil
    isActive = false
  }

  private func resolveSaveDirectoryForOperation() -> URL? {
    SandboxFileAccessManager.shared.ensureExportDirectoryForOperation(
      promptMessage: "Choose where Snapzy should save screenshots and recordings")
  }

  private func showSaveLocationPermissionAlert() {
    let alert = NSAlert()
    alert.messageText = "Save Location Access Required"
    alert.informativeText = "Snapzy needs a save folder permission to continue. Please choose a folder in onboarding or grant it now."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Annotation Overlay

  private func setupAnnotationOverlay(for rect: CGRect) {
    guard let window = toolbarWindow else { return }
    let annotationState = window.annotationState

    // Create overlay window covering recording rect
    let overlayWindow = RecordingAnnotationOverlayWindow(
      recordingRect: rect,
      annotationState: annotationState
    )
    overlayWindow.orderFrontRegardless()
    annotationOverlayWindow = overlayWindow

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
    guard isEnabled else { return }

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

    // Add to ScreenCaptureKit's exceptingWindows so the effect is captured
    Task {
      await recorder.addExceptedWindow(windowID: highlightWindow.overlayWindowID)
    }
  }

  private func cleanupClickHighlightOverlay() {
    clickHighlightService?.stop()
    clickHighlightService = nil
    clickHighlightWindow?.close()
    clickHighlightWindow = nil
  }

  // MARK: - Keystroke Overlay

  private func setupKeystrokeOverlay(for rect: CGRect) {
    let isEnabled = UserDefaults.standard.object(forKey: PreferencesKeys.recordingShowKeystrokes) as? Bool ?? false
    guard isEnabled else { return }

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

    // Add to ScreenCaptureKit's exceptingWindows so keystrokes are captured
    Task {
      await recorder.addExceptedWindow(windowID: overlayWindow.overlayWindowID)
    }
  }

  private func cleanupKeystrokeOverlay() {
    keystrokeMonitorService?.stop()
    keystrokeMonitorService = nil
    keystrokeOverlayWindow?.close()
    keystrokeOverlayWindow = nil
  }

  /// Update the selected rect and sync all overlays + toolbar
  private func updateSelectedRect(_ rect: CGRect) {
    selectedRect = rect
    // Save updated rect for next time
    saveLastAreaRect(rect)
    for overlay in regionOverlayWindows {
      overlay.updateHighlightRect(rect)
    }
    toolbarWindow?.updateAnchorRect(rect)
  }

  /// Restart area selection (preserves format)
  private func restartAreaSelection() {
    let savedFormat = toolbarWindow?.selectedFormat ?? .mov

    // Close current overlays and toolbar
    for overlay in regionOverlayWindows {
      overlay.close()
    }
    regionOverlayWindows.removeAll()

    toolbarWindow?.close()
    toolbarWindow = nil
    selectedRect = nil

    // Start new selection using shared controller
    AreaSelectionController.shared.startSelection(mode: .recording) { [weak self] rect, _ in
      guard let self = self else { return }

      if let rect = rect {
        self.selectedRect = rect
        self.toolbarWindow = RecordingToolbarWindow(anchorRect: rect)
        self.toolbarWindow?.selectedFormat = savedFormat
        self.toolbarWindow?.onRecord = { [weak self] in self?.startRecording() }
        self.toolbarWindow?.onCapture = { [weak self] in self?.captureScreenshot() }
        self.toolbarWindow?.onCancel = { [weak self] in self?.cancel() }
        self.toolbarWindow?.onDelete = { [weak self] in self?.deleteRecording() }
        self.toolbarWindow?.onRestart = { [weak self] in self?.restartRecording() }
        self.toolbarWindow?.onStop = { [weak self] in self?.stopRecording() }
        self.toolbarWindow?.onCaptureModeChanged = { [weak self] mode in
          self?.handleCaptureModeChange(mode)
        }
        self.showRegionOverlay(for: rect)
      } else {
        // User cancelled
        self.cleanup()
      }
    }
  }
}

// MARK: - RecordingRegionOverlayDelegate

extension RecordingCoordinator: RecordingRegionOverlayDelegate {
  func overlayDidRequestReselection(_ overlay: RecordingRegionOverlayWindow) {
    restartAreaSelection()
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
