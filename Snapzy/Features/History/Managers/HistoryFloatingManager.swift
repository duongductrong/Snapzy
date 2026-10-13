//
//  HistoryFloatingManager.swift
//  Snapzy
//
//  State management for the floating history panel
//

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

enum HistoryCloudUploadState: Equatable {
  case uploading
  case completed
}

/// Manages the floating history panel settings and display state
@MainActor
final class HistoryFloatingManager: ObservableObject {

  static let shared = HistoryFloatingManager()

  // MARK: - Published State

  @Published var position: HistoryPanelPosition = .topCenter {
    didSet {
      UserDefaults.standard.set(position.rawValue, forKey: Keys.position)
      guard presentationMode == .compact else { return }
      panelController.updatePosition(position)
    }
  }

  @Published var isEnabled: Bool = true {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
      if !isEnabled {
        hide()
      }
    }
  }

  @Published var defaultFilter: CaptureHistoryType? = nil {
    didSet {
      if let filter = defaultFilter {
        UserDefaults.standard.set(filter.rawValue, forKey: Keys.defaultFilter)
      } else {
        UserDefaults.standard.removeObject(forKey: Keys.defaultFilter)
      }
    }
  }

  @Published var maxDisplayedItems: Int = 10 {
    didSet {
      UserDefaults.standard.set(maxDisplayedItems, forKey: Keys.maxDisplayedItems)
    }
  }

  @Published var panelScale: Double = HistoryFloatingLayout.defaultScale {
    didSet {
      let clamped = HistoryFloatingLayout.clampedScale(panelScale)
      guard clamped == panelScale else {
        panelScale = clamped
        return
      }
      UserDefaults.standard.set(panelScale, forKey: PreferencesKeys.historyFloatingScale)
      refreshPanel()
    }
  }

  @Published var autoClearDays: Int = 0 {
    didSet {
      UserDefaults.standard.set(autoClearDays, forKey: Keys.autoClearDays)
    }
  }

  @Published var toggleModeShortcut: ShortcutConfig? = nil {
    didSet {
      saveToggleModeShortcut()
    }
  }

  @Published var isToggleModeShortcutEnabled: Bool = true {
    didSet {
      UserDefaults.standard.set(isToggleModeShortcutEnabled, forKey: Keys.isToggleModeShortcutEnabled)
    }
  }

  static let defaultToggleModeShortcut = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_E),
    modifiers: UInt32(cmdKey)
  )

  @Published private(set) var presentationMode: HistoryFloatingPresentationMode = .compact
  @Published var expandedFilter: CaptureHistoryType? = nil
  @Published var expandedTimeFilter: HistoryFloatingTimeFilter = .all
  @Published var searchText: String = ""
  @Published private(set) var isPinned: Bool = false
  @Published private(set) var cloudUploadStates: [UUID: HistoryCloudUploadState] = [:]

  // MARK: - Private

  private let panelController = HistoryFloatingPanelController()
  private lazy var panelContentView = HistoryFloatingContentView(manager: self)
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  private var cloudUploadTasks: [UUID: Task<Void, Never>] = [:]
  private var cloudUploadClearTasks: [UUID: Task<Void, Never>] = [:]
  private var modalInteractionSuppressionCount = 0
  private var isModalInteractionActive: Bool {
    modalInteractionSuppressionCount > 0
  }

  private enum Keys {
    static let enabled = "history.floating.enabled"
    static let position = "history.floating.position"
    static let defaultFilter = "history.floating.defaultFilter"
    static let maxDisplayedItems = "history.floating.maxDisplayedItems"
    static let autoClearDays = "history.floating.autoClearDays"
    static let toggleModeShortcut = "history.toggleModeShortcut"
    static let isToggleModeShortcutEnabled = "history.isToggleModeShortcutEnabled"
  }

  // MARK: - Init

  private init() {
    panelController.onPanelDidResignKey = { [weak self] in
      self?.handlePanelDidResignKey()
    }
    loadSettings()
  }

  private func loadSettings() {
    isEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true

    if let positionRaw = UserDefaults.standard.string(forKey: Keys.position),
      let savedPosition = HistoryPanelPosition(rawValue: positionRaw)
    {
      position = savedPosition
    }

    if let filterRaw = UserDefaults.standard.string(forKey: Keys.defaultFilter),
      let filter = CaptureHistoryType(rawValue: filterRaw)
    {
      defaultFilter = filter
    }

    maxDisplayedItems = UserDefaults.standard.object(forKey: Keys.maxDisplayedItems) as? Int ?? 10
    autoClearDays = UserDefaults.standard.object(forKey: Keys.autoClearDays) as? Int ?? 0
    panelScale = HistoryFloatingLayout.storedScale()
    expandedFilter = defaultFilter
    loadToggleModeShortcut()
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Floating history settings loaded",
      context: [
        "enabled": isEnabled ? "true" : "false",
        "position": position.rawValue,
        "maxDisplayedItems": "\(maxDisplayedItems)",
      ]
    )
  }

  private func loadToggleModeShortcut() {
    let enabled = UserDefaults.standard.object(forKey: Keys.isToggleModeShortcutEnabled) as? Bool ?? true
    _isToggleModeShortcutEnabled = Published(initialValue: enabled)

    if let data = UserDefaults.standard.data(forKey: Keys.toggleModeShortcut),
       let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
      _toggleModeShortcut = Published(initialValue: config)
    } else {
      _toggleModeShortcut = Published(initialValue: Self.defaultToggleModeShortcut)
    }
  }

  private func saveToggleModeShortcut() {
    if let config = toggleModeShortcut {
      if let data = try? JSONEncoder().encode(config) {
        UserDefaults.standard.set(data, forKey: Keys.toggleModeShortcut)
      }
    } else {
      UserDefaults.standard.removeObject(forKey: Keys.toggleModeShortcut)
    }
  }

  func resetToggleModeShortcut() {
    toggleModeShortcut = Self.defaultToggleModeShortcut
    isToggleModeShortcutEnabled = true
  }

  // MARK: - Public Methods

  /// Toggle the floating history panel visibility
  func toggle() {
    DiagnosticLogger.shared.log(
      .info,
      .history,
      "Floating history toggled",
      context: [
        "isPresenting": panelController.isPresenting ? "true" : "false",
        "enabled": isEnabled ? "true" : "false",
      ]
    )
    if panelController.isPresenting {
      hide()
    } else {
      isEnabled ? showCompact() : showExpanded()
    }
  }

  /// Show the floating history panel
  func show() {
    guard isEnabled else {
      DiagnosticLogger.shared.log(.debug, .history, "Floating history show skipped; disabled")
      return
    }
    showCompact()
  }

  /// Toggle pinned state of the floating history panel
  func togglePin() {
    isPinned.toggle()
    panelController.updatePinnedState(isPinned)
    DiagnosticLogger.shared.log(
      .info,
      .history,
      isPinned ? "Floating history pinned" : "Floating history unpinned"
    )
  }

  /// Hide the floating history panel
  func hide() {
    isPinned = false
    panelController.updatePinnedState(false)
    removeEscapeMonitors()
    panelController.hide()
    DiagnosticLogger.shared.log(.debug, .history, "Floating history hidden")
  }

  func showCompact() {
    guard isEnabled else {
      DiagnosticLogger.shared.log(.debug, .history, "Floating history compact show skipped; disabled")
      return
    }
    presentationMode = .compact
    presentCurrentMode()
  }

  func showExpanded(initialFilter: CaptureHistoryType? = nil) {
    resetExpandedState(initialFilter: initialFilter ?? expandedFilter ?? defaultFilter)
    presentationMode = .expanded
    DiagnosticLogger.shared.log(
      .info,
      .history,
      "Floating history expanded",
      context: ["filter": (initialFilter ?? expandedFilter ?? defaultFilter)?.rawValue ?? "all"]
    )
    presentCurrentMode()
  }

  func collapse() {
    guard isEnabled else {
      DiagnosticLogger.shared.log(.debug, .history, "Floating history collapse routed to hide; disabled")
      hide()
      return
    }
    presentationMode = .compact
    DiagnosticLogger.shared.log(.debug, .history, "Floating history collapsed")
    presentCurrentMode()
  }

  func togglePresentationMode() {
    guard isEnabled else { return }
    if presentationMode == .compact {
      showExpanded()
    } else {
      collapse()
    }
  }

  /// Refresh panel content if visible
  func refreshPanel() {
    guard panelController.isVisible else { return }
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Floating history refreshed",
      context: ["mode": "\(presentationMode)"]
    )
    presentCurrentMode()
  }

  /// Check if panel is currently visible
  var isVisible: Bool {
    panelController.isVisible
  }

  func focusPanel() {
    panelController.focusPanel()
    DiagnosticLogger.shared.log(.debug, .history, "Floating history focused")
  }

  func cloudUploadState(for record: CaptureHistoryRecord) -> HistoryCloudUploadState? {
    cloudUploadStates[record.id]
  }

  func uploadToCloud(_ record: CaptureHistoryRecord) {
    guard cloudUploadStates[record.id] != .uploading else {
      DiagnosticLogger.shared.log(
        .debug,
        .cloud,
        "History cloud upload skipped; already uploading",
        context: ["fileName": record.fileName]
      )
      return
    }

    guard CloudManager.shared.isConfigured else {
      AppToastManager.shared.show(message: L10n.CloudOperation.notConfigured, style: .warning, variant: .compact)
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "History cloud upload skipped; cloud not configured",
        context: ["fileName": record.fileName]
      )
      return
    }

    let recordId = record.id
    cloudUploadClearTasks[recordId]?.cancel()
    cloudUploadStates[recordId] = .uploading

    let uploadStartTime = Date()
    DiagnosticLogger.shared.log(
      .info,
      .cloud,
      "History cloud upload started",
      context: ["fileName": record.fileName, "type": record.captureType.rawValue]
    )

    cloudUploadTasks[recordId]?.cancel()
    cloudUploadTasks[recordId] = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(record.fileURL)
        defer { fileAccess.stop() }

        guard FileManager.default.fileExists(atPath: record.filePath) else {
          throw CloudError.fileNotFound(record.fileURL)
        }

        let result = try await CloudManager.shared.upload(fileURL: record.fileURL)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        let elapsed = Date().timeIntervalSince(uploadStartTime)
        let remainingDelay = max(0, 0.6 - elapsed)
        if remainingDelay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
        }

        self.cloudUploadTasks[recordId] = nil
        self.markCloudUploadCompleted(recordId: recordId)
        SoundManager.play("Pop")
        AppToastManager.shared.show(
          message: L10n.PreferencesHistory.uploadedToCloudAndCopiedLink,
          style: .success,
          duration: 1.8,
          variant: .compact
        )
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "History cloud upload completed",
          context: [
            "fileName": record.fileName,
            "publicURL": result.publicURL.absoluteString,
          ]
        )
      } catch {
        self.cloudUploadTasks[recordId] = nil
        self.cloudUploadStates[recordId] = nil
        AppToastManager.shared.show(
          message: error.localizedDescription,
          style: .error,
          duration: 2.5,
          variant: .compact
        )
        DiagnosticLogger.shared.logError(
          .cloud,
          error,
          "History cloud upload failed",
          context: ["fileName": record.fileName, "type": record.captureType.rawValue]
        )
      }
    }
  }

  func performModalInteraction<Result>(_ action: () -> Result) -> Result {
    modalInteractionSuppressionCount += 1
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Floating history modal interaction began",
      context: ["depth": "\(modalInteractionSuppressionCount)"]
    )
    let result = action()

    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.modalInteractionSuppressionCount = max(0, self.modalInteractionSuppressionCount - 1)
        DiagnosticLogger.shared.log(
          .debug,
          .history,
          "Floating history modal interaction ended",
          context: ["depth": "\(self.modalInteractionSuppressionCount)"]
        )
        if self.panelController.isPresenting {
          self.focusPanel()
        }
      }
    }

    return result
  }

  private var preferredPanelSize: CGSize {
    HistoryFloatingLayout.panelSize(
      for: panelScale,
      mode: presentationMode,
      on: ScreenUtility.activeScreen()
    )
  }

  private var preferredPosition: HistoryPanelPosition {
    position
  }

  private var preferredCornerRadius: CGFloat {
    HistoryFloatingLayout.cornerRadius(
      for: panelScale,
      mode: presentationMode,
      on: ScreenUtility.activeScreen()
    )
  }

  private func presentCurrentMode() {
    panelController.show(
      panelContentView,
      size: preferredPanelSize,
      position: preferredPosition,
      cornerRadius: preferredCornerRadius
    )
    setupEscapeMonitors()
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Floating history presented",
      context: [
        "mode": "\(presentationMode)",
        "position": preferredPosition.rawValue,
      ]
    )
  }

  private func handlePanelDidResignKey() {
    guard !isModalInteractionActive else {
      DiagnosticLogger.shared.log(.debug, .history, "Floating history resign-key ignored during modal interaction")
      return
    }
    guard !isPinned else {
      DiagnosticLogger.shared.log(.debug, .history, "Floating history resign-key ignored while pinned")
      return
    }
    hide()
  }

  private func resetExpandedState(initialFilter: CaptureHistoryType? = nil) {
    expandedFilter = initialFilter ?? defaultFilter
    expandedTimeFilter = .all
    searchText = ""
  }

  private func markCloudUploadCompleted(recordId: UUID) {
    cloudUploadClearTasks[recordId]?.cancel()
    cloudUploadStates[recordId] = .completed
    cloudUploadClearTasks[recordId] = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      guard !Task.isCancelled else { return }
      self?.cloudUploadStates[recordId] = nil
      self?.cloudUploadClearTasks[recordId] = nil
    }
  }

  private func setupEscapeMonitors() {
    removeEscapeMonitors()

    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return event }
      guard self?.isModalInteractionActive == false else { return event }
      self?.hide()
      return nil
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard !self.isModalInteractionActive, !self.isPinned else { return }
        self.hide()
      }
    }
  }

  private func removeEscapeMonitors() {
    if let localEscapeMonitor {
      NSEvent.removeMonitor(localEscapeMonitor)
      self.localEscapeMonitor = nil
    }

    if let globalEscapeMonitor {
      NSEvent.removeMonitor(globalEscapeMonitor)
      self.globalEscapeMonitor = nil
    }
  }
}

enum HistoryFloatingPresentationMode: Equatable {
  case compact
  case expanded
}

enum HistoryFloatingTimeFilter: String, CaseIterable, Identifiable, Equatable {
  case all
  case last24Hours
  case last7Days
  case last30Days

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "Any Time"
    case .last24Hours: return "24H"
    case .last7Days: return "7D"
    case .last30Days: return "30D"
    }
  }

  func includes(_ date: Date, relativeTo now: Date = Date()) -> Bool {
    switch self {
    case .all:
      return true
    case .last24Hours:
      return date >= now.addingTimeInterval(-86_400)
    case .last7Days:
      return date >= now.addingTimeInterval(-604_800)
    case .last30Days:
      return date >= now.addingTimeInterval(-2_592_000)
    }
  }
}

enum HistoryFloatingLayout {
  static let compactBasePanelSize = CGSize(width: 920, height: 316)
  static let expandedBasePanelSize = CGSize(width: 1_040, height: 680)
  static let compactBaseCornerRadius: CGFloat = 30
  static let expandedBaseCornerRadius: CGFloat = 32
  static let defaultScale = 1.0
  static let scaleRange: ClosedRange<Double> = 0.8...1.4

  static func basePanelSize(for mode: HistoryFloatingPresentationMode) -> CGSize {
    switch mode {
    case .compact:
      return compactBasePanelSize
    case .expanded:
      return expandedBasePanelSize
    }
  }

  static func baseCornerRadius(for mode: HistoryFloatingPresentationMode) -> CGFloat {
    switch mode {
    case .compact:
      return compactBaseCornerRadius
    case .expanded:
      return expandedBaseCornerRadius
    }
  }

  static func clampedScale(_ value: Double) -> Double {
    min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
  }

  static func storedScale(userDefaults: UserDefaults = .standard) -> Double {
    clampedScale(userDefaults.object(forKey: PreferencesKeys.historyFloatingScale) as? Double ?? defaultScale)
  }

  static func effectiveScale(
    for scale: Double,
    mode: HistoryFloatingPresentationMode,
    on screen: NSScreen = ScreenUtility.activeScreen()
  ) -> CGFloat {
    let requestedScale = CGFloat(clampedScale(scale))
    let baseSize = basePanelSize(for: mode)
    let safeFrame = screen.visibleFrame.insetBy(
      dx: mode == .expanded ? 42 : 24,
      dy: mode == .expanded ? 42 : 24
    )
    let fittingScale = min(safeFrame.width / baseSize.width, safeFrame.height / baseSize.height)
    return max(0.58, min(requestedScale, fittingScale))
  }

  static func panelSize(
    for scale: Double,
    mode: HistoryFloatingPresentationMode,
    on screen: NSScreen = ScreenUtility.activeScreen()
  ) -> CGSize {
    let resolvedScale = effectiveScale(for: scale, mode: mode, on: screen)
    let baseSize = basePanelSize(for: mode)
    return CGSize(
      width: baseSize.width * resolvedScale,
      height: baseSize.height * resolvedScale
    )
  }

  static func cornerRadius(
    for scale: Double,
    mode: HistoryFloatingPresentationMode,
    on screen: NSScreen = ScreenUtility.activeScreen()
  ) -> CGFloat {
    baseCornerRadius(for: mode) * effectiveScale(for: scale, mode: mode, on: screen)
  }
}
