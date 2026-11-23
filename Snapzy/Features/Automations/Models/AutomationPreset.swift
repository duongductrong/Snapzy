//
//  AutomationPreset.swift
//  Snapzy
//
//  Built-in automations seeded on first launch. Shortcuts ship unbound so a
//  preset never takes a combination the user already uses elsewhere.
//

import Foundation

enum AutomationPreset: String, CaseIterable {
  case quickCopy = "quick-copy"
  case cloudShare = "cloud-share"

  /// Name written to storage. Kept in English so `displayName` can tell an
  /// untouched preset (shown localized) from one the user renamed.
  var storedName: String {
    switch self {
    case .quickCopy: "Quick Copy"
    case .cloudShare: "Cloud Share"
    }
  }

  var localizedName: String {
    switch self {
    case .quickCopy: L10n.Automations.presetQuickCopy
    case .cloudShare: L10n.Automations.presetCloudShare
    }
  }

  var symbol: String {
    switch self {
    case .quickCopy: "doc.on.clipboard"
    case .cloudShare: "link"
    }
  }

  func makeAutomation() -> Automation {
    let steps: [AutomationStep] = switch self {
    case .quickCopy:
      [AutomationStep(.copyImage), AutomationStep(.notify)]
    case .cloudShare:
      [AutomationStep(.copyImage), AutomationStep(.uploadAndCopyLink(.url)), AutomationStep(.notify)]
    }
    return Automation(
      name: storedName,
      symbol: symbol,
      // Offered on Quick Access cards and History items; existing users keep their own setup.
      triggers: [.quickAccessAction, .historyAction],
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: steps,
      presetID: rawValue
    )
  }
}
