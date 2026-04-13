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
  case webp

  var format: ImageFormat {
    switch self {
    case .png: return .png
    case .jpeg: return .jpeg(quality: 0.9)
    case .webp: return .webp
    }
  }

  var displayName: String {
    switch self {
    case .png: return "PNG"
    case .jpeg: return "JPEG"
    case .webp: return "WebP"
    }
  }
}

// MARK: - ViewModel

@MainActor
final class ScreenCaptureViewModel: ObservableObject, KeyboardShortcutDelegate {
  @Published var hasPermission: Bool = false
  @Published var isCapturing: Bool = false
  @Published var saveDirectory: URL
  @Published var selectedFormat: ImageFormatOption {
    didSet {
      UserDefaults.standard.set(selectedFormat.rawValue, forKey: PreferencesKeys.screenshotFormat)
    }
  }

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
  @Published var scrollingCaptureShortcut: ShortcutConfig
  @Published var recordingShortcut: ShortcutConfig
  @Published var objectCutoutShortcut: ShortcutConfig

  init() {
    // Initialize format from saved preference
    if let savedFormat = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
       let format = ImageFormatOption(rawValue: savedFormat) {
      selectedFormat = format
    } else {
      selectedFormat = .png
    }

    fileAccessManager.ensureExportLocationInitialized()
    saveDirectory = fileAccessManager.resolvedExportDirectoryURL()

    // Initialize shortcuts from manager
    fullscreenShortcut = KeyboardShortcutManager.shared.fullscreenShortcut
    areaShortcut = KeyboardShortcutManager.shared.areaShortcut
    scrollingCaptureShortcut = KeyboardShortcutManager.shared.scrollingCaptureShortcut
    recordingShortcut = KeyboardShortcutManager.shared.recordingShortcut
    objectCutoutShortcut = KeyboardShortcutManager.shared.objectCutoutShortcut

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

  private var showsCursorInScreenshots: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.screenshotShowCursor) as? Bool ?? false
  }

  private var isBackgroundCutoutAutoCropEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.backgroundCutoutAutoCropEnabled) as? Bool ?? true
  }

  /// Always read format from UserDefaults to stay in sync with Settings @AppStorage
  private var resolvedFormat: ImageFormat {
    if let raw = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
       let option = ImageFormatOption(rawValue: raw) {
      return option.format
    }
    return .png
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

  func updateScrollingCaptureShortcut(_ config: ShortcutConfig) {
    shortcutManager.setScrollingCaptureShortcut(config)
    scrollingCaptureShortcut = config
  }

  func updateObjectCutoutShortcut(_ config: ShortcutConfig) {
    shortcutManager.setObjectCutoutShortcut(config)
    objectCutoutShortcut = config
  }

  // MARK: - KeyboardShortcutDelegate

  func shortcutTriggered(_ action: ShortcutAction) {
    switch action {
    case .captureFullscreen:
      captureFullscreen()
    case .captureArea:
      captureArea()
    case .captureScrolling:
      captureScrolling()
    case .captureOCR:
      captureOCR()
    case .captureObjectCutout:
      captureObjectCutout()
    case .recordVideo:
      startRecordingFlow()
    case .openAnnotate:
      AnnotateManager.shared.openEmptyAnnotation()
    case .openVideoEditor:
      VideoEditorManager.shared.openEmptyEditor()
    case .openCloudUploads:
      CloudUploadHistoryWindowController.shared.showWindow()
      NSApp.activate(ignoringOtherApps: true)
    case .openShortcutList:
      ShortcutOverlayManager.shared.toggle()
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
          promptMessage: L10n.Recording.chooseSaveLocationMessage)
      else {
        lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
        DiagnosticLogger.shared.log(.error, .capture, "Fullscreen capture aborted: no save location")
        return
      }
      saveDirectory = resolvedSaveDirectory

      isCapturing = true
      DiagnosticLogger.shared.log(.info, .capture, "Fullscreen capture flow started", context: ["format": resolvedFormat.fileExtension])
      let prefetchedContentTask = captureManager.prefetchShareableContent()
      await Task.yield()

      // Resolve save directory based on auto-save toggle
      let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
        for: .screenshot,
        exportDirectory: resolvedSaveDirectory
      )

      let result = await captureManager.captureFullscreen(
        saveDirectory: actualSaveDirectory,
        format: resolvedFormat,
        showCursor: showsCursorInScreenshots,
        excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
        excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
        excludeOwnApplication: !includesOwnAppInScreenshots,
        prefetchedContentTask: prefetchedContentTask
      )

      isCapturing = false
      lastCaptureResult = result

      if case .success = result {
        SoundManager.playScreenshotCapture()
      }
    }
  }

  func captureArea() {
    // Prevent multiple area captures - only one at a time
    if isAreaSelectionActive {
      DiagnosticLogger.shared.log(.debug, .capture, "captureArea blocked: already active")
      return
    }

    guard
      let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
        promptMessage: L10n.Recording.chooseSaveLocationMessage)
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }
    saveDirectory = resolvedSaveDirectory

    // Set flag BEFORE delay to close the race window
    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .capture, "Area capture flow started", context: ["format": resolvedFormat.fileExtension])
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    // Hide only normal-level app windows (not overlay panels) to avoid hiding pooled overlay windows
    hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    // Minimal delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureArea: self deallocated")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureArea completion: self deallocated")
          return
        }
        // Always reset flag regardless of outcome
        defer {
          self.isAreaSelectionActive = false
        }

        guard let selectedRect = rect else {
          // Cancelled
          DiagnosticLogger.shared.log(.info, .capture, "Area capture cancelled by user")
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        DiagnosticLogger.shared.log(.info, .capture, "Area selected", context: ["rect": "\(Int(selectedRect.width))x\(Int(selectedRect.height))"])
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
            format: self.resolvedFormat,
            showCursor: self.showsCursorInScreenshots,
            excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
            excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
            excludeOwnApplication: !self.includesOwnAppInScreenshots,
            prefetchedContentTask: prefetchedContentTask
          )

          self.isCapturing = false
          self.lastCaptureResult = result

          if case .success = result {
            SoundManager.playScreenshotCapture()
          }
        }
      }
    }
  }

  func captureScrolling() {
    guard !ScrollingCaptureCoordinator.shared.isActive else {
      AppToastManager.shared.show(
        message: L10n.ScrollingCapture.toastSessionAlreadyActive,
        style: .warning,
        position: .bottomCenter
      )
      return
    }

    if isAreaSelectionActive {
      DiagnosticLogger.shared.log(.debug, .capture, "captureScrolling blocked: area selection active")
      return
    }

    guard
      let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
        promptMessage: L10n.Recording.chooseSaveLocationMessage)
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }
    saveDirectory = resolvedSaveDirectory

    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .capture, "Scrolling capture flow started", context: ["format": resolvedFormat.fileExtension])
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    hideVisibleNormalWindowsIfNeeded(true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureScrolling: self deallocated")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      AreaSelectionController.shared.startSelection(mode: .scrollingCapture) { [weak self] rect, _ in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureScrolling completion: self deallocated")
          return
        }

        defer {
          self.isAreaSelectionActive = false
        }

        guard let selectedRect = rect else {
          DiagnosticLogger.shared.log(.info, .capture, "Scrolling capture cancelled by user")
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .screenshot,
          exportDirectory: resolvedSaveDirectory
        )

        ScrollingCaptureCoordinator.shared.beginSession(
          rect: selectedRect,
          saveDirectory: actualSaveDirectory,
          format: self.resolvedFormat,
          prefetchedContentTask: prefetchedContentTask
        )
      }
    }
  }

  func chooseSaveDirectory() {
    if let url = fileAccessManager.chooseExportDirectory(
      message: L10n.Recording.chooseSaveLocationMessage,
      prompt: L10n.PreferencesGeneral.saveHereButton,
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
      DiagnosticLogger.shared.log(.debug, .recording, "startRecordingFlow blocked: area selection active")
      return
    }

    // Set flag BEFORE delay to close race window
    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .recording, "Recording flow started")

    // Hide only normal-level app windows (not overlay panels)
    hideVisibleNormalWindowsIfNeeded(shouldHideOwnWindowsForRecordingToolbarFlow)

    // Small delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .recording, "startRecordingFlow: self deallocated")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      // Check for saved recording area - restore if enabled and available
      let rememberLastArea = UserDefaults.standard.object(forKey: PreferencesKeys.recordingRememberLastArea) as? Bool ?? true
      if rememberLastArea, let savedRect = RecordingCoordinator.shared.loadLastAreaRect() {
        self.isAreaSelectionActive = false
        DiagnosticLogger.shared.log(.info, .recording, "Using saved recording area", context: ["rect": "\(Int(savedRect.width))x\(Int(savedRect.height))"])
        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(for: savedRect)
        }
        return
      }

      // No saved rect or disabled - start area selection
      AreaSelectionController.shared.startSelection(mode: .recording) { [weak self] rect, mode in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .recording, "startRecordingFlow completion: self deallocated")
          return
        }

        self.isAreaSelectionActive = false

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
      DiagnosticLogger.shared.log(.debug, .ocr, "captureOCR blocked: area selection active")
      return
    }

    // Set flag BEFORE delay to close the race window
    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .ocr, "OCR capture flow started")
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    // Hide only normal-level app windows (not overlay panels)
    hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    // Minimal delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .ocr, "captureOCR: self deallocated")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .ocr, "captureOCR completion: self deallocated")
          return
        }

        guard let selectedRect = rect else {
          self.isAreaSelectionActive = false
          DiagnosticLogger.shared.log(.info, .ocr, "OCR capture cancelled")
          return
        }

        DiagnosticLogger.shared.log(.info, .ocr, "OCR area selected", context: ["rect": "\(Int(selectedRect.width))x\(Int(selectedRect.height))"])
        Task { @MainActor in
          defer {
            self.isAreaSelectionActive = false
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
            DiagnosticLogger.shared.log(.info, .ocr, "OCR text copied to clipboard", context: ["chars": "\(text.count)"])
            QuickAccessSound.complete.play()

          } catch {
            // Error feedback
            DiagnosticLogger.shared.logError(.ocr, error, "OCR capture failed")
            QuickAccessSound.failed.play()
          }
        }
      }
    }
  }

  // MARK: - Object Cutout Capture

  func captureObjectCutout() {
    // Feature gate: keep app compatible on macOS 13 while disabling this flow safely.
    guard #available(macOS 14.0, *) else {
      DiagnosticLogger.shared.log(.warning, .capture, "Object cutout unavailable: macOS < 14")
      lastCaptureResult = .failure(.unavailable(L10n.ForegroundCutout.unsupportedOS))
      AppToastManager.shared.show(
        message: L10n.ForegroundCutout.unsupportedOS,
        style: .warning,
        position: .bottomCenter
      )
      QuickAccessSound.failed.play()
      return
    }

    // Prevent multiple area captures
    if isAreaSelectionActive {
      DiagnosticLogger.shared.log(.debug, .capture, "captureObjectCutout blocked: area selection active")
      return
    }

    guard
      let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
        promptMessage: L10n.Recording.chooseSaveLocationMessage)
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }
    saveDirectory = resolvedSaveDirectory

    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .capture, "Object cutout flow started")
    let prefetchedContentTask = captureManager.prefetchShareableContent()

    // Hide only normal-level app windows (not overlay panels)
    hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureObjectCutout: self deallocated")
        AreaSelectionController.shared.cancelSelection()
        return
      }

      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureObjectCutout completion: self deallocated")
          return
        }

        guard let selectedRect = rect else {
          self.isAreaSelectionActive = false
          DiagnosticLogger.shared.log(.info, .capture, "Object cutout capture cancelled")
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        Task { @MainActor in
          defer {
            self.isAreaSelectionActive = false
          }

          self.isCapturing = true
          await Task.yield()

          do {
            guard let capturedImage = try await self.captureManager.captureAreaAsImage(
              rect: selectedRect,
              excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
              excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
              excludeOwnApplication: !self.includesOwnAppInScreenshots,
              prefetchedContentTask: prefetchedContentTask
            ) else {
              self.isCapturing = false
              self.lastCaptureResult = .failure(.captureFailed(L10n.ScreenCapture.unableToCaptureSelectedArea))
              AppToastManager.shared.show(
                message: L10n.ScreenCapture.unableToCaptureSelectedArea,
                style: .error,
                position: .bottomCenter
              )
              QuickAccessSound.failed.play()
              return
            }

            let cutoutResult = try await ForegroundCutoutService.shared.extractForegroundResult(
              from: capturedImage
            )
            let (outputImage, didAutoCrop) = self.resolveObjectCutoutOutputImage(
              from: cutoutResult,
              autoCropEnabled: self.isBackgroundCutoutAutoCropEnabled
            )
            DiagnosticLogger.shared.log(
              .info,
              .capture,
              "Object cutout auto-crop evaluation",
              context: [
                "autoCropEnabled": "\(self.isBackgroundCutoutAutoCropEnabled)",
                "decision": cutoutResult.autoCropDecision.rawValue,
                "autoCropApplied": "\(didAutoCrop)"
              ]
            )

            // Transparency cannot be stored in JPEG. For this mode we force alpha-capable output.
            let output = self.resolvedCutoutOutputFormat()
            if output.didOverrideFromJPEG {
              DiagnosticLogger.shared.log(
                .warning,
                .capture,
                "Object cutout format overridden to PNG because JPEG does not support transparency"
              )
            }

            let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
              for: .screenshot,
              exportDirectory: resolvedSaveDirectory
            )

            let result = await self.captureManager.saveProcessedImage(
              outputImage,
              to: actualSaveDirectory,
              format: output.format
            )
            self.lastCaptureResult = result
            self.isCapturing = false

            switch result {
            case .success:
              SoundManager.playScreenshotCapture()
            case .failure(let error):
              AppToastManager.shared.show(
                message: error.localizedDescription,
                style: .error,
                position: .bottomCenter
              )
              QuickAccessSound.failed.play()
            }
          } catch {
            self.isCapturing = false
            self.lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
            self.showCutoutFailureToast(for: error)
            DiagnosticLogger.shared.logError(.capture, error, "Object cutout capture failed")
            QuickAccessSound.failed.play()
          }
        }
      }
    }
  }

  private func resolveObjectCutoutOutputImage(
    from result: ForegroundCutoutResult,
    autoCropEnabled: Bool
  ) -> (image: CGImage, didAutoCrop: Bool) {
    guard autoCropEnabled,
          result.autoCropDecision == .suggested,
          let suggestedRect = result.suggestedAutoCropRect?.integral,
          suggestedRect.width > 0,
          suggestedRect.height > 0
    else {
      return (result.fullCanvasImage, false)
    }

    guard let croppedImage = result.fullCanvasImage.cropping(to: suggestedRect) else {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Object cutout auto-crop skipped because crop operation failed",
        context: ["rect": "\(suggestedRect)"]
      )
      return (result.fullCanvasImage, false)
    }
    return (croppedImage, true)
  }

  private func resolvedCutoutOutputFormat() -> (format: ImageFormat, didOverrideFromJPEG: Bool) {
    guard let raw = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat),
          let option = ImageFormatOption(rawValue: raw) else {
      return (.png, false)
    }

    switch option {
    case .png:
      return (.png, false)
    case .webp:
      return (.webp, false)
    case .jpeg:
      return (.png, true)
    }
  }

  private func showCutoutFailureToast(for error: Error) {
    if let cutoutError = error as? ForegroundCutoutError {
      switch cutoutError {
      case .noSubjectDetected:
        AppToastManager.shared.show(
          message: L10n.ForegroundCutout.noSubjectDetectedTryTighterArea,
          style: .warning,
          position: .bottomCenter
        )
      case .unsupportedOS:
        AppToastManager.shared.show(
          message: L10n.ForegroundCutout.unsupportedOS,
          style: .warning,
          position: .bottomCenter
        )
      case .imageConversionFailed:
        AppToastManager.shared.show(
          message: L10n.ForegroundCutout.unableToProcessImageTryAgain,
          style: .error,
          position: .bottomCenter
        )
      case .cutoutFailed(let underlying):
        AppToastManager.shared.show(
          message: L10n.ForegroundCutout.cutoutFailed(underlying.localizedDescription),
          style: .error,
          position: .bottomCenter
        )
      }
      return
    }

    AppToastManager.shared.show(
      message: L10n.ForegroundCutout.genericFailure,
      style: .error,
      position: .bottomCenter
    )
  }
}
