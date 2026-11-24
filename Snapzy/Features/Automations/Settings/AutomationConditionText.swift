//
//  AutomationConditionText.swift
//  Snapzy
//
//  Conditions as readable sentences ("App is Figma or Sketch, else skip 2
//  steps") for the step list, the inspector preview and the activity log.
//

import AppKit
import Foundation

@MainActor
enum AutomationConditionText {
  static func sentence(_ config: AutomationConditionConfig) -> String {
    let parts = config.predicates.map(describe)
    let joined = parts.isEmpty
      ? L10n.Automations.conditionAlways
      : parts.joined(separator: config.match == .all ? L10n.Automations.conditionAnd : L10n.Automations.conditionOr)
    return "\(joined) · \(otherwise(config.otherwise))"
  }

  static func otherwise(_ otherwise: AutomationConditionConfig.Otherwise) -> String {
    switch otherwise {
    case .stop: L10n.Automations.conditionElseStop
    case .skip(let count): L10n.Automations.conditionElseSkip(count)
    }
  }

  static func describe(_ predicate: AutomationPredicate) -> String {
    switch predicate {
    case .frontmostApp(let bundleIDs, let negate):
      let names = bundleIDs.isEmpty ? "…" : list(bundleIDs.map(appName(for:)))
      return negate ? L10n.Automations.conditionAppIsNot(names) : L10n.Automations.conditionAppIs(names)
    case .captureMode(let modes):
      return L10n.Automations.conditionCaptureIs(modes.isEmpty ? "…" : list(modes.map(\.displayName)))
    case .invocation(let invocations):
      return L10n.Automations.conditionStartedFrom(invocations.isEmpty ? "…" : list(invocations.map(\.displayName)))
    case .fileKind(let kinds):
      return L10n.Automations.conditionFileIs(kinds.isEmpty ? "…" : list(kinds.map(\.displayName)))
    case .pixelSize(let dimension, let comparison, let value):
      return "\(dimension.displayName) \(comparison.symbol) \(value) px"
    case .fileSize(let comparison, let bytes):
      let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
      return "\(L10n.Automations.conditionFileSize) \(comparison.symbol) \(size)"
    case .hasText(let contains):
      guard let contains, !contains.isEmpty else { return L10n.Automations.conditionHasText }
      return L10n.Automations.conditionTextContains(contains)
    case .unsupported:
      return L10n.Automations.unsupported
    }
  }

  /// "A, B or C".
  private static func list(_ items: [String]) -> String {
    guard items.count > 1, let last = items.last else { return items.first ?? "" }
    return items.dropLast().joined(separator: ", ") + L10n.Automations.conditionOr + last
  }

  /// Localized app name for a bundle id, the id itself when the app isn't installed.
  static func appName(for bundleID: String) -> String {
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
       let name = running.localizedName
    {
      return name
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    return bundleID
  }
}

extension AutomationComparison {
  var symbol: String {
    switch self {
    case .greaterThan: ">"
    case .lessThan: "<"
    }
  }
}

extension AutomationDimension {
  var displayName: String {
    switch self {
    case .width: L10n.Automations.dimensionWidth
    case .height: L10n.Automations.dimensionHeight
    case .longest: L10n.Automations.dimensionLongest
    }
  }
}

extension AutomationFileKind {
  var displayName: String {
    switch self {
    case .image: L10n.Automations.fileKindImage
    case .video: L10n.Automations.fileKindVideo
    case .gif: "GIF"
    }
  }
}

extension AutomationInvocation {
  var displayName: String {
    switch self {
    case .hotkey: L10n.Automations.invocationHotkey
    case .urlScheme: L10n.Automations.invocationURLScheme
    case .cli: L10n.Automations.invocationCLI
    case .menuBar: L10n.Automations.invocationMenuBar
    case .quickAccess: L10n.Automations.invocationQuickAccess
    case .history: L10n.Automations.invocationHistory
    case .appIntent: L10n.Automations.invocationShortcuts
    case .retry: L10n.Automations.invocationRetry
    case .finder: "Finder"
    case .menuBarDrop: L10n.Automations.invocationMenuBarDrop
    }
  }

  /// Invocations a condition can match, in menu order.
  static let conditionChoices: [AutomationInvocation] = [
    .hotkey, .menuBar, .quickAccess, .history, .finder, .menuBarDrop, .urlScheme, .cli, .appIntent,
  ]
}

extension AutomationPredicate {
  /// Label for the predicate type in the editor's menu.
  static func typeDisplayName(_ type: String) -> String {
    switch type {
    case "frontmost_app": L10n.Automations.predicateApp
    case "capture_mode": L10n.Automations.predicateCaptureMode
    case "invocation": L10n.Automations.predicateInvocation
    case "file_kind": L10n.Automations.predicateFileKind
    case "pixel_size": L10n.Automations.predicatePixelSize
    case "file_size": L10n.Automations.predicateFileSize
    case "has_text": L10n.Automations.predicateHasText
    default: L10n.Automations.unsupported
    }
  }
}
