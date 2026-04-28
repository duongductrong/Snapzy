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

  private let windowHideSettleDelay: TimeInterval = 1.0 / 60.0
  private let frozenSnapshotWindowHideSettleDelay: TimeInterval = 0.05

  @MainActor
  private final class HiddenWindowSession {
    private struct Entry {
      weak var window: NSWindow?
      let windowNumber: Int
      let orderIndex: Int
    }

    private var entries: [Entry]
    private let keyWindowNumber: Int?
    private let mainWindowNumber: Int?
    private let shouldReactivateApp: Bool
    private var didRestore = false

    init(
      windows: [NSWindow] = [],
      keyWindow: NSWindow? = nil,
      mainWindow: NSWindow? = nil,
      shouldReactivateApp: Bool = false
    ) {
      entries = windows.enumerated().map { index, window in
        Entry(window: window, windowNumber: window.windowNumber, orderIndex: index)
      }
      keyWindowNumber = keyWindow?.windowNumber
      mainWindowNumber = mainWindow?.windowNumber
      self.shouldReactivateApp = shouldReactivateApp
    }

    var didHideWindows: Bool {
      !entries.isEmpty
    }

    func restore() {
      guard !didRestore else { return }
      didRestore = true

      let liveEntries = entries.compactMap { entry -> (window: NSWindow, windowNumber: Int, orderIndex: Int)? in
        guard let window = entry.window else { return nil }
        return (window, entry.windowNumber, entry.orderIndex)
      }
      guard !liveEntries.isEmpty else { return }

      for entry in liveEntries.sorted(by: { $0.orderIndex < $1.orderIndex }) where !entry.window.isVisible {
        entry.window.orderFront(nil)
      }

      let keyCandidate = liveEntries.first {
        $0.windowNumber == keyWindowNumber && $0.window.canBecomeKey
      } ?? liveEntries.first {
        $0.windowNumber == mainWindowNumber && $0.window.canBecomeKey
      } ?? liveEntries.last(where: { $0.window.canBecomeKey })

      if let keyCandidate {
        keyCandidate.window.makeKeyAndOrderFront(nil)
      }

      if shouldReactivateApp {
        NSApp.activate(ignoringOtherApps: true)
      }

      DiagnosticLogger.shared.log(.debug, .ui, "Hidden Snapzy windows restored", context: [
        "count": "\(liveEntries.count)"
      ])
    }
  }

  private func hideVisibleNormalWindowsIfNeeded(_ shouldHide: Bool) -> HiddenWindowSession {
    guard shouldHide else { return HiddenWindowSession() }

    let visibleNormalWindows = NSApp.windows.filter {
      $0.isVisible &&
      $0.level == .normal &&
      $0.className != "NSStatusBarWindow"
    }
    let session = HiddenWindowSession(
      windows: visibleNormalWindows,
      keyWindow: NSApp.keyWindow,
      mainWindow: NSApp.mainWindow,
      shouldReactivateApp: NSApp.isActive
    )
    guard !visibleNormalWindows.isEmpty else { return session }

    visibleNormalWindows.forEach { $0.orderOut(nil) }
    DiagnosticLogger.shared.log(.debug, .ui, "Snapzy windows hidden for capture", context: [
      "count": "\(visibleNormalWindows.count)"
    ])
    return session
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
    case .captureApplication:
      captureApplication()
    case .captureScrolling:
      captureScrolling()
    case .captureOCR:
      captureOCR()
    case .captureObjectCutout:
      captureObjectCutout()
    case .recordVideo:
      startRecordingFlow()
    case .recordApplication:
      startApplicationRecordingFlow()
    case .openAnnotate:
      AnnotateManager.shared.openEmptyAnnotation()
    case .openVideoEditor:
      VideoEditorManager.shared.openEmptyEditor()
    case .openCloudUploads:
      if CloudUploadHistoryWindowController.shared.toggleWindow() {
        NSApp.activate(ignoringOtherApps: true)
      }
    case .openShortcutList:
      ShortcutOverlayManager.shared.toggle()
    case .openHistory:
      HistoryFloatingManager.shared.toggle()
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
      let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
      let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
      let prefetchedContentTask = captureManager.prefetchShareableContent(
        includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
      )
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
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
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
    startAreaCapture(initialInteractionMode: .manualRegion)
  }

  func captureApplication() {
    startAreaCapture(initialInteractionMode: .applicationWindow)
  }

  private func startAreaCapture(initialInteractionMode: AreaSelectionInteractionMode) {
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
    DiagnosticLogger.shared.log(.info, .capture, "Area capture flow started", context: [
      "format": resolvedFormat.fileExtension,
      "initialMode": initialInteractionMode == .applicationWindow ? "application" : "manual",
    ])
    let targetDisplayID = ScreenUtility.activeDisplayID()
    let showCursor = showsCursorInScreenshots
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let excludeOwnApplication = !includesOwnAppInScreenshots
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    let shouldHideOwnWindows = excludeOwnApplication

    // Hide only normal-level app windows (not overlay panels) to avoid hiding pooled overlay windows
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(shouldHideOwnWindows)

    // Frozen snapshots can run through the CoreGraphics fast path, so give WindowServer
    // a few frames to fully remove hidden app windows before the display image is read.
    let snapshotDelay = hiddenWindowSession.didHideWindows ? frozenSnapshotWindowHideSettleDelay : 0
    DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureArea: self deallocated")
        hiddenWindowSession.restore()
        AreaSelectionController.shared.cancelSelection()
        return
      }

      Task { @MainActor in
        let frozenSession: FrozenAreaCaptureSession
        do {
          self.isCapturing = true
          let snapshotStartedAt = Date()
          let captureMode: String
          if let fastSnapshot = self.captureManager.captureFastDisplaySnapshot(
            displayID: targetDisplayID,
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets
          ) {
            frozenSession = FrozenAreaCaptureSession.fromSnapshot(fastSnapshot)
            captureMode = "coregraphics"
          } else {
            let shareableContentTask = prefetchedContentTask ?? self.captureManager.prefetchShareableContent(
              includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
            )
            frozenSession = try await FrozenAreaCaptureSession.prepare(
              displayIDs: [targetDisplayID],
              showCursor: showCursor,
              excludeDesktopIcons: excludeDesktopIcons,
              excludeDesktopWidgets: excludeDesktopWidgets,
              excludeOwnApplication: excludeOwnApplication,
              prefetchedContentTask: shareableContentTask
            )
            captureMode = "screencapturekit"
          }
          let snapshotDurationMs = Int(Date().timeIntervalSince(snapshotStartedAt) * 1000)
          DiagnosticLogger.shared.log(
            .info,
            .capture,
            "Frozen area snapshot prepared",
            context: [
              "displayID": "\(targetDisplayID)",
              "duration_ms": "\(snapshotDurationMs)",
              "mode": captureMode,
            ]
          )
          self.isCapturing = false
        } catch let error as CaptureError {
          self.isCapturing = false
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(error)
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(.error, .capture, "Frozen area capture setup failed: \(error.localizedDescription)")
          return
        } catch {
          self.isCapturing = false
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(.error, .capture, "Frozen area capture setup failed: \(error.localizedDescription)")
          return
        }
        self.startFrozenAreaSelection(
          with: frozenSession,
          saveDirectory: resolvedSaveDirectory,
          prefetchedContentTask: prefetchedContentTask,
          showCursor: showCursor,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: excludeOwnApplication,
          initialInteractionMode: initialInteractionMode,
          hiddenWindowSession: hiddenWindowSession
        )
      }
    }
  }

  private func startFrozenAreaSelection(
    with frozenSession: FrozenAreaCaptureSession,
    saveDirectory resolvedSaveDirectory: URL,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    hiddenWindowSession: HiddenWindowSession
  ) {
    AreaSelectionController.shared.startSelection(
      mode: .screenshot,
      backdrops: frozenSession.backdrops,
      applicationConfiguration: AreaSelectionApplicationConfiguration(
        prefetchedContentTask: prefetchedContentTask,
        excludeOwnApplication: excludeOwnApplication
      ),
      initialInteractionMode: initialInteractionMode
    ) { [weak self] selection in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureArea completion: self deallocated")
        frozenSession.invalidate()
        hiddenWindowSession.restore()
        return
      }
      defer {
        self.isAreaSelectionActive = false
      }

      guard let selection else {
        frozenSession.invalidate()
        hiddenWindowSession.restore()
        DiagnosticLogger.shared.log(.info, .capture, "Area capture cancelled by user")
        self.lastCaptureResult = .failure(.cancelled)
        return
      }

      Task { @MainActor in
        defer {
          hiddenWindowSession.restore()
        }
        self.isCapturing = true
        await Task.yield()

        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .screenshot,
          exportDirectory: resolvedSaveDirectory
        )

        switch selection.target {
        case .rect:
          DiagnosticLogger.shared.log(
            .info,
            .capture,
            "Area selected from frozen snapshot",
            context: ["rect": "\(Int(selection.rect.width))x\(Int(selection.rect.height))"]
          )

          do {
            let cropResult = try frozenSession.cropImage(for: selection)
            let result = await self.captureManager.saveProcessedImage(
              cropResult.image,
              to: actualSaveDirectory,
              format: self.resolvedFormat,
              scaleFactor: cropResult.scaleFactor
            )

            frozenSession.invalidate()
            self.isCapturing = false
            self.lastCaptureResult = result

            if case .success = result {
              SoundManager.playScreenshotCapture()
            }
          } catch let error as CaptureError {
            frozenSession.invalidate()
            self.isCapturing = false
            self.lastCaptureResult = .failure(error)
            DiagnosticLogger.shared.log(.error, .capture, "Frozen area crop failed: \(error.localizedDescription)")
          } catch {
            frozenSession.invalidate()
            self.isCapturing = false
            self.lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
            DiagnosticLogger.shared.log(.error, .capture, "Frozen area crop failed: \(error.localizedDescription)")
          }
        case .window(let target):
          DiagnosticLogger.shared.log(
            .info,
            .capture,
            "Application mode target selected",
            context: [
              "windowID": "\(target.windowID)",
              "rect": "\(Int(target.frame.width))x\(Int(target.frame.height))"
            ]
          )
          let result = await self.captureManager.captureWindow(
            target: target,
            saveDirectory: actualSaveDirectory,
            format: self.resolvedFormat,
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication,
            prefetchedContentTask: prefetchedContentTask
          )

          frozenSession.invalidate()
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
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )

    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(true)

    DispatchQueue.main.asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureScrolling: self deallocated")
        hiddenWindowSession.restore()
        AreaSelectionController.shared.cancelSelection()
        return
      }

      AreaSelectionController.shared.startSelection(mode: .scrollingCapture) { [weak self] rect, _ in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureScrolling completion: self deallocated")
          hiddenWindowSession.restore()
          return
        }

        defer {
          self.isAreaSelectionActive = false
        }

        guard let selectedRect = rect else {
          DiagnosticLogger.shared.log(.info, .capture, "Scrolling capture cancelled by user")
          self.lastCaptureResult = .failure(.cancelled)
          hiddenWindowSession.restore()
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
          prefetchedContentTask: prefetchedContentTask,
          onSessionEnded: {
            hiddenWindowSession.restore()
          }
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
    startRecordingFlow(initialInteractionMode: .manualRegion)
  }

  func startApplicationRecordingFlow() {
    startRecordingFlow(initialInteractionMode: .applicationWindow)
  }

  private func startRecordingFlow(initialInteractionMode: AreaSelectionInteractionMode) {
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
    DiagnosticLogger.shared.log(.info, .recording, "Recording flow started", context: [
      "initialMode": initialInteractionMode == .applicationWindow ? "application" : "manual",
    ])

    // Hide only normal-level app windows (not overlay panels)
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(shouldHideOwnWindowsForRecordingToolbarFlow)

    // Small delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .recording, "startRecordingFlow: self deallocated")
        hiddenWindowSession.restore()
        AreaSelectionController.shared.cancelSelection()
        return
      }

      // Check for saved recording area - restore if enabled and available
      let rememberLastArea = UserDefaults.standard.object(forKey: PreferencesKeys.recordingRememberLastArea) as? Bool ?? true
      if initialInteractionMode == .manualRegion,
         rememberLastArea,
         let savedRect = RecordingCoordinator.shared.loadLastAreaRect() {
        self.isAreaSelectionActive = false
        DiagnosticLogger.shared.log(.info, .recording, "Using saved recording area", context: ["rect": "\(Int(savedRect.width))x\(Int(savedRect.height))"])
        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(
            for: savedRect,
            onSessionEnded: {
              hiddenWindowSession.restore()
            }
          )
        }
        return
      }

      // No saved rect or disabled - start area selection
      let applicationConfiguration = AreaSelectionApplicationConfiguration(
        prefetchedContentTask: self.captureManager.prefetchShareableContent(),
        excludeOwnApplication: !self.includesOwnAppInRecordings
      )
      AreaSelectionController.shared.startSelection(
        mode: .recording,
        backdrops: [:],
        applicationConfiguration: applicationConfiguration,
        initialInteractionMode: initialInteractionMode
      ) { [weak self] selection in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .recording, "startRecordingFlow completion: self deallocated")
          hiddenWindowSession.restore()
          return
        }

        self.isAreaSelectionActive = false

        guard let selection else {
          hiddenWindowSession.restore()
          return
        }

        Task { @MainActor in
          switch selection.target {
          case .rect:
            RecordingCoordinator.shared.showToolbar(
              for: selection.rect,
              onSessionEnded: {
                hiddenWindowSession.restore()
              }
            )
          case .window(let target):
            RecordingCoordinator.shared.showToolbar(
              for: selection.rect,
              captureMode: .application,
              windowTarget: target,
              onSessionEnded: {
                hiddenWindowSession.restore()
              }
            )
          }
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
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )

    // Hide only normal-level app windows (not overlay panels)
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    // Minimal delay to ensure window is hidden when we actually hid one.
    DispatchQueue.main.asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .ocr, "captureOCR: self deallocated")
        hiddenWindowSession.restore()
        AreaSelectionController.shared.cancelSelection()
        return
      }



      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .ocr, "captureOCR completion: self deallocated")
          hiddenWindowSession.restore()
          return
        }

        guard let selectedRect = rect else {
          self.isAreaSelectionActive = false
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(.info, .ocr, "OCR capture cancelled")
          return
        }

        DiagnosticLogger.shared.log(.info, .ocr, "OCR area selected", context: ["rect": "\(Int(selectedRect.width))x\(Int(selectedRect.height))"])
        Task { @MainActor in
          defer {
            self.isAreaSelectionActive = false
            hiddenWindowSession.restore()
          }
          await Task.yield()

          do {
            let operationStartTime = CFAbsoluteTimeGetCurrent()

            // Show menubar spinner for processing feedback
            AppStatusBarController.shared.setProcessing(true)

            // Capture the screen region
            let captureStartTime = CFAbsoluteTimeGetCurrent()
            guard let image = try await self.captureManager.captureAreaAsImage(
              rect: selectedRect,
              excludeDesktopIcons: excludeDesktopIcons,
              excludeDesktopWidgets: excludeDesktopWidgets,
              excludeOwnApplication: !self.includesOwnAppInScreenshots,
              prefetchedContentTask: prefetchedContentTask
            ) else {
              AppStatusBarController.shared.setProcessing(false)
              AppToastManager.shared.show(
                message: L10n.ScreenCapture.unableToCaptureSelectedArea,
                style: .error,
                position: .bottomCenter
              )
              QuickAccessSound.failed.play()
              return
            }
            let captureDurationMs = Self.elapsedMilliseconds(since: captureStartTime)

            let processingStartTime = CFAbsoluteTimeGetCurrent()
            async let qrResultTask = self.detectQRCodes(in: image)
            async let recognizedTextTask = self.recognizeOCRText(in: image)
            let (qrResult, recognizedText) = await (qrResultTask, recognizedTextTask)
            let processingDurationMs = Self.elapsedMilliseconds(since: processingStartTime)
            let totalDurationMs = Self.elapsedMilliseconds(since: operationStartTime)

            let clipboardText = OCRQRPayloadComposer.compose(
              recognizedText: recognizedText,
              qrDetections: qrResult.detections,
              qrSectionTitle: L10n.OCR.qrCodesLabel
            )
            let performanceContext = [
              "captureMs": captureDurationMs,
              "processingMs": processingDurationMs,
              "totalMs": totalDurationMs
            ]

            AppStatusBarController.shared.setProcessing(false)

            guard let clipboardText else {
              if qrResult.unsupportedPayloadCount > 0 {
                var context = performanceContext
                context["unsupportedQRCount"] = "\(qrResult.unsupportedPayloadCount)"
                DiagnosticLogger.shared.log(.warning, .ocr, "OCR QR capture found unsupported QR payloads", context: context)
                AppToastManager.shared.show(
                  message: L10n.OCR.qrTextOnlyUnsupported,
                  style: .warning,
                  position: .bottomCenter
                )
              } else {
                DiagnosticLogger.shared.log(.warning, .ocr, "OCR capture failed: no text or QR payload found", context: performanceContext)
                AppToastManager.shared.show(
                  message: L10n.OCR.noTextFound,
                  style: .warning,
                  position: .bottomCenter
                )
              }
              QuickAccessSound.failed.play()
              return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(clipboardText, forType: .string)

            var successContext = performanceContext
            successContext["chars"] = "\(clipboardText.count)"
            successContext["qrCount"] = "\(qrResult.detections.count)"
            successContext["unsupportedQRCount"] = "\(qrResult.unsupportedPayloadCount)"
            DiagnosticLogger.shared.log(.info, .ocr, "OCR text copied to clipboard", context: successContext)
            let showOCRNotification = UserDefaults.standard.object(forKey: PreferencesKeys.ocrSuccessNotificationEnabled) as? Bool ?? false
            if showOCRNotification {
              AppToastManager.shared.show(
                message: L10n.Common.copiedToClipboard,
                style: .success,
                position: .bottomCenter
              )
              QuickAccessSound.complete.play()
            }

          } catch {
            // Error feedback
            AppStatusBarController.shared.setProcessing(false)
            DiagnosticLogger.shared.logError(.ocr, error, "OCR capture failed")
            AppToastManager.shared.show(
              message: error.localizedDescription,
              style: .error,
              position: .bottomCenter
            )
            QuickAccessSound.failed.play()
          }
        }
      }
    }
  }

  private func detectQRCodes(in image: CGImage) async -> QRCodeDetectionResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try await QRCodeService.shared.detect(in: image)
      }.value

      if result.hasCopyablePayloads || result.unsupportedPayloadCount > 0 {
        DiagnosticLogger.shared.log(
          .info,
          .ocr,
          "OCR QR detection completed",
          context: [
            "qrCount": "\(result.detections.count)",
            "unsupportedQRCount": "\(result.unsupportedPayloadCount)",
            "payloadTypes": result.detections
              .map(\.classification.diagnosticName)
              .joined(separator: ","),
            "durationMs": Self.elapsedMilliseconds(since: startTime)
          ]
        )
      } else {
        DiagnosticLogger.shared.log(
          .debug,
          .ocr,
          "OCR QR detection completed without QR payloads",
          context: ["durationMs": Self.elapsedMilliseconds(since: startTime)]
        )
      }
      return result
    } catch {
      DiagnosticLogger.shared.logError(
        .ocr,
        error,
        "OCR QR detection failed",
        context: ["durationMs": Self.elapsedMilliseconds(since: startTime)]
      )
      return .empty
    }
  }

  private func recognizeOCRText(in image: CGImage) async -> String? {
    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let text = try await OCRService.shared.recognizeText(
        from: image,
        preferredLanguageIdentifier: AppLanguageManager.shared.activeOCRLanguageIdentifier,
        contentType: .interfaceText
      )
      DiagnosticLogger.shared.log(
        .debug,
        .ocr,
        "OCR text recognition timing",
        context: ["durationMs": Self.elapsedMilliseconds(since: startTime)]
      )
      return text
    } catch OCRError.noTextFound {
      DiagnosticLogger.shared.log(
        .debug,
        .ocr,
        "OCR text recognition found no text",
        context: ["durationMs": Self.elapsedMilliseconds(since: startTime)]
      )
      return nil
    } catch {
      DiagnosticLogger.shared.logError(
        .ocr,
        error,
        "OCR text recognition failed",
        context: ["durationMs": Self.elapsedMilliseconds(since: startTime)]
      )
      return nil
    }
  }

  private static func elapsedMilliseconds(since startTime: CFAbsoluteTime) -> String {
    String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
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
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )

    // Hide only normal-level app windows (not overlay panels)
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    DispatchQueue.main.asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
      guard let self = self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureObjectCutout: self deallocated")
        hiddenWindowSession.restore()
        AreaSelectionController.shared.cancelSelection()
        return
      }

      AreaSelectionController.shared.startSelection { [weak self] rect in
        guard let self = self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureObjectCutout completion: self deallocated")
          hiddenWindowSession.restore()
          return
        }

        guard let selectedRect = rect else {
          self.isAreaSelectionActive = false
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(.info, .capture, "Object cutout capture cancelled")
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        Task { @MainActor in
          defer {
            self.isAreaSelectionActive = false
            hiddenWindowSession.restore()
          }

          self.isCapturing = true
          await Task.yield()

          do {
            guard let capturedImage = try await self.captureManager.captureAreaAsImage(
              rect: selectedRect,
              excludeDesktopIcons: excludeDesktopIcons,
              excludeDesktopWidgets: excludeDesktopWidgets,
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
            let cutoutScaleFactor: CGFloat
            if selectedRect.width > 0 {
              cutoutScaleFactor = CGFloat(capturedImage.width) / selectedRect.width
            } else if selectedRect.height > 0 {
              cutoutScaleFactor = CGFloat(capturedImage.height) / selectedRect.height
            } else {
              cutoutScaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
            }

            let result = await self.captureManager.saveProcessedImage(
              outputImage,
              to: actualSaveDirectory,
              format: output.format,
              scaleFactor: cutoutScaleFactor
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
