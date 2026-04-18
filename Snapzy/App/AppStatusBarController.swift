//
//  AppStatusBarController.swift
//  Snapzy
//
//  Manages the NSStatusItem for menu-driven capture actions and live recording status.
//

import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppStatusBarController: ObservableObject {

  static let shared = AppStatusBarController()

  // MARK: - Properties

  private var statusItem: NSStatusItem?
  private var cancellables = Set<AnyCancellable>()
  private let recorder = ScreenRecordingManager.shared
  private lazy var idleStatusImage = makeIdleStatusImage()
  private var menu: NSMenu?
  private var didDetectCrash = false

  // Dependencies injected after setup
  private var viewModel: ScreenCaptureViewModel?
  private var updater: SPUUpdater?

  // Track if we elevated activation policy for Settings window
  private var didElevateForSettings = false
  private weak var trackedPreferencesWindow: NSWindow?
  private var trackedPreferencesExcludedWindowID: CGWindowID?
  private var pendingPreferencesWindowTrackingWorkItem: DispatchWorkItem?

  private init() {}

  // MARK: - Public API

  /// Setup the status bar item with required dependencies
  func setup(viewModel: ScreenCaptureViewModel, updater: SPUUpdater, didCrash: Bool = false) {
    self.viewModel = viewModel
    self.updater = updater
    self.didDetectCrash = didCrash

    setupStatusItem()
    buildMenu()
    observeRecordingState()

    // Pre-allocate area selection windows for instant activation (<150ms)
    AreaSelectionController.shared.prepareWindowPool()
  }

  func stopRecording() {
    RecordingCoordinator.shared.stopFromStatusItem()
  }

  // MARK: - Private Setup

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(statusBarButtonClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      renderStatusItem()
    }
  }

  @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    switch event.type {
    case .leftMouseUp, .rightMouseUp:
      showMenu()
    default:
      break
    }
  }

  private func showMenu() {
    guard let button = statusItem?.button else { return }
    buildMenu()  // Rebuild to update state
    statusItem?.menu = menu
    button.performClick(nil)
    statusItem?.menu = nil  // Reset to allow custom click handling
  }

  // MARK: - State Observation

  private func observeRecordingState() {
    recorder.$state
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.renderStatusItem()
        self?.syncTrackedPreferencesWindowExclusion()
      }
      .store(in: &cancellables)

    recorder.$elapsedSeconds
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.renderStatusItem()
      }
      .store(in: &cancellables)
  }

  private func renderStatusItem() {
    guard let button = statusItem?.button else { return }
    button.image = idleStatusImage
    button.contentTintColor = nil
    button.attributedTitle = statusItemAttributedTitle(for: recorder.state)
    button.toolTip = statusItemTooltip(for: recorder.state)
  }

  private func statusItemAttributedTitle(for state: RecordingState) -> NSAttributedString {
    let title: String
    switch state {
    case .recording:
      title = recorder.formattedDuration
    case .paused:
      title = "|| \(recorder.formattedDuration)"
    case .idle, .preparing, .stopping:
      title = ""
    }

    guard !title.isEmpty else {
      return NSAttributedString(string: "")
    }

    let menuBarFont = NSFont.menuBarFont(ofSize: 0)
    let monospacedDigitsFont = NSFont.monospacedDigitSystemFont(
      ofSize: menuBarFont.pointSize,
      weight: .regular
    )

    return NSAttributedString(
      string: title,
      attributes: [
        .font: monospacedDigitsFont,
        .foregroundColor: NSColor.labelColor,
      ]
    )
  }

  private func statusItemTooltip(for state: RecordingState) -> String {
    switch state {
    case .recording:
      return "\(L10n.RecordingToolbar.recordingInProgress) (\(recorder.formattedDuration))"
    case .paused:
      return "\(L10n.RecordingToolbar.recordingPaused) (\(recorder.formattedDuration))"
    case .preparing:
      return "Snapzy"
    case .stopping:
      return "Snapzy"
    case .idle:
      return "Snapzy"
    }
  }

  private func makeIdleStatusImage() -> NSImage? {
    guard let appIcon = NSImage(named: "MenubarIcon") else { return nil }

    let size = NSSize(width: 18, height: 18)
    let resizedIcon = NSImage(size: size)
    resizedIcon.lockFocus()
    appIcon.draw(
      in: NSRect(origin: .zero, size: size),
      from: NSRect(origin: .zero, size: appIcon.size),
      operation: .copy,
      fraction: 1.0
    )
    resizedIcon.unlockFocus()
    // Template images let AppKit adapt the glyph color to the current menu bar material.
    resizedIcon.isTemplate = true
    return resizedIcon
  }

  // MARK: - Menu Building

  private func buildMenu() {
    menu = NSMenu()
    menu?.autoenablesItems = false

    guard let viewModel = viewModel else { return }

    // Recording status indicator (when recording)
    if recorder.state == .recording || recorder.state == .paused {
      let stopItem = NSMenuItem(
        title: L10n.Menu.stopRecording(recorder.formattedDuration),
        action: #selector(stopRecordingAction),
        keyEquivalent: ""
      )
      stopItem.target = self
      stopItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
      stopItem.isEnabled = true
      menu?.addItem(stopItem)

      let pauseResumeItem = NSMenuItem(
        title: recorder.isPaused ? L10n.RecordingToolbar.resumeRecording : L10n.RecordingToolbar.pauseRecording,
        action: #selector(togglePauseRecordingAction),
        keyEquivalent: ""
      )
      pauseResumeItem.target = self
      pauseResumeItem.image = NSImage(
        systemSymbolName: recorder.isPaused ? "play.fill" : "pause.fill",
        accessibilityDescription: nil
      )
      pauseResumeItem.isEnabled = recorder.state == .recording || recorder.state == .paused
      menu?.addItem(pauseResumeItem)

      menu?.addItem(NSMenuItem.separator())
    }

    // Capture Actions
    let captureAreaItem = NSMenuItem(
      title: L10n.Actions.captureArea,
      action: #selector(captureAreaAction),
      keyEquivalent: "4"
    )
    captureAreaItem.keyEquivalentModifierMask = [.command, .shift]
    captureAreaItem.target = self
    captureAreaItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
    captureAreaItem.isEnabled = viewModel.hasPermission
    menu?.addItem(captureAreaItem)

    let captureFullscreenItem = NSMenuItem(
      title: L10n.Actions.captureFullscreen,
      action: #selector(captureFullscreenAction),
      keyEquivalent: "3"
    )
    captureFullscreenItem.keyEquivalentModifierMask = [.command, .shift]
    captureFullscreenItem.target = self
    captureFullscreenItem.image = NSImage(
      systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
    captureFullscreenItem.isEnabled = viewModel.hasPermission
    menu?.addItem(captureFullscreenItem)

    let scrollingCaptureItem = NSMenuItem(
      title: L10n.Actions.scrollingCapture,
      action: #selector(captureScrollingAction),
      keyEquivalent: "6"
    )
    scrollingCaptureItem.keyEquivalentModifierMask = [.command, .shift]
    scrollingCaptureItem.target = self
    scrollingCaptureItem.image = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: nil)
    scrollingCaptureItem.isEnabled = viewModel.hasPermission && !ScrollingCaptureCoordinator.shared.isActive
    menu?.addItem(scrollingCaptureItem)

    let captureOCRItem = NSMenuItem(
      title: L10n.Actions.captureTextOCR,
      action: #selector(captureOCRAction),
      keyEquivalent: "2"
    )
    captureOCRItem.keyEquivalentModifierMask = [.command, .shift]
    captureOCRItem.target = self
    captureOCRItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
    captureOCRItem.isEnabled = viewModel.hasPermission
    menu?.addItem(captureOCRItem)

    let captureObjectCutoutItem = NSMenuItem(
      title: GlobalShortcutKind.objectCutout.displayName,
      action: #selector(captureObjectCutoutAction),
      keyEquivalent: "1"
    )
    captureObjectCutoutItem.keyEquivalentModifierMask = [.command, .shift]
    captureObjectCutoutItem.target = self
    captureObjectCutoutItem.image = NSImage(systemSymbolName: "person.crop.rectangle", accessibilityDescription: nil)
    if #available(macOS 14.0, *) {
      captureObjectCutoutItem.isEnabled = viewModel.hasPermission
    } else {
      captureObjectCutoutItem.isEnabled = false
    }
    menu?.addItem(captureObjectCutoutItem)

    menu?.addItem(NSMenuItem.separator())

    // Recording
    let recordItem = NSMenuItem(
      title: L10n.Menu.recordScreen,
      action: #selector(recordScreenAction),
      keyEquivalent: "5"
    )
    recordItem.keyEquivalentModifierMask = [.command, .shift]
    recordItem.target = self
    recordItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
    recordItem.isEnabled = viewModel.hasPermission && !recorder.isActive
    menu?.addItem(recordItem)

    menu?.addItem(NSMenuItem.separator())

    // Tools
    let annotateItem = NSMenuItem(
      title: L10n.Actions.openAnnotate,
      action: #selector(openAnnotateAction),
      keyEquivalent: "a"
    )
    annotateItem.keyEquivalentModifierMask = [.command, .shift]
    annotateItem.target = self
    annotateItem.image = NSImage(
      systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
    annotateItem.isEnabled = true
    menu?.addItem(annotateItem)

    let editVideoItem = NSMenuItem(
      title: L10n.Menu.editVideo,
      action: #selector(editVideoAction),
      keyEquivalent: "e"
    )
    editVideoItem.keyEquivalentModifierMask = [.command, .shift]
    editVideoItem.target = self
    editVideoItem.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
    editVideoItem.isEnabled = true
    menu?.addItem(editVideoItem)

    let cloudUploadsItem = NSMenuItem(
      title: L10n.Actions.cloudUploads,
      action: #selector(openCloudUploadsAction),
      keyEquivalent: "l"
    )
    cloudUploadsItem.keyEquivalentModifierMask = [.command, .shift]
    cloudUploadsItem.target = self
    cloudUploadsItem.image = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: nil)
    cloudUploadsItem.isEnabled = CloudManager.shared.isConfigured
    menu?.addItem(cloudUploadsItem)

    let shortcutListItem = NSMenuItem(
      title: L10n.Menu.keyboardShortcuts,
      action: #selector(showShortcutListAction),
      keyEquivalent: "k"
    )
    shortcutListItem.keyEquivalentModifierMask = [.command, .shift]
    shortcutListItem.target = self
    shortcutListItem.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil)
    shortcutListItem.isEnabled = true
    menu?.addItem(shortcutListItem)

    menu?.addItem(NSMenuItem.separator())

    // Permission (if not granted)
    if !viewModel.hasPermission {
      let permissionItem = NSMenuItem(
        title: L10n.Menu.grantPermission,
        action: #selector(grantPermissionAction),
        keyEquivalent: ""
      )
      permissionItem.target = self
      permissionItem.image = NSImage(
        systemSymbolName: "lock.shield", accessibilityDescription: nil)
      permissionItem.isEnabled = true
      menu?.addItem(permissionItem)
      menu?.addItem(NSMenuItem.separator())
    }

    // Check for Updates
    let updateItem = NSMenuItem(
      title: L10n.Menu.checkForUpdates,
      action: #selector(checkForUpdatesAction),
      keyEquivalent: ""
    )
    updateItem.target = self
    updateItem.isEnabled = true
    menu?.addItem(updateItem)

    // Preferences
    let prefsItem = NSMenuItem(
      title: L10n.Menu.preferences,
      action: #selector(openPreferencesAction),
      keyEquivalent: ","
    )
    prefsItem.keyEquivalentModifierMask = .command
    prefsItem.target = self
    prefsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
    prefsItem.isEnabled = true
    menu?.addItem(prefsItem)

    menu?.addItem(NSMenuItem.separator())

    // Quit
    let quitItem = NSMenuItem(
      title: L10n.Menu.quitSnapzy,
      action: #selector(quitAction),
      keyEquivalent: "q"
    )
    quitItem.keyEquivalentModifierMask = .command
    quitItem.target = self
    quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
    quitItem.isEnabled = true
    menu?.addItem(quitItem)
  }

  // MARK: - Menu Actions

  @objc private func stopRecordingAction() {
    stopRecording()
  }

  @objc private func togglePauseRecordingAction() {
    recorder.togglePause()
  }

  @objc private func captureAreaAction() {
    viewModel?.captureArea()
  }

  @objc private func captureFullscreenAction() {
    viewModel?.captureFullscreen()
  }

  @objc private func captureScrollingAction() {
    viewModel?.captureScrolling()
  }

  @objc private func captureOCRAction() {
    viewModel?.captureOCR()
  }

  @objc private func captureObjectCutoutAction() {
    viewModel?.captureObjectCutout()
  }

  @objc private func recordScreenAction() {
    viewModel?.startRecordingFlow()
  }

  @objc private func openAnnotateAction() {
    AnnotateManager.shared.openEmptyAnnotation()
  }

  @objc private func editVideoAction() {
    VideoEditorManager.shared.openEmptyEditor()
  }

  @objc private func openCloudUploadsAction() {
    CloudUploadHistoryWindowController.shared.showWindow()
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func showShortcutListAction() {
    ShortcutOverlayManager.shared.toggle()
  }

  @objc private func grantPermissionAction() {
    viewModel?.requestPermission()
  }

  @objc private func checkForUpdatesAction() {
    UpdaterManager.shared.checkForUpdates()
  }

  @objc private func submitCrashReportAction() {
    CrashReportService.presentAlert()
    didDetectCrash = false
  }

  @objc private func openPreferencesAction() {
    openPreferencesWindow()
  }

  func openPreferencesWindow(tab: PreferencesTab? = nil) {
    if let tab {
      PreferencesNavigationState.shared.selectedTab = tab
    }
    presentPreferencesWindow()
  }

  private func presentPreferencesWindow() {
    let existingWindowNumbers = Set(NSApp.windows.map(\.windowNumber))

    // Elevate to regular app so Snapzy appears in top-left menu bar
    if !didElevateForSettings {
      NSApp.setActivationPolicy(.regular)
      didElevateForSettings = true

      // Observe when Settings window closes to revert policy
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidClose(_:)),
        name: NSWindow.willCloseNotification,
        object: nil
      )
    }

    NSApp.activate(ignoringOtherApps: true)

    // Trigger Settings scene - equivalent to SettingsLink behavior
    if #available(macOS 14.0, *) {
      if let keyEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: .command,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: ",",
        charactersIgnoringModifiers: ",",
        isARepeat: false,
        keyCode: 43
      ) {
        NSApp.mainMenu?.performKeyEquivalent(with: keyEvent)
      }
    } else {
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    schedulePreferencesWindowTracking(excludingWindowNumbers: existingWindowNumbers)
  }

  @objc private func windowDidClose(_ notification: Notification) {
    if let window = notification.object as? NSWindow, trackedPreferencesWindow === window {
      trackedPreferencesWindow = nil
      removeTrackedPreferencesWindowExclusion()
    }

    // Check if any visible windows remain (excluding status bar popover)
    let visibleWindows = NSApp.windows.filter { window in
      window.isVisible &&
      window.className != "NSStatusBarWindow" &&
      window.level == .normal
    }

    // If no visible windows, revert to accessory (menu bar only) mode
    if visibleWindows.isEmpty && didElevateForSettings {
      NSApp.setActivationPolicy(.accessory)
      didElevateForSettings = false
      NotificationCenter.default.removeObserver(
        self,
        name: NSWindow.willCloseNotification,
        object: nil
      )
    }
  }

  @objc private func quitAction() {
    NSApp.terminate(nil)
  }

  private func schedulePreferencesWindowTracking(excludingWindowNumbers existingWindowNumbers: Set<Int>) {
    pendingPreferencesWindowTrackingWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.trackPreferencesWindow(excludingWindowNumbers: existingWindowNumbers, remainingAttempts: 12)
    }
    pendingPreferencesWindowTrackingWorkItem = workItem
    DispatchQueue.main.async(execute: workItem)
  }

  private func trackPreferencesWindow(excludingWindowNumbers existingWindowNumbers: Set<Int>, remainingAttempts: Int) {
    pendingPreferencesWindowTrackingWorkItem = nil

    if let trackedPreferencesWindow, trackedPreferencesWindow.isVisible {
      syncTrackedPreferencesWindowExclusion()
      return
    }

    if let candidate = NSApp.windows.first(where: {
      $0.isVisible &&
      $0.level == .normal &&
      $0.className != "NSStatusBarWindow" &&
      !existingWindowNumbers.contains($0.windowNumber)
    }) {
      trackedPreferencesWindow = candidate
      syncTrackedPreferencesWindowExclusion()
      return
    }

    guard remainingAttempts > 1 else { return }

    let workItem = DispatchWorkItem { [weak self] in
      self?.trackPreferencesWindow(
        excludingWindowNumbers: existingWindowNumbers,
        remainingAttempts: remainingAttempts - 1
      )
    }
    pendingPreferencesWindowTrackingWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
  }

  private func syncTrackedPreferencesWindowExclusion() {
    guard let trackedPreferencesWindow, trackedPreferencesWindow.isVisible else {
      removeTrackedPreferencesWindowExclusion()
      return
    }

    let windowID = CGWindowID(trackedPreferencesWindow.windowNumber)

    guard recorder.isActive else {
      removeTrackedPreferencesWindowExclusion()
      return
    }

    guard trackedPreferencesExcludedWindowID != windowID else { return }

    let previousWindowID = trackedPreferencesExcludedWindowID
    trackedPreferencesExcludedWindowID = windowID

    Task { @MainActor [weak self] in
      guard let self else { return }
      if let previousWindowID, previousWindowID != windowID {
        await self.recorder.removeRuntimeExcludedWindow(windowID: previousWindowID)
      }
      await self.recorder.addRuntimeExcludedWindow(windowID: windowID)
    }
  }

  private func removeTrackedPreferencesWindowExclusion() {
    guard let windowID = trackedPreferencesExcludedWindowID else { return }
    trackedPreferencesExcludedWindowID = nil

    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.recorder.removeRuntimeExcludedWindow(windowID: windowID)
    }
  }
}
