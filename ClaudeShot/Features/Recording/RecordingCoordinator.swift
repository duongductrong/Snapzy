//
//  RecordingCoordinator.swift
//  ClaudeShot
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
  private var areaSelectionController: AreaSelectionController?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?

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
        self?.cancel()
        return nil
      }
      return event
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        DispatchQueue.main.async {
          self?.cancel()
        }
      }
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
    }
    cleanup()
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
    let captureAudio: Bool
    if UserDefaults.standard.object(forKey: PreferencesKeys.recordingCaptureAudio) != nil {
      captureAudio = UserDefaults.standard.bool(forKey: PreferencesKeys.recordingCaptureAudio)
    } else {
      captureAudio = true
    }

    // Get save directory
    let saveDirectory: URL
    if let path = UserDefaults.standard.string(forKey: PreferencesKeys.exportLocation),
      !path.isEmpty
    {
      saveDirectory = URL(fileURLWithPath: path)
    } else {
      saveDirectory =
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        .appendingPathComponent("ClaudeShot")
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
          captureAudio: captureAudio,
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
    alert.addButton(withTitle: "OK")
    alert.runModal()
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
    areaSelectionController = nil
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

    // Start new selection
    areaSelectionController = AreaSelectionController()
    areaSelectionController?.startSelection(mode: .recording) { [weak self] rect, _ in
      guard let self = self else { return }
      self.areaSelectionController = nil

      if let rect = rect {
        self.selectedRect = rect
        self.toolbarWindow = RecordingToolbarWindow(anchorRect: rect)
        self.toolbarWindow?.selectedFormat = savedFormat
        self.toolbarWindow?.onRecord = { [weak self] in self?.startRecording() }
        self.toolbarWindow?.onCancel = { [weak self] in self?.cancel() }
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
