//
//  AppStatusBarController.swift
//  Snapzy
//
//  Manages the NSStatusItem for dynamic recording status and click-to-stop functionality
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
  private var menu: NSMenu?
  private var didDetectCrash = false

  // Dependencies injected after setup
  private var viewModel: ScreenCaptureViewModel?
  private var updater: SPUUpdater?

  // Track if we elevated activation policy for Settings window
  private var didElevateForSettings = false

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

  /// Stop recording from external trigger (click-to-stop)
  func stopRecording() {
    Task {
      // Properly stop recording (saves video and shows QuickAccess)
      let url = await ScreenRecordingManager.shared.stopRecording()
      if let url = url {
        NSSound(named: "Glass")?.play()
        await QuickAccessManager.shared.addVideo(url: url)
      }
      // Cleanup coordinator UI (toolbar, overlays) - cancel() now guards against double cleanup
      RecordingCoordinator.shared.cancel()
    }
  }

  // MARK: - Private Setup

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      // Use AppIcon from Assets, resized for menu bar (18pt standard height)
      if let appIcon = NSImage(named: "MenubarIcon") {
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
        resizedIcon.isTemplate = false
        button.image = resizedIcon
      }

      // Set up click action
      button.target = self
      button.action = #selector(statusBarButtonClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
  }

  @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    if recorder.isActive {
      // During recording: left-click stops, right-click shows menu
      if event.type == .leftMouseUp {
        stopRecording()
      } else {
        showMenu()
      }
    } else {
      // Not recording: always show menu
      showMenu()
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
      .sink { [weak self] state in
        self?.updateStatusIcon(for: state)
      }
      .store(in: &cancellables)
  }

  private func updateStatusIcon(for state: RecordingState) {
    guard let button = statusItem?.button else { return }

    let iconName: String
    let useTemplate: Bool

    switch state {
    case .recording:
      iconName = "record.circle.fill"
      useTemplate = false
    case .paused:
      iconName = "pause.circle.fill"
      useTemplate = false
    case .preparing, .stopping:
      iconName = "record.circle"
      useTemplate = false
    case .idle:
      iconName = "camera.aperture"
      useTemplate = true
    }

    if useTemplate {
      // Use MenubarIcon for idle state, resized for menu bar
      if let appIcon = NSImage(named: "MenubarIcon") {
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
        resizedIcon.isTemplate = false
        button.image = resizedIcon
        button.contentTintColor = nil
      }
    } else {
      // Colored icon for recording states - use hierarchical rendering with red
      let config = NSImage.SymbolConfiguration(hierarchicalColor: .systemRed)
      if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Snapzy")?
        .withSymbolConfiguration(config)
      {
        image.isTemplate = false
        button.image = image
        button.contentTintColor = nil
      }
    }
  }

  // MARK: - Menu Building

  private func buildMenu() {
    menu = NSMenu()
    menu?.autoenablesItems = false

    guard let viewModel = viewModel else { return }

    // Recording status indicator (when recording)
    if recorder.isActive {
      let stopItem = NSMenuItem(
        title: "Stop Recording (\(recorder.formattedDuration))",
        action: #selector(stopRecordingAction),
        keyEquivalent: ""
      )
      stopItem.target = self
      stopItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
      stopItem.isEnabled = true
      menu?.addItem(stopItem)
      menu?.addItem(NSMenuItem.separator())
    }

    // Capture Actions
    let captureAreaItem = NSMenuItem(
      title: "Capture Area",
      action: #selector(captureAreaAction),
      keyEquivalent: "4"
    )
    captureAreaItem.keyEquivalentModifierMask = [.command, .shift]
    captureAreaItem.target = self
    captureAreaItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
    captureAreaItem.isEnabled = viewModel.hasPermission
    menu?.addItem(captureAreaItem)

    let captureFullscreenItem = NSMenuItem(
      title: "Capture Fullscreen",
      action: #selector(captureFullscreenAction),
      keyEquivalent: "3"
    )
    captureFullscreenItem.keyEquivalentModifierMask = [.command, .shift]
    captureFullscreenItem.target = self
    captureFullscreenItem.image = NSImage(
      systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
    captureFullscreenItem.isEnabled = viewModel.hasPermission
    menu?.addItem(captureFullscreenItem)

    let captureOCRItem = NSMenuItem(
      title: "Capture Text (OCR)",
      action: #selector(captureOCRAction),
      keyEquivalent: "2"
    )
    captureOCRItem.keyEquivalentModifierMask = [.command, .shift]
    captureOCRItem.target = self
    captureOCRItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
    captureOCRItem.isEnabled = viewModel.hasPermission
    menu?.addItem(captureOCRItem)

    menu?.addItem(NSMenuItem.separator())

    // Recording
    let recordItem = NSMenuItem(
      title: "Record Screen",
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
      title: "Open Annotate",
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
      title: "Edit Video...",
      action: #selector(editVideoAction),
      keyEquivalent: "e"
    )
    editVideoItem.keyEquivalentModifierMask = [.command, .shift]
    editVideoItem.target = self
    editVideoItem.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
    editVideoItem.isEnabled = true
    menu?.addItem(editVideoItem)

    menu?.addItem(NSMenuItem.separator())

    // Permission (if not granted)
    if !viewModel.hasPermission {
      let permissionItem = NSMenuItem(
        title: "Grant Permission...",
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
      title: "Check for Updates...",
      action: #selector(checkForUpdatesAction),
      keyEquivalent: ""
    )
    updateItem.target = self
    updateItem.isEnabled = true
    menu?.addItem(updateItem)

    // Preferences
    let prefsItem = NSMenuItem(
      title: "Preferences...",
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
      title: "Quit Snapzy",
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

  @objc private func captureAreaAction() {
    viewModel?.captureArea()
  }

  @objc private func captureFullscreenAction() {
    viewModel?.captureFullscreen()
  }

  @objc private func captureOCRAction() {
    viewModel?.captureOCR()
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
  }

  @objc private func windowDidClose(_ notification: Notification) {
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
}
