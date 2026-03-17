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
  private let postCaptureHandler = PostCaptureActionHandler.shared
  private let fileAccessManager = SandboxFileAccessManager.shared
  private let tempCaptureManager = TempCaptureManager.shared
  private var isAreaSelectionActive = false
  private var cancellables = Set<AnyCancellable>()

  // Shortcut bindings for UI
  @Published var fullscreenShortcut: ShortcutConfig
  @Published var areaShortcut: ShortcutConfig
  @Published var recordingShortcut: ShortcutConfig

  init() {
    fileAccessManager.ensureExportLocationInitialized()
    saveDirectory = fileAccessManager.resolvedExportDirectoryURL()

    // Initialize shortcuts from manager
    fullscreenShortcut = KeyboardShortcutManager.shared.fullscreenShortcut
    areaShortcut = KeyboardShortcutManager.shared.areaShortcut
    recordingShortcut = KeyboardShortcutManager.shared.recordingShortcut

    // Set up shortcut delegate
    shortcutManager.delegate = self

    // Subscribe to capture completions for post-capture actions
    captureManager.captureCompletedPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] url in
        guard let self = self else { return }
        Task {
          await self.postCaptureHandler.handleScreenshotCapture(url: url)
        }
      }
      .store(in: &cancellables)

    captureManager.$hasPermission
      .receive(on: DispatchQueue.main)
      .sink { [weak self] hasPermission in
        self?.hasPermission = hasPermission
      }
      .store(in: &cancellables)

    // Sync permission state
    Task {
      await updatePermissionState()
    }
  }

  private var includesOwnAppInScreenshots: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.screenshotIncludeOwnApp)
  }

  private var includesOwnAppInRecordings: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.recordingIncludeOwnApp)
  }

  private var shouldHideOwnWindowsForRecordingToolbarFlow: Bool {
    !includesOwnAppInScreenshots && !includesOwnAppInRecordings
  }

  private func hideVisibleNormalWindowsIfNeeded(_ shouldHide: Bool) {
    guard shouldHide else { return }
    NSApp.windows
      .filter { $0.isVisible && $0.level == .normal }
      .forEach { $0.orderOut(nil) }
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
    case .captureOCR:
      captureOCR()
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
      guard
        let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
          promptMessage: "Choose where Snapzy should save screenshots and recordings")
      else {
        lastCaptureResult = .failure(.saveFailed("Save location permission is required"))
        return
      }
      saveDirectory = resolvedSaveDirectory

      isCapturing = true
      let prefetchedContentTask = captureManager.prefetchShareableContent()
      await Task.yield()

      // Resolve save directory based on auto-save toggle
      let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
        for: .screenshot,
        exportDirectory: resolvedSaveDirectory
      )

      let result = await captureManager.captureFullscreen(
        saveDirectory: actualSaveDirectory,
        format: selectedFormat.format,
        excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
        excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
        excludeOwnApplication: !includesOwnAppInScreenshots,
        prefetchedContentTask: prefetchedContentTask
      )

      isCapturing = false
      lastCaptureResult = result

      if case .success = result {
        SoundManager.play("Glass")
      }
    }
  }

  func captureArea() {
    // Prevent multiple area captures - only one at a time
    if isAreaSelectionActive {
      print("[Snapzy:CaptureVM] captureArea() blocked — isAreaSelectionActive=true")
      return
    }

    guard
      let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
        promptMessage: "Choose where Snapzy should save screenshots and recordings")
    else {
      lastCaptureResult = .failure(.saveFailed("Save location permission is required"))
      return
    }
    saveDirectory = resolvedSaveDirectory

    // Set flag BEFORE delay to close the race window
    isAreaSelectionActive = true
    print("[Snapzy:CaptureVM] captureArea() — flag set to true")
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    // Hide only normal-level app windows (not overlay panels) to avoid hiding pooled overlay windows
    hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    // Minimal delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else {
        print("[Snapzy:CaptureVM] captureArea() asyncAfter — self is nil, resetting flag")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      print("[Snapzy:CaptureVM] captureArea() — starting selection")
      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          print("[Snapzy:CaptureVM] captureArea() completion — self is nil, flag stuck!")
          return
        }
        // Always reset flag regardless of outcome
        defer {
          self.isAreaSelectionActive = false
          print("[Snapzy:CaptureVM] captureArea() — flag reset to false (defer)")
        }

        guard let selectedRect = rect else {
          // Cancelled
          print("[Snapzy:CaptureVM] captureArea() — cancelled by user")
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        print("[Snapzy:CaptureVM] captureArea() — rect selected: \(selectedRect)")
        Task { @MainActor in
          self.isCapturing = true
          await Task.yield()

          // Resolve save directory based on auto-save toggle
          let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
            for: .screenshot,
            exportDirectory: resolvedSaveDirectory
          )

          let result = await self.captureManager.captureArea(
            rect: selectedRect,
            saveDirectory: actualSaveDirectory,
            format: self.selectedFormat.format,
            excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
            excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
            excludeOwnApplication: !self.includesOwnAppInScreenshots,
            prefetchedContentTask: prefetchedContentTask
          )

          self.isCapturing = false
          self.lastCaptureResult = result
          print("[Snapzy:CaptureVM] captureArea() — capture result: \(result)")

          if case .success = result {
            SoundManager.play("Glass")
          }
        }
      }
    }
  }

  func chooseSaveDirectory() {
    if let url = fileAccessManager.chooseExportDirectory(
      message: "Choose where Snapzy should save screenshots and recordings",
      prompt: "Save Here",
      directoryURL: fileAccessManager.resolvedExportDirectoryURL()
    ) {
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
    guard !isAreaSelectionActive else {
      print("[Snapzy:CaptureVM] startRecordingFlow() blocked — isAreaSelectionActive=true")
      return
    }

    // Set flag BEFORE delay to close race window
    isAreaSelectionActive = true
    print("[Snapzy:CaptureVM] startRecordingFlow() — flag set to true")

    // Hide only normal-level app windows (not overlay panels)
    hideVisibleNormalWindowsIfNeeded(shouldHideOwnWindowsForRecordingToolbarFlow)

    // Small delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else {
        print("[Snapzy:CaptureVM] startRecordingFlow() asyncAfter — self is nil, resetting flag")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      // Check for saved recording area - restore if enabled and available
      let rememberLastArea = UserDefaults.standard.object(forKey: PreferencesKeys.recordingRememberLastArea) as? Bool ?? true
      if rememberLastArea, let savedRect = RecordingCoordinator.shared.loadLastAreaRect() {
        self.isAreaSelectionActive = false
        print("[Snapzy:CaptureVM] startRecordingFlow() — using saved rect, flag reset")
        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(for: savedRect)
        }
        return
      }

      // No saved rect or disabled - start area selection
      print("[Snapzy:CaptureVM] startRecordingFlow() — starting selection")
      AreaSelectionController.shared.startSelection(mode: .recording) { [weak self] rect, mode in
        guard let self = self else {
          print("[Snapzy:CaptureVM] startRecordingFlow() completion — self is nil, flag stuck!")
          return
        }

        // Cleanup flag
        self.isAreaSelectionActive = false
        print("[Snapzy:CaptureVM] startRecordingFlow() — flag reset to false")

        guard let rect = rect else { return }

        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(for: rect)
        }
      }
    }
  }



  // MARK: - OCR Capture

  func captureOCR() {
    // Prevent multiple area captures
    if isAreaSelectionActive {
      print("[Snapzy:CaptureVM] captureOCR() blocked — isAreaSelectionActive=true")
      return
    }

    // Set flag BEFORE delay to close the race window
    isAreaSelectionActive = true
    print("[Snapzy:CaptureVM] captureOCR() — flag set to true")
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    // Hide only normal-level app windows (not overlay panels)
    hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    // Minimal delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else {
        print("[Snapzy:CaptureVM] captureOCR() asyncAfter — self is nil, resetting flag")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      print("[Snapzy:CaptureVM] captureOCR() — starting selection")
      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          print("[Snapzy:CaptureVM] captureOCR() completion — self is nil, flag stuck!")
          return
        }

        guard let selectedRect = rect else {
          self.isAreaSelectionActive = false
          print("[Snapzy:CaptureVM] captureOCR() — cancelled, flag reset")
          return
        }

        print("[Snapzy:CaptureVM] captureOCR() — rect selected: \(selectedRect)")
        Task { @MainActor in
          defer {
            self.isAreaSelectionActive = false
            print("[Snapzy:CaptureVM] captureOCR() — flag reset to false (defer)")
          }
          await Task.yield()

          do {
            // Capture the screen region
            guard let image = try await self.captureManager.captureAreaAsImage(
              rect: selectedRect,
              excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
              excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
              excludeOwnApplication: !self.includesOwnAppInScreenshots,
              prefetchedContentTask: prefetchedContentTask
            ) else {
              QuickAccessSound.failed.play()
              return
            }

            // Perform OCR
            let text = try await OCRService.shared.recognizeText(from: image)

            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            // Success feedback
            QuickAccessSound.complete.play()

          } catch {
            // Error feedback
            QuickAccessSound.failed.play()
          }
        }
      }
    }
  }
}
