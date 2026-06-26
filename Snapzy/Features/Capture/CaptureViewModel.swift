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
  private var activeAreaSelectionSessionID: UUID?
  private var lazyAreaSnapshotTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
  private var lazyAreaSnapshotFailedDisplayIDs = Set<CGDirectDisplayID>()
  private var cancellables = Set<AnyCancellable>()

  // Shortcut bindings for UI
  @Published var fullscreenShortcut: ShortcutConfig
  @Published var areaShortcut: ShortcutConfig
  @Published var scrollingCaptureShortcut: ShortcutConfig
  @Published var recordingShortcut: ShortcutConfig
  @Published var pauseResumeRecordingShortcut: ShortcutConfig?
  @Published var togglePenRecordingShortcut: ShortcutConfig?
  @Published var restartRecordingShortcut: ShortcutConfig?
  @Published var deleteRecordingShortcut: ShortcutConfig?
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
    pauseResumeRecordingShortcut = KeyboardShortcutManager.shared.shortcut(for: .pauseResumeRecording)
    togglePenRecordingShortcut = KeyboardShortcutManager.shared.shortcut(for: .togglePenRecording)
    restartRecordingShortcut = KeyboardShortcutManager.shared.shortcut(for: .restartRecording)
    deleteRecordingShortcut = KeyboardShortcutManager.shared.shortcut(for: .deleteRecording)
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

  /// When enabled (default), area capture selects against a frozen snapshot of the screen. When
  /// disabled, the screen stays live during selection (e.g. video keeps playing) and the region is
  /// captured at the moment selection completes.
  private var freezesAreaCapture: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.screenshotFreezeArea) as? Bool ?? true
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

  private var preferredScreenshotOutputScaleFactor: CGFloat {
    max(NSScreen.screens.map(\.backingScaleFactor).max() ?? 2.0, 2.0)
  }

  private var includesOwnAppInRecordings: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.recordingIncludeOwnApp)
  }

  private var shouldHideOwnWindowsForRecordingToolbarFlow: Bool {
    !includesOwnAppInScreenshots && !includesOwnAppInRecordings
  }

  private let windowHideSettleDelay: TimeInterval = 1.0 / 60.0
  private let frozenSnapshotWindowHideSettleDelay: TimeInterval = 1.0 / 60.0

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

  func updatePauseResumeRecordingShortcut(_ config: ShortcutConfig?) {
    shortcutManager.setPauseResumeRecordingShortcut(config)
    pauseResumeRecordingShortcut = config
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
    case .captureAreaAnnotate:
      captureAreaAnnotate()
    case .captureApplication:
      captureApplication()
    case .captureActiveWindow:
      captureActiveWindow()
    case .captureScrolling:
      captureScrolling()
    case .captureOCR:
      captureOCR()
    case .captureSmartElement:
      SmartElementCaptureController.shared.startCapture()
    case .captureObjectCutout:
      captureObjectCutout()
    case .recordVideo:
      toggleRecordingFromShortcut(initialInteractionMode: .manualRegion)
    case .recordApplication:
      toggleRecordingFromShortcut(initialInteractionMode: .applicationWindow)
    case .pauseResumeRecording:
      togglePauseFromShortcut()
    case .togglePenRecording:
      togglePenRecordingFromShortcut()
    case .restartRecording:
      restartRecordingFromShortcut()
    case .deleteRecording:
      deleteRecordingFromShortcut()
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
      let targetDisplayID = ScreenUtility.activeDisplayID()

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
      DiagnosticLogger.shared.log(.info, .capture, "Fullscreen capture flow started", context: [
        "displayID": "\(targetDisplayID)",
        "format": resolvedFormat.fileExtension,
      ])
      let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
      let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
      let excludeOwnApplication = !includesOwnAppInScreenshots
      let canUseFastMultiDisplayPath = !showsCursorInScreenshots
        && !excludeDesktopIcons
        && !excludeDesktopWidgets
      let prefetchedContentTask = canUseFastMultiDisplayPath
        ? nil
        : captureManager.prefetchShareableContent(
          includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
        )
      await Task.yield()
      let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(excludeOwnApplication)

      // Resolve save directory based on auto-save toggle
      let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
        for: .screenshot,
        exportDirectory: resolvedSaveDirectory
      )

      if hiddenWindowSession.didHideWindows {
        try? await Task.sleep(nanoseconds: UInt64(windowHideSettleDelay * 1_000_000_000))
      }

      let result = await captureManager.captureAllDisplays(
        saveDirectory: actualSaveDirectory,
        format: resolvedFormat,
        showCursor: showsCursorInScreenshots,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        allowFastPathWhenOwnApplicationHidden: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask,
        targetDisplayIDs: [targetDisplayID]
      )

      isCapturing = false
      lastCaptureResult = result.primaryCaptureResult
      hiddenWindowSession.restore()

      if !result.savedURLs.isEmpty {
        SoundManager.playScreenshotCapture()
        await postCaptureHandler.handleScreenshotCaptures(urls: result.savedURLs)
      }
    }
  }

  func captureActiveWindow() {
    Task {
      guard
        let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
          promptMessage: L10n.Recording.chooseSaveLocationMessage)
      else {
        lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
        DiagnosticLogger.shared.log(.error, .capture, "Active window capture aborted: no save location")
        return
      }
      saveDirectory = resolvedSaveDirectory

      isCapturing = true
      DiagnosticLogger.shared.log(.info, .capture, "Active window capture flow started", context: [
        "format": resolvedFormat.fileExtension,
      ])

      let prefetchedContentTask = captureManager.prefetchShareableContent(includeDesktopWindows: false)
      guard let target = await ActiveWindowResolver.resolveActiveWindowTarget(
        prefetchedContentTask: prefetchedContentTask
      ) else {
        isCapturing = false
        lastCaptureResult = .failure(.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage))
        DiagnosticLogger.shared.log(.error, .capture, "Active window capture failed: no resolvable window")
        return
      }

      let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
        for: .screenshot,
        exportDirectory: resolvedSaveDirectory
      )

      let result = await captureManager.captureWindow(
        target: target,
        saveDirectory: actualSaveDirectory,
        format: resolvedFormat,
        showCursor: showsCursorInScreenshots,
        excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
        excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
        excludeOwnApplication: false,
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

  func captureAreaAnnotate() {
    startInlineAreaAnnotateCapture()
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

    // Live mode: skip the frozen snapshot so on-screen content keeps playing during selection,
    // then capture the chosen region at completion time.
    if !freezesAreaCapture {
      startLiveAreaSelection(
        saveDirectory: resolvedSaveDirectory,
        prefetchedContentTask: prefetchedContentTask,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        initialInteractionMode: initialInteractionMode,
        hiddenWindowSession: hiddenWindowSession
      )
      return
    }

    // Give WindowServer enough time to fully remove hidden app windows before
    // the frozen backdrop is prepared.
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
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication
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

  private func startInlineAreaAnnotateCapture() {
    if isAreaSelectionActive {
      DiagnosticLogger.shared.log(.debug, .capture, "captureAreaAnnotate blocked: already active")
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
    DiagnosticLogger.shared.log(.info, .capture, "Inline area annotate flow started", context: [
      "format": resolvedFormat.fileExtension
    ])

    let targetDisplayID = ScreenUtility.activeDisplayID()
    let showCursor = showsCursorInScreenshots
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let excludeOwnApplication = !includesOwnAppInScreenshots
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(excludeOwnApplication)
    let snapshotDelay = hiddenWindowSession.didHideWindows ? frozenSnapshotWindowHideSettleDelay : 0

    DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
      guard let self = self else {
        hiddenWindowSession.restore()
        return
      }

      Task { @MainActor in
        let frozenSession: FrozenAreaCaptureSession
        do {
          self.isCapturing = true
          let snapshotStartedAt = Date()
          let preparedSession = try await self.prepareInlineAreaAnnotateFrozenSession(
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication,
            prefetchedContentTask: prefetchedContentTask
          )
          frozenSession = preparedSession.session
          let snapshotDurationMs = Int(Date().timeIntervalSince(snapshotStartedAt) * 1000)
          DiagnosticLogger.shared.log(
            .info,
            .capture,
            "Inline area annotate snapshots prepared",
            context: [
              "displayCount": "\(frozenSession.displayIDs.count)",
              "duration_ms": "\(snapshotDurationMs)",
              "mode": preparedSession.mode,
            ]
          )
          self.isCapturing = false
        } catch let error as CaptureError {
          self.isCapturing = false
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(error)
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(.error, .capture, "Inline area annotate setup failed: \(error.localizedDescription)")
          return
        } catch {
          self.isCapturing = false
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(.error, .capture, "Inline area annotate setup failed: \(error.localizedDescription)")
          return
        }

        let snapshotDisplayIDs = frozenSession.displayIDs
        let screens = NSScreen.screens.filter { screen in
          guard let displayID = screen.displayID else { return false }
          return snapshotDisplayIDs.contains(displayID)
        }
        let primaryDisplayID = snapshotDisplayIDs.contains(targetDisplayID)
          ? targetDisplayID
          : screens.compactMap(\.displayID).first ?? targetDisplayID
        guard !screens.isEmpty else {
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(.noDisplayFound)
          hiddenWindowSession.restore()
          frozenSession.invalidate()
          return
        }

        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .screenshot,
          exportDirectory: resolvedSaveDirectory
        )
        InlineAreaAnnotateCoordinator.shared.start(
          screens: screens,
          primaryDisplayID: primaryDisplayID,
          backdrops: frozenSession.backdrops,
          frozenSession: frozenSession,
          saveDirectory: actualSaveDirectory,
          outputFormat: self.resolvedFormat
        ) { [weak self] result in
          guard let self else {
            hiddenWindowSession.restore()
            return
          }
          self.isAreaSelectionActive = false
          self.lastCaptureResult = result
          hiddenWindowSession.restore()
          if case .failure(let error) = result {
            DiagnosticLogger.shared.log(.info, .capture, "Inline area annotate ended", context: [
              "result": error.localizedDescription
            ])
          }
        }
      }
    }
  }

  private func prepareInlineAreaAnnotateFrozenSession(
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async throws -> (session: FrozenAreaCaptureSession, mode: String) {
    if !showCursor, !excludeDesktopIcons, !excludeDesktopWidgets, !excludeOwnApplication {
      let snapshots = NSScreen.screens.compactMap { screen -> FrozenDisplaySnapshot? in
        guard let displayID = screen.displayID else { return nil }
        return captureManager.captureFastDisplaySnapshot(
          displayID: displayID,
          showCursor: false,
          excludeDesktopIcons: false,
          excludeDesktopWidgets: false,
          excludeOwnApplication: false
        )
      }
      if !snapshots.isEmpty, snapshots.count == NSScreen.screens.count {
        return (FrozenAreaCaptureSession.fromSnapshots(snapshots), "coregraphics-all")
      }
    }

    let shareableContentTask = prefetchedContentTask ?? captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    let session = try await FrozenAreaCaptureSession.prepare(
      displayIDs: nil,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: shareableContentTask
    )
    return (session, "screencapturekit-all")
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
    cancelLazyAreaSnapshotTasks()
    let sessionID = UUID()
    activeAreaSelectionSessionID = sessionID

    AreaSelectionController.shared.startSelection(
      mode: .screenshot,
      backdrops: frozenSession.backdrops,
      applicationConfiguration: AreaSelectionApplicationConfiguration(
        prefetchedContentTask: prefetchedContentTask,
        excludeOwnApplication: excludeOwnApplication
      ),
      initialInteractionMode: initialInteractionMode,
      onDisplayActivationRequested: { [weak self] displayID in
        self?.prepareLazyFrozenDisplay(
          displayID,
          sessionID: sessionID,
          frozenSession: frozenSession,
          prefetchedContentTask: prefetchedContentTask,
          showCursor: showCursor,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: excludeOwnApplication
        )
      }
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
        self.cancelLazyAreaSnapshotTasks()
        frozenSession.invalidate()
        hiddenWindowSession.restore()
        DiagnosticLogger.shared.log(.info, .capture, "Area capture cancelled by user")
        self.lastCaptureResult = .failure(.cancelled)
        return
      }

      self.cancelLazyAreaSnapshotTasks(clearFailures: false)

      Task { @MainActor in
        defer {
          self.lazyAreaSnapshotFailedDisplayIDs.removeAll()
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

          if selection.spansMultipleDisplays || frozenSession.containsSnapshot(for: selection.displayID) {
            do {
              if selection.spansMultipleDisplays {
                try await self.ensureFrozenSnapshots(
                  for: selection.displayIDs,
                  frozenSession: frozenSession,
                  prefetchedContentTask: prefetchedContentTask,
                  showCursor: showCursor,
                  excludeDesktopIcons: excludeDesktopIcons,
                  excludeDesktopWidgets: excludeDesktopWidgets,
                  excludeOwnApplication: excludeOwnApplication
                )
              }
              let cropResult: FrozenAreaCropResult
              let outputScaleFactor = self.preferredScreenshotOutputScaleFactor
              if selection.spansMultipleDisplays {
                cropResult = try frozenSession.cropCompositeImage(
                  for: selection,
                  minimumOutputScaleFactor: outputScaleFactor
                )
              } else {
                cropResult = try frozenSession.cropImage(
                  for: selection,
                  minimumOutputScaleFactor: outputScaleFactor
                )
              }
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
          } else if self.lazyAreaSnapshotFailedDisplayIDs.contains(selection.displayID) {
            DiagnosticLogger.shared.log(
              .info,
              .capture,
              "Using live area capture fallback after lazy snapshot failure",
              context: ["displayID": "\(selection.displayID)"]
            )
            let result = await self.captureManager.captureArea(
              rect: selection.rect,
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
          } else {
            frozenSession.invalidate()
            self.isCapturing = false
            self.lastCaptureResult = .failure(.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds))
            DiagnosticLogger.shared.log(
              .error,
              .capture,
              "Area selection completed without a frozen snapshot",
              context: ["displayID": "\(selection.displayID)"]
            )
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

  /// Area selection without a frozen backdrop: the overlay sits over the live screen (excluded from
  /// capture via its `.none` sharing type), and the region is captured when the user commits.
  private func startLiveAreaSelection(
    saveDirectory resolvedSaveDirectory: URL,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    initialInteractionMode: AreaSelectionInteractionMode,
    hiddenWindowSession: HiddenWindowSession
  ) {
    activeAreaSelectionSessionID = UUID()

    AreaSelectionController.shared.startSelection(
      mode: .screenshot,
      backdrops: [:],
      applicationConfiguration: AreaSelectionApplicationConfiguration(
        prefetchedContentTask: prefetchedContentTask,
        excludeOwnApplication: excludeOwnApplication
      ),
      initialInteractionMode: initialInteractionMode
    ) { [weak self] selection in
      guard let self = self else {
        hiddenWindowSession.restore()
        return
      }
      defer { self.isAreaSelectionActive = false }

      guard let selection else {
        hiddenWindowSession.restore()
        DiagnosticLogger.shared.log(.info, .capture, "Live area capture cancelled by user")
        self.lastCaptureResult = .failure(.cancelled)
        return
      }

      Task { @MainActor in
        defer { hiddenWindowSession.restore() }
        self.isCapturing = true
        await Task.yield()

        let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
          for: .screenshot,
          exportDirectory: resolvedSaveDirectory
        )

        let result: CaptureResult
        switch selection.target {
        case .rect:
          DiagnosticLogger.shared.log(
            .info,
            .capture,
            "Area captured live",
            context: ["rect": "\(Int(selection.rect.width))x\(Int(selection.rect.height))"]
          )
          result = await self.captureManager.captureArea(
            rect: selection.rect,
            saveDirectory: actualSaveDirectory,
            format: self.resolvedFormat,
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication,
            prefetchedContentTask: prefetchedContentTask
          )
        case .window(let target):
          result = await self.captureManager.captureWindow(
            target: target,
            saveDirectory: actualSaveDirectory,
            format: self.resolvedFormat,
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication,
            prefetchedContentTask: prefetchedContentTask
          )
        }

        self.isCapturing = false
        self.lastCaptureResult = result
        if case .success = result {
          SoundManager.playScreenshotCapture()
        }
      }
    }
  }

  private func ensureFrozenSnapshots(
    for displayIDs: Set<CGDirectDisplayID>,
    frozenSession: FrozenAreaCaptureSession,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool
  ) async throws {
    var missingDisplayIDs = frozenSession.missingSnapshotDisplayIDs(for: displayIDs)
    guard !missingDisplayIDs.isEmpty else { return }

    let startedAt = Date()
    if !showCursor, !excludeDesktopIcons, !excludeDesktopWidgets {
      for displayID in missingDisplayIDs {
        let fastSnapshot = AreaSelectionController.shared.withDisplayOverlayHidden(for: displayID) {
          captureManager.captureFastDisplaySnapshot(
            displayID: displayID,
            showCursor: false,
            excludeDesktopIcons: false,
            excludeDesktopWidgets: false,
            excludeOwnApplication: false
          )
        }
        if let fastSnapshot {
          frozenSession.addSnapshot(fastSnapshot)
        }
      }
      missingDisplayIDs = frozenSession.missingSnapshotDisplayIDs(for: displayIDs)
    }

    if !missingDisplayIDs.isEmpty {
      let snapshots = try await captureManager.captureDisplaySnapshots(
        displayIDs: missingDisplayIDs,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask
      )
      for snapshot in snapshots.values {
        frozenSession.addSnapshot(snapshot)
      }
    }

    let unresolvedDisplayIDs = frozenSession.missingSnapshotDisplayIDs(for: displayIDs)
    guard unresolvedDisplayIDs.isEmpty else {
      throw CaptureError.noDisplayFound
    }

    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
    DiagnosticLogger.shared.log(
      durationMs <= 50 ? .info : .warning,
      .capture,
      "Cross-display frozen snapshots ensured",
      context: [
        "displayCount": "\(displayIDs.count)",
        "duration_ms": "\(durationMs)",
        "target_ms": "50",
      ]
    )
  }

  private func prepareLazyFrozenDisplay(
    _ displayID: CGDirectDisplayID,
    sessionID: UUID,
    frozenSession: FrozenAreaCaptureSession,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool
  ) {
    guard activeAreaSelectionSessionID == sessionID else { return }
    guard !frozenSession.containsSnapshot(for: displayID) else {
      if let backdrop = frozenSession.backdrop(for: displayID) {
        AreaSelectionController.shared.applyBackdrop(backdrop, for: displayID)
      }
      return
    }
    guard lazyAreaSnapshotTasks[displayID] == nil else { return }
    guard !lazyAreaSnapshotFailedDisplayIDs.contains(displayID) else { return }

    let startedAt = Date()
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      guard self.activeAreaSelectionSessionID == sessionID else { return }

      // Try fast CG path first (only when no cursor/desktop exclusion needed)
      if !showCursor, !excludeDesktopIcons, !excludeDesktopWidgets {
        let fastSnapshot = AreaSelectionController.shared.withDisplayOverlayHidden(for: displayID) {
          self.captureManager.captureFastDisplaySnapshot(
            displayID: displayID,
            showCursor: false,
            excludeDesktopIcons: false,
            excludeDesktopWidgets: false,
            excludeOwnApplication: false
          )
        }
        if let fastSnapshot {
          self.applyLazyFrozenSnapshot(
            fastSnapshot,
            mode: excludeOwnApplication ? "coregraphics-hidden-overlay" : "coregraphics",
            displayID: displayID,
            startedAt: startedAt,
            sessionID: sessionID,
            frozenSession: frozenSession
          )
          self.lazyAreaSnapshotTasks[displayID] = nil
          return
        }
      }

      // SCK async path
      do {
        let snapshots = try await self.captureManager.captureDisplaySnapshots(
          displayIDs: [displayID],
          showCursor: showCursor,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: excludeOwnApplication,
          prefetchedContentTask: prefetchedContentTask
        )
        guard let snapshot = snapshots[displayID] else {
          throw CaptureError.noDisplayFound
        }
        self.applyLazyFrozenSnapshot(
          snapshot,
          mode: "screencapturekit",
          displayID: displayID,
          startedAt: startedAt,
          sessionID: sessionID,
          frozenSession: frozenSession
        )
      } catch {
        guard self.activeAreaSelectionSessionID == sessionID else { return }
        self.lazyAreaSnapshotFailedDisplayIDs.insert(displayID)
        AreaSelectionController.shared.enableLiveFallbackSelection(for: displayID)
        DiagnosticLogger.shared.logError(
          .capture,
          error,
          "Lazy frozen display snapshot failed; enabled live fallback",
          context: ["displayID": "\(displayID)"]
        )
      }
      self.lazyAreaSnapshotTasks[displayID] = nil
    }
    lazyAreaSnapshotTasks[displayID] = task
  }

  private func applyLazyFrozenSnapshot(
    _ snapshot: FrozenDisplaySnapshot,
    mode: String,
    displayID: CGDirectDisplayID,
    startedAt: Date,
    sessionID: UUID,
    frozenSession: FrozenAreaCaptureSession
  ) {
    guard activeAreaSelectionSessionID == sessionID else { return }
    frozenSession.addSnapshot(snapshot)
    guard let backdrop = frozenSession.backdrop(for: displayID) else { return }
    AreaSelectionController.shared.applyBackdrop(backdrop, for: displayID)

    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
    DiagnosticLogger.shared.log(
      durationMs <= 50 ? .info : .warning,
      .capture,
      "Lazy frozen display snapshot prepared",
      context: [
        "displayID": "\(displayID)",
        "duration_ms": "\(durationMs)",
        "mode": mode,
        "target_ms": "50",
      ]
    )
  }

  private func cancelLazyAreaSnapshotTasks(clearFailures: Bool = true) {
    for task in lazyAreaSnapshotTasks.values {
      task.cancel()
    }
    lazyAreaSnapshotTasks.removeAll()
    activeAreaSelectionSessionID = nil
    if clearFailures {
      lazyAreaSnapshotFailedDisplayIDs.removeAll()
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

  /// Pause/resume entry from global shortcut. No-op when no active recording.
  /// Reuses existing `ScreenRecordingManager.togglePause()` (already used by the menu bar).
  func togglePauseFromShortcut() {
    let state = ScreenRecordingManager.shared.state
    guard state.isPauseResumeEligible else {
      DiagnosticLogger.shared.log(.debug, .recording, "Pause shortcut ignored: no active recording", context: [
        "state": "\(state)",
      ])
      return
    }
    DiagnosticLogger.shared.log(.info, .recording, "Pause shortcut: toggle", context: [
      "fromState": "\(state)",
    ])
    ScreenRecordingManager.shared.togglePause()
  }

  /// Toggle pen/annotations overlay from global shortcut.
  func togglePenRecordingFromShortcut() {
    guard RecordingCoordinator.shared.isActive else { return }
    RecordingCoordinator.shared.togglePenFromShortcut()
  }

  /// Restart/Re-record from global shortcut.
  func restartRecordingFromShortcut() {
    guard RecordingCoordinator.shared.isActive else { return }
    RecordingCoordinator.shared.restartFromShortcut()
  }

  /// Cancel/Delete current recording from global shortcut.
  func deleteRecordingFromShortcut() {
    guard RecordingCoordinator.shared.isActive else { return }
    RecordingCoordinator.shared.deleteFromShortcut()
  }


  /// Toggle entry from global shortcut: stop/cancel if a recording session is active, otherwise start.
  /// Reuses `RecordingCoordinator.stopFromStatusItem()` which is state-aware
  /// (`.recording`/`.paused` → stop, `.preparing` → cancel, `.idle`/`.stopping` → no-op).
  func toggleRecordingFromShortcut(initialInteractionMode: AreaSelectionInteractionMode) {
    if RecordingCoordinator.shared.isActive {
      DiagnosticLogger.shared.log(.info, .recording, "Recording shortcut: stop", context: [
        "recorderState": "\(ScreenRecordingManager.shared.state)",
        "initialMode": initialInteractionMode == .applicationWindow ? "application" : "manual",
      ])
      RecordingCoordinator.shared.stopFromStatusItem()
    } else {
      DiagnosticLogger.shared.log(.info, .recording, "Recording shortcut: start", context: [
        "initialMode": initialInteractionMode == .applicationWindow ? "application" : "manual",
      ])
      startRecordingFlow(initialInteractionMode: initialInteractionMode)
    }
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

    // Use the same conditional settle delay as screenshot flows:
    // only wait when windows were actually hidden, and use 1-frame settle (~16ms)
    // instead of the previous hardcoded 200ms which caused perceptible launch lag.
    DispatchQueue.main.asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
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



  // MARK: - Smart Element Capture

  func captureSmartElement(rect: CGRect) async {
    guard rect.width > 0, rect.height > 0 else {
      DiagnosticLogger.shared.log(.warning, .capture, "Smart element capture skipped: empty rect")
      return
    }

    guard !isAreaSelectionActive, !isCapturing else {
      DiagnosticLogger.shared.log(.debug, .capture, "captureSmartElement blocked: capture already active")
      return
    }

    guard
      let resolvedSaveDirectory = fileAccessManager.ensureExportDirectoryForOperation(
        promptMessage: L10n.Recording.chooseSaveLocationMessage
      )
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }

    saveDirectory = resolvedSaveDirectory
    isCapturing = true
    AppStatusBarController.shared.setProcessing(true)
    DiagnosticLogger.shared.log(.info, .capture, "Smart element capture committed")

    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(!includesOwnAppInScreenshots)

    if hiddenWindowSession.didHideWindows {
      let settleNanoseconds = UInt64(windowHideSettleDelay * 1_000_000_000)
      try? await Task.sleep(nanoseconds: settleNanoseconds)
    }

    defer {
      isCapturing = false
      hiddenWindowSession.restore()
      AppStatusBarController.shared.setProcessing(false)
    }

    do {
      guard let image = try await captureManager.captureAreaAsImage(
        rect: rect,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: !includesOwnAppInScreenshots,
        prefetchedContentTask: prefetchedContentTask
      ) else {
        lastCaptureResult = .failure(.captureFailed(L10n.ScreenCapture.unableToCaptureSelectedArea))
        AppToastManager.shared.show(
          message: L10n.ScreenCapture.unableToCaptureSelectedArea,
          style: .error,
          position: .bottomCenter
        )
        QuickAccessSound.failed.play()
        return
      }

      let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
        for: .screenshot,
        exportDirectory: resolvedSaveDirectory
      )
      let scaleFactor = Self.captureScaleFactor(for: image, rect: rect)
      let result = await captureManager.saveProcessedImage(
        image,
        to: actualSaveDirectory,
        format: resolvedFormat,
        scaleFactor: scaleFactor
      )
      lastCaptureResult = result

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
      lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
      DiagnosticLogger.shared.logError(.capture, error, "Smart element capture failed")
      AppToastManager.shared.show(
        message: error.localizedDescription,
        style: .error,
        position: .bottomCenter
      )
      QuickAccessSound.failed.play()
    }
  }

  private static func captureScaleFactor(for image: CGImage, rect: CGRect) -> CGFloat {
    if rect.width > 0 {
      return CGFloat(image.width) / rect.width
    }
    if rect.height > 0 {
      return CGFloat(image.height) / rect.height
    }
    return NSScreen.main?.backingScaleFactor ?? 2.0
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
