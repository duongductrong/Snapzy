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
  private let menuBarCustomizationStore = MenuBarCustomizationStore.shared
  private let menuBarIconRenderer = MenuBarIconRenderer.shared
  private var cachedIdleStatusImage: NSImage?
  private var cachedIdleStatusStyle: MenuBarIconStyle?
  private var cachedCustomIconDate: Date?
  private lazy var recordingStopImage = makeRecordingStopImage()
  private var menu: NSMenu?
  private var didDetectCrash = false

  // Dependencies injected after setup
  private var viewModel: ScreenCaptureViewModel?
  private var updater: SPUUpdater?

  var screenCaptureViewModel: ScreenCaptureViewModel? {
    viewModel
  }

  // Track if we elevated activation policy for Settings window
  private var didElevateForSettings = false
  private weak var trackedPreferencesWindow: NSWindow?
  private var trackedPreferencesExcludedWindowID: CGWindowID?
  private var pendingPreferencesWindowTrackingWorkItem: DispatchWorkItem?

  // Processing indicator (OCR, etc.)
  private var processingSpinner: NSProgressIndicator?
  private(set) var isProcessing = false

  private init() {}

  // MARK: - Public API

  /// Setup the status bar item with required dependencies
  func setup(viewModel: ScreenCaptureViewModel, updater: SPUUpdater, didCrash: Bool = false) {
    self.viewModel = viewModel
    self.updater = updater
    self.didDetectCrash = didCrash

    syncStatusItemVisibility()
    buildMenu()
    observeRecordingState()

    // Pre-allocate area selection windows for instant activation (<150ms)
    AreaSelectionController.shared.prepareWindowPool()
    DiagnosticLogger.shared.log(
      .info,
      .ui,
      "Status bar item initialized",
      context: ["previousCrashPrompt": didCrash ? "true" : "false"]
    )
  }

  func stopRecording() {
    RecordingCoordinator.shared.stopFromStatusItem()
  }

  /// Show or hide a processing spinner on the menu bar icon (e.g. during OCR).
  /// The spinner runs on Core Animation so it stays animated even when the main thread is briefly busy.
  func setProcessing(_ active: Bool) {
    guard active != isProcessing else { return }
    isProcessing = active

    guard let button = statusItem?.button else { return }

    if active {
      // Swap to a transparent placeholder of the same size to preserve layout
      if let icon = button.image {
        let placeholder = NSImage(size: icon.size)
        placeholder.isTemplate = true
        button.image = placeholder
      }

      // Create a spinning indicator sized to match the icon
      let size: CGFloat = 16
      let spinner = NSProgressIndicator()
      spinner.style = .spinning
      spinner.controlSize = .small
      spinner.isIndeterminate = true
      spinner.isDisplayedWhenStopped = false
      spinner.frame = CGRect(
        x: (button.bounds.width - size) / 2,
        y: (button.bounds.height - size) / 2,
        width: size,
        height: size
      )
      spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
      button.addSubview(spinner)
      spinner.startAnimation(nil)
      processingSpinner = spinner

      DiagnosticLogger.shared.log(.debug, .ui, "Status bar processing indicator started")
    } else {
      processingSpinner?.stopAnimation(nil)
      processingSpinner?.removeFromSuperview()
      processingSpinner = nil

      // Restore original icon
      button.image = idleStatusImage
      DiagnosticLogger.shared.log(.debug, .ui, "Status bar processing indicator stopped")
    }
  }

  // MARK: - Private Setup

  func setMenuBarIconVisible(_ visible: Bool) {
    UserDefaults.standard.set(visible, forKey: PreferencesKeys.showMenuBarIcon)
    syncStatusItemVisibility()
  }

  var isMenuBarIconVisible: Bool {
    statusItem != nil
  }

  private func syncStatusItemVisibility() {
    let shouldShow = UserDefaults.standard.object(forKey: PreferencesKeys.showMenuBarIcon) as? Bool ?? true

    if shouldShow {
      setupStatusItem()
    } else {
      removeStatusItem()
    }
  }

  private func setupStatusItem() {
    guard statusItem == nil else {
      renderStatusItem()
      return
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(statusBarButtonClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      renderStatusItem()
    }
  }

  private func removeStatusItem() {
    guard let statusItem else { return }
    processingSpinner?.stopAnimation(nil)
    processingSpinner?.removeFromSuperview()
    processingSpinner = nil
    isProcessing = false
    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
  }

  @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    switch event.type {
    case .leftMouseUp:
      // With the hover bar hidden during recording, a left-click stops immediately
      // (macOS ⌘⇧5 parity). Right-click still opens the full menu.
      if isMenuBarActingAsStopControl {
        DiagnosticLogger.shared.log(.debug, .ui, "Status bar direct stop (hover bar hidden)")
        stopRecording()
        return
      }
      DiagnosticLogger.shared.log(.debug, .ui, "Status bar menu opened", context: ["event": "leftMouseUp"])
      showMenu()
    case .rightMouseUp:
      DiagnosticLogger.shared.log(.debug, .ui, "Status bar menu opened", context: ["event": "rightMouseUp"])
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

  // MARK: - Recording UI Preferences

  /// Whether the floating recording controls bar is shown during recording.
  /// When hidden, the menu bar becomes the primary stop control (macOS ⌘⇧5 parity).
  /// Shared source of truth with `RecordingCoordinator` via `RecordingToolbarPreferences`.
  private var isHoverBarVisible: Bool {
    RecordingToolbarPreferences.hoverBarVisible()
  }

  /// Whether the elapsed recording time is shown next to the menu bar icon. Defaults to `true`.
  private var showsRecordingTimeOnMenuBar: Bool {
    RecordingToolbarPreferences.showTimeOnMenuBar()
  }

  /// True while the menu bar item acts as the direct stop control
  /// (recording/paused AND the hover bar is hidden).
  private var isMenuBarActingAsStopControl: Bool {
    (recorder.state == .recording || recorder.state == .paused) && !isHoverBarVisible
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

    // Re-render when recording UI preferences change (e.g. toggled in Settings mid-recording).
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.scheduleRenderStatusItem()
      }
      .store(in: &cancellables)
  }

  private var isStatusItemRenderScheduled = false

  /// Coalesce bursts of UserDefaults changes (e.g. slider drags) into one
  /// status-item render per runloop (see issue #335).
  private func scheduleRenderStatusItem() {
    guard !isStatusItemRenderScheduled else { return }
    isStatusItemRenderScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      isStatusItemRenderScheduled = false
      renderStatusItem()
    }
  }

  private func renderStatusItem() {
    guard let button = statusItem?.button else { return }
    // When the hover bar is hidden during recording, the menu bar item becomes the stop
    // control and shows a distinct stop glyph (macOS ⌘⇧5 parity). Otherwise use the app icon.
    button.image = isMenuBarActingAsStopControl ? (recordingStopImage ?? idleStatusImage) : idleStatusImage
    button.contentTintColor = nil
    button.attributedTitle = statusItemAttributedTitle(for: recorder.state)
    button.toolTip = statusItemTooltip(for: recorder.state)
  }

  /// Pure decision for the menu bar title text. Empty when the time display is off or there is
  /// nothing to show. Extracted for deterministic testing of the optional-time gating.
  nonisolated static func menuBarTitleString(
    for state: RecordingState,
    duration: String,
    showTime: Bool
  ) -> String {
    guard showTime else { return "" }
    switch state {
    case .recording:
      return duration
    case .paused:
      return "|| \(duration)"
    case .idle, .preparing, .stopping:
      return ""
    }
  }

  private func statusItemAttributedTitle(for state: RecordingState) -> NSAttributedString {
    let title = Self.menuBarTitleString(
      for: state,
      duration: recorder.formattedDuration,
      showTime: showsRecordingTimeOnMenuBar
    )

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
    // When the menu bar is the stop control, tell the user a click stops the recording.
    if isMenuBarActingAsStopControl {
      return L10n.RecordingToolbar.clickToStop(recorder.formattedDuration)
    }
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

  /// Idle menu bar icon for the configured style. Cached per style + custom
  /// icon file date; recomputed when the user changes icon preferences.
  private var idleStatusImage: NSImage? {
    let style = menuBarCustomizationStore.iconStyle
    let customDate = style == .custom ? menuBarIconRenderer.customIconModificationDate : nil

    if let cachedIdleStatusImage,
       cachedIdleStatusStyle == style,
       cachedCustomIconDate == customDate {
      return cachedIdleStatusImage
    }

    let image = menuBarIconRenderer.statusImage(for: style)
    cachedIdleStatusImage = image
    cachedIdleStatusStyle = style
    cachedCustomIconDate = customDate
    return image
  }

  /// Distinct "stop" glyph shown on the menu bar item while recording with the hover bar hidden.
  /// Signals that a click stops the recording (macOS ⌘⇧5 parity).
  private func makeRecordingStopImage() -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    // Actionable a11y cue matching the icon's behavior (a click stops the recording).
    let image = NSImage(
      systemSymbolName: "stop.circle.fill",
      accessibilityDescription: L10n.RecordingToolbar.stopRecordingHint
    )?.withSymbolConfiguration(config)
    image?.isTemplate = true
    return image
  }

  // MARK: - Menu Building

  private func buildMenu() {
    menu = NSMenu()
    menu?.autoenablesItems = false

    guard let viewModel = viewModel else {
      DiagnosticLogger.shared.log(.warning, .ui, "Status bar menu requested before view model setup")
      return
    }
    let shortcutManager = KeyboardShortcutManager.shared

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

    // Customizable groups (Capture → Recording → Tools): user-ordered, hidden
    // items filtered out, separators only between non-empty groups.
    for group in MenuBarItemGroup.allCases {
      let groupItems = menuBarCustomizationStore.orderedVisibleItems(for: group).map {
        makeMenuItem(for: $0, viewModel: viewModel, shortcutManager: shortcutManager)
      }
      guard !groupItems.isEmpty else { continue }
      groupItems.forEach { menu?.addItem($0) }
      menu?.addItem(NSMenuItem.separator())
    }

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

    // What's New
    if let campaign = FeatureIntroManager.shared.getPendingCampaign() {
      let whatsNewItem = NSMenuItem(
        title: campaign.menuTitle ?? "What's New",
        action: #selector(showPendingFeatureIntroAction),
        keyEquivalent: ""
      )
      whatsNewItem.target = self
      whatsNewItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
      whatsNewItem.isEnabled = true
      menu?.addItem(whatsNewItem)
    }

    // Check for Updates (hideable, fixed position)
    if !menuBarCustomizationStore.isHidden(.checkForUpdates) {
      menu?.addItem(makeMenuItem(for: .checkForUpdates, viewModel: viewModel, shortcutManager: shortcutManager))
    }

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

  // MARK: - Menu Item Factory

  /// Builds a configured menu entry for a customizable item. Titles, icons,
  /// actions, shortcuts, and enabled states are identical to the original
  /// fixed menu regardless of user ordering or visibility.
  private func makeMenuItem(
    for kind: MenuBarItemKind,
    viewModel: ScreenCaptureViewModel,
    shortcutManager: KeyboardShortcutManager
  ) -> NSMenuItem {
    switch kind {
    case .captureArea:
      let item = NSMenuItem(
        title: L10n.Actions.captureArea,
        action: #selector(captureAreaAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .area, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .captureAreaAnnotate:
      let item = NSMenuItem(
        title: L10n.Actions.captureAreaAnnotate,
        action: #selector(captureAreaAnnotateAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .areaAnnotate, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .captureApplication:
      let item = NSMenuItem(
        title: L10n.PreferencesShortcuts.applicationCaptureTitle,
        action: #selector(captureApplicationAction),
        keyEquivalent: ""
      )
      configureOverlayMenuItem(
        item,
        base: L10n.PreferencesShortcuts.applicationCaptureTitle,
        shortcut: CaptureOverlayShortcutSettings.applicationCaptureShortcut,
        parentKind: .area,
        using: shortcutManager
      )
      item.target = self
      item.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .captureFullscreen:
      let item = NSMenuItem(
        title: L10n.Actions.captureFullscreen,
        action: #selector(captureFullscreenAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .fullscreen, using: shortcutManager)
      item.target = self
      item.image = NSImage(
        systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .captureActiveWindow:
      let item = NSMenuItem(
        title: L10n.Actions.captureActiveWindow,
        action: #selector(captureActiveWindowAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .activeWindow, using: shortcutManager)
      item.target = self
      item.image = NSImage(
        systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .scrollingCapture:
      let item = NSMenuItem(
        title: L10n.Actions.scrollingCapture,
        action: #selector(captureScrollingAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .scrollingCapture, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission && !ScrollingCaptureCoordinator.shared.isActive
      return item

    case .captureOCR:
      let item = NSMenuItem(
        title: L10n.Actions.captureTextOCR,
        action: #selector(captureOCRAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .ocr, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .captureSmartElement:
      let item = NSMenuItem(
        title: L10n.Actions.captureSmartElement,
        action: #selector(captureSmartElementAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .smartElement, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "dot.viewfinder", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission
      return item

    case .captureObjectCutout:
      let item = NSMenuItem(
        title: GlobalShortcutKind.objectCutout.displayName,
        action: #selector(captureObjectCutoutAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .objectCutout, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "person.crop.rectangle", accessibilityDescription: nil)
      if #available(macOS 14.0, *) {
        item.isEnabled = viewModel.hasPermission
      } else {
        item.isEnabled = false
      }
      return item

    case .recordScreen:
      let item = NSMenuItem(
        title: L10n.Menu.recordScreen,
        action: #selector(recordScreenAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .recording, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission && !recorder.isActive
      return item

    case .recordApplication:
      let item = NSMenuItem(
        title: L10n.PreferencesShortcuts.applicationRecordingTitle,
        action: #selector(recordApplicationAction),
        keyEquivalent: ""
      )
      configureOverlayMenuItem(
        item,
        base: L10n.PreferencesShortcuts.applicationRecordingTitle,
        shortcut: CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut,
        parentKind: .recording,
        using: shortcutManager
      )
      item.target = self
      item.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
      item.isEnabled = viewModel.hasPermission && !recorder.isActive
      return item

    case .openAnnotate:
      let item = NSMenuItem(
        title: L10n.Actions.openAnnotate,
        action: #selector(openAnnotateAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .annotate, using: shortcutManager)
      item.target = self
      item.image = NSImage(
        systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
      item.isEnabled = true
      return item

    case .combineImages:
      let item = NSMenuItem(
        title: L10n.Combine.open,
        action: #selector(openCombineImagesAction),
        keyEquivalent: ""
      )
      item.target = self
      item.image = NSImage(
        systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
      item.isEnabled = true
      return item

    case .editVideo:
      let item = NSMenuItem(
        title: L10n.Menu.editVideo,
        action: #selector(editVideoAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .videoEditor, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
      item.isEnabled = true
      return item

    case .cloudUploads:
      let item = NSMenuItem(
        title: L10n.Actions.cloudUploads,
        action: #selector(openCloudUploadsAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .cloudUploads, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: nil)
      item.isEnabled = CloudManager.shared.isConfigured
      return item

    case .openHistory:
      let item = NSMenuItem(
        title: L10n.Actions.openHistory,
        action: #selector(openHistoryAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .history, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
      item.isEnabled = true
      return item

    case .shortcutList:
      let item = NSMenuItem(
        title: L10n.Menu.keyboardShortcuts,
        action: #selector(showShortcutListAction),
        keyEquivalent: ""
      )
      applyConfiguredShortcut(item, for: .shortcutList, using: shortcutManager)
      item.target = self
      item.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil)
      item.isEnabled = true
      return item

    case .checkForUpdates:
      let item = NSMenuItem(
        title: L10n.Menu.checkForUpdates,
        action: #selector(checkForUpdatesAction),
        keyEquivalent: ""
      )
      item.target = self
      item.image = NSImage(
        systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
      item.isEnabled = true
      return item
    }
  }

  // MARK: - Menu Actions

  @objc private func stopRecordingAction() {
    logMenuAction("stopRecording", context: ["state": "\(recorder.state)"])
    stopRecording()
  }

  @objc private func togglePauseRecordingAction() {
    logMenuAction("togglePauseRecording", context: ["state": "\(recorder.state)"])
    recorder.togglePause()
  }

  @objc private func captureAreaAction() {
    logMenuAction("captureArea")
    viewModel?.captureArea()
  }

  @objc private func captureAreaAnnotateAction() {
    logMenuAction("captureAreaAnnotate")
    viewModel?.captureAreaAnnotate()
  }

  @objc private func captureApplicationAction() {
    logMenuAction("captureApplication")
    viewModel?.captureApplication()
  }

  @objc private func captureFullscreenAction() {
    logMenuAction("captureFullscreen")
    viewModel?.captureFullscreen()
  }

  @objc private func captureActiveWindowAction() {
    logMenuAction("captureActiveWindow")
    viewModel?.captureActiveWindow()
  }

  @objc private func captureScrollingAction() {
    logMenuAction("captureScrolling")
    viewModel?.captureScrolling()
  }

  @objc private func captureOCRAction() {
    logMenuAction("captureOCR")
    viewModel?.captureOCR()
  }

  @objc private func captureSmartElementAction() {
    logMenuAction("captureSmartElement")
    SmartElementCaptureController.shared.startCapture()
  }

  @objc private func captureObjectCutoutAction() {
    logMenuAction("captureObjectCutout")
    viewModel?.captureObjectCutout()
  }

  @objc private func recordScreenAction() {
    logMenuAction("recordScreen")
    viewModel?.startRecordingFlow()
  }

  @objc private func recordApplicationAction() {
    logMenuAction("recordApplication")
    viewModel?.startApplicationRecordingFlow()
  }

  @objc private func openAnnotateAction() {
    logMenuAction("openAnnotate")
    AnnotateManager.shared.openEmptyAnnotation()
  }

  @objc private func openCombineImagesAction() {
    logMenuAction("openCombineImages")
    CombineImagesCoordinator.shared.presentPicker()
  }

  @objc private func editVideoAction() {
    logMenuAction("editVideo")
    VideoEditorManager.shared.openEmptyEditor()
  }

  @objc private func openCloudUploadsAction() {
    logMenuAction(
      "openCloudUploads",
      context: ["cloudConfigured": CloudManager.shared.isConfigured ? "true" : "false"]
    )
    let didShow = CloudUploadHistoryWindowController.shared.toggleWindow()
    DiagnosticLogger.shared.log(
      .debug,
      .cloud,
      "Cloud uploads window toggled",
      context: ["shown": didShow ? "true" : "false"]
    )
    if didShow {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  @objc private func openHistoryAction() {
    logMenuAction("openHistory")
    HistoryFloatingManager.shared.toggle()
  }

  @objc private func showShortcutListAction() {
    logMenuAction("showShortcutList")
    ShortcutOverlayManager.shared.toggle()
  }

  @objc private func grantPermissionAction() {
    logMenuAction("grantPermission")
    viewModel?.requestPermission()
  }

  @objc private func checkForUpdatesAction() {
    logMenuAction("checkForUpdates")
    UpdaterManager.shared.checkForUpdates()
  }

  @objc private func showPendingFeatureIntroAction() {
    logMenuAction("showPendingFeatureIntro")
    if let campaign = FeatureIntroManager.shared.getPendingCampaign() {
      FeatureIntroManager.shared.showCampaign(campaign)
    }
  }

  @objc private func reportProblemAction() {
    logMenuAction("reportProblem")
    CrashReportService.presentAlert()
    didDetectCrash = false
  }

  @objc private func openPreferencesAction() {
    logMenuAction("openPreferences")
    openPreferencesWindow()
  }

  func openPreferencesWindow(tab: PreferencesTab? = nil) {
    if let tab {
      PreferencesNavigationState.shared.selectedTab = tab
    }
    DiagnosticLogger.shared.log(
      .info,
      .preferences,
      "Preferences window requested",
      context: ["tab": tab.map { "\($0)" } ?? "current"]
    )
    presentPreferencesWindow()
  }

  private func presentPreferencesWindow() {
    let existingWindowNumbers = Set(NSApp.windows.map(\.windowNumber))

    // Elevate to regular app so Snapzy appears in top-left menu bar
    if !didElevateForSettings {
      NSApp.setActivationPolicy(.regular)
      didElevateForSettings = true
      DiagnosticLogger.shared.log(.debug, .ui, "Activation policy elevated for preferences window")

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
    let closingWindow = notification.object as? NSWindow
    if let window = closingWindow, trackedPreferencesWindow === window {
      DiagnosticLogger.shared.log(.debug, .preferences, "Tracked preferences window closed")
      trackedPreferencesWindow = nil
      removeTrackedPreferencesWindowExclusion()
    }

    // Check if any visible windows remain (excluding status bar popover and the closing window)
    let visibleWindows = NSApp.windows.filter { window in
      window.isVisible &&
      window !== closingWindow &&
      window.className != "NSStatusBarWindow" &&
      window.level == .normal
    }

    // If no visible windows, revert to accessory (menu bar only) mode
    if visibleWindows.isEmpty && didElevateForSettings {
      NSApp.setActivationPolicy(.accessory)
      didElevateForSettings = false
      DiagnosticLogger.shared.log(.debug, .ui, "Activation policy restored after preferences closed")
      NotificationCenter.default.removeObserver(
        self,
        name: NSWindow.willCloseNotification,
        object: nil
      )
    }
  }

  @objc private func quitAction() {
    logMenuAction("quit")
    NSApp.terminate(nil)
  }

  private func logMenuAction(_ action: String, context: [String: String]? = nil) {
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Menu action invoked",
      context: {
        var values = context ?? [:]
        values["action"] = action
        return values
      }()
    )
  }

  private func applyConfiguredShortcut(
    _ item: NSMenuItem,
    for kind: GlobalShortcutKind,
    using manager: KeyboardShortcutManager
  ) {
    guard manager.isShortcutEnabled(for: kind) else {
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }

    let config = manager.shortcut(for: kind)
    guard let config, let keyEquivalent = config.menuKeyEquivalent else {
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }

    item.keyEquivalent = keyEquivalent
    item.keyEquivalentModifierMask = config.menuModifierFlags
  }

  private func configureOverlayMenuItem(
    _ item: NSMenuItem,
    base: String,
    shortcut: CaptureOverlayShortcut?,
    parentKind: GlobalShortcutKind,
    using manager: KeyboardShortcutManager
  ) {
    guard let shortcut else {
      item.title = base
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }

    if shortcut.isIndependent {
      item.title = base
      guard let config = shortcut.independentShortcutConfig,
            let keyEquivalent = config.menuKeyEquivalent else {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
        return
      }

      item.keyEquivalent = keyEquivalent
      item.keyEquivalentModifierMask = config.menuModifierFlags
      return
    }

    let childDisplay = CaptureOverlayShortcut.inlineDisplay(parts: shortcut.displayParts)
    guard manager.isShortcutEnabled(for: parentKind),
          let parentConfig = manager.shortcut(for: parentKind),
          let parentKeyEquivalent = parentConfig.menuKeyEquivalent else {
      item.title = base
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }

    item.title = "\(base) \(childDisplay)"
    item.keyEquivalent = parentKeyEquivalent
    item.keyEquivalentModifierMask = parentConfig.menuModifierFlags
  }

  private func schedulePreferencesWindowTracking(excludingWindowNumbers existingWindowNumbers: Set<Int>) {
    pendingPreferencesWindowTrackingWorkItem?.cancel()
    DiagnosticLogger.shared.log(
      .debug,
      .preferences,
      "Preferences window tracking scheduled",
      context: ["existingWindows": "\(existingWindowNumbers.count)"]
    )

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
      DiagnosticLogger.shared.log(
        .debug,
        .preferences,
        "Preferences window tracked",
        context: ["windowNumber": "\(candidate.windowNumber)"]
      )
      syncTrackedPreferencesWindowExclusion()
      return
    }

    guard remainingAttempts > 1 else {
      DiagnosticLogger.shared.log(.warning, .preferences, "Preferences window tracking timed out")
      return
    }

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
    DiagnosticLogger.shared.log(
      .debug,
      .recording,
      "Preferences window added to runtime recording exclusion",
      context: ["windowID": "\(windowID)"]
    )

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
    DiagnosticLogger.shared.log(
      .debug,
      .recording,
      "Preferences window removed from runtime recording exclusion",
      context: ["windowID": "\(windowID)"]
    )

    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.recorder.removeRuntimeExcludedWindow(windowID: windowID)
    }
  }

  #if DEBUG
    var didElevateForSettingsForTesting: Bool {
      get { didElevateForSettings }
      set { didElevateForSettings = newValue }
    }

    var trackedPreferencesWindowForTesting: NSWindow? {
      get { trackedPreferencesWindow }
      set { trackedPreferencesWindow = newValue }
    }

    func simulateWindowDidClose(notification: Notification) {
      windowDidClose(notification)
    }

    var isHoverBarVisibleForTesting: Bool { isHoverBarVisible }
    var showsRecordingTimeOnMenuBarForTesting: Bool { showsRecordingTimeOnMenuBar }
  #endif
}
