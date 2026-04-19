//
//  PreferencesKeys.swift
//  Snapzy
//
//  Shared UserDefaults keys for preferences
//

import Foundation

/// Centralized keys for UserDefaults storage
enum PreferencesKeys {
  // Onboarding
  static let onboardingCompleted = "onboardingCompleted"
  static let sponsorPromptSeen = "sponsorPromptSeen"
  static let splashSkipped = "splashSkipped"
  static let splashSkipOnceAfterOnboardingRelaunch = "splash.skipOnceAfterOnboardingRelaunch"
  static let legacyLicenseCleanupCompleted = "legacyLicenseCleanupCompleted"

  // General
  static let playSounds = "playSounds"
  static let showMenuBarIcon = "showMenuBarIcon"
  static let exportLocation = "exportLocation"
  static let exportLocationBookmark = "exportLocation.bookmark"
  static let hideDesktopIcons = "hideDesktopIcons"
  static let hideDesktopWidgets = "hideDesktopWidgets"
  static let wallpaperDirectoryBookmark = "wallpaper.directoryBookmark"

  // Appearance
  static let appearanceMode = "appearanceMode"

  // Shortcuts
  static let shortcutsEnabled = "shortcutsEnabled"
  static let fullscreenShortcut = "fullscreenShortcut"
  static let areaShortcut = "areaShortcut"
  static let areaApplicationCaptureShortcut = "shortcuts.area.applicationCapture"
  static let shortcutListShortcut = "shortcutListShortcut"
  static let disabledGlobalShortcuts = "shortcuts.disabledGlobalActions"
  static let disabledAnnotateActionShortcuts = "shortcuts.disabledAnnotateActionShortcuts"
  static let disabledAnnotateToolShortcuts = "shortcuts.disabledAnnotateToolShortcuts"

  // Screenshot
  static let screenshotFormat = "screenshot.format"
  static let screenshotFileNameTemplate = "screenshot.fileNameTemplate"
  static let screenshotIncludeOwnApp = "screenshot.includeOwnApp"
  static let screenshotShowCursor = "screenshot.showCursor"
  static let scrollingCaptureShowHints = "scrollingCapture.showHints"
  static let backgroundCutoutAutoCropEnabled = "backgroundCutout.autoCropEnabled"
  static let annotateCanvasPresets = "annotate.canvasPresets.v1"

  // Floating Screenshot (Quick Access)
  static let floatingEnabled = "floatingScreenshot.enabled"
  static let floatingPosition = "floatingScreenshot.position"
  static let floatingAutoDismissEnabled = "floatingScreenshot.autoDismissEnabled"
  static let floatingAutoDismissDelay = "floatingScreenshot.autoDismissDelay"
  static let floatingOverlayScale = "floatingScreenshot.overlayScale"
  static let floatingDragDropEnabled = "floatingScreenshot.dragDropEnabled"

  // Recording
  static let recordingFormat = "recording.format"
  static let recordingFileNameTemplate = "recording.fileNameTemplate"
  static let recordingFPS = "recording.fps"
  static let recordingQuality = "recording.quality"
  static let recordingCaptureAudio = "recording.captureAudio"
  static let recordingCaptureMicrophone = "recording.captureMicrophone"
  static let recordingShortcut = "recordingShortcut"
  static let recordingLastAreaRect = "recording.lastAreaRect"
  static let recordingRememberLastArea = "recording.rememberLastArea"
  static let recordingOutputMode = "recording.outputMode"
  static let recordingIncludeOwnApp = "recording.includeOwnApp"
  static let recordingHighlightClicks = "recording.highlightClicks"
  static let recordingShowKeystrokes = "recording.showKeystrokes"
  static let videoEditorZoomTransitionDuration = "videoEditor.zoom.transitionDuration"

  // Mouse Highlight Customization
  static let mouseHighlightSize = "recording.mouseHighlight.size"
  static let mouseHighlightAnimationDuration = "recording.mouseHighlight.animationDuration"
  static let mouseHighlightColor = "recording.mouseHighlight.color"
  static let mouseHighlightOpacity = "recording.mouseHighlight.opacity"
  static let mouseHighlightRippleCount = "recording.mouseHighlight.rippleCount"

  // Keystroke Overlay Customization
  static let keystrokeFontSize = "recording.keystroke.fontSize"
  static let keystrokePosition = "recording.keystroke.position"
  static let keystrokeDisplayDuration = "recording.keystroke.displayDuration"

  // Recording Annotation Shortcuts
  static let annotationShortcutModifier = "recording.annotation.shortcutModifier"
  static let annotationShortcutHoldDuration = "recording.annotation.shortcutHoldDuration"

  // Diagnostics
  static let diagnosticsEnabled = "diagnostics.enabled"
  static let diagnosticsSessionActive = "diagnostics.sessionActive"

  // Cloud
  static let cloudProviderType = "cloud.providerType"
  static let cloudBucket = "cloud.bucket"
  static let cloudRegion = "cloud.region"
  static let cloudEndpoint = "cloud.endpoint"
  static let cloudCustomDomain = "cloud.customDomain"
  static let cloudExpireTime = "cloud.expireTime"
  static let cloudConfigured = "cloud.configured"
  static let cloudPasswordEnabled = "cloud.passwordEnabled"
  static let cloudPasswordSkipped = "cloud.passwordSkipped"
  static let cloudUsageStatsCache = "cloud.usageStatsCache"
}
