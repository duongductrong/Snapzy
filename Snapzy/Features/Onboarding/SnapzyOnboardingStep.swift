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
    case .meetSnapzy: return "The Flow"
    case .quickAccess: return "Quick Access"
    case .shortcuts: return "Shortcuts"
    case .permissions: return "Permissions"
    }
  }

  var title: String {
    switch self {
    case .meetSnapzy: return "Capture to Quick Access"
    case .quickAccess: return "Action on the Fly"
    case .shortcuts: return "Global Keys & Sync"
    case .permissions: return "Permissions & Privacy"
    }
  }

  var subtitle: String {
    switch self {
    case .meetSnapzy:
      return "Press ⇧⌘4 to freeze and select an area. Your capture instantly lands in a floating Quick Access card—ready to copy, save, or open in Annotate."
    case .quickAccess:
      return "Every screenshot or recording lands in a sleek floating card. Hover and press ⌘C to copy, ⌘S to save, or ⌘E to edit."
    case .shortcuts:
      return "Assign native macOS shortcuts to Snapzy. Keep your workflows portable with optional config.toml support."
    case .permissions:
      return "Snapzy runs entirely on your Mac. These macOS grants enable screen capture, audio recording, and global shortcuts."
    }
  }

  var symbol: String {
    switch self {
    case .meetSnapzy: return "camera.viewfinder"
    case .quickAccess: return "sparkles.rectangle.stack"
    case .shortcuts: return "keyboard"
    case .permissions: return "lock.shield"
    }
  }

  var examplePrompt: String {
    switch self {
    case .meetSnapzy:
      return "Try the complete flow: Click 'Simulate Capture' → Hover Quick Access card → Click card to open Annotate."
    case .quickAccess:
      return "Hover the floating card and press ⌘C to copy, or drag directly to another app."
    case .shortcuts:
      return "Check for macOS shortcut conflicts and enable portable config.toml."
    case .permissions:
      return ""
    }
  }

  var tip: String {
    switch self {
    case .meetSnapzy: return "Clicking the Quick Access card directly opens the full vector Annotate window."
    case .quickAccess: return "Swipe left with two fingers on any card to instantly dismiss it."
    case .shortcuts: return "You can customize every shortcut anytime in Preferences → Shortcuts."
    case .permissions: return "All OCR and processing happen on-device using Apple Vision."
    }
  }

  var challenges: [SnapzyOnboardingChallenge] {
    switch self {
    case .meetSnapzy:
      return [.selectArea, .captureToQuickAccess, .openAnnotateWindow]
    case .quickAccess:
      return [.hoverCard, .triggerQuickAction]
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
  case hoverCard
  case triggerQuickAction
  case checkShortcuts
  case grantScreenRecording
  case grantSaveFolder
  case grantAccessibility

  var id: String { rawValue }

  var label: String {
    switch self {
    case .selectArea:             return "Select an area on the screen."
    case .addAnnotation:          return "Pick an annotation tool (arrow, rect, blur)."
    case .captureToQuickAccess:   return "Capture lands in Quick Access card."
    case .openAnnotateWindow:     return "Click card to open Annotate window."
    case .hoverCard:              return "Hover over the Quick Access card."
    case .triggerQuickAction:     return "Press ⌘C to copy or ⌘E to edit."
    case .checkShortcuts:         return "Review global capture shortcuts."
    case .grantScreenRecording:   return "Allow Screen Recording."
    case .grantSaveFolder:       return "Select captures save folder."
    case .grantAccessibility:     return "Allow Accessibility (optional)."
    }
  }

  var keys: [String] {
    switch self {
    case .selectArea:             return ["⇧", "⌘", "4"]
    case .addAnnotation:          return ["A"]
    case .captureToQuickAccess:   return ["⌘S"]
    case .openAnnotateWindow:     return ["⌘E"]
    case .hoverCard:              return []
    case .triggerQuickAction:     return ["⌘C"]
    case .checkShortcuts:         return ["⇧", "⌘", "3"]
    default:                      return []
    }
  }
}
