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
  case commandLine
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
    case .commandLine:
      return L10n.Preferences.commandLineTab
    case .cloud:
      return L10n.Preferences.cloudTab
    case .advanced:
      return L10n.Preferences.advancedTab
    case .about:
      return L10n.Preferences.aboutTab
    }
  }

  /// Layered glyph drawn duotone (silver body, `iconTint` accent) on the tab's dark squircle;
  /// each symbol needs a second layer for the accent to land on.
  var symbol: String {
    switch self {
    case .general:
      return "gearshape.fill"
    case .menuBar:
      return "menubar.dock.rectangle"
    case .capture:
      return "camera.viewfinder"
    case .annotate:
      return "pencil.and.scribble"
    case .quickAccess:
      return "square.stack.3d.up.fill"
    case .history:
      return "clock.arrow.circlepath"
    case .shortcuts:
      return "command"
    case .permissions:
      return "lock.shield.fill"
    case .commandLine:
      return "terminal.fill"
    case .cloud:
      return "icloud.and.arrow.up.fill"
    case .advanced:
      return "gearshape.2.fill"
    case .about:
      return "info.circle.fill"
    }
  }

  /// Pages that open with their own icon hero, which already names the page, so the window
  /// header stays untitled.
  var showsHero: Bool {
    self == .shortcuts
  }

  /// Extra non-displayed terms the sidebar search matches besides the localized title;
  /// `PreferencesSearchEngine` weighs them below the title.
  var searchKeywords: [String] {
    switch self {
    case .general:
      return ["startup", "login", "sound", "language", "theme", "appearance", "save location", "updates"]
    case .menuBar:
      return ["icon", "status item", "menu"]
    case .capture:
      return ["screenshot", "recording", "video", "gif", "ocr", "format", "magnifier", "audio", "microphone"]
    case .annotate:
      return ["editor", "crop", "highlighter", "drag"]
    case .quickAccess:
      return ["floating", "overlay", "card", "swipe", "pin"]
    case .history:
      return ["retention", "storage", "panel"]
    case .shortcuts:
      return ["keyboard", "hotkey", "keys"]
    case .permissions:
      return ["accessibility", "screen recording", "privacy", "microphone"]
    case .commandLine:
      return ["cli", "terminal", "agent"]
    case .cloud:
      return ["upload", "s3", "r2", "bucket"]
    case .advanced:
      return ["backup", "config", "toml", "diagnostics", "logs", "url scheme"]
    case .about:
      return ["version", "contributors", "support"]
    }
  }

  /// The sidebar list, in unlabelled groups separated by whitespace.
  /// The profile header at the top of the sidebar also opens About.
  static let groups: [[PreferencesTab]] = [
    [.general, .capture, .quickAccess, .shortcuts],
    [.annotate, .history, .menuBar, .cloud],
    [.permissions, .commandLine, .advanced],
    [.about],
  ]

  /// Every page in sidebar reading order.
  static let sidebarOrder: [PreferencesTab] = groups.flatMap { $0 }
}

/// A pending jump to a setting row; distinct per request so repeating a jump re-fires it.
struct PreferencesRevealRequest: Equatable {
  let id = UUID()
  let title: String
  let pane: String?
  /// The row is a `SettingRow` anchored by `title`; otherwise only `pane` is opened.
  let scrolls: Bool
}

@MainActor
final class PreferencesNavigationState: ObservableObject {
  static let shared = PreferencesNavigationState()

  @Published var selectedTab: PreferencesTab {
    didSet {
      UserDefaults.standard.set(selectedTab.rawValue, forKey: PreferencesTab.storageKey)
    }
  }

  /// Setting row the detail page should scroll to, set by a search jump.
  @Published private(set) var revealRequest: PreferencesRevealRequest?
  /// Title of the setting row currently flashing after a search jump.
  @Published private(set) var highlightedSetting: String?

  @Published private(set) var backStack: [PreferencesTab] = []
  @Published private(set) var forwardStack: [PreferencesTab] = []

  var canGoBack: Bool { !backStack.isEmpty }
  var canGoForward: Bool { !forwardStack.isEmpty }

  /// Header title; empty on pages whose hero already names them.
  var title: String {
    selectedTab.showsHero ? "" : selectedTab.title
  }

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

  /// Opens a search result's page, its pane if it has one, and scrolls to an anchored setting.
  func reveal(_ entry: PreferencesSearchEntry) {
    select(entry.tab)
    guard entry.anchored || entry.pane != nil else {
      revealRequest = nil
      return
    }
    revealRequest = PreferencesRevealRequest(title: entry.title, pane: entry.pane, scrolls: entry.anchored)
  }

  /// Called once the page has scrolled to `request`; flashes the row briefly.
  func didReveal(_ request: PreferencesRevealRequest) {
    guard revealRequest == request else { return }
    revealRequest = nil
    guard request.scrolls else { return }
    highlightedSetting = request.title
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
      guard self?.highlightedSetting == request.title else { return }
      self?.highlightedSetting = nil
    }
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
