//
//  SnapzyOnboardingStep.swift
//  Snapzy
//
//  Step models and interactive challenges for Snapzy onboarding.
//

import SwiftUI

enum SnapzyOnboardingStep: String, CaseIterable, Identifiable, Hashable {
  case meetSnapzy
  case quickAccess
  case shortcuts
  case permissions

  var id: String { rawValue }

  var stepNumber: Int {
    switch self {
    case .meetSnapzy: return 1
    case .quickAccess: return 2
    case .shortcuts: return 3
    case .permissions: return 4
    }
  }

  var shortTitle: String {
    switch self {
    case .meetSnapzy: return L10n.Onboarding.stepCaptureShortTitle
    case .quickAccess: return L10n.Onboarding.stepRecordingShortTitle
    case .shortcuts: return L10n.Onboarding.stepShortcutsShortTitle
    case .permissions: return L10n.Onboarding.stepPermissionsShortTitle
    }
  }

  var title: String {
    switch self {
    case .meetSnapzy: return L10n.Onboarding.stepCaptureTitle
    case .quickAccess: return L10n.Onboarding.stepRecordingTitle
    case .shortcuts: return L10n.Onboarding.stepShortcutsTitle
    case .permissions: return L10n.Onboarding.stepPermissionsTitle
    }
  }

  var subtitle: String {
    switch self {
    case .meetSnapzy:
      return L10n.Onboarding.stepCaptureSubtitle
    case .quickAccess:
      return L10n.Onboarding.stepRecordingSubtitle
    case .shortcuts:
      return L10n.Onboarding.stepShortcutsSubtitle
    case .permissions:
      return L10n.Onboarding.stepPermissionsSubtitle
    }
  }

  var symbol: String {
    switch self {
    case .meetSnapzy: return "camera.viewfinder"
    case .quickAccess: return "record.circle"
    case .shortcuts: return "keyboard"
    case .permissions: return "lock.shield"
    }
  }

  var examplePrompt: String {
    switch self {
    case .meetSnapzy:
      return L10n.Onboarding.stepCapturePromptReady
    case .quickAccess:
      return L10n.Onboarding.stepRecordingPromptReady
    case .shortcuts:
      return L10n.Onboarding.stepShortcutsPromptConflicts
    case .permissions:
      return ""
    }
  }

  var tip: String {
    switch self {
    case .meetSnapzy: return L10n.Onboarding.stepCaptureTip
    case .quickAccess: return L10n.Onboarding.stepRecordingTip
    case .shortcuts: return L10n.Onboarding.stepShortcutsTip
    case .permissions: return L10n.Onboarding.stepPermissionsTip
    }
  }

  var challenges: [SnapzyOnboardingChallenge] {
    switch self {
    case .meetSnapzy:
      return [.selectArea, .captureToQuickAccess, .openAnnotateWindow]
    case .quickAccess:
      return [.selectRecordArea, .recordVideo3s, .openVideoEditor]
    case .shortcuts:
      return [.checkShortcuts]
    case .permissions:
      return [.grantScreenRecording, .grantSaveFolder]
    }
  }

  var usesWideLayout: Bool { self == .permissions }
}

enum SnapzyOnboardingChallenge: String, CaseIterable, Identifiable, Hashable {
  case selectArea
  case addAnnotation
  case captureToQuickAccess
  case openAnnotateWindow
  case selectRecordArea
  case recordVideo3s
  case openVideoEditor
  case hoverCard
  case triggerQuickAction
  case checkShortcuts
  case grantScreenRecording
  case grantSaveFolder
  case grantAccessibility

  var id: String { rawValue }

  var title: String {
    label
  }

  var label: String {
    switch self {
    case .selectArea:             return L10n.Onboarding.challengeSelectArea
    case .addAnnotation:          return L10n.Onboarding.challengeAddAnnotation
    case .captureToQuickAccess:   return L10n.Onboarding.challengeCaptureToQuickAccess
    case .openAnnotateWindow:     return L10n.Onboarding.challengeOpenAnnotateWindow
    case .hoverCard:              return L10n.Onboarding.challengeHoverCard
    case .triggerQuickAction:     return L10n.Onboarding.challengeTriggerQuickAction
    case .checkShortcuts:         return L10n.Onboarding.challengeCheckShortcuts
    case .grantScreenRecording:   return L10n.Onboarding.challengeGrantScreenRecording
    case .grantSaveFolder:       return L10n.Onboarding.challengeGrantSaveFolder
    case .grantAccessibility:     return L10n.Onboarding.challengeGrantAccessibility
    case .selectRecordArea:       return L10n.Onboarding.challengeSelectRecordArea
    case .recordVideo3s:          return L10n.Onboarding.challengeRecordVideo3s
    case .openVideoEditor:        return L10n.Onboarding.challengeOpenVideoEditor
    }
  }

  var keys: [String] {
    switch self {
    case .selectArea:             return ["⇧", "⌘", "4"]
    case .addAnnotation:          return ["A"]
    case .captureToQuickAccess:   return ["⌘S"]
    case .openAnnotateWindow:     return ["⌘E"]
    case .selectRecordArea:       return ["⇧", "⌘", "5"]
    case .recordVideo3s:          return ["●"]
    case .openVideoEditor:        return ["⌘E"]
    case .hoverCard:              return []
    case .triggerQuickAction:     return ["⌘C"]
    case .checkShortcuts:         return ["⇧", "⌘", "3"]
    default:                      return []
    }
  }
}
