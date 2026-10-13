//
//  PreferencesNavigationState.swift
//  Snapzy
//
//  Shared navigation state for selecting Preferences tabs programmatically.
//

import Combine
import Foundation

enum PreferencesTab: String, CaseIterable, Identifiable, Hashable {
  case general
  case menuBar
  case capture
  case annotate
  case quickAccess
  case history
  case shortcuts
  case permissions
  case cloud
  case advanced
  case about

  var id: String { rawValue }

  static let storageKey = "preferences.lastSelectedTab"

  static var lastSelected: PreferencesTab {
    guard let raw = UserDefaults.standard.string(forKey: storageKey),
          let tab = PreferencesTab(rawValue: raw) else {
      return .general
    }
    return tab
  }

  var title: String {
    switch self {
    case .general:
      return L10n.Preferences.generalTab
    case .menuBar:
      return L10n.Preferences.menuBarTab
    case .capture:
      return L10n.Preferences.captureTab
    case .annotate:
      return L10n.Preferences.annotateTab
    case .quickAccess:
      return L10n.Preferences.quickAccessTab
    case .history:
      return L10n.Preferences.historyTab
    case .shortcuts:
      return L10n.Preferences.shortcutsTab
    case .permissions:
      return L10n.Preferences.permissionsTab
    case .cloud:
      return L10n.Preferences.cloudTab
    case .advanced:
      return L10n.Preferences.advancedTab
    case .about:
      return L10n.Preferences.aboutTab
    }
  }

  var symbol: String {
    switch self {
    case .general:
      return "gearshape"
    case .menuBar:
      return "menubar.rectangle"
    case .capture:
      return "camera"
    case .annotate:
      return "pencil.and.scribble"
    case .quickAccess:
      return "square.stack"
    case .history:
      return "clock.arrow.circlepath"
    case .shortcuts:
      return "keyboard"
    case .permissions:
      return "lock.shield"
    case .cloud:
      return "icloud"
    case .advanced:
      return "slider.horizontal.3"
    case .about:
      return "info.circle"
    }
  }

  /// The sidebar's running order in 4 unlabelled groups separated by natural whitespace (Ruru & macOS System Settings style).
  static let groups: [[PreferencesTab]] = [
    [.general, .menuBar, .quickAccess, .history],
    [.capture, .annotate, .cloud],
    [.shortcuts, .permissions, .advanced],
    [.about],
  ]
}

@MainActor
final class PreferencesNavigationState: ObservableObject {
  static let shared = PreferencesNavigationState()

  @Published var selectedTab: PreferencesTab {
    didSet {
      UserDefaults.standard.set(selectedTab.rawValue, forKey: PreferencesTab.storageKey)
    }
  }

  @Published private(set) var backStack: [PreferencesTab] = []
  @Published private(set) var forwardStack: [PreferencesTab] = []

  var canGoBack: Bool { !backStack.isEmpty }
  var canGoForward: Bool { !forwardStack.isEmpty }

  init(initialTab: PreferencesTab? = nil) {
    self.selectedTab = initialTab ?? PreferencesTab.lastSelected
  }

  /// User directly selects a tab (via sidebar or programmatic link).
  func select(_ tab: PreferencesTab) {
    guard tab != selectedTab else { return }
    backStack.append(selectedTab)
    forwardStack.removeAll()
    selectedTab = tab
  }

  /// Navigates back to the previous tab in history.
  func goBack() {
    guard let previous = backStack.popLast() else { return }
    forwardStack.append(selectedTab)
    selectedTab = previous
  }

  /// Navigates forward to the next tab in history.
  func goForward() {
    guard let next = forwardStack.popLast() else { return }
    backStack.append(selectedTab)
    selectedTab = next
  }
}
