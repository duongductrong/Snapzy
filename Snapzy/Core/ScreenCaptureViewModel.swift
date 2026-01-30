//
//  ScreenCaptureViewModel.swift
//  Snapzy
//
//  ViewModel for screen capture operations
//

import AppKit
import Combine
import Foundation

// MARK: - Image Format Option

enum ImageFormatOption: String, CaseIterable {
  case png
  case jpeg
  case tiff

  var format: ImageFormat {
    switch self {
    case .png: return .png
    case .jpeg: return .jpeg(quality: 0.9)
    case .tiff: return .tiff
    }
  }
}

// MARK: - ViewModel

@MainActor
final class ScreenCaptureViewModel: ObservableObject, KeyboardShortcutDelegate {
  @Published var hasPermission: Bool = false
  @Published var isCapturing: Bool = false
  @Published var saveDirectory: URL
  @Published var selectedFormat: ImageFormatOption = .png
  @Published var showCursor: Bool = true
  @Published var playSound: Bool = true
  @Published var lastCaptureResult: CaptureResult?
  @Published var shortcutsEnabled: Bool = false {
    didSet {
      if shortcutsEnabled {
        shortcutManager.enable()
      } else {
        shortcutManager.disable()
      }
    }
  }

  private let captureManager = ScreenCaptureManager.shared
  private let shortcutManager = KeyboardShortcutManager.shared
  private let quickAccessManager = QuickAccessManager.shared
  private var isAreaSelectionActive = false
  private var cancellables = Set<AnyCancellable>()

  // Shortcut bindings for UI
  @Published var fullscreenShortcut: ShortcutConfig
  @Published var areaShortcut: ShortcutConfig
  @Published var recordingShortcut: ShortcutConfig

  init() {
    // Default save directory: Desktop/Snapzy
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    saveDirectory = desktop.appendingPathComponent("Snapzy")

    // Initialize shortcuts from manager
    fullscreenShortcut = KeyboardShortcutManager.shared.fullscreenShortcut
    areaShortcut = KeyboardShortcutManager.shared.areaShortcut
    recordingShortcut = KeyboardShortcutManager.shared.recordingShortcut

    // Set up shortcut delegate
    shortcutManager.delegate = self

    // Subscribe to capture completions for quick access preview
    captureManager.captureCompletedPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] url in
        guard self?.quickAccessManager.isEnabled == true else { return }
        Task {
          await self?.quickAccessManager.addScreenshot(url: url)
        }
      }
      .store(in: &cancellables)

    // Sync permission state
    Task {
      await updatePermissionState()
    }
  }

  // MARK: - Quick Access Settings

  var quickAccessEnabled: Bool {
    get { quickAccessManager.isEnabled }
    set { quickAccessManager.isEnabled = newValue }
  }

  var quickAccessPosition: QuickAccessPosition {
    get { quickAccessManager.position }
    set { quickAccessManager.setPosition(newValue) }
  }

  var quickAccessAutoDismiss: Bool {
    get { quickAccessManager.autoDismissEnabled }
    set { quickAccessManager.autoDismissEnabled = newValue }
  }

  var quickAccessAutoDismissDelay: TimeInterval {
    get { quickAccessManager.autoDismissDelay }
    set { quickAccessManager.autoDismissDelay = newValue }
  }

  // MARK: - Shortcut Management

  func updateFullscreenShortcut(_ config: ShortcutConfig) {
    shortcutManager.setFullscreenShortcut(config)
    fullscreenShortcut = config
  }

  func updateAreaShortcut(_ config: ShortcutConfig) {
    shortcutManager.setAreaShortcut(config)
    areaShortcut = config
  }

  func updateRecordingShortcut(_ config: ShortcutConfig) {
    shortcutManager.setRecordingShortcut(config)
    recordingShortcut = config
  }

  // MARK: - KeyboardShortcutDelegate

  func shortcutTriggered(_ action: ShortcutAction) {
    switch action {
    case .captureFullscreen:
      captureFullscreen()
    case .captureArea:
      captureArea()
    case .recordVideo:
      startRecordingFlow()
    case .openAnnotate:
      AnnotateManager.shared.openEmptyAnnotation()
    case .openVideoEditor:
      VideoEditorManager.shared.openEmptyEditor()
    }
  }

  func updatePermissionState() async {
    await captureManager.checkPermission()
    hasPermission = captureManager.hasPermission
  }

  func requestPermission() {
    Task {
      _ = await captureManager.requestPermission()
      await updatePermissionState()
    }
  }

  func openSettings() {
    captureManager.openScreenRecordingPreferences()
  }

  func captureFullscreen() {
    Task {
      isCapturing = true

      // Minimal delay to ensure UI state updates before capture
      try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

      let result = await captureManager.captureFullscreen(
        saveDirectory: saveDirectory,
        format: selectedFormat.format
      )

      isCapturing = false
      lastCaptureResult = result

      if case .success = result, playSound {
        playScreenshotSound()
      }
    }
  }

  func captureArea() {
    // Prevent multiple area captures - only one at a time
    if isAreaSelectionActive {
      return
    }

    // Hide main window
    NSApp.hide(nil)

    // Minimal delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else { return }

      // Double-check to prevent race condition
      guard !self.isAreaSelectionActive else { return }
      self.isAreaSelectionActive = true

      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else { return }

        // Note: Do NOT call NSApp.unhide/activate here - it steals focus from user's current app
        // Screenshot capture doesn't need app activation

        guard let selectedRect = rect else {
          // Cancelled - clear flag so user can start new selection
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        Task { @MainActor in
          self.isCapturing = true

          let result = await self.captureManager.captureArea(
            rect: selectedRect,
            saveDirectory: self.saveDirectory,
            format: self.selectedFormat.format
          )

          self.isCapturing = false
          self.lastCaptureResult = result

          if case .success = result, self.playSound {
            self.playScreenshotSound()
          }
        }

        self.isAreaSelectionActive = false
      }
    }
  }

  func chooseSaveDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose where to save screenshots"

    if panel.runModal() == .OK, let url = panel.url {
      saveDirectory = url
    }
  }

  // MARK: - Recording

  func startRecordingFlow() {
    guard hasPermission else {
      requestPermission()
      return
    }

    // Check if already recording
    guard !RecordingCoordinator.shared.isActive else { return }

    // Prevent multiple area selections
    guard !isAreaSelectionActive else { return }

    // Hide main window
    NSApp.hide(nil)

    // Small delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else { return }
      self.isAreaSelectionActive = true

      AreaSelectionController.shared.startSelection(mode: .recording) { [weak self] rect, mode in
        guard let self = self else { return }

        // Cleanup flag
        self.isAreaSelectionActive = false

        // Note: Do NOT call NSApp.unhide/activate here - it steals focus from user's current app
        // The recording toolbar uses orderFrontRegardless() which doesn't require app activation

        guard let rect = rect else { return }

        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(for: rect)
        }
      }
    }
  }

  private func playScreenshotSound() {
    NSSound(named: "Glass")?.play()
  }
}
