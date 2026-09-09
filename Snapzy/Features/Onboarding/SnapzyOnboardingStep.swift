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
    case .meetSnapzy: return "Capture"
    case .quickAccess: return "Recording"
    case .shortcuts: return "Shortcuts"
    case .permissions: return "Permissions"
    }
  }

  var title: String {
    switch self {
    case .meetSnapzy: return "Screen Capture & Annotate"
    case .quickAccess: return "Screen Recording & Video Editor"
    case .shortcuts: return "Global Keys & Sync"
    case .permissions: return "Permissions & Privacy"
    }
  }

  var subtitle: String {
    switch self {
    case .meetSnapzy:
      return "Press ⇧⌘4 to freeze and select an area. Your capture instantly lands in a floating Quick Access card—ready to copy, save, or open in Annotate."
    case .quickAccess:
      return "Press ⇧⌘5 to frame any region. Capture system audio & microphone, trim in the timeline, and export crisp MP4 or GIF."
    case .shortcuts:
      return "Assign native macOS shortcuts to Snapzy. Keep your workflows portable with optional config.toml support."
    case .permissions:
      return "Snapzy runs entirely on your Mac. These macOS grants enable screen capture, audio recording, and global shortcuts."
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
      return "Try the complete flow: Click 'Simulate Capture' → Hover Quick Access card → Click card to open Annotate."
    case .quickAccess:
      return "Try the recording flow: Click 'Simulate ⇧⌘5' → Click 'Record' → Open Video Editor from card."
    case .shortcuts:
      return "Check for macOS shortcut conflicts and enable portable config.toml."
    case .permissions:
      return ""
    }
  }

  var tip: String {
    switch self {
    case .meetSnapzy: return "Clicking the Quick Access card directly opens the full vector Annotate window."
    case .quickAccess: return "You can pause, resume, and annotate on screen while recording video."
    case .shortcuts: return "You can customize every shortcut anytime in Preferences → Shortcuts."
    case .permissions: return "All OCR and processing happen on-device using Apple Vision."
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
    switch self {
    case .selectArea: return "Select capture area (⇧⌘4)"
    case .addAnnotation: return "Add vector annotation"
    case .captureToQuickAccess: return "Capture lands in Quick Access"
    case .openAnnotateWindow: return "Open Annotate window"
    case .selectRecordArea: return "Select record area (⇧⌘5)"
    case .recordVideo3s: return "Record 3s video clip"
    case .openVideoEditor: return "Open Video Editor from card"
    case .hoverCard: return "Hover floating card"
    case .triggerQuickAction: return "Trigger ⌘C / ⌘S quick action"
    case .checkShortcuts: return "Review shortcut configuration"
    case .grantScreenRecording: return "Allow Screen Recording"
    case .grantSaveFolder: return "Choose default save destination"
    case .grantAccessibility: return "Enable Accessibility features"
    }
  }

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
    case .selectRecordArea:       return "Select an area for screen recording."
    case .recordVideo3s:          return "Record a short 3-second video clip."
    case .openVideoEditor:        return "Open the video editor from the card."
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
