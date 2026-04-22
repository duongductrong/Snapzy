//
//  HistoryFloatingManager.swift
//  Snapzy
//
//  State management for the floating history panel
//

import AppKit
import Combine
import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "Snapzy", category: "HistoryFloatingManager")

/// Manages the floating history panel settings and display state
@MainActor
final class HistoryFloatingManager: ObservableObject {

  static let shared = HistoryFloatingManager()

  // MARK: - Published State

  @Published var position: HistoryPanelPosition = .topCenter {
    didSet {
      UserDefaults.standard.set(position.rawValue, forKey: Keys.position)
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
      refreshPanel()
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

  // MARK: - Private

  private let panelController = HistoryFloatingPanelController()
  private var cancellable: AnyCancellable?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?

  private enum Keys {
    static let enabled = "history.floating.enabled"
    static let position = "history.floating.position"
    static let defaultFilter = "history.floating.defaultFilter"
    static let maxDisplayedItems = "history.floating.maxDisplayedItems"
    static let autoClearDays = "history.floating.autoClearDays"
  }

  // MARK: - Init

  private init() {
    panelController.onPanelDidResignKey = { [weak self] in
      self?.hide()
    }
    loadSettings()
    observeStoreChanges()
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
  }

  private func observeStoreChanges() {
    cancellable = CaptureHistoryStore.shared.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] in
        self?.refreshPanel()
      }
  }

  // MARK: - Public Methods

  /// Toggle the floating history panel visibility
  func toggle() {
    if panelController.isPresenting {
      hide()
    } else {
      show()
    }
  }

  /// Show the floating history panel
  func show() {
    guard isEnabled else {
      HistoryWindowController.shared.showWindow()
      return
    }

    let contentView = HistoryFloatingContentView(manager: self)
    panelController.show(contentView, size: preferredPanelSize, position: position)
    setupEscapeMonitors()
  }

  /// Hide the floating history panel
  func hide() {
    removeEscapeMonitors()
    panelController.hide()
  }

  /// Refresh panel content if visible
  func refreshPanel() {
    guard panelController.isVisible else { return }
    let contentView = HistoryFloatingContentView(manager: self)
    panelController.updateContent(contentView)
    panelController.updateSize(preferredPanelSize)
  }

  /// Check if panel is currently visible
  var isVisible: Bool {
    panelController.isVisible
  }

  func focusPanel() {
    panelController.focusPanel()
  }

  private var preferredPanelSize: CGSize {
    HistoryFloatingLayout.panelSize(for: panelScale)
  }

  private func setupEscapeMonitors() {
    removeEscapeMonitors()

    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return event }
      self?.hide()
      return nil
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return }
      DispatchQueue.main.async {
        self?.hide()
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

enum HistoryFloatingLayout {
  static let basePanelSize = CGSize(width: 920, height: 316)
  static let baseCornerRadius: CGFloat = 30
  static let defaultScale = 1.0
  static let scaleRange: ClosedRange<Double> = 0.8...1.4

  static func clampedScale(_ value: Double) -> Double {
    min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
  }

  static func storedScale(userDefaults: UserDefaults = .standard) -> Double {
    clampedScale(userDefaults.object(forKey: PreferencesKeys.historyFloatingScale) as? Double ?? defaultScale)
  }

  static func panelSize(for scale: Double) -> CGSize {
    let clamped = CGFloat(clampedScale(scale))
    return CGSize(
      width: basePanelSize.width * clamped,
      height: basePanelSize.height * clamped
    )
  }

  static func cornerRadius(for scale: Double) -> CGFloat {
    baseCornerRadius * CGFloat(clampedScale(scale))
  }
}
