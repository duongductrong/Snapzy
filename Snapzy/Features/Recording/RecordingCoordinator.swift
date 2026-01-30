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
  private var isShowingConfirmationDialog = false

  private init() {}

  // MARK: - Public API

  /// Start recording flow after area selection
  func showToolbar(for rect: CGRect) {
    guard !isActive else { return }
    isActive = true
    selectedRect = rect

    toolbarWindow = RecordingToolbarWindow(anchorRect: rect)
    toolbarWindow?.onRecord = { [weak self] in
      self?.startRecording()
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

  /// Handle ESC key based on recording state
  private func handleEscapeKey() {
    // Prevent multiple dialogs
    guard !isShowingConfirmationDialog else { return }

    // If recording is in progress, show confirmation dialog
    if recorder.isRecording || recorder.isPaused {
      showStopConfirmationDialog()
    } else {
      // Not recording yet (pre-record mode), allow immediate cancel
      cancel()
    }
  }

  /// Show confirmation dialog when user presses ESC during recording
  private func showStopConfirmationDialog() {
    isShowingConfirmationDialog = true

    // Pause recording while showing dialog
    let wasRecording = recorder.isRecording
    if wasRecording {
      recorder.pauseRecording()
    }

    // Remove escape monitors while dialog is open to prevent ESC from triggering handlers
    removeEscapeMonitors()

    let alert = NSAlert()
    alert.messageText = "Stop Recording?"
    alert.informativeText = "Do you want to discard this recording?"
    alert.alertStyle = .warning

    // Discard is primary (first button), Continue is secondary
    alert.addButton(withTitle: "Discard")
    alert.addButton(withTitle: "Continue")

    // Auto-focus Continue button (second button) by setting it as default
    if alert.buttons.count > 1 {
      let continueButton = alert.buttons[1]
      continueButton.keyEquivalent = "\r"  // Return key
      alert.buttons[0].keyEquivalent = ""  // Remove default from Discard
    }

    let response = alert.runModal()
    isShowingConfirmationDialog = false

    switch response {
    case .alertFirstButtonReturn:
      // Discard - cancel without saving
      deleteRecording()
    case .alertSecondButtonReturn, .cancel:
      // Continue or ESC pressed - resume recording if it was recording
      if wasRecording {
        recorder.resumeRecording()
      }
      // Re-add escape monitors for future ESC presses
      setupEscapeMonitors()
    default:
      // Any other case (shouldn't happen) - resume recording
      if wasRecording {
        recorder.resumeRecording()
      }
      setupEscapeMonitors()
    }
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

  /// Delete current recording and close
  private func deleteRecording() {
    Task {
      await recorder.cancelRecording()
      NSSound(named: "Funk")?.play()
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

        let saveDirectory: URL
        if let path = UserDefaults.standard.string(forKey: PreferencesKeys.exportLocation),
          !path.isEmpty
        {
          saveDirectory = URL(fileURLWithPath: path)
        } else {
          saveDirectory =
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Snapzy")
        }

        try await recorder.prepareRecording(
          rect: rect,
          format: savedFormat,
          quality: savedQuality,
          fps: fps,
          captureSystemAudio: savedCaptureAudio,
          captureMicrophone: savedCaptureMicrophone,
          saveDirectory: saveDirectory
        )

        try await recorder.startRecording()

        // Play sound to indicate restart
        NSSound(named: "Purr")?.play()

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

    // Get save directory
    let saveDirectory: URL
    if let path = UserDefaults.standard.string(forKey: PreferencesKeys.exportLocation),
      !path.isEmpty
    {
      saveDirectory = URL(fileURLWithPath: path)
    } else {
      saveDirectory =
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Snapzy")
    }

    // Save selected format to preferences
    UserDefaults.standard.set(format.rawValue, forKey: PreferencesKeys.recordingFormat)

    Task {
      do {
        try await recorder.prepareRecording(
          rect: rect,
          format: format,
          quality: quality,
          fps: fps,
          captureSystemAudio: captureSystemAudio,
          captureMicrophone: captureMicrophone,
          saveDirectory: saveDirectory
        )

        try await recorder.startRecording()

        // Hide border on overlay (would appear in video)
        // Disable interaction during recording
        for overlay in regionOverlayWindows {
          overlay.hideBorder()
          overlay.setInteractionEnabled(false)
        }

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

    let saveDirectory: URL
    if let path = UserDefaults.standard.string(forKey: PreferencesKeys.exportLocation), !path.isEmpty {
      saveDirectory = URL(fileURLWithPath: path)
    } else {
      saveDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Snapzy")
    }

    Task {
      do {
        try await recorder.prepareRecording(
          rect: rect,
          format: format,
          quality: quality,
          fps: fps,
          captureSystemAudio: captureSystemAudio,
          captureMicrophone: false,
          saveDirectory: saveDirectory
        )
        try await recorder.startRecording()

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
    Task {
      let url = await recorder.stopRecording()

      if let url = url {
        // Play sound
        NSSound(named: "Glass")?.play()

        // Add to QuickAccess stack
        await QuickAccessManager.shared.addVideo(url: url)
      }

      cleanup()
    }
  }

  private func cleanup() {
    // Remove escape monitors
    removeEscapeMonitors()

    // Close region overlay windows
    for overlay in regionOverlayWindows {
      overlay.close()
    }
    regionOverlayWindows.removeAll()

    toolbarWindow?.close()
    toolbarWindow = nil
    selectedRect = nil
    isActive = false
  }

  /// Update the selected rect and sync all overlays + toolbar
  private func updateSelectedRect(_ rect: CGRect) {
    selectedRect = rect
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
        self.toolbarWindow?.onCancel = { [weak self] in self?.cancel() }
        self.toolbarWindow?.onDelete = { [weak self] in self?.deleteRecording() }
        self.toolbarWindow?.onRestart = { [weak self] in self?.restartRecording() }
        self.toolbarWindow?.onStop = { [weak self] in self?.stopRecording() }
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
