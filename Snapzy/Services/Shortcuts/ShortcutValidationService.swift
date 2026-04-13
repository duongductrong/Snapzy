//
//  ShortcutValidationService.swift
//  Snapzy
//
//  Centralized validation rules for editable keyboard shortcuts
//

import Foundation

enum ShortcutValidationSeverity: Equatable {
  case warning
  case error
}

struct ShortcutValidationIssue: Equatable {
  let severity: ShortcutValidationSeverity
  let message: String
}

enum ShortcutValidationDecision: Equatable {
  case accept(issue: ShortcutValidationIssue?)
  case reject(issue: ShortcutValidationIssue)
}

@MainActor
final class ShortcutValidationService {

  static let shared = ShortcutValidationService()

  func validateGlobalShortcut(
    _ config: ShortcutConfig,
    for kind: GlobalShortcutKind
  ) -> ShortcutValidationDecision {
    if let conflictKind = conflictingGlobalShortcut(for: config, excluding: kind) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedBy(conflictKind.displayName)
      ))
    }

    if let conflictKind = conflictingAnnotateActionShortcut(for: config, excluding: nil) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedByInAnnotate(conflictKind.displayName)
      ))
    }

    let systemConflicts = SystemScreenshotShortcutManager.shared.conflictDescriptions(
      for: kind,
      shortcut: config
    )

    if let systemConflict = systemConflicts.first {
      return .accept(issue: ShortcutValidationIssue(
        severity: .warning,
        message: L10n.ShortcutValidation.matchesSystemConflict(systemConflict)
      ))
    }

    return .accept(issue: nil)
  }

  func validateAnnotateActionShortcut(
    _ config: ShortcutConfig,
    for kind: AnnotateActionShortcutKind
  ) -> ShortcutValidationDecision {
    if let conflictKind = conflictingAnnotateActionShortcut(for: config, excluding: kind) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedBy(conflictKind.displayName)
      ))
    }

    if let conflictKind = conflictingGlobalShortcut(for: config, excluding: nil) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedBy(conflictKind.displayName)
      ))
    }

    return .accept(issue: nil)
  }

  func validateAnnotateToolShortcut(
    _ key: Character,
    for tool: AnnotationToolType
  ) -> ShortcutValidationDecision {
    if let conflictTool = AnnotateShortcutManager.shared.conflictingTool(for: key, excluding: tool) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedBy(conflictTool.displayName)
      ))
    }

    return .accept(issue: nil)
  }

  private func conflictingGlobalShortcut(
    for config: ShortcutConfig,
    excluding excludedKind: GlobalShortcutKind?
  ) -> GlobalShortcutKind? {
    GlobalShortcutKind.allCases.first(where: {
      $0 != excludedKind
        && KeyboardShortcutManager.shared.isShortcutEnabled(for: $0)
        && KeyboardShortcutManager.shared.shortcut(for: $0) == config
    })
  }

  private func conflictingAnnotateActionShortcut(
    for config: ShortcutConfig,
    excluding excludedKind: AnnotateActionShortcutKind?
  ) -> AnnotateActionShortcutKind? {
    AnnotateActionShortcutKind.allCases.first(where: {
      $0 != excludedKind
        && AnnotateShortcutManager.shared.isActionShortcutEnabled(for: $0)
        && AnnotateShortcutManager.shared.shortcut(for: $0) == config
    })
  }

  private init() {}
}

private extension AnnotateActionShortcutKind {
  var displayName: String {
    switch self {
    case .copyAndClose:
      return L10n.ShortcutOverlay.copyAndClose
    case .togglePin:
      return L10n.ShortcutOverlay.togglePin
    case .cloudUpload:
      return L10n.ShortcutOverlay.cloudUpload
    }
  }
}
