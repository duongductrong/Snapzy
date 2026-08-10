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
    _ config: ShortcutConfig?,
    for kind: GlobalShortcutKind
  ) -> ShortcutValidationDecision {
    guard let config else { return .accept(issue: nil) }

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
    _ config: ShortcutConfig?,
    for kind: AnnotateActionShortcutKind
  ) -> ShortcutValidationDecision {
    guard let config else { return .accept(issue: nil) }

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

  /// Quick Access card actions live in their own namespace: they are only
  /// registered while a card is hovered, so they may reuse Annotate keys. They do
  /// shadow global shortcuts during hover, which is a warning rather than a block.
  func validateQuickAccessActionShortcut(
    _ config: ShortcutConfig?,
    for action: QuickAccessActionKind
  ) -> ShortcutValidationDecision {
    guard let config else { return .accept(issue: nil) }

    if QuickAccessActionShortcutStore.containsFunctionModifier(config) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.quickAccessFnUnsupported
      ))
    }

    guard QuickAccessActionShortcutStore.hasRequiredModifier(config) else {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.quickAccessModifierRequired
      ))
    }

    if let conflictAction = conflictingQuickAccessActionShortcut(for: config, excluding: action) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedBy(conflictAction.settingsTitle)
      ))
    }

    if let conflictKind = conflictingGlobalShortcut(for: config, excluding: nil) {
      return .accept(issue: ShortcutValidationIssue(
        severity: .warning,
        message: L10n.ShortcutValidation.quickAccessShadowsGlobal(conflictKind.displayName)
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

  func validateCaptureOverlayShortcut(
    _ shortcut: CaptureOverlayShortcut?,
    for kind: CaptureOverlayShortcutKind
  ) -> ShortcutValidationDecision {
    guard let shortcut else { return .accept(issue: nil) }
    guard let config = shortcut.independentShortcutConfig else {
      return .accept(issue: nil)
    }

    if let conflictKind = conflictingGlobalShortcut(for: config, excluding: nil) {
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

    if let conflictKind = conflictingCaptureOverlayShortcut(for: config, excluding: kind) {
      return .reject(issue: ShortcutValidationIssue(
        severity: .error,
        message: L10n.ShortcutValidation.alreadyUsedBy(conflictKind.displayName)
      ))
    }

    let systemConflicts = SystemScreenshotShortcutManager.shared.conflictDescriptions(
      for: kind.systemConflictKind,
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

  private func conflictingQuickAccessActionShortcut(
    for config: ShortcutConfig,
    excluding excludedAction: QuickAccessActionKind
  ) -> QuickAccessActionKind? {
    QuickAccessActionKind.allCases.first(where: {
      $0 != excludedAction
        && QuickAccessActionShortcutStore.shared.isEnabled(for: $0)
        && QuickAccessActionShortcutStore.shared.shortcut(for: $0) == config
    })
  }

  private func conflictingCaptureOverlayShortcut(
    for config: ShortcutConfig,
    excluding excludedKind: CaptureOverlayShortcutKind
  ) -> CaptureOverlayShortcutKind? {
    [CaptureOverlayShortcutKind.applicationCapture, .applicationRecording].first(where: {
      $0 != excludedKind
        && CaptureOverlayShortcutSettings.shortcut(for: $0)?.independentShortcutConfig == config
    })
  }

  private init() {}
}

private extension CaptureOverlayShortcutKind {
  var systemConflictKind: GlobalShortcutKind {
    switch self {
    case .applicationCapture:
      return .area
    case .applicationRecording:
      return .recording
    }
  }
}

private extension AnnotateActionShortcutKind {
  var displayName: String {
    switch self {
    case .copyAndClose:
      return L10n.ShortcutOverlay.copyAndClose
    case .toggleSidebar:
      return L10n.AnnotateUI.toggleSidebar
    case .togglePin:
      return L10n.ShortcutOverlay.togglePin
    case .cloudUpload:
      return L10n.ShortcutOverlay.cloudUpload
    case .autoRedactSensitiveData:
      return L10n.ShortcutOverlay.autoRedactSensitiveData
    }
  }
}
