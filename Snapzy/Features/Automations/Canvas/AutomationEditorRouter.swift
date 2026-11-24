//
//  AutomationEditorRouter.swift
//  Snapzy
//
//  Both editors stay available: Settings → Automations picks which one Edit
//  and New open, and each editor can hand its current draft to the other.
//

import Foundation

enum AutomationEditorStyle: String, CaseIterable, Identifiable {
  /// The two-pane sheet: steps as a list, inspector on the right.
  case list
  /// The node canvas in its own window.
  case canvas

  var id: String { rawValue }

  var title: String {
    switch self {
    case .list: L10n.Automations.editorStyleList
    case .canvas: L10n.Automations.editorStyleCanvas
    }
  }

  var symbol: String {
    switch self {
    case .list: "list.bullet"
    case .canvas: "point.3.connected.trianglepath.dotted"
    }
  }

  static var current: AutomationEditorStyle {
    UserDefaults.standard.string(forKey: PreferencesKeys.automationsEditorStyle)
      .flatMap(AutomationEditorStyle.init(rawValue:)) ?? .list
  }
}

/// A draft the list editor should open (handed over from the canvas).
struct AutomationEditorRequest: Identifiable, Equatable {
  let automation: Automation
  let isNew: Bool
  var id: UUID { automation.id }
}

@MainActor
enum AutomationEditorRouter {
  static func openCanvas(_ automation: Automation, isNew: Bool) {
    AutomationCanvasWindowController.shared.open(automation, isNew: isNew) { draft, isNew in
      openList(draft, isNew: isNew)
    }
  }

  /// Shows Settings → Automations with the list editor on `automation`.
  static func openList(_ automation: Automation, isNew: Bool) {
    let navigation = AutomationSettingsNavigation.shared
    navigation.page = .automations
    navigation.listEditorRequest = AutomationEditorRequest(automation: automation, isNew: isNew)
    PreferencesWindowController.shared.show(tab: .automations)
  }
}
