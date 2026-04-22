//
//  PreferencesNavigationState.swift
//  Snapzy
//
//  Shared navigation state for selecting Preferences tabs programmatically.
//

import Combine

enum PreferencesTab: Hashable {
  case general
  case capture
  case quickAccess
  case history
  case shortcuts
  case permissions
  case cloud
  case about
}

@MainActor
final class PreferencesNavigationState: ObservableObject {
  static let shared = PreferencesNavigationState()

  @Published var selectedTab: PreferencesTab = .general

  private init() {}
}
