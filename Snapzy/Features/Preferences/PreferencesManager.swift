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
    case .showQuickAccess: return "Show Quick Access Overlay"
    case .copyFile: return "Copy file"
    case .save: return "Save"
    case .openAnnotate: return "Open Annotate Editor"
    }
  }
}

/// Types of capture operations
enum CaptureType: String, CaseIterable, Codable {
  case screenshot
  case recording
}

/// Manager for complex preferences that require more than simple @AppStorage
@MainActor
final class PreferencesManager: ObservableObject {

  static let shared = PreferencesManager()

  // MARK: - Published State

  @Published var afterCaptureActions: [AfterCaptureAction: [CaptureType: Bool]] = [:]

  // MARK: - Private

  private let afterCaptureActionsKey = "afterCaptureActions"

  private init() {
    loadAfterCaptureActions()
  }

  // MARK: - After Capture Actions

  /// Set whether an action is enabled for a capture type
  func setAction(_ action: AfterCaptureAction, for type: CaptureType, enabled: Bool) {
    if afterCaptureActions[action] == nil {
      afterCaptureActions[action] = [:]
    }
    afterCaptureActions[action]?[type] = enabled
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

    if let data = try? JSONEncoder().encode(serializable) {
      UserDefaults.standard.set(data, forKey: afterCaptureActionsKey)
    }
  }

  private func loadAfterCaptureActions() {
    guard let data = UserDefaults.standard.data(forKey: afterCaptureActionsKey),
      let serializable = try? JSONDecoder().decode([String: [String: Bool]].self, from: data)
    else {
      // Initialize with defaults
      initializeDefaults()
      return
    }

    // Convert back to typed format
    for (actionRaw, typeDict) in serializable {
      guard let action = AfterCaptureAction(rawValue: actionRaw) else { continue }
      for (typeRaw, enabled) in typeDict {
        guard let captureType = CaptureType(rawValue: typeRaw) else { continue }
        if afterCaptureActions[action] == nil {
          afterCaptureActions[action] = [:]
        }
        afterCaptureActions[action]?[captureType] = enabled
      }
    }
  }

  private func initializeDefaults() {
    for action in AfterCaptureAction.allCases {
      afterCaptureActions[action] = [:]
      for type in CaptureType.allCases {
        afterCaptureActions[action]?[type] = defaultValue(for: action, type: type)
      }
    }
  }
}
