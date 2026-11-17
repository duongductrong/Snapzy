//
//  VideoEditorAILayout.swift
//  Snapzy
//
//  Where the Video Editor AI assistant lives (Settings › AI):
//  - sidebar: a right panel with the whole conversation and each reply's edit steps.
//  - dock: the compact floating prompt over the player, with a one-line result pill.
//

import Foundation

enum VideoEditorAILayout: String, CaseIterable, Identifiable {
  case sidebar
  case dock

  static let defaultValue: VideoEditorAILayout = .sidebar

  var id: String { rawValue }

  static func current(_ defaults: UserDefaults = .standard) -> VideoEditorAILayout {
    defaults.string(forKey: PreferencesKeys.videoEditorAILayout).flatMap(Self.init(rawValue:)) ?? defaultValue
  }

  var title: String {
    switch self {
    case .sidebar: return L10n.VideoEditorAI.layoutSidebar
    case .dock: return L10n.VideoEditorAI.layoutDock
    }
  }
}
