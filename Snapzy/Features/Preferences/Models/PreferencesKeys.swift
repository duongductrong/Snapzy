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
  static let onboardingActiveStep = "onboarding.activeStep"
  static let sponsorPromptSeen = "sponsorPromptSeen"
  static let splashSkipped = "splashSkipped"
  static let splashSkipOnceAfterOnboardingRelaunch = "splash.skipOnceAfterOnboardingRelaunch"
  static let legacyLicenseCleanupCompleted = "legacyLicenseCleanupCompleted"
  static let sandboxOffMigrationCompleted = "migration.sandboxOff.completed"

  // General
  static let playSounds = "playSounds"
  static let urlSchemeEnabled = "urlSchemeEnabled"
  /// `snapzy` command line access (the CLI socket server). No dot in the key:
  /// CLIServer observes it with KVO, which treats dots as key paths.
  static let cliEnabled = "cliEnabled"
  /// JSON `[CLIApprovedCaller]`; machine-specific, never exported to config.toml.
  static let cliApprovedCallers = "cliApprovedCallers"
  static let showMenuBarIcon = "showMenuBarIcon"
  static let exportLocation = "exportLocation"
  static let exportLocationBookmark = "exportLocation.bookmark"
  static let configurationFileBookmark = "configuration.fileBookmark"
  static let configurationDirectoryBookmark = "configuration.directoryBookmark"
  static let configurationLastAppliedSignature = "configuration.lastAppliedSignature"
  static let configurationAccessOnboardingPrompted = "configuration.accessOnboardingPrompted"
  static let hideDesktopIcons = "hideDesktopIcons"
  static let hideDesktopWidgets = "hideDesktopWidgets"
  static let wallpaperDirectoryBookmark = "wallpaper.directoryBookmark"
  static let customWallpaperBookmarks = "wallpaper.customBookmarks"

  // Menu Bar
  static let menuBarItemOrder = "menuBar.itemOrder"
  static let menuBarHiddenItems = "menuBar.hiddenItems"
  static let menuBarIconStyle = "menuBar.iconStyle"
  static let menuBarShowItemIcons = "menuBar.showItemIcons"

  /// Appearance
  static let appearanceMode = "appearanceMode"
  static let useLiquidGlass = "appearance.useLiquidGlass"

  /// Updates
  static let updateChannel = "updates.channel"

  // Shortcuts
  static let shortcutsEnabled = "shortcutsEnabled"
  static let fullscreenShortcut = "fullscreenShortcut"
  static let areaShortcut = "areaShortcut"
  static let areaApplicationCaptureShortcut = "shortcuts.area.applicationCapture"
  static let recordingApplicationCaptureShortcut = "shortcuts.recording.applicationCapture"
  static let smartElementShortcut = "smartElementShortcut"
  static let shortcutListShortcut = "shortcutListShortcut"
  static let disabledGlobalShortcuts = "shortcuts.disabledGlobalActions"
  static let clearedGlobalShortcuts = "shortcuts.clearedGlobalActions"
  static let disabledAnnotateActionShortcuts = "shortcuts.disabledAnnotateActionShortcuts"
  static let disabledAnnotateToolShortcuts = "shortcuts.disabledAnnotateToolShortcuts"
  static let disabledVideoEditorActionShortcuts = "shortcuts.disabledVideoEditorActionShortcuts"

  // Screenshot
  static let screenshotFormat = "screenshot.format"
  /// `ClipboardImageContentOption` raw value: image copies with or without a file reference.
  static let clipboardImageContent = "clipboard.imageContent"
  static let screenshotFileNameTemplate = "screenshot.fileNameTemplate"
  static let screenshotIncludeOwnApp = "screenshot.includeOwnApp"
  static let screenshotShowCursor = "screenshot.showCursor"
  static let captureIncludeWindowShadow = "capture.includeWindowShadow"
  static let screenshotFreezeArea = "screenshot.freezeArea"
  static let screenshotDelayedCaptureSeconds = "screenshot.delayedCaptureSeconds"
  static let screenshotLivePassthrough = "screenshot.livePassthrough"
  static let screenshotShowSelectionAreaOverlay = "screenshot.showSelectionAreaOverlay"
  static let screenshotReverseMagnifierZoomDirection = "screenshot.reverseMagnifierZoomDirection"
  static let screenshotAutoDetectWindowUnderCursor = "screenshot.autoDetectWindowUnderCursor"
  static let screenshotAutoDetectElementUnderCursor = "screenshot.autoDetectElementUnderCursor"
  static let screenshotShowMagnifierByDefault = "screenshot.showMagnifierByDefault"
  static let screenshotShowMagnifierColorPanel = "screenshot.showMagnifierColorPanel"
  static let screenshotMagnifierSize = "screenshot.magnifierSize"
  /// Pick Color loupe zoom and size, remembered from the last session (indexes into
  /// `ColorPickerLoupe.cellSizes` / `.diameters`).
  static let colorPickerLoupeCellSizeIndex = "colorPicker.loupeCellSizeIndex"
  static let colorPickerLoupeDiameterIndex = "colorPicker.loupeDiameterIndex"
  /// `ColorPickerFormat` raw value copied when a color is picked (default HEX).
  static let colorPickerCopyFormat = "colorPicker.copyFormat"
  /// Recently picked colors, newest first, as hex strings.
  static let colorPickerRecentColors = "colorPicker.recentColors"
  /// Screen Ruler unit (`ScreenRulerUnit` raw value, default points).
  static let screenRulerUnit = "screenRuler.unit"
  /// Screen Ruler edge tolerance: smallest per-channel step (0–64) treated as an edge on
  /// noise-free UI (default 3); noisy backgrounds raise the threshold automatically.
  static let screenRulerEdgeTolerance = "screenRuler.edgeTolerance"
  static let screenshotLastAreaRect = "screenshot.lastAreaRect"
  static let scrollingCaptureShowHints = "scrollingCapture.showHints"
  static let backgroundCutoutAutoCropEnabled = "backgroundCutout.autoCropEnabled"
  static let annotateCanvasPresets = "annotate.canvasPresets.v1"
  static let annotateDefaultCanvasPresetId = "annotate.defaultCanvasPresetId.v1"
  static let annotateClipboardImageOpenBehavior = "annotate.clipboardImageOpenBehavior"
  static let annotateDefaultTool = "annotate.defaultTool"
  static let annotateRememberLastTool = "annotate.rememberLastTool"
  static let annotateLastUsedTool = "annotate.lastUsedTool"
  static let annotateCloseAfterDrag = "annotate.closeAfterDrag"
  static let annotateBringForwardAfterDrag = "annotate.bringForwardAfterDrag"
  static let annotatePrimaryColor = "annotate.primaryColor.v1"
  static let annotateParameterDefaults = "annotate.parameterDefaults.v1"
  /// Annotate AI prompt provider: "automatic", "apple", "endpoint:<uuid>" or "cli:<kind>".
  static let annotateAgentProvider = "annotateAgent.provider"
  /// Provider ids ("endpoint:<uuid>@<origin>", "cli:<kind>") the user allowed to receive screenshots.
  static let annotateAgentConsentedProviders = "annotateAgent.consentedProviders"
  /// Send the screenshot image to endpoints and agent CLIs (scene text always goes). Default on.
  static let annotateAgentSendImage = "annotateAgent.sendImage"
  /// Seconds before an agent CLI run is stopped (default 180).
  static let annotateAgentCLITimeout = "annotateAgent.cliTimeout"
  static let annotateToolParameterDefaults = "annotate.toolParameterDefaults.v1"
  static let annotateQuickPropertiesSyncEnabled = "annotate.quickPropertiesSyncEnabled"
  static let annotateCropSnapToEdgesEnabled = "annotate.cropSnapToEdgesEnabled"
  static let annotateAutoExpandCanvasEnabled = "annotate.autoExpandCanvasEnabled"
  static let annotateHighlighterTextSnappingEnabled = "annotate.highlighterTextSnappingEnabled"
  /// Annotate Measure tool unit (`MeasureUnit` raw value, default points). Edge tolerance is
  /// shared with Screen Ruler (`screenRulerEdgeTolerance`).
  static let annotateMeasureUnit = "annotate.measureUnit"
  /// Annotate Measure tool axis for click spans (`MeasureAxis` raw value, default both).
  static let annotateMeasureAxis = "annotate.measureAxis"
  /// Annotate Magnifier tool style for new loupes (JSON `MagnifierStyle`: zoom, shape,
  /// connector, shadow).
  static let annotateMagnifierStyle = "annotate.magnifierStyle"
  static let annotateCombineSaveAsEdit = "annotate.combineSaveAsEdit"
  static let annotateCustomColors = "annotate.customColors.v1"
  static let annotateFavoriteColors = "annotate.favoriteColors.v1"
  static let ocrSuccessNotificationEnabled = "ocr.successNotificationEnabled"
  static let ocrLinkDetectionEnabled = "ocr.linkDetectionEnabled"
  static let ocrSelectedModel = "ocr.selectedModel"
  static let ocrCustomModels = "ocr.customModels"
  /// Snip to Translate target language (BCP-47). Unset = ask on first use.
  static let translateTargetLanguage = "translate.targetLanguage"
  /// Snip to Translate engine: `builtin` (Apple Translation), `custom:<uuid>` or `cli:<kind>`.
  static let translateSelectedEngine = "translate.selectedEngine"
  // Per-CLI translation model override: `translate.cli.<kind>.model` (TranslationAgentCLISettings).

  // Floating Screenshot (Quick Access)
  static let floatingEnabled = "floatingScreenshot.enabled"
  static let floatingPosition = "floatingScreenshot.position"
  static let floatingAutoDismissEnabled = "floatingScreenshot.autoDismissEnabled"
  static let floatingAutoDismissDelay = "floatingScreenshot.autoDismissDelay"
  static let floatingOverlayScale = "floatingScreenshot.overlayScale"
  static let floatingDragDropEnabled = "floatingScreenshot.dragDropEnabled"
  static let floatingTwoFingerSwipeToDismissEnabled = "floatingScreenshot.twoFingerSwipeToDismissEnabled"
  static let floatingSwipeSensitivity = "floatingScreenshot.swipeSensitivity"
  static let quickAccessTrackpadSwipeMode = "quickAccess.trackpad.swipe.mode"
  static let quickAccessPinZoomMode = "quickAccess.pin.zoom.mode"
  static let quickAccessActionOrder = "quickAccess.actions.order.v1"
  static let quickAccessEnabledActions = "quickAccess.actions.enabled.v1"
  static let quickAccessKnownActions = "quickAccess.actions.known.v1"
  static let quickAccessActionSlotAssignments = "quickAccess.actions.slots.v1"
  static let quickAccessSwipeLeftAction = "quickAccess.swipe.action.left"
  static let quickAccessSwipeRightAction = "quickAccess.swipe.action.right"
  static let quickAccessHideCardWhenWindowOpen = "quickAccess.hideCardWhenWindowOpen"
  static let quickAccessAnimationStyle = "quickAccess.animationStyle"
  static let quickAccessPlaySounds = "quickAccess.playSounds"
  static let quickAccessOpenInFinderAfterSave = "quickAccess.openInFinderAfterSave"
  static let quickAccessOptimizePresets = "quickAccess.optimize.presets.v1"
  static let quickAccessOptimizeLastCustom = "quickAccess.optimize.lastCustom.v1"

  // Recording
  static let recordingFormat = "recording.format"
  static let recordingFileNameTemplate = "recording.fileNameTemplate"
  static let recordingFPS = "recording.fps"
  static let recordingQuality = "recording.quality"
  static let recordingMaxResolution = "recording.maxResolution"
  static let recordingCaptureAudio = "recording.captureAudio"
  static let recordingCaptureMicrophone = "recording.captureMicrophone"
  nonisolated static let recordingMicrophoneDeviceID = "recording.microphoneDeviceID"
  static let recordingCaptureCamera = "recording.captureCamera"
  static let recordingCameraDeviceID = "recording.cameraDeviceID"
  static let recordingCameraShape = "recording.cameraShape"
  static let recordingCameraSize = "recording.cameraSize"
  static let recordingCameraMirrored = "recording.cameraMirrored"
  static let recordingShortcut = "recordingShortcut"
  static let recordingLastAreaRect = "recording.lastAreaRect"
  static let recordingRememberLastArea = "recording.rememberLastArea"
  static let recordingOutputMode = "recording.outputMode"
  static let recordingIncludeOwnApp = "recording.includeOwnApp"
  static let recordingShowCursor = "recording.showCursor"
  /// Studio recording: cursor captured as editable data, flattened after stop. Default false.
  static let recordingStudioMode = "recording.studioMode"
  static let recordingDimNonSelectedArea = "recording.dimNonSelectedArea"
  static let recordingShowAreaBorder = "recording.showAreaBorder"
  static let recordingHighlightClicks = "recording.highlightClicks"
  static let recordingShowKeystrokes = "recording.showKeystrokes"
  static let recordingHoverBarVisible = "recording.hoverBarVisible"
  static let recordingShowTimeOnMenuBar = "recording.showTimeOnMenuBar"
  static let recordingHoverBarFrameOrigin = "recording.hoverBarFrameOrigin"
  static let videoEditorZoomTransitionDuration = "videoEditor.zoom.transitionDuration"
  /// Video Editor AI assistant layout: "sidebar" (right panel, default) or "dock" (floating over the player).
  static let videoEditorAILayout = "videoEditor.ai.layout"
  /// Speech language for new captions (BCP-47); unset = app language, then the Mac's.
  static let videoEditorCaptionLanguage = "videoEditor.captions.language"

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
  nonisolated static let diagnosticsEnabled = "diagnostics.enabled"
  static let diagnosticsRetentionDays = "diagnostics.retentionDays"
  static let diagnosticsSessionActive = "diagnostics.sessionActive"
  /// Hidden developer switch: writes scrolling-capture frame pairs that would
  /// not align to the log folder. Off unless set with `defaults write`, since
  /// the frames are raw screen content.
  static let diagnosticsDumpUnalignedScrollingFrames = "diagnostics.scrollingCapture.dumpUnalignedFrames"

  // History
  static let historyEnabled = "history.enabled"
  static let historyRetentionDays = "history.retentionDays"
  static let historyMaxCount = "history.maxCount"
  static let historyBackgroundStyle = "history.backgroundStyle"
  static let historyFloatingScale = "history.floating.scale"
  static let historyOpenOnLaunch = "history.openOnLaunch"

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
  nonisolated static let cloudUploadsFloatingPosition = "cloud.uploads.floatingPosition"
  nonisolated static let cloudShareLinkStyle = "cloud.shareLinkStyle"
  static let cloudGoogleFolderId = "cloud.google.folderId"
  /// JSON array of `CustomUploader` definitions (no secret values, only `{secret:NAME}` references).
  nonisolated static let cloudCustomUploaders = "cloud.customUploaders"
  /// UUID of the custom uploader used when the Cloud provider is `custom_http`.
  nonisolated static let cloudCustomUploaderID = "cloud.customUploaderID"

  // Automations
  /// JSON `[Automation]`.
  static let automations = "automations.items"
  /// Built-in presets were seeded once; deleting them must not re-seed.
  static let automationsSeeded = "automations.seeded"
  /// Milestone 6: the two default after-capture automations (JSON array).
  static let automationsSystemDefaults = "automations.systemDefaults"
  /// JSON `[UUID: {bookmark, path}]` of folders picked for Save to Folder steps.
  static let automationFolders = "automations.folders"
  /// Keep the Activity run log (on by default).
  static let automationsActivityLogEnabled = "automations.activityLogEnabled"
  /// Allow shell script and Apple Shortcut steps to run (off by default). Never
  /// imported from a configuration file.
  static let automationsAllowCodeSteps = "automations.allowCodeSteps"
  /// Name → Keychain account index for automation secrets (values live in the Keychain).
  static let automationSecrets = "automations.secrets"
  /// Finder service / menu bar drop: skip the picker when only one automation fits (off by default).
  static let automationsRunSingleFileTriggerDirectly = "automations.runSingleFileTriggerDirectly"
  /// Last app version that refreshed the Services menu (Finder "Run Snapzy Automation…").
  static let automationsServicesRegisteredVersion = "automations.servicesRegisteredVersion"
  /// Which editor Edit / New opens: `list` (sheet) or `canvas` (node window).
  static let automationsEditorStyle = "automations.editorStyle"
  /// Milestone 7: stop every event trigger (capture saved, image copied, folder watch). Off by default.
  static let automationsEventTriggersPaused = "automations.eventTriggersPaused"
}
