//
//  PreferencesManager.swift
//  Snapzy
//
//  Centralized state management for complex preferences
//

import Combine
import Foundation

/// Actions that can be triggered after capture
enum AfterCaptureAction: String, CaseIterable, Codable {
  case showQuickAccess = "showQuickAccess"
  case copyFile = "copyFile"
  case save = "save"
  case openAnnotate = "openAnnotate"

  var displayName: String {
    switch self {
    case .showQuickAccess: return L10n.Actions.showQuickAccessOverlay
    case .copyFile: return L10n.AfterCapture.copyFileAction
    case .save: return L10n.AfterCapture.saveAction
    case .openAnnotate: return L10n.AfterCapture.openAnnotateAction
    }
  }
}

/// Types of capture operations
enum CaptureType: String, CaseIterable, Codable {
  case screenshot
  case recording

  var displayName: String {
    switch self {
    case .screenshot:
      return L10n.CaptureKind.screenshot
    case .recording:
      return L10n.CaptureKind.recording
    }
  }
}

/// Behavior for importing clipboard images when opening an empty Annotate editor.
enum AnnotateClipboardImageBehavior: String, CaseIterable, Identifiable {
  case ask = "ask"
  case loadAutomatically = "loadAutomatically"
  case doNothing = "doNothing"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ask:
      return L10n.PreferencesAnnotate.clipboardAsk
    case .loadAutomatically:
      return L10n.PreferencesAnnotate.clipboardLoadAutomatically
    case .doNothing:
      return L10n.PreferencesAnnotate.clipboardDoNothing
    }
  }

  static func stored(userDefaults: UserDefaults = .standard) -> Self {
    guard let rawValue = userDefaults.string(forKey: PreferencesKeys.annotateClipboardImageOpenBehavior),
          let behavior = Self(rawValue: rawValue) else {
      return .ask
    }
    return behavior
  }

  func persist(to userDefaults: UserDefaults = .standard) {
    userDefaults.set(rawValue, forKey: PreferencesKeys.annotateClipboardImageOpenBehavior)
  }
}

enum AnnotateQuickPropertiesSyncPreference {
  static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
    userDefaults.object(forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled) as? Bool ?? true
  }
}

enum AnnotateToolPreference {
  static let fallbackTool: AnnotationToolType = .selection

  static func defaultTool(userDefaults: UserDefaults = .standard) -> AnnotationToolType {
    storedTool(forKey: PreferencesKeys.annotateDefaultTool, userDefaults: userDefaults) ?? fallbackTool
  }

  static func remembersLastTool(userDefaults: UserDefaults = .standard) -> Bool {
    userDefaults.object(forKey: PreferencesKeys.annotateRememberLastTool) as? Bool ?? false
  }

  static func initialTool(userDefaults: UserDefaults = .standard) -> AnnotationToolType {
    guard remembersLastTool(userDefaults: userDefaults) else {
      return defaultTool(userDefaults: userDefaults)
    }
    return storedTool(forKey: PreferencesKeys.annotateLastUsedTool, userDefaults: userDefaults)
      ?? defaultTool(userDefaults: userDefaults)
  }

  static func remember(_ tool: AnnotationToolType, userDefaults: UserDefaults = .standard) {
    guard remembersLastTool(userDefaults: userDefaults),
          AnnotationToolType.inlineAnnotateTools.contains(tool) else { return }
    userDefaults.set(tool.rawValue, forKey: PreferencesKeys.annotateLastUsedTool)
  }

  private static func storedTool(
    forKey key: String,
    userDefaults: UserDefaults
  ) -> AnnotationToolType? {
    guard let rawValue = userDefaults.string(forKey: key),
          let tool = AnnotationToolType(rawValue: rawValue),
          AnnotationToolType.inlineAnnotateTools.contains(tool) else { return nil }
    return tool
  }
}

/// When enabled (default), stitching extra images into a capture-origin annotate session
/// saves the combined render as a normal edit of the current image (silent, no dialog).
/// When disabled, the "Save Combined Image" confirmation dialog is shown instead.
enum CombineSaveAsEditPreference {
  static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
    userDefaults.object(forKey: PreferencesKeys.annotateCombineSaveAsEdit) as? Bool ?? true
  }
}

/// Manager for complex preferences that require more than simple @AppStorage
@MainActor
final class PreferencesManager: ObservableObject {

  static let shared = PreferencesManager()

  // MARK: - Published State

  @Published var afterCaptureActions: [AfterCaptureAction: [CaptureType: Bool]] = [:]

  // MARK: - Private

  private let afterCaptureActionsKey = "afterCaptureActions"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    loadAfterCaptureActions()
  }

  // MARK: - After Capture Actions

  /// Set whether an action is enabled for a capture type
  func setAction(_ action: AfterCaptureAction, for type: CaptureType, enabled: Bool) {
    if afterCaptureActions[action] == nil {
      afterCaptureActions[action] = [:]
    }
    afterCaptureActions[action]?[type] = enabled
    DiagnosticLogger.shared.log(
      .info,
      .preferences,
      "After-capture action changed",
      context: [
        "action": action.rawValue,
        "captureType": type.rawValue,
        "enabled": enabled ? "true" : "false",
      ]
    )
    saveAfterCaptureActions()
  }

  /// Check if an action is enabled for a capture type
  func isActionEnabled(_ action: AfterCaptureAction, for type: CaptureType) -> Bool {
    afterCaptureActions[action]?[type] ?? defaultValue(for: action, type: type)
  }

  /// Default values for after-capture actions
  private func defaultValue(for action: AfterCaptureAction, type: CaptureType) -> Bool {
    switch action {
    case .showQuickAccess, .save, .copyFile:
      return true
    case .openAnnotate:
      // Opt-in: disabled by default, only for screenshots
      return false
    }
  }

  // MARK: - Persistence

  private func saveAfterCaptureActions() {
    // Convert to serializable format
    var serializable: [String: [String: Bool]] = [:]
    for (action, typeDict) in afterCaptureActions {
      var innerDict: [String: Bool] = [:]
      for (captureType, enabled) in typeDict {
        innerDict[captureType.rawValue] = enabled
      }
      serializable[action.rawValue] = innerDict
    }

    do {
      let data = try JSONEncoder().encode(serializable)
      defaults.set(data, forKey: afterCaptureActionsKey)
    } catch {
      DiagnosticLogger.shared.logError(
        .preferences,
        error,
        "Failed to save after-capture actions",
        context: ["actionCount": "\(afterCaptureActions.count)"]
      )
    }
  }

  private func loadAfterCaptureActions() {
    guard let data = defaults.data(forKey: afterCaptureActionsKey) else {
      initializeDefaults()
      return
    }

    let serializable: [String: [String: Bool]]
    do {
      serializable = try JSONDecoder().decode([String: [String: Bool]].self, from: data)
    } catch {
      DiagnosticLogger.shared.logError(
        .preferences,
        error,
        "Failed to decode after-capture actions; using defaults",
        context: ["dataBytes": "\(data.count)"]
      )
      initializeDefaults()
      return
    }

    // Convert back to typed format
    for (actionRaw, typeDict) in serializable {
      guard let action = AfterCaptureAction(rawValue: actionRaw) else {
        DiagnosticLogger.shared.log(
          .warning,
          .preferences,
          "Unknown after-capture action ignored",
          context: ["action": actionRaw]
        )
        continue
      }
      for (typeRaw, enabled) in typeDict {
        guard let captureType = CaptureType(rawValue: typeRaw) else {
          DiagnosticLogger.shared.log(
            .warning,
            .preferences,
            "Unknown after-capture capture type ignored",
            context: ["captureType": typeRaw]
          )
          continue
        }
        if afterCaptureActions[action] == nil {
          afterCaptureActions[action] = [:]
        }
        afterCaptureActions[action]?[captureType] = enabled
      }
    }
    DiagnosticLogger.shared.log(
      .debug,
      .preferences,
      "After-capture actions loaded",
      context: ["actionCount": "\(afterCaptureActions.count)"]
    )
  }

  private func initializeDefaults() {
    for action in AfterCaptureAction.allCases {
      afterCaptureActions[action] = [:]
      for type in CaptureType.allCases {
        afterCaptureActions[action]?[type] = defaultValue(for: action, type: type)
      }
    }
    DiagnosticLogger.shared.log(.debug, .preferences, "After-capture action defaults initialized")
  }
}
