//
//  CaptureViewModel.swift
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
    case .png: .png
    case .jpeg: .jpeg(quality: 0.9)
    case .webp: .webp
    }
  }

  var displayName: String {
    switch self {
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .webp: "WebP"
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
        guard let self else { return }
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

  /// When enabled, area capture selects against a frozen snapshot of the screen. When
  /// disabled (default), the screen stays live during selection (e.g. video keeps playing) and the region is
  /// captured at the moment selection completes.
  private var freezesAreaCapture: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.screenshotFreezeArea) as? Bool ?? false
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
    // Let crop/composite use each display's native density. Mixed-DPI selections
    // still promote low-density slices to the highest native scale in the selection.
    1.0
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
  final class HiddenWindowSession {
    static var onPostSyntheticMouseEvent: ((NSEvent) -> Void)?

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

      // Force cursor tracking re-evaluation on restored windows.
      // orderFront does not trigger mouseEntered, so if the mouse is
      // already over a restored window, tracking areas won't fire and
      // the cursor may appear stuck or invisible.
      // Post a synthetic mouse-moved event to force macOS to
      // re-evaluate cursor rects immediately.
      DispatchQueue.main.async {
        let mouseLocation = NSEvent.mouseLocation
        if let syntheticEvent = NSEvent.mouseEvent(
          with: .mouseMoved,
          location: mouseLocation,
          modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: 0,
          context: nil,
          eventNumber: 0,
          clickCount: 0,
          pressure: 0
        ) {
          NSApp.postEvent(syntheticEvent, atStart: false)
          Self.onPostSyntheticMouseEvent?(syntheticEvent)
        }
      }

      DiagnosticLogger.shared.log(.debug, .ui, "Hidden Snapzy windows restored", context: [
        "count": "\(liveEntries.count)",
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
      "count": "\(visibleNormalWindows.count)",
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
    case .captureRepeatArea:
      captureRepeatArea()
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
          promptMessage: L10n.Recording.chooseSaveLocationMessage
        )
      else {
        lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
        DiagnosticLogger.shared.log(.error, .capture, "Fullscreen capture aborted: no save location")
        return
      }
      saveDirectory = resolvedSaveDirectory

      let context = CaptureContext.fromFrontmostApp()
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
        targetDisplayIDs: [targetDisplayID],
        context: context
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
          promptMessage: L10n.Recording.chooseSaveLocationMessage
        )
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

      let context = CaptureContext.fromPID(target.ownerPID, windowTitle: target.title)
      let result = await captureManager.captureWindow(
        target: target,
        saveDirectory: actualSaveDirectory,
        format: resolvedFormat,
        showCursor: showsCursorInScreenshots,
        excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
        excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
        excludeOwnApplication: false,
        prefetchedContentTask: prefetchedContentTask,
        context: context
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


  /// Re-capture the most recently selected area screenshot rect without
  /// re-entering selection mode. Never opens the selection flow: when no
  /// previous area is stored (or it is no longer visible on any display), the
  /// user is asked to capture an area first — via a native notification,
  /// falling back to an in-app toast when notifications are unavailable.
  func captureRepeatArea() {
    // Prevent repeat capture while a selection overlay is active
    if isAreaSelectionActive {
      DiagnosticLogger.shared.log(.debug, .capture, "captureRepeatArea blocked: already active")
      return
    }

    guard let lastRect = ScreenshotLastAreaStore.load() else {
      // No previous area stored — repeat must never enter the selection flow.
      // Prefer a native notification; fall back to an in-app toast when
      // notifications are unavailable or denied (mirrors OCRResultNotifier).
      DiagnosticLogger.shared.log(.info, .capture, "Repeat area capture skipped: no stored area")
      Task { @MainActor in
        let delivered = await SystemNotificationService.shared.post(
          title: L10n.Actions.captureRepeatArea,
          body: L10n.ScreenCapture.repeatAreaNoPreviousSelection
        )
        if !delivered {
          AppToastManager.shared.show(
            message: L10n.ScreenCapture.repeatAreaNoPreviousSelection,
            style: .warning
          )
        }
      }
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

    let captureContext = CaptureContext.fromFrontmostApp()
    let showCursor = showsCursorInScreenshots
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let excludeOwnApplication = !includesOwnAppInScreenshots
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(excludeOwnApplication)

    DiagnosticLogger.shared.log(.info, .capture, "Repeat area capture started", context: [
      "rect": "\(Int(lastRect.width))x\(Int(lastRect.height))",
    ])

    Task { @MainActor in
      defer { hiddenWindowSession.restore() }
      self.isCapturing = true
      await Task.yield()

      let actualSaveDirectory = self.tempCaptureManager.resolveSaveDirectory(
        for: .screenshot,
        exportDirectory: resolvedSaveDirectory
      )

      let result = await self.captureManager.captureArea(
        rect: lastRect,
        saveDirectory: actualSaveDirectory,
        format: self.resolvedFormat,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask,
        context: captureContext
      )

      self.isCapturing = false
      self.lastCaptureResult = result
      if case .success = result {
        SoundManager.playScreenshotCapture()
      }
    }
  }

  private func startAreaCapture(initialInteractionMode: AreaSelectionInteractionMode) {
    // Prevent multiple area captures - only one at a time
    if isAreaSelectionActive {
      DiagnosticLogger.shared.log(.debug, .capture, "captureArea blocked: already active")
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

    let captureContext = CaptureContext.fromFrontmostApp()
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
    let immediateMenuBarPopoverCaptures = freezesAreaCapture
      ? []
      : WindowSelectionQueryService.captureImmediateMenuBarPopoverCaptures(
        excludeOwnApplication: excludeOwnApplication
      )
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
        immediateMenuBarPopoverCaptures: immediateMenuBarPopoverCaptures,
        initialInteractionMode: initialInteractionMode,
        hiddenWindowSession: hiddenWindowSession,
        context: captureContext
      )
      return
    }

    // Give WindowServer enough time to fully remove hidden app windows before
    // the frozen backdrop is prepared.
    let snapshotDelay = hiddenWindowSession.didHideWindows ? frozenSnapshotWindowHideSettleDelay : 0

    // Resolve NSScreen data on main thread (AppKit requirement), then pass as
    // value types across the thread boundary for off-main CGDisplayCreateImage.
    // Eligibility mirrors captureFastDisplaySnapshot guards for these call-site args;
    // the own-application guard always passes because own windows were hidden above.
    // Both call sites are on the main thread, so NSScreen access stays safe.
    let makeFastSnapshotTask: () -> Task<FrozenDisplaySnapshot?, Never>? = {
      guard !showCursor && !excludeDesktopIcons && !excludeDesktopWidgets,
            let screen = NSScreen.screens.first(where: { $0.displayID == targetDisplayID })
      else { return nil }
      let screenFrame = screen.frame
      let backingScaleFactor = screen.backingScaleFactor
      let colorSpaceName = self.captureManager.preferredCaptureColorSpaceName(for: screen)
      let captureManager = self.captureManager
      // Task.detached ensures CGDisplayCreateImage runs on the cooperative thread
      // pool, freeing the main thread.
      return Task.detached {
        captureManager.captureFastDisplaySnapshotOffMain(
          displayID: targetDisplayID,
          screenFrame: screenFrame,
          backingScaleFactor: backingScaleFactor,
          colorSpaceName: colorSpaceName
        )
      }
    }
    // Only pre-start the task when no windows were hidden: when they were, the
    // off-main snapshot must wait out the settle delay or it can pick up
    // Snapzy's own just-hidden windows.
    let fastSnapshotTask = hiddenWindowSession.didHideWindows ? nil : makeFastSnapshotTask()

    DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
      guard let self else {
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
          if let fastSnapshotTask = fastSnapshotTask ?? makeFastSnapshotTask(),
             let fastSnapshot = await fastSnapshotTask.value
          {
            frozenSession = FrozenAreaCaptureSession.fromSnapshot(fastSnapshot)
            captureMode = "coregraphics-offmain"
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
          DiagnosticLogger.shared.log(
            .error,
            .capture,
            "Frozen area capture setup failed: \(error.localizedDescription)"
          )
          return
        } catch {
          self.isCapturing = false
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(
            .error,
            .capture,
            "Frozen area capture setup failed: \(error.localizedDescription)"
          )
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
          hiddenWindowSession: hiddenWindowSession,
          context: captureContext
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
        promptMessage: L10n.Recording.chooseSaveLocationMessage
      )
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }
    saveDirectory = resolvedSaveDirectory

    let captureContext = CaptureContext.fromFrontmostApp()
    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .capture, "Inline area annotate flow started", context: [
      "format": resolvedFormat.fileExtension,
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
      guard let self else {
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
          DiagnosticLogger.shared.log(
            .error,
            .capture,
            "Inline area annotate setup failed: \(error.localizedDescription)"
          )
          return
        } catch {
          self.isCapturing = false
          self.isAreaSelectionActive = false
          self.lastCaptureResult = .failure(.captureFailed(error.localizedDescription))
          hiddenWindowSession.restore()
          DiagnosticLogger.shared.log(
            .error,
            .capture,
            "Inline area annotate setup failed: \(error.localizedDescription)"
          )
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
          outputFormat: self.resolvedFormat,
          context: captureContext
        ) { [weak self] result in
          guard let self else {
            hiddenWindowSession.restore()
            return
          }
          isAreaSelectionActive = false
          lastCaptureResult = result
          hiddenWindowSession.restore()
          if case .failure(let error) = result {
            DiagnosticLogger.shared.log(.info, .capture, "Inline area annotate ended", context: [
              "result": error.localizedDescription,
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
    // Own normal windows are already hidden by the caller, so CoreGraphics can be
    // used even when the user excludes Snapzy from screenshots (same as fullscreen).
    let canUseFastPath = !showCursor
      && !excludeDesktopIcons
      && !excludeDesktopWidgets
    if canUseFastPath {
      // Resolve NSScreen data on main thread (AppKit requirement), then run
      // CGDisplayCreateImage concurrently off-main for all displays.
      let captureManager = captureManager
      let screens = NSScreen.screens
      let screenInputs: [(displayID: CGDirectDisplayID, screenFrame: CGRect, backingScaleFactor: CGFloat, colorSpaceName: CFString?)] =
        screens.compactMap { screen in
          guard let displayID = screen.displayID else { return nil }
          return (
            displayID,
            screen.frame,
            screen.backingScaleFactor,
            captureManager.preferredCaptureColorSpaceName(for: screen)
          )
        }
      let snapshots = await withTaskGroup(of: FrozenDisplaySnapshot?.self) { group in
        for input in screenInputs {
          group.addTask {
            captureManager.captureFastDisplaySnapshotOffMain(
              displayID: input.displayID,
              screenFrame: input.screenFrame,
              backingScaleFactor: input.backingScaleFactor,
              colorSpaceName: input.colorSpaceName
            )
          }
        }
        var results: [FrozenDisplaySnapshot] = []
        for await snapshot in group {
          if let snapshot { results.append(snapshot) }
        }
        return results
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
    hiddenWindowSession: HiddenWindowSession,
    context: CaptureContext = .empty
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
      },
      onTransitionRecapture: { [weak self] in
        self?.refreshFrozenDisplaysAfterTransition(
          sessionID: sessionID,
          frozenSession: frozenSession,
          showCursor: showCursor,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: excludeOwnApplication
        )
      },
      allowsRepeatAreaCompletion: true
    ) { [weak self] selection in
      guard let self else {
        DiagnosticLogger.shared.log(.warning, .capture, "captureArea completion: self deallocated")
        frozenSession.invalidate()
        hiddenWindowSession.restore()
        return
      }
      defer {
        self.isAreaSelectionActive = false
      }

      guard let selection else {
        cancelLazyAreaSnapshotTasks()
        frozenSession.invalidate()
        hiddenWindowSession.restore()
        DiagnosticLogger.shared.log(.info, .capture, "Area capture cancelled by user")
        lastCaptureResult = .failure(.cancelled)
        return
      }

      // Remember the manual area selection for instant repeat capture
      if case .rect(let rect) = selection.target {
        ScreenshotLastAreaStore.save(rect)
      }

      let selectionContext: CaptureContext = switch selection.target {
      case .window(let target):
        CaptureContext.fromPID(target.ownerPID, windowTitle: target.title)
      case .rect:
        context
      }

      cancelLazyAreaSnapshotTasks(clearFailures: false)

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
              let snapshotsByID = frozenSession.allSnapshots()
              let outputScaleFactor = self.preferredScreenshotOutputScaleFactor
              let cropStartedAt = Date()
              let cropResult: FrozenAreaCropResult
              if selection.spansMultipleDisplays {
                cropResult = try await Task.detached {
                  try FrozenAreaCaptureSession.cropCompositeImage(
                    snapshots: snapshotsByID,
                    for: selection,
                    minimumOutputScaleFactor: outputScaleFactor
                  )
                }.value
              } else {
                cropResult = try await Task.detached {
                  try FrozenAreaCaptureSession.cropImage(
                    snapshots: snapshotsByID,
                    for: selection,
                    minimumOutputScaleFactor: outputScaleFactor
                  )
                }.value
              }
              DiagnosticLogger.shared.log(
                .debug,
                .capture,
                "Frozen area crop completed",
                context: [
                  "duration_ms": "\(Int(Date().timeIntervalSince(cropStartedAt) * 1000))",
                  "mode": selection.spansMultipleDisplays ? "composite" : "single",
                  "width": "\(cropResult.image.width)",
                  "height": "\(cropResult.image.height)",
                ]
              )
              let result = await self.captureManager.saveProcessedImage(
                cropResult.image,
                to: actualSaveDirectory,
                format: self.resolvedFormat,
                scaleFactor: cropResult.scaleFactor,
                context: selectionContext
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
              prefetchedContentTask: prefetchedContentTask,
              context: selectionContext
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
              "rect": "\(Int(target.frame.width))x\(Int(target.frame.height))",
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
            prefetchedContentTask: prefetchedContentTask,
            context: selectionContext
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
    immediateMenuBarPopoverCaptures: [ImmediateMenuBarPopoverCapture],
    initialInteractionMode: AreaSelectionInteractionMode,
    hiddenWindowSession: HiddenWindowSession,
    context: CaptureContext = .empty
  ) {
    activeAreaSelectionSessionID = UUID()

    // `dismissesAfterSelection: false` keeps the overlay visible until the mouse-up snapshots
    // are secured inside the completion (which then calls `cancelSelection()` itself). Passed
    // as a start parameter — not `setDismissesAfterSelection` — so a session-replacement
    // teardown cannot wipe or inherit the policy.
    AreaSelectionController.shared.startSelection(
      mode: .screenshot,
      backdrops: [:],
      applicationConfiguration: AreaSelectionApplicationConfiguration(
        prefetchedContentTask: prefetchedContentTask,
        excludeOwnApplication: excludeOwnApplication,
        immediateMenuBarPopoverCaptures: immediateMenuBarPopoverCaptures
      ),
      initialInteractionMode: initialInteractionMode,
      dismissesAfterSelection: false,
      allowsRepeatAreaCompletion: true
    ) { [weak self] selection in
      guard let self else {
        hiddenWindowSession.restore()
        return
      }
      defer { self.isAreaSelectionActive = false }

      guard let selection else {
        hiddenWindowSession.restore()
        DiagnosticLogger.shared.log(.info, .capture, "Live area capture cancelled by user")
        lastCaptureResult = .failure(.cancelled)
        return
      }

      // Remember the manual area selection for instant repeat capture
      if case .rect(let rect) = selection.target {
        ScreenshotLastAreaStore.save(rect)
      }

      let selectionContext: CaptureContext = switch selection.target {
      case .window(let target):
        CaptureContext.fromPID(target.ownerPID, windowTitle: target.title)
      case .rect:
        context
      }

      // Frame lock: synchronously snapshot every display the `.rect` selection touches at
      // the instant of mouse-up (~5-20ms per display via the existing CGDisplayCreateImage
      // fast path), BEFORE any async hop — every await/Task suspension widens the window in
      // which a post-release Cmd+Tab could recomposite the screen and change the captured
      // pixels. Empty when the fast path can't honor the capture options; the capture task
      // then falls back to captureArea() (status quo).
      let mouseUpSnapshots: [FrozenDisplaySnapshot]
      if case .rect = selection.target {
        mouseUpSnapshots = self.captureLiveMouseUpSnapshots(
          selection: selection,
          showCursor: showCursor,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets
        )
      } else {
        mouseUpSnapshots = []
      }

      // Secure pixels first: immediately after the snapshot is taken, we dismiss the overlay
      AreaSelectionController.shared.cancelSelection()

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
          result = await self.captureLiveRectFromSnapshots(
            selection: selection,
            snapshots: mouseUpSnapshots,
            saveDirectory: actualSaveDirectory,
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication,
            prefetchedContentTask: prefetchedContentTask,
            selectionContext: selectionContext
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
            prefetchedContentTask: prefetchedContentTask,
            immediateMenuBarPopoverCapture: immediateMenuBarPopoverCaptures.first {
              $0.target.windowID == target.windowID
            },
            context: selectionContext
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

  /// Synchronously snapshot each display the live `.rect` selection touches, at the instant
  /// of mouse-up, via the existing CGDisplayCreateImage fast path (~5-20ms per display, no
  /// SCStream, no recording indicator). The area-selection overlay never bakes in: its
  /// windows are `sharingType = .none`, which CGDisplayCreateImage respects — the same
  /// mechanism frozen-mode lazy snapshots rely on while overlays are visible.
  ///
  /// Own-app exclusion does NOT disqualify the fast path here: live sessions hide own
  /// normal windows for their whole duration (`hideVisibleNormalWindowsIfNeeded`), so at
  /// mouse-up no own window is visible — the same reasoning as the fullscreen fast path's
  /// `allowFastPathWhenOwnApplicationHidden`.
  ///
  /// Returns `[]` when the fast path can't honor the capture options (cursor shown /
  /// desktop-icon / widget exclusion — CGDisplayCreateImage can't filter those) or when any
  /// touched display fails to snapshot (mixed-source composites are worse than a uniform
  /// fallback). The caller then falls back to `captureArea()` (status quo).
  private func captureLiveMouseUpSnapshots(
    selection: AreaSelectionResult,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool
  ) -> [FrozenDisplaySnapshot] {
    let grabStartedAt = Date()
    let neededDisplayIDs = selection.spansMultipleDisplays ? selection.displayIDs : [selection.displayID]
    let snapshots = Self.gatherLiveMouseUpSnapshots(
      displayIDs: neededDisplayIDs,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets
    ) { displayID in
      let snapshot = captureManager.captureFastDisplaySnapshot(
        displayID: displayID,
        showCursor: false,
        excludeDesktopIcons: false,
        excludeDesktopWidgets: false,
        excludeOwnApplication: false
      )
      if snapshot == nil {
        DiagnosticLogger.shared.log(
          .info, .capture,
          "Mouse-up fast snapshot unavailable; falling back to captureArea",
          context: ["displayID": "\(displayID)"]
        )
      }
      return snapshot
    }
    if !snapshots.isEmpty {
      DiagnosticLogger.shared.log(
        .info, .capture,
        "Mouse-up fast snapshots grabbed",
        context: [
          "displays": "\(snapshots.count)",
          "grabMs": "\(Int(Date().timeIntervalSince(grabStartedAt) * 1000))"
        ]
      )
    }
    return snapshots
  }

  /// Testable core of `captureLiveMouseUpSnapshots`: fast-path gating plus the
  /// all-or-nothing per-display gather. Returns `[]` when the requested options can't be
  /// honored by the CG fast path or when ANY display's grab fails — a partial result would
  /// produce a mixed-source composite, which is worse than a uniform fallback.
  /// `snapshotProvider` is `captureFastDisplaySnapshot` in production; injected so this
  /// logic is unit-testable without displays or Screen Recording permission.
  static func gatherLiveMouseUpSnapshots(
    displayIDs: Set<CGDirectDisplayID>,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    snapshotProvider: (CGDirectDisplayID) -> FrozenDisplaySnapshot?
  ) -> [FrozenDisplaySnapshot] {
    guard !showCursor, !excludeDesktopIcons, !excludeDesktopWidgets else { return [] }

    var snapshots: [FrozenDisplaySnapshot] = []
    for displayID in displayIDs {
      guard let snapshot = snapshotProvider(displayID) else { return [] }
      snapshots.append(snapshot)
    }
    return snapshots
  }

  /// Crop the live `.rect` selection from the snapshots grabbed synchronously at mouse-up
  /// and save it. The snapshots were read ~5-20ms after release — before any human-initiated
  /// app switch can recomposite the screen — so the captured pixels match what was on screen
  /// at release. If no snapshots are available (fast path gated off or a display grab
  /// failed), fall back to today's `captureArea()` (status quo). Mirrors the frozen
  /// completion's crop+save path (DRY via the shared `FrozenAreaCaptureSession.cropImage` /
  /// `cropCompositeImage`).
  private func captureLiveRectFromSnapshots(
    selection: AreaSelectionResult,
    snapshots: [FrozenDisplaySnapshot],
    saveDirectory: URL,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    selectionContext: CaptureContext
  ) async -> CaptureResult {
    let mouseUpStartedAt = Date()

    guard !snapshots.isEmpty else {
      DiagnosticLogger.shared.log(
        .info, .capture,
        "Area captured live",
        context: ["rect": "\(Int(selection.rect.width))x\(Int(selection.rect.height))"]
      )
      return await captureManager.captureArea(
        rect: selection.rect,
        saveDirectory: saveDirectory,
        format: resolvedFormat,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask,
        context: selectionContext
      )
    }

    let frozenSession = FrozenAreaCaptureSession.fromSnapshots(snapshots)

    do {
      let snapshotsByID = frozenSession.allSnapshots()
      let outputScaleFactor = preferredScreenshotOutputScaleFactor
      let cropStartedAt = Date()
      let cropResult: FrozenAreaCropResult
      if selection.spansMultipleDisplays {
        cropResult = try await Task.detached {
          try FrozenAreaCaptureSession.cropCompositeImage(
            snapshots: snapshotsByID,
            for: selection,
            minimumOutputScaleFactor: outputScaleFactor
          )
        }.value
      } else {
        cropResult = try await Task.detached {
          try FrozenAreaCaptureSession.cropImage(
            snapshots: snapshotsByID,
            for: selection,
            minimumOutputScaleFactor: outputScaleFactor
          )
        }.value
      }
      DiagnosticLogger.shared.log(
        .debug, .capture,
        "Frozen area crop completed",
        context: [
          "duration_ms": "\(Int(Date().timeIntervalSince(cropStartedAt) * 1000))",
          "mode": selection.spansMultipleDisplays ? "composite" : "single",
          "width": "\(cropResult.image.width)",
          "height": "\(cropResult.image.height)"
        ]
      )
      let result = await captureManager.saveProcessedImage(
        cropResult.image,
        to: saveDirectory,
        format: resolvedFormat,
        scaleFactor: cropResult.scaleFactor,
        context: selectionContext
      )
      let durationMs = Int(Date().timeIntervalSince(mouseUpStartedAt) * 1000)
      DiagnosticLogger.shared.log(
        .info, .capture,
        "Area captured from mouse-up fast snapshot",
        context: [
          "rect": "\(Int(selection.rect.width))x\(Int(selection.rect.height))",
          "spanMultiple": "\(selection.spansMultipleDisplays)",
          "cropSaveMs": "\(durationMs)"
        ]
      )
      return result
    } catch {
      DiagnosticLogger.shared.log(
        .error, .capture,
        "Mouse-up snapshot crop failed; falling back to captureArea: \(error.localizedDescription)"
      )
      DiagnosticLogger.shared.log(
        .info, .capture,
        "Area captured live",
        context: ["rect": "\(Int(selection.rect.width))x\(Int(selection.rect.height))"]
      )
      return await captureManager.captureArea(
        rect: selection.rect,
        saveDirectory: saveDirectory,
        format: resolvedFormat,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask,
        context: selectionContext
      )
    }
  }

  /// Resolve the captured image for a live (backdrop-less) selection with the same
  /// transient-UI preservation as live area capture (⌘⇧4):
  /// - a retained menu-bar popover target uses the pixels snapshotted at shortcut time
  ///   (the transient WindowServer window may already be gone by mouse-up);
  /// - otherwise the selection is cropped from the frame-locked mouse-up snapshots,
  ///   which include hover states, dropdowns, tooltips, and popovers exactly as shown;
  /// - when the fast path is unavailable (exclusion options or a failed grab), falls
  ///   back to a fresh ScreenCaptureKit area capture — the same status-quo fallback
  ///   live area capture uses.
  /// Used by OCR and object-cutout captures, which consume an image rather than a
  /// saved file. `minimumOutputScaleFactor: 1` keeps native pixels — no upscale or
  /// sharpen cost beyond the previous behavior.
  private func captureLiveSelectionImage(
    selection: AreaSelectionResult,
    mouseUpSnapshots: [FrozenDisplaySnapshot],
    immediateMenuBarPopoverCaptures: [ImmediateMenuBarPopoverCapture],
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async throws -> (image: CGImage, scaleFactor: CGFloat)? {
    if let windowTarget = selection.target.windowTarget,
       let retained = immediateMenuBarPopoverCaptures.first(where: {
         $0.target.windowID == windowTarget.windowID
       })
    {
      return (retained.image, retained.scaleFactor)
    }

    if !mouseUpSnapshots.isEmpty {
      do {
        let snapshotsByID = FrozenAreaCaptureSession.fromSnapshots(mouseUpSnapshots).allSnapshots()
        let cropResult: FrozenAreaCropResult
        if selection.spansMultipleDisplays {
          cropResult = try await Task.detached {
            try FrozenAreaCaptureSession.cropCompositeImage(
              snapshots: snapshotsByID,
              for: selection,
              minimumOutputScaleFactor: 1
            )
          }.value
        } else {
          cropResult = try await Task.detached {
            try FrozenAreaCaptureSession.cropImage(
              snapshots: snapshotsByID,
              for: selection,
              minimumOutputScaleFactor: 1
            )
          }.value
        }
        return (cropResult.image, cropResult.scaleFactor)
      } catch {
        DiagnosticLogger.shared.log(
          .error,
          .capture,
          "Mouse-up snapshot crop failed; falling back to captureAreaAsImage: \(error.localizedDescription)"
        )
      }
    }

    guard
      let image = try await captureManager.captureAreaAsImage(
        rect: selection.rect,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask
      )
    else { return nil }

    return (image, Self.captureScaleFactor(for: image, rect: selection.rect))
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
      guard activeAreaSelectionSessionID == sessionID else { return }

      // Try fast CG path first (only when no cursor/desktop exclusion needed)
      cgFastPath: do {
        guard !showCursor, !excludeDesktopIcons, !excludeDesktopWidgets else { break cgFastPath }

        // Resolve NSScreen data on main thread (AppKit requirement), then pass as
        // value types across the thread boundary for off-main CGDisplayCreateImage.
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
          // Display not found — fall through to SCK async path below
          break cgFastPath
        }
        let screenFrame = screen.frame
        let backingScale = screen.backingScaleFactor
        let colorSpaceName = captureManager.preferredCaptureColorSpaceName(for: screen)
        let captureManager = captureManager

        // withDisplayOverlayHiddenAsync: hides overlay on main, runs work off-main, restores on main.
        let fastSnapshot = await AreaSelectionController.shared.withDisplayOverlayHiddenAsync(
          for: displayID
        ) {
          // Task.detached ensures CGDisplayCreateImage runs on cooperative thread pool,
          // not on MainActor, freeing main thread for mouse event processing.
          await Task.detached {
            captureManager.captureFastDisplaySnapshotOffMain(
              displayID: displayID,
              screenFrame: screenFrame,
              backingScaleFactor: backingScale,
              colorSpaceName: colorSpaceName
            )
          }.value
        }

        // Re-validate session after awaiting — user may have dismissed capture area.
        guard activeAreaSelectionSessionID == sessionID else { return }

        if let fastSnapshot {
          applyLazyFrozenSnapshot(
            fastSnapshot,
            mode: excludeOwnApplication ? "coregraphics-hidden-overlay" : "coregraphics",
            displayID: displayID,
            startedAt: startedAt,
            sessionID: sessionID,
            frozenSession: frozenSession
          )
          lazyAreaSnapshotTasks[displayID] = nil
          return
        }
      }

      // SCK async path
      do {
        let snapshots = try await captureManager.captureDisplaySnapshots(
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
        applyLazyFrozenSnapshot(
          snapshot,
          mode: "screencapturekit",
          displayID: displayID,
          startedAt: startedAt,
          sessionID: sessionID,
          frozenSession: frozenSession
        )
      } catch {
        guard activeAreaSelectionSessionID == sessionID else { return }
        lazyAreaSnapshotFailedDisplayIDs.insert(displayID)
        AreaSelectionController.shared.enableLiveFallbackSelection(for: displayID)
        DiagnosticLogger.shared.logError(
          .capture,
          error,
          "Lazy frozen display snapshot failed; enabled live fallback",
          context: ["displayID": "\(displayID)"]
        )
      }
      lazyAreaSnapshotTasks[displayID] = nil
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

  /// Re-freeze the frozen session's displays at full quality after a Space/app/desktop
  /// transition settles. Updates both the visible backdrop and the crop source
  /// (`FrozenAreaCaptureSession`) so the on-screen preview AND the final capture reflect
  /// the current screen — not the stale initial freeze. Frozen sessions only. Reuses the
  /// same capture + apply path as lazy display preparation (DRY). Fresh shareable content
  /// (no stale prefetch) so exclusions/window list match the post-transition state.
  private func refreshFrozenDisplaysAfterTransition(
    sessionID: UUID,
    frozenSession: FrozenAreaCaptureSession,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool
  ) {
    guard activeAreaSelectionSessionID == sessionID else { return }
    let currentDisplayIDs = Set(NSScreen.screens.compactMap { $0.displayID })
    let displayIDs = frozenSession.displayIDs.intersection(currentDisplayIDs)
    guard !displayIDs.isEmpty else { return }

    for displayID in displayIDs {
      Task { @MainActor [weak self] in
        guard let self, self.activeAreaSelectionSessionID == sessionID else { return }
        let startedAt = Date()

        // Fast CoreGraphics path when no cursor/desktop exclusions are needed. The overlay
        // is capture-excluded (sharingType == .none), so it is not baked into the snapshot.
        if !showCursor, !excludeDesktopIcons, !excludeDesktopWidgets,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
          let screenFrame = screen.frame
          let backingScale = screen.backingScaleFactor
          let colorSpaceName = self.captureManager.preferredCaptureColorSpaceName(for: screen)
          let captureManager = self.captureManager
          let fastSnapshot = await AreaSelectionController.shared.withDisplayOverlayHiddenAsync(
            for: displayID
          ) {
            await Task.detached {
              captureManager.captureFastDisplaySnapshotOffMain(
                displayID: displayID,
                screenFrame: screenFrame,
                backingScaleFactor: backingScale,
                colorSpaceName: colorSpaceName
              )
            }.value
          }
          guard self.activeAreaSelectionSessionID == sessionID else { return }
          if let fastSnapshot {
            self.applyLazyFrozenSnapshot(
              fastSnapshot,
              mode: "transition-refreeze-cg",
              displayID: displayID,
              startedAt: startedAt,
              sessionID: sessionID,
              frozenSession: frozenSession
            )
            return
          }
        }

        // ScreenCaptureKit path (exclusions on, or fast path unavailable).
        do {
          let snapshots = try await self.captureManager.captureDisplaySnapshots(
            displayIDs: [displayID],
            showCursor: showCursor,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets,
            excludeOwnApplication: excludeOwnApplication,
            prefetchedContentTask: nil
          )
          guard self.activeAreaSelectionSessionID == sessionID,
                let snapshot = snapshots[displayID] else { return }
          self.applyLazyFrozenSnapshot(
            snapshot,
            mode: "transition-refreeze-sck",
            displayID: displayID,
            startedAt: startedAt,
            sessionID: sessionID,
            frozenSession: frozenSession
          )
        } catch {
          DiagnosticLogger.shared.logError(
            .capture,
            error,
            "Frozen transition re-freeze failed",
            context: ["displayID": "\(displayID)"]
          )
        }
      }
    }
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
        promptMessage: L10n.Recording.chooseSaveLocationMessage
      )
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }
    saveDirectory = resolvedSaveDirectory

    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Scrolling capture flow started",
      context: ["format": resolvedFormat.fileExtension]
    )
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )

    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(true)

    DispatchQueue.main
      .asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
        guard let self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureScrolling: self deallocated")
          hiddenWindowSession.restore()
          AreaSelectionController.shared.cancelSelection()
          return
        }

        AreaSelectionController.shared.startSelection(mode: .scrollingCapture) { [weak self] rect, _ in
          guard let self else {
            DiagnosticLogger.shared.log(.warning, .capture, "captureScrolling completion: self deallocated")
            hiddenWindowSession.restore()
            return
          }

          defer {
            self.isAreaSelectionActive = false
          }

          guard let selectedRect = rect else {
            DiagnosticLogger.shared.log(.info, .capture, "Scrolling capture cancelled by user")
            lastCaptureResult = .failure(.cancelled)
            hiddenWindowSession.restore()
            return
          }

          let actualSaveDirectory = tempCaptureManager.resolveSaveDirectory(
            for: .screenshot,
            exportDirectory: resolvedSaveDirectory
          )

          ScrollingCaptureCoordinator.shared.beginSession(
            rect: selectedRect,
            saveDirectory: actualSaveDirectory,
            format: resolvedFormat,
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
    DispatchQueue.main
      .asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
        guard let self else {
          DiagnosticLogger.shared.log(.warning, .recording, "startRecordingFlow: self deallocated")
          hiddenWindowSession.restore()
          AreaSelectionController.shared.cancelSelection()
          return
        }

        // Check for saved recording area - restore if enabled and available
        let rememberLastArea = UserDefaults.standard
          .object(forKey: PreferencesKeys.recordingRememberLastArea) as? Bool ?? true
        if initialInteractionMode == .manualRegion,
           rememberLastArea,
           let savedRect = RecordingCoordinator.shared.loadLastAreaRect() {
          isAreaSelectionActive = false
          DiagnosticLogger.shared.log(
            .info,
            .recording,
            "Using saved recording area",
            context: ["rect": "\(Int(savedRect.width))x\(Int(savedRect.height))"]
          )
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
          prefetchedContentTask: captureManager.prefetchShareableContent(),
          excludeOwnApplication: !includesOwnAppInRecordings
        )
        AreaSelectionController.shared.startSelection(
          mode: .recording,
          backdrops: [:],
          applicationConfiguration: applicationConfiguration,
          initialInteractionMode: initialInteractionMode
        ) { [weak self] selection in
          guard let self else {
            DiagnosticLogger.shared.log(.warning, .recording, "startRecordingFlow completion: self deallocated")
            hiddenWindowSession.restore()
            return
          }

          isAreaSelectionActive = false

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

    let captureContext = CaptureContext.fromFrontmostApp()

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
        scaleFactor: scaleFactor,
        context: captureContext
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
    let excludeOwnApplication = !includesOwnAppInScreenshots
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    // Same transient-UI preservation as live area capture (⌘⇧4): retain the pixels of
    // any visible menu-bar popover before Snapzy presents its selection UI — menu
    // extras may close as a side effect of global-hotkey handling or overlay ordering.
    let immediateMenuBarPopoverCaptures = WindowSelectionQueryService.captureImmediateMenuBarPopoverCaptures(
      excludeOwnApplication: excludeOwnApplication
    )

    // Hide only normal-level app windows (not overlay panels)
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(excludeOwnApplication)

    // Minimal delay to ensure window is hidden when we actually hid one.
    DispatchQueue.main
      .asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
        guard let self else {
          DiagnosticLogger.shared.log(.warning, .ocr, "captureOCR: self deallocated")
          hiddenWindowSession.restore()
          AreaSelectionController.shared.cancelSelection()
          return
        }

        // `dismissesAfterSelection: false` keeps the overlay visible until the mouse-up
        // snapshots are secured inside the completion (which then calls `cancelSelection()`
        // itself) — the capture-before-hide sequencing live area capture relies on.
        AreaSelectionController.shared.startSelection(
          mode: .screenshot,
          backdrops: [:],
          applicationConfiguration: AreaSelectionApplicationConfiguration(
            prefetchedContentTask: prefetchedContentTask,
            excludeOwnApplication: excludeOwnApplication,
            immediateMenuBarPopoverCaptures: immediateMenuBarPopoverCaptures
          ),
          initialInteractionMode: .manualRegion,
          dismissesAfterSelection: false
        ) { [weak self] selection in
          guard let self else {
            DiagnosticLogger.shared.log(.warning, .ocr, "captureOCR completion: self deallocated")
            hiddenWindowSession.restore()
            return
          }

          guard let selection else {
            isAreaSelectionActive = false
            hiddenWindowSession.restore()
            DiagnosticLogger.shared.log(.info, .ocr, "OCR capture cancelled")
            return
          }

          let selectedRect = selection.rect
          DiagnosticLogger.shared.log(
            .info,
            .ocr,
            "OCR area selected",
            context: ["rect": "\(Int(selectedRect.width))x\(Int(selectedRect.height))"]
          )

          // Frame lock: synchronously snapshot every display the selection touches at the
          // instant of mouse-up, BEFORE any async hop — hover states, dropdowns, tooltips,
          // and popovers are captured exactly as on screen (mirrors live area capture).
          let mouseUpSnapshots = self.captureLiveMouseUpSnapshots(
            selection: selection,
            showCursor: false,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets
          )

          // Secure pixels first: immediately after the snapshot is taken, dismiss the overlay.
          AreaSelectionController.shared.cancelSelection()

          // The menu-bar spinner is the primary progress surface, but `setProcessing` is a no-op
          // without a status item, so it reports nothing when the icon is hidden. Fall back to a
          // toast only in that case, never alongside it.
          let progressToast = AppStatusBarController.shared.isMenuBarIconVisible
            ? nil
            : AppToastManager.shared.show(
              message: L10n.OCR.capturingContent,
              style: .info,
              duration: nil,
              variant: .compact,
              iconMode: .spinner
            )

          Task { @MainActor in
            var progressToastResolved = false
            defer {
              self.isAreaSelectionActive = false
              hiddenWindowSession.restore()
              if let progressToast, !progressToastResolved {
                AppToastManager.shared.dismiss(progressToast)
              }
            }
            await Task.yield()

            do {
              let operationStartTime = CFAbsoluteTimeGetCurrent()

              // Show menubar spinner for processing feedback
              AppStatusBarController.shared.setProcessing(true)

              // Capture the screen region
              let captureStartTime = CFAbsoluteTimeGetCurrent()
              guard let liveCapture = try await self.captureLiveSelectionImage(
                selection: selection,
                mouseUpSnapshots: mouseUpSnapshots,
                immediateMenuBarPopoverCaptures: immediateMenuBarPopoverCaptures,
                excludeDesktopIcons: excludeDesktopIcons,
                excludeDesktopWidgets: excludeDesktopWidgets,
                excludeOwnApplication: excludeOwnApplication,
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
              let image = liveCapture.image
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
                "totalMs": totalDurationMs,
              ]

              AppStatusBarController.shared.setProcessing(false)

              guard let clipboardText else {
                if let progressToast {
                  AppToastManager.shared.update(
                    progressToast,
                    message: qrResult.unsupportedPayloadCount > 0
                      ? L10n.OCR.qrTextOnlyUnsupported
                      : L10n.OCR.noTextFound,
                    style: .warning,
                    duration: 2.5,
                    variant: .compact
                  )
                  progressToastResolved = true
                }
                if qrResult.unsupportedPayloadCount > 0 {
                  var context = performanceContext
                  context["unsupportedQRCount"] = "\(qrResult.unsupportedPayloadCount)"
                  DiagnosticLogger.shared.log(
                    .warning,
                    .ocr,
                    "OCR QR capture found unsupported QR payloads",
                    context: context
                  )
                  OCRResultNotifier.shared.report(.qrTextOnlyUnsupported)
                } else {
                  DiagnosticLogger.shared.log(
                    .warning,
                    .ocr,
                    "OCR capture failed: no text or QR payload found",
                    context: performanceContext
                  )
                  OCRResultNotifier.shared.report(.noText)
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

              if let progressToast {
                AppToastManager.shared.update(
                  progressToast,
                  message: L10n.Common.copiedToClipboard,
                  style: .success,
                  duration: 2.0,
                  variant: .compact
                )
                progressToastResolved = true
              }

              OCRResultNotifier.shared.report(.copied(clipboardText))
              if OCRResultNotifier.isEnabled() {
                QuickAccessSound.complete.play()
              }

              let linkDetectionEnabled = UserDefaults.standard
                .object(forKey: PreferencesKeys.ocrLinkDetectionEnabled) as? Bool ?? true
              if linkDetectionEnabled {
                let detectedLinks = OCRLinkDetector.detectWebLinks(in: clipboardText)
                if !detectedLinks.isEmpty {
                  OCRLinkPromptManager.shared.show(links: detectedLinks)
                }
              }

            } catch {
              // Error feedback
              AppStatusBarController.shared.setProcessing(false)
              DiagnosticLogger.shared.logError(.ocr, error, "OCR capture failed")
              if let progressToast {
                AppToastManager.shared.update(
                  progressToast,
                  message: error.localizedDescription,
                  style: .error,
                  duration: 2.5,
                  variant: .compact
                )
                progressToastResolved = true
              }
              OCRResultNotifier.shared.report(.failed(errorDescription: error.localizedDescription))
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
            "durationMs": Self.elapsedMilliseconds(since: startTime),
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
        promptMessage: L10n.Recording.chooseSaveLocationMessage
      )
    else {
      lastCaptureResult = .failure(.saveFailed(L10n.ScreenCapture.saveLocationPermissionRequired))
      return
    }
    saveDirectory = resolvedSaveDirectory

    let captureContext = CaptureContext.fromFrontmostApp()

    isAreaSelectionActive = true
    DiagnosticLogger.shared.log(.info, .capture, "Object cutout flow started")
    let excludeDesktopIcons = DesktopIconManager.shared.isIconHidingEnabled
    let excludeDesktopWidgets = DesktopIconManager.shared.isWidgetHidingEnabled
    let excludeOwnApplication = !includesOwnAppInScreenshots
    let prefetchedContentTask = captureManager.prefetchShareableContent(
      includeDesktopWindows: excludeDesktopIcons || excludeDesktopWidgets
    )
    // Same transient-UI preservation as live area capture (⌘⇧4): retain the pixels of
    // any visible menu-bar popover before Snapzy presents its selection UI — menu
    // extras may close as a side effect of global-hotkey handling or overlay ordering.
    let immediateMenuBarPopoverCaptures = WindowSelectionQueryService.captureImmediateMenuBarPopoverCaptures(
      excludeOwnApplication: excludeOwnApplication
    )

    // Hide only normal-level app windows (not overlay panels)
    let hiddenWindowSession = hideVisibleNormalWindowsIfNeeded(excludeOwnApplication)

    DispatchQueue.main
      .asyncAfter(deadline: .now() + (hiddenWindowSession.didHideWindows ? windowHideSettleDelay : 0)) { [weak self] in
        guard let self else {
          DiagnosticLogger.shared.log(.warning, .capture, "captureObjectCutout: self deallocated")
          hiddenWindowSession.restore()
          AreaSelectionController.shared.cancelSelection()
          return
        }

        // `dismissesAfterSelection: false` keeps the overlay visible until the mouse-up
        // snapshots are secured inside the completion (which then calls `cancelSelection()`
        // itself) — the capture-before-hide sequencing live area capture relies on.
        AreaSelectionController.shared.startSelection(
          mode: .screenshot,
          backdrops: [:],
          applicationConfiguration: AreaSelectionApplicationConfiguration(
            prefetchedContentTask: prefetchedContentTask,
            excludeOwnApplication: excludeOwnApplication,
            immediateMenuBarPopoverCaptures: immediateMenuBarPopoverCaptures
          ),
          initialInteractionMode: .manualRegion,
          dismissesAfterSelection: false
        ) { [weak self] selection in
          guard let self else {
            DiagnosticLogger.shared.log(.warning, .capture, "captureObjectCutout completion: self deallocated")
            hiddenWindowSession.restore()
            return
          }

          guard let selection else {
            isAreaSelectionActive = false
            hiddenWindowSession.restore()
            DiagnosticLogger.shared.log(.info, .capture, "Object cutout capture cancelled")
            lastCaptureResult = .failure(.cancelled)
            return
          }

          let selectionContext: CaptureContext = switch selection.target {
          case .window(let target):
            CaptureContext.fromPID(target.ownerPID, windowTitle: target.title)
          case .rect:
            captureContext
          }

          // Frame lock: synchronously snapshot every display the selection touches at the
          // instant of mouse-up, BEFORE any async hop — hover states, dropdowns, tooltips,
          // and popovers are captured exactly as on screen (mirrors live area capture).
          let mouseUpSnapshots = self.captureLiveMouseUpSnapshots(
            selection: selection,
            showCursor: false,
            excludeDesktopIcons: excludeDesktopIcons,
            excludeDesktopWidgets: excludeDesktopWidgets
          )

          // Secure pixels first: immediately after the snapshot is taken, dismiss the overlay.
          AreaSelectionController.shared.cancelSelection()

          Task { @MainActor in
            defer {
              self.isAreaSelectionActive = false
              hiddenWindowSession.restore()
            }

            self.isCapturing = true
            await Task.yield()

            do {
              guard let liveCapture = try await self.captureLiveSelectionImage(
                selection: selection,
                mouseUpSnapshots: mouseUpSnapshots,
                immediateMenuBarPopoverCaptures: immediateMenuBarPopoverCaptures,
                excludeDesktopIcons: excludeDesktopIcons,
                excludeDesktopWidgets: excludeDesktopWidgets,
                excludeOwnApplication: excludeOwnApplication,
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

              let capturedImage = liveCapture.image
              let cutoutScaleFactor = liveCapture.scaleFactor
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
                  "autoCropApplied": "\(didAutoCrop)",
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
                format: output.format,
                scaleFactor: cutoutScaleFactor,
                context: selectionContext
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
