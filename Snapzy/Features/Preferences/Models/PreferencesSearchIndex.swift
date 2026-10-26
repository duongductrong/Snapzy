//
//  PreferencesSearchIndex.swift
//  Snapzy
//
//  Searchable catalog of individual settings, so the sidebar search can reach rows inside pages.
//  Keep in sync with the page views: `title` must equal the row's displayed title, which is
//  also the row's scroll anchor.
//

import Foundation

extension PreferencesSearchEntry {
  /// Every searchable setting, in page order. Built on demand so it follows the app language.
  static func catalog() -> [PreferencesSearchEntry] {
    general + menuBar + capture + annotate + quickAccess + history + shortcuts
      + permissions + commandLine + cloud + advanced + about
  }

  // MARK: - General

  private static var general: [PreferencesSearchEntry] {
    let startup = L10n.PreferencesGeneral.startupSection
    let appearance = L10n.PreferencesGeneral.appearanceSection
    let storage = L10n.PreferencesGeneral.storageSection
    let updates = L10n.PreferencesGeneral.updatesSection
    let help = L10n.PreferencesGeneral.helpSection
    let bugReportAddress = CrashReportService.bugReportURL.absoluteString
      .replacingOccurrences(of: "https://", with: "")
    return [
      .init(.general, section: startup, title: L10n.PreferencesGeneral.startAtLoginTitle,
            detail: L10n.PreferencesGeneral.startAtLoginDescription, keywords: ["boot", "launch", "autostart"]),
      .init(.general, section: startup, title: L10n.PreferencesGeneral.playSoundsTitle,
            detail: L10n.PreferencesGeneral.playSoundsDescription, keywords: ["audio", "mute", "shutter"]),
      .init(.general, section: startup, title: L10n.PreferencesGeneral.menuBarIconTitle,
            detail: L10n.PreferencesGeneral.menuBarIconDescription, keywords: ["status bar", "tray", "hide"]),
      .init(.general, section: appearance, title: L10n.PreferencesGeneral.languageTitle,
            detail: L10n.PreferencesGeneral.languageDescription, keywords: ["locale", "localization", "translation"]),
      .init(.general, section: appearance, title: L10n.PreferencesGeneral.themeTitle,
            detail: L10n.PreferencesGeneral.themeDescription, keywords: ["dark mode", "light mode", "appearance"]),
      .init(.general, section: appearance, title: L10n.PreferencesGeneral.liquidGlassTitle,
            detail: L10n.PreferencesGeneral.liquidGlassDescription, keywords: ["blur", "transparency", "translucent"]),
      .init(.general, section: storage, title: L10n.PreferencesGeneral.saveLocationTitle,
            keywords: ["folder", "export", "directory", "path"]),
      .init(.general, section: updates, title: L10n.PreferencesGeneral.checkAutomaticallyTitle,
            detail: L10n.PreferencesGeneral.checkAutomaticallyDescription, keywords: ["updates", "sparkle"]),
      .init(.general, section: updates, title: L10n.PreferencesGeneral.downloadAutomaticallyTitle,
            detail: L10n.PreferencesGeneral.downloadAutomaticallyDescription, keywords: ["updates", "install"]),
      .init(.general, section: updates, title: L10n.PreferencesGeneral.lastCheckedTitle,
            keywords: ["updates"]),
      .init(.general, section: help, title: L10n.PreferencesGeneral.restartOnboardingTitle,
            detail: L10n.PreferencesGeneral.restartOnboardingDescription, keywords: ["welcome", "setup", "tutorial"]),
      .init(.general, section: help, title: L10n.PreferencesGeneral.reportIssueTitle,
            detail: L10n.PreferencesGeneral.reportIssueDescription(bugReportAddress),
            keywords: ["bug", "feedback", "crash", "logs"]),
    ]
  }

  // MARK: - Menu Bar

  private static var menuBar: [PreferencesSearchEntry] {
    let icon = L10n.PreferencesMenuBar.iconSection
    var entries: [PreferencesSearchEntry] = [
      .init(.menuBar, section: icon, title: icon,
            detail: L10n.PreferencesMenuBar.iconSectionDescription,
            keywords: ["status bar", "custom", "png"], anchored: false),
    ]
    for group in MenuBarItemGroup.allCases {
      let section = menuBarGroupTitle(group)
      entries += MenuBarItemKind.allCases
        .filter { $0.group == group }
        .map {
          PreferencesSearchEntry(.menuBar, section: section, title: $0.settingsTitle,
                                 keywords: ["menu item"], anchored: false)
        }
    }
    entries += [
      .init(.menuBar, section: L10n.PreferencesMenuBar.appSection,
            title: MenuBarItemKind.checkForUpdates.settingsTitle, keywords: ["menu item"]),
      .init(.menuBar, section: nil, title: L10n.PreferencesMenuBar.resetButton,
            detail: L10n.PreferencesMenuBar.itemsDescription, keywords: ["menu items", "reorder"], anchored: false),
    ]
    return entries
  }

  private static func menuBarGroupTitle(_ group: MenuBarItemGroup) -> String {
    switch group {
    case .capture: return L10n.PreferencesMenuBar.captureSection
    case .recording: return L10n.PreferencesMenuBar.recordingSection
    case .tools: return L10n.PreferencesMenuBar.toolsSection
    }
  }

  // MARK: - Capture

  private static var capture: [PreferencesSearchEntry] {
    // Raw values of `CaptureSettingsPane`, which shows one segment at a time.
    captureGeneral.map { $0.inPane("general") }
      + captureScreenshot.map { $0.inPane("screenshot") }
      + captureRecording.map { $0.inPane("recording") }
      + captureOCR.map { $0.inPane("ocr") }
  }

  private static var captureGeneral: [PreferencesSearchEntry] {
    let appWindows = L10n.PreferencesCapture.appWindowsSection
    let desktop = L10n.PreferencesCapture.desktopSection
    let overlay = L10n.PreferencesCapture.overlaySection
    let magnifier = L10n.PreferencesCapture.magnifierZoomSection
    let naming = L10n.PreferencesCapture.outputNamingSection
    let afterCapture = L10n.PreferencesCapture.afterCaptureSection
    return [
      .init(.capture, section: appWindows, title: L10n.PreferencesCapture.includeInScreenshotsTitle,
            detail: L10n.PreferencesCapture.includeInScreenshotsDescription, keywords: ["snapzy windows", "exclude"]),
      .init(.capture, section: appWindows, title: L10n.PreferencesCapture.includeInRecordingsTitle,
            detail: L10n.PreferencesCapture.includeInRecordingsDescription, keywords: ["snapzy windows", "exclude"]),
      .init(.capture, section: desktop, title: L10n.PreferencesCapture.hideDesktopIconsTitle,
            detail: L10n.PreferencesCapture.hideDesktopIconsDescription, keywords: ["clean", "clutter", "files"]),
      .init(.capture, section: desktop, title: L10n.PreferencesCapture.hideDesktopWidgetsTitle,
            detail: L10n.PreferencesCapture.hideDesktopWidgetsDescription, keywords: ["clean", "clutter"]),
      .init(.capture, section: overlay, title: L10n.PreferencesCapture.showSelectionAreaOverlayTitle,
            detail: L10n.PreferencesCapture.showSelectionAreaOverlayDescription, keywords: ["crosshair", "dimensions"]),
      .init(.capture, section: overlay, title: L10n.PreferencesCapture.autoDetectWindowUnderCursorTitle,
            detail: L10n.PreferencesCapture.autoDetectWindowUnderCursorDescription, keywords: ["snapping", "hover"]),
      .init(.capture, section: overlay, title: L10n.PreferencesCapture.autoDetectElementUnderCursorTitle,
            detail: L10n.PreferencesCapture.autoDetectElementUnderCursorDescription, keywords: ["smart", "ui"]),
      .init(.capture, section: magnifier, title: L10n.PreferencesCapture.showMagnifierByDefaultTitle,
            detail: L10n.PreferencesCapture.showMagnifierByDefaultDescription, keywords: ["loupe", "zoom"]),
      .init(.capture, section: magnifier, title: L10n.PreferencesCapture.reverseMagnifierZoomDirectionTitle,
            detail: L10n.PreferencesCapture.reverseMagnifierZoomDirectionDescription,
            keywords: ["scroll", "invert", "loupe"]),
      .init(.capture, section: magnifier, title: L10n.PreferencesCapture.showMagnifierColorPanelTitle,
            detail: L10n.PreferencesCapture.showMagnifierColorPanelDescription,
            keywords: ["hex", "eyedropper", "loupe"]),
      .init(.capture, section: magnifier, title: L10n.PreferencesCapture.magnifierSizeTitle,
            detail: L10n.PreferencesCapture.magnifierSizeDescription, keywords: ["loupe"]),
      .init(.capture, section: naming, title: L10n.PreferencesCapture.screenshotTemplateTitle,
            detail: L10n.PreferencesCapture.screenshotTemplateDescription,
            keywords: ["filename", "file name", "naming"]),
      .init(.capture, section: naming, title: L10n.PreferencesCapture.recordingTemplateTitle,
            detail: L10n.PreferencesCapture.recordingTemplateDescription,
            keywords: ["filename", "file name", "naming"]),
      .init(.capture, section: naming, title: L10n.PreferencesCapture.resetNamingDefaults,
            keywords: ["filename"], anchored: false),
      .init(.capture, section: afterCapture, title: AfterCaptureAction.showQuickAccess.displayName,
            detail: L10n.AfterCapture.showQuickAccessDescription, keywords: ["post capture"], anchored: false),
      .init(.capture, section: afterCapture, title: AfterCaptureAction.copyFile.displayName,
            detail: L10n.AfterCapture.copyFileDescription, keywords: ["clipboard", "post capture"], anchored: false),
      .init(.capture, section: afterCapture, title: AfterCaptureAction.save.displayName,
            detail: L10n.AfterCapture.saveDescription, keywords: ["auto", "disk", "post capture"], anchored: false),
      .init(.capture, section: afterCapture, title: AfterCaptureAction.openAnnotate.displayName,
            detail: L10n.AfterCapture.openAnnotateDescription, keywords: ["markup", "post capture"], anchored: false),
      .init(.capture, section: afterCapture, title: L10n.PreferencesCapture.autoCropSubjectTitle,
            detail: L10n.PreferencesCapture.autoCropSubjectDescription, keywords: ["remove background", "cutout"]),
    ]
  }

  private static var captureScreenshot: [PreferencesSearchEntry] {
    let format = L10n.PreferencesCapture.screenshotFormatSection
    let preset = L10n.PreferencesCapture.screenshotPresetSection
    let scrolling = L10n.PreferencesCapture.scrollingCaptureSection
    return [
      .init(.capture, section: format, title: L10n.PreferencesCapture.showCursorTitle,
            detail: L10n.PreferencesCapture.showCursorDescription, keywords: ["pointer", "mouse", "screenshot"]),
      .init(.capture, section: format, title: L10n.PreferencesCapture.includeWindowShadowTitle,
            detail: L10n.PreferencesCapture.includeWindowShadowDescription, keywords: ["drop"]),
      .init(.capture, section: format, title: L10n.PreferencesCapture.freezeAreaTitle,
            detail: L10n.PreferencesCapture.freezeAreaDescription, keywords: ["still", "frozen"]),
      .init(.capture, section: format, title: L10n.PreferencesCapture.delayedCaptureTitle,
            detail: L10n.PreferencesCapture.delayedCaptureDescription, keywords: ["timer", "seconds"]),
      .init(.capture, section: format, title: L10n.PreferencesCapture.livePassthroughTitle,
            detail: L10n.PreferencesCapture.livePassthroughDescription, keywords: ["live", "click through"]),
      .init(.capture, section: format, title: L10n.PreferencesCapture.imageFormatTitle,
            detail: L10n.PreferencesCapture.imageFormatDescription, keywords: ["png", "jpeg", "webp", "file type"]),
      .init(.capture, section: preset, title: L10n.PreferencesCapture.defaultPresetTitle,
            detail: L10n.PreferencesCapture.defaultPresetDescription, keywords: ["canvas", "background", "template"]),
      .init(.capture, section: scrolling, title: L10n.PreferencesCapture.showSessionHintsTitle,
            detail: L10n.PreferencesCapture.showSessionHintsDescription,
            keywords: ["scrolling capture", "long screenshot"]),
    ]
  }

  private static var captureRecording: [PreferencesSearchEntry] {
    let format = L10n.PreferencesCapture.recordingFormatSection
    let quality = L10n.PreferencesCapture.recordingQualitySection
    let behavior = L10n.PreferencesCapture.recordingBehaviorSection
    let controls = L10n.PreferencesCapture.recordingControlsSection
    let mouse = L10n.PreferencesCapture.mouseHighlightSection
    let keystroke = L10n.PreferencesCapture.keystrokeOverlaySection
    let audio = L10n.PreferencesCapture.audioSection
    return [
      .init(.capture, section: format, title: L10n.PreferencesCapture.videoFormatTitle,
            detail: L10n.PreferencesCapture.videoFormatDescription, keywords: ["mp4", "mov", "gif", "codec"]),
      .init(.capture, section: quality, title: L10n.PreferencesCapture.frameRateTitle,
            detail: L10n.PreferencesCapture.frameRateDescription, keywords: ["fps"]),
      .init(.capture, section: quality, title: L10n.PreferencesCapture.maxResolutionTitle,
            detail: L10n.PreferencesCapture.maxResolutionDescription, keywords: ["1080p", "4k", "scale"]),
      .init(.capture, section: quality, title: L10n.PreferencesCapture.qualityTitle,
            detail: L10n.PreferencesCapture.qualityDescription, keywords: ["bitrate", "video"]),
      .init(.capture, section: behavior, title: L10n.PreferencesCapture.showCursorTitle,
            detail: L10n.PreferencesCapture.recordingShowCursorDescription,
            keywords: ["pointer", "mouse", "recording"]),
      .init(.capture, section: behavior, title: L10n.PreferencesCapture.recordingDimNonSelectedAreaTitle,
            detail: L10n.PreferencesCapture.recordingDimNonSelectedAreaDescription, keywords: ["darken", "focus"]),
      .init(.capture, section: behavior, title: L10n.PreferencesCapture.rememberLastAreaTitle,
            detail: L10n.PreferencesCapture.rememberLastAreaDescription, keywords: ["previous region", "selection"]),
      .init(.capture, section: controls, title: L10n.PreferencesCapture.hoverBarVisibleTitle,
            detail: L10n.PreferencesCapture.hoverBarVisibleDescription, keywords: ["toolbar", "hover bar"]),
      .init(.capture, section: controls, title: L10n.PreferencesCapture.menuBarTimeTitle,
            detail: L10n.PreferencesCapture.menuBarTimeDescription, keywords: ["elapsed", "clock", "status bar"]),
      .init(.capture, section: mouse, title: L10n.PreferencesCapture.highlightSizeTitle,
            keywords: ["click", "ripple", "cursor"]),
      .init(.capture, section: mouse, title: L10n.PreferencesCapture.animationDurationTitle,
            keywords: ["click", "ripple", "speed"]),
      .init(.capture, section: mouse, title: L10n.PreferencesCapture.rippleCountTitle,
            detail: L10n.PreferencesCapture.rippleCountDescription, keywords: ["click"]),
      .init(.capture, section: mouse, title: L10n.PreferencesCapture.highlightColorTitle,
            detail: L10n.PreferencesCapture.highlightColorDescription, keywords: ["click", "ripple"]),
      .init(.capture, section: mouse, title: L10n.PreferencesCapture.opacityTitle,
            keywords: ["transparency", "ripple"]),
      .init(.capture, section: keystroke, title: L10n.PreferencesCapture.fontSizeTitle,
            keywords: ["keystroke", "keys", "text"]),
      .init(.capture, section: keystroke, title: L10n.PreferencesCapture.positionTitle,
            detail: L10n.PreferencesCapture.positionDescription, keywords: ["keystroke", "keys", "placement"]),
      .init(.capture, section: keystroke, title: L10n.PreferencesCapture.displayDurationTitle,
            keywords: ["keystroke", "keys", "fade"]),
      .init(.capture, section: audio, title: L10n.PreferencesCapture.systemAudioTitle,
            detail: L10n.PreferencesCapture.systemAudioDescription, keywords: ["sound", "internal"]),
      .init(.capture, section: audio, title: L10n.Onboarding.microphone,
            detail: L10n.PreferencesCapture.microphoneDescription, keywords: ["mic", "voice", "voiceover"]),
      .init(.capture, section: audio, title: L10n.PreferencesCapture.microphoneInputTitle,
            detail: L10n.PreferencesCapture.microphoneInputDescription, keywords: ["mic", "device"]),
    ]
  }

  private static var captureOCR: [PreferencesSearchEntry] {
    let model = L10n.PreferencesCapture.ocrModelSection
    let notifications = L10n.PreferencesCapture.ocrNotificationsSection
    let textActions = L10n.PreferencesCapture.ocrTextActionsSection
    return [
      .init(.capture, section: model, title: L10n.PreferencesCapture.ocrModelBuiltinTitle,
            detail: L10n.PreferencesCapture.ocrModelBuiltinDescription,
            keywords: ["text recognition", "vision"], anchored: false),
      .init(.capture, section: model, title: L10n.PreferencesCapture.ocrModelAddCustom,
            keywords: ["llm", "ai", "api", "text recognition"], anchored: false),
      .init(.capture, section: notifications, title: L10n.PreferencesCapture.ocrSuccessNotificationTitle,
            detail: L10n.PreferencesCapture.ocrSuccessNotificationDescription, keywords: ["alert", "text recognition"]),
      .init(.capture, section: textActions, title: L10n.PreferencesCapture.ocrLinkDetectionTitle,
            detail: L10n.PreferencesCapture.ocrLinkDetectionDescription, keywords: ["url", "ocr"]),
    ]
  }

  // MARK: - Annotate

  private static var annotate: [PreferencesSearchEntry] {
    let tools = L10n.PreferencesAnnotate.toolsSection
    let drawing = L10n.PreferencesAnnotate.drawingSection
    let openSave = L10n.PreferencesAnnotate.openSaveSection
    let drag = L10n.PreferencesAnnotate.dragSection
    return [
      .init(.annotate, section: tools, title: L10n.PreferencesAnnotate.defaultToolTitle,
            detail: L10n.PreferencesAnnotate.defaultToolDescription, keywords: ["editor", "initial"]),
      .init(.annotate, section: tools, title: L10n.PreferencesAnnotate.rememberLastToolTitle,
            detail: L10n.PreferencesAnnotate.rememberLastToolDescription, keywords: ["editor", "restore"]),
      .init(.annotate, section: tools, title: L10n.PreferencesAnnotate.quickPropertiesSyncTitle,
            detail: L10n.PreferencesAnnotate.quickPropertiesSyncDescription,
            keywords: ["properties", "color", "stroke"]),
      .init(.annotate, section: openSave, title: L10n.PreferencesAnnotate.combineSaveAsEditTitle,
            detail: L10n.PreferencesAnnotate.combineSaveAsEditDescription, keywords: ["merge", "stitch"]),
      .init(.annotate, section: drawing, title: L10n.AnnotateUI.cropSnapToEdges,
            detail: L10n.AnnotateUI.cropSnapToEdgesDescription, keywords: ["crop", "magnet"]),
      .init(.annotate, section: drawing, title: L10n.AnnotateUI.highlighterTextSnapping,
            detail: L10n.AnnotateUI.highlighterTextSnappingDescription, keywords: ["marker", "align"]),
      .init(.annotate, section: openSave, title: L10n.PreferencesAnnotate.clipboardTitle,
            detail: L10n.PreferencesAnnotate.clipboardDescription, keywords: ["paste", "pasteboard"]),
      .init(.annotate, section: drag, title: L10n.PreferencesAnnotate.closeAfterDragTitle,
            detail: L10n.PreferencesAnnotate.closeAfterDragDescription, keywords: ["drag", "dismiss"]),
      .init(.annotate, section: drag, title: L10n.PreferencesAnnotate.bringForwardAfterDragTitle,
            detail: L10n.PreferencesAnnotate.bringForwardAfterDragDescription, keywords: ["drag", "focus"]),
    ]
  }

  // MARK: - Quick Access

  private static var quickAccess: [PreferencesSearchEntry] {
    let quickActions = L10n.PreferencesQuickAccess.quickActionsSection
    let pinZoom = L10n.PreferencesQuickAccess.pinZoomSection
    let position = L10n.PreferencesQuickAccess.positionSection
    let appearance = L10n.PreferencesQuickAccess.appearanceSection
    let behaviors = L10n.PreferencesQuickAccess.behaviorsSection
    let swipeActions = L10n.PreferencesQuickAccess.swipeActionsSection
    return [
      .init(.quickAccess, section: quickActions, title: quickActions,
            detail: L10n.PreferencesQuickAccess.quickActionsDescription,
            keywords: ["buttons", "card buttons", "reorder", "context menu"], anchored: false),
      .init(.quickAccess, section: quickActions, title: L10n.PreferencesQuickAccess.resetActions,
            keywords: ["card"], anchored: false),
      .init(.quickAccess, section: pinZoom, title: L10n.PreferencesQuickAccess.pinZoomModeWindow,
            keywords: ["pin", "zoom", "float"], anchored: false),
      .init(.quickAccess, section: pinZoom, title: L10n.PreferencesQuickAccess.pinZoomModeFixed,
            keywords: ["pin", "zoom", "float"], anchored: false),
      .init(.quickAccess, section: position, title: L10n.PreferencesQuickAccess.screenEdgeTitle,
            detail: L10n.PreferencesQuickAccess.screenEdgeDescription, keywords: ["left", "right", "corner"]),
      .init(.quickAccess, section: appearance, title: L10n.PreferencesQuickAccess.overlaySizeTitle,
            detail: L10n.PreferencesQuickAccess.overlaySizeDescription, keywords: ["scale", "thumbnail"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.floatingOverlayTitle,
            detail: L10n.PreferencesQuickAccess.floatingOverlayDescription, keywords: ["thumbnail", "preview"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.autoCloseTitle,
            keywords: ["dismiss", "timeout"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.hideCardWhenWindowOpenTitle,
            detail: L10n.PreferencesQuickAccess.hideCardWhenWindowOpenDescription, keywords: ["editor"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.animationStyleTitle,
            detail: L10n.PreferencesQuickAccess.animationStyleDescription, keywords: ["transition", "motion"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.soundEffectsTitle,
            detail: L10n.PreferencesQuickAccess.soundEffectsDescription, keywords: ["audio", "mute"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.closeAfter,
            keywords: ["auto-close", "seconds", "delay"], anchored: false),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.pauseOnHoverTitle,
            detail: L10n.PreferencesQuickAccess.pauseOnHoverDescription, keywords: ["countdown", "auto-close"],
            anchored: false),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.dragAndDropTitle,
            detail: L10n.PreferencesQuickAccess.dragAndDropDescription, keywords: ["export", "move file"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.openInFinderAfterSaveTitle,
            detail: L10n.PreferencesQuickAccess.openInFinderAfterSaveDescription, keywords: ["reveal", "folder"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.twoFingerSwipeTitle,
            detail: L10n.PreferencesQuickAccess.twoFingerSwipeDescription,
            keywords: ["trackpad", "gesture", "dismiss"]),
      .init(.quickAccess, section: behaviors, title: L10n.PreferencesQuickAccess.swipeSensitivityTitle,
            detail: L10n.PreferencesQuickAccess.swipeSensitivityDescription, keywords: ["trackpad", "gesture"]),
      .init(.quickAccess, section: swipeActions, title: L10n.PreferencesQuickAccess.trackpadSwipeModeTitle,
            detail: L10n.PreferencesQuickAccess.trackpadSwipeModeDescription,
            keywords: ["gesture", "natural scrolling"]),
    ]
  }

  // MARK: - History

  private static var history: [PreferencesSearchEntry] {
    let panel = L10n.PreferencesHistory.floatingPanelSection
    let display = L10n.PreferencesHistory.displaySection
    let retention = L10n.PreferencesHistory.retentionSection
    let storage = L10n.PreferencesHistory.storageSection
    return [
      .init(.history, section: panel, title: L10n.PreferencesHistory.floatingPanelTitle,
            detail: L10n.PreferencesHistory.floatingPanelDescription, keywords: ["recent captures", "browser"]),
      .init(.history, section: panel, title: L10n.PreferencesHistory.panelPositionTitle,
            detail: L10n.PreferencesHistory.panelPositionDescription, keywords: ["placement", "edge"]),
      .init(.history, section: display, title: L10n.PreferencesHistory.defaultFilterTitle,
            detail: L10n.PreferencesHistory.defaultFilterDescription, keywords: ["screenshots", "videos", "gifs"]),
      .init(.history, section: display, title: L10n.PreferencesHistory.backgroundStyleTitle,
            detail: L10n.PreferencesHistory.backgroundStyleDescription, keywords: ["blur", "material"]),
      .init(.history, section: display, title: L10n.PreferencesHistory.panelSizeTitle,
            detail: L10n.PreferencesHistory.panelSizeDescription, keywords: ["scale", "thumbnail"]),
      .init(.history, section: display, title: L10n.PreferencesHistory.maxItemsTitle,
            detail: L10n.PreferencesHistory.maxItemsDescription, keywords: ["limit", "count"]),
      .init(.history, section: retention, title: L10n.PreferencesHistory.retentionDaysTitle,
            keywords: ["retention", "delete", "days", "cleanup"]),
      .init(.history, section: retention, title: L10n.PreferencesHistory.maxCountTitle,
            detail: L10n.PreferencesHistory.maxCountDescription, keywords: ["limit", "retention"]),
      .init(.history, section: storage, title: L10n.PreferencesHistory.captureStorageTitle,
            keywords: ["disk", "size", "folder"]),
      .init(.history, section: storage, title: L10n.PreferencesHistory.clearHistoryTitle,
            detail: L10n.PreferencesHistory.clearHistoryDescription, keywords: ["delete", "erase", "reset"]),
    ]
  }

  // MARK: - Shortcuts

  private static var shortcuts: [PreferencesSearchEntry] {
    let capture = L10n.ShortcutOverlay.captureSection
    let recording = L10n.PreferencesShortcuts.recordingPage
    let tools = L10n.ShortcutOverlay.toolsSection
    let history = L10n.Preferences.historyTab
    let quickAccess = L10n.PreferencesShortcuts.quickAccessSection
    let annotateActions = L10n.ShortcutOverlay.annotateActions
    let annotateTools = L10n.ShortcutOverlay.annotateToolKeys

    var entries: [PreferencesSearchEntry] = [
      .init(.shortcuts, section: nil, title: L10n.PreferencesShortcuts.enableShortcutsTitle,
            detail: L10n.PreferencesShortcuts.enableShortcutsDescription,
            keywords: ["hotkey", "keyboard", "disable"], anchored: false),
      .init(.shortcuts, section: nil, title: L10n.PreferencesShortcuts.systemConflictTitle,
            keywords: ["conflict", "cmd shift 3", "cmd shift 4"], anchored: false),
      .init(.shortcuts, section: nil, title: L10n.PreferencesShortcuts.resetToDefaults,
            keywords: ["hotkey", "keyboard"], anchored: false),

      // Capture
      shortcutEntry(capture, L10n.Actions.captureFullscreen, L10n.PreferencesShortcuts.captureFullscreenDescription,
                    ["full screen", "entire screen"]),
      shortcutEntry(capture, L10n.Actions.captureArea, L10n.PreferencesShortcuts.captureAreaDescription,
                    ["region", "selection", "crop"]),
      shortcutEntry(capture, L10n.PreferencesShortcuts.applicationCaptureTitle,
                    L10n.PreferencesShortcuts.applicationCaptureDescription, ["app", "window"]),
      shortcutEntry(capture, L10n.Actions.captureRepeatArea, L10n.PreferencesShortcuts.captureRepeatAreaDescription,
                    ["previous region", "last"]),
      shortcutEntry(capture, L10n.Actions.captureDelayed, L10n.PreferencesShortcuts.captureDelayedDescription,
                    ["timer", "countdown"]),
      shortcutEntry(capture, L10n.Actions.captureDelayedFullscreen,
                    L10n.PreferencesShortcuts.captureDelayedFullscreenDescription, ["timer", "countdown"]),
      shortcutEntry(capture, L10n.Actions.captureAreaAnnotate, L10n.PreferencesShortcuts.captureAreaAnnotateDescription,
                    ["annotate", "edit"]),
      shortcutEntry(capture, L10n.Actions.captureActiveWindow, L10n.PreferencesShortcuts.captureActiveWindowDescription,
                    ["frontmost", "focused"]),
      shortcutEntry(capture, GlobalShortcutKind.scrollingCapture.displayName, nil, ["long screenshot", "full page"]),
      shortcutEntry(capture, GlobalShortcutKind.objectCutout.displayName, nil,
                    ["remove background", "cutout"]),
      shortcutEntry(capture, L10n.Actions.captureTextOCR, L10n.PreferencesShortcuts.captureTextDescription,
                    ["recognize", "extract"]),
      shortcutEntry(capture, L10n.Actions.captureSmartElement, L10n.PreferencesShortcuts.smartElementCaptureDescription,
                    ["ui", "control"]),

      // Recording
      shortcutEntry(recording, L10n.Actions.recordVideo, L10n.PreferencesShortcuts.recordVideoDescription,
                    ["screencast", "mp4"]),
      shortcutEntry(recording, L10n.PreferencesShortcuts.applicationRecordingTitle,
                    L10n.PreferencesShortcuts.applicationRecordingDescription, ["app", "window", "video"]),
      shortcutEntry(recording, L10n.Actions.pauseResumeRecording,
                    L10n.PreferencesShortcuts.pauseResumeRecordingDescription,
                    ["video"]),
      shortcutEntry(recording, L10n.Actions.togglePenRecording, L10n.PreferencesShortcuts.togglePenRecordingDescription,
                    ["draw", "video"]),
      shortcutEntry(recording, L10n.Actions.restartRecording, L10n.PreferencesShortcuts.restartRecordingDescription,
                    ["video"]),
      shortcutEntry(recording, L10n.Actions.deleteRecording, L10n.PreferencesShortcuts.deleteRecordingDescription,
                    ["discard", "video"]),

      // Tools
      shortcutEntry(tools, L10n.Actions.openAnnotate, L10n.PreferencesShortcuts.openAnnotateDescription,
                    ["editor"]),
      shortcutEntry(tools, L10n.Actions.openVideoEditor, L10n.PreferencesShortcuts.openVideoEditorDescription,
                    ["trim", "cut"]),
      shortcutEntry(tools, L10n.Actions.cloudUploads, L10n.PreferencesShortcuts.cloudUploadsDescription,
                    ["s3", "r2"]),
      shortcutEntry(tools, L10n.Actions.pickColor, L10n.PreferencesShortcuts.pickColorDescription,
                    ["eyedropper", "hex"]),
      shortcutEntry(tools, L10n.Actions.showShortcutList, L10n.PreferencesShortcuts.shortcutListDescription,
                    ["cheat sheet", "keyboard"]),

      // History
      shortcutEntry(history, L10n.Actions.openHistory, L10n.PreferencesShortcuts.openHistoryDescription,
                    ["recent captures"]),
      shortcutEntry(history, L10n.PreferencesHistory.toggleModeShortcutTitle,
                    L10n.PreferencesHistory.toggleModeShortcutDescription, ["floating panel"]),

      // Quick Access
      shortcutEntry(quickAccess, L10n.PreferencesShortcuts.editLatestCapture,
                    L10n.PreferencesShortcuts.editLatestCaptureDescription, ["annotate", "last screenshot"]),
      .init(.shortcuts, section: quickAccess, title: L10n.PreferencesShortcuts.cardActionsEnableTitle,
            detail: L10n.PreferencesShortcuts.cardActionsEnableDescription,
            keywords: ["hotkey", "quick access"], anchored: false),
    ]

    entries += QuickAccessActionKind.defaultOrder.map {
      shortcutEntry(quickAccess, $0.settingsTitle, L10n.PreferencesShortcuts.cardActionsHoverFootnote, ["card action"])
    }

    entries += [
      // Annotate actions
      shortcutEntry(annotateActions, L10n.ShortcutOverlay.copyAndClose,
                    L10n.PreferencesShortcuts.copyAndCloseDescription,
                    ["clipboard", "editor"]),
      shortcutEntry(annotateActions, L10n.AnnotateUI.toggleSidebar, nil, ["editor", "panel"]),
      shortcutEntry(annotateActions, L10n.ShortcutOverlay.togglePin, L10n.PreferencesShortcuts.togglePinDescription,
                    ["float", "always on top"]),
      shortcutEntry(annotateActions, L10n.ShortcutOverlay.cloudUpload, L10n.PreferencesShortcuts.cloudUploadDescription,
                    ["s3", "r2", "share"]),
      shortcutEntry(annotateActions, L10n.ShortcutOverlay.autoRedactSensitiveData,
                    L10n.PreferencesShortcuts.autoRedactSensitiveDataDescription, ["blur", "privacy", "pii"]),
    ]

    entries += AnnotateShortcutManager.configurableTools.map {
      shortcutEntry(annotateTools, $0.displayName, nil, ["tool key", "single key"])
    }

    return entries
  }

  /// A configurable shortcut recorder row on the Shortcuts page. These sit inside collapsible
  /// cards, so they are never scroll targets.
  private static func shortcutEntry(
    _ section: String,
    _ title: String,
    _ detail: String?,
    _ keywords: [String] = []
  ) -> PreferencesSearchEntry {
    .init(.shortcuts, section: section, title: title, detail: detail,
          keywords: ["hotkey"] + keywords, anchored: false)
  }

  // MARK: - Permissions

  private static var permissions: [PreferencesSearchEntry] {
    let section = L10n.Preferences.permissionsTab
    return [
      .init(.permissions, section: section, title: L10n.Onboarding.screenRecording,
            keywords: ["capture", "privacy", "tcc"], anchored: false),
      .init(.permissions, section: section, title: L10n.Onboarding.saveFolder,
            detail: L10n.Onboarding.requiredForCaptures, keywords: ["file access", "sandbox", "privacy"],
            anchored: false),
      .init(.permissions, section: section, title: L10n.Onboarding.microphone,
            detail: L10n.Onboarding.optionalForVoiceRecording, keywords: ["mic", "audio", "privacy"],
            anchored: false),
      .init(.permissions, section: section, title: L10n.Onboarding.accessibility,
            detail: L10n.Onboarding.optionalForGlobalShortcuts, keywords: ["ax", "privacy", "hotkey"],
            anchored: false),
      .init(.permissions, section: section, title: L10n.Onboarding.refreshStatus,
            keywords: ["permissions", "recheck"], anchored: false),
    ]
  }

  // MARK: - Command Line

  private static var commandLine: [PreferencesSearchEntry] {
    let allowedApps = L10n.CommandLine.allowedAppsTitle
    return [
      .init(.commandLine, section: nil, title: L10n.CommandLine.accessTitle,
            detail: L10n.CommandLine.accessDescription, keywords: ["cli", "terminal", "ai agent"], anchored: false),
      .init(.commandLine, section: nil, title: L10n.CommandLine.toolTitle,
            detail: L10n.CommandLine.installExplanation, keywords: ["cli", "install", "path", "homebrew"],
            anchored: false),
      .init(.commandLine, section: allowedApps, title: allowedApps,
            detail: L10n.CommandLine.allowedAppsDescription, keywords: ["cli", "approval", "revoke"],
            anchored: false),
    ]
  }

  // MARK: - Cloud

  private static var cloud: [PreferencesSearchEntry] {
    let provider = L10n.CloudSettings.providerSection
    let credentials = L10n.CloudSettings.credentialsSection
    let storage = L10n.CloudSettings.storageSection
    let expiration = L10n.CloudSettings.fileExpirationSection
    let password = L10n.CloudSettings.protectionPasswordSection
    let transfer = L10n.CloudSettings.transferSection
    let googleCredentials = L10n.CloudSettings.googleCredentialsSection
    let googleFolder = L10n.CloudSettings.googleFolderSection
    let uploadsWindow = L10n.CloudSettings.uploadsWindowSection
    return [
      .init(.cloud, section: provider, title: L10n.CloudSettings.provider,
            keywords: ["s3", "r2", "google drive", "aws"]),
      .init(.cloud, section: provider, title: L10n.CloudSettings.edit,
            keywords: ["cloud settings", "credentials"], anchored: false),
      .init(.cloud, section: provider, title: L10n.CloudSettings.reset,
            keywords: ["cloud settings", "disconnect", "remove"], anchored: false),
      .init(.cloud, section: provider, title: L10n.Common.exportAction,
            keywords: ["cloud credentials", "archive", "backup"], anchored: false),
      .init(.cloud, section: transfer, title: L10n.CloudSettings.importEncryptedArchive,
            detail: L10n.CloudSettings.importEncryptedArchiveDescription,
            keywords: ["cloud credentials", "restore"], anchored: false),
      .init(.cloud, section: credentials, title: L10n.CloudSettings.accessKeyID,
            keywords: ["s3", "r2", "aws", "credentials"]),
      .init(.cloud, section: credentials, title: L10n.CloudSettings.secretAccessKey,
            keywords: ["s3", "r2", "aws", "credentials"]),
      .init(.cloud, section: provider, title: L10n.CloudSettings.accessKey,
            keywords: ["s3", "r2", "aws", "credentials"]),
      .init(.cloud, section: storage, title: L10n.CloudSettings.bucketName,
            keywords: ["s3", "r2"]),
      .init(.cloud, section: storage, title: L10n.CloudSettings.region,
            keywords: ["s3", "aws", "us-east-1"]),
      .init(.cloud, section: storage, title: L10n.CloudSettings.endpoint,
            keywords: ["s3", "r2", "url", "minio"]),
      .init(.cloud, section: storage, title: L10n.CloudSettings.customDomain,
            keywords: ["cdn", "url", "cname"]),
      .init(.cloud, section: expiration, title: L10n.CloudSettings.expireTime,
            keywords: ["lifecycle", "retention", "auto delete"]),
      .init(.cloud, section: password, title: L10n.CloudSettings.password,
            detail: L10n.CloudSettings.protectionRecommendation, keywords: ["protection", "lock", "encrypt"],
            anchored: false),
      .init(.cloud, section: googleCredentials, title: L10n.CloudSettings.googleClientId,
            detail: L10n.CloudSettings.googleSetupGuide, keywords: ["google drive", "oauth"], anchored: false),
      .init(.cloud, section: googleCredentials, title: L10n.CloudSettings.googleClientSecret,
            keywords: ["google drive", "oauth"], anchored: false),
      .init(.cloud, section: googleFolder, title: L10n.CloudSettings.googleFolderName,
            detail: L10n.CloudSettings.googleFolderDescription, keywords: ["google drive"], anchored: false),
      .init(.cloud, section: uploadsWindow, title: L10n.CloudSettings.uploadsWindowPositionTitle,
            detail: L10n.CloudSettings.uploadsWindowPositionDescription, keywords: ["upload progress", "placement"]),
    ]
  }

  // MARK: - Advanced

  private static var advanced: [PreferencesSearchEntry] {
    let backup = L10n.PreferencesAdvanced.backupSection
    let integration = L10n.PreferencesAdvanced.integrationSection
    let diagnostics = L10n.PreferencesAdvanced.diagnosticsSection
    return [
      .init(.advanced, section: backup, title: L10n.PreferencesAdvanced.importTitle,
            detail: L10n.PreferencesAdvanced.importDescription, keywords: ["restore", "settings", "config"]),
      .init(.advanced, section: backup, title: L10n.PreferencesAdvanced.exportTitle,
            detail: L10n.PreferencesAdvanced.exportDescription, keywords: ["save settings", "config"]),
      .init(.advanced, section: backup, title: L10n.PreferencesAdvanced.restoreDefaultsTitle,
            detail: L10n.PreferencesAdvanced.restoreDefaultsDescription, keywords: ["reset", "factory"]),
      .init(.advanced, section: backup, title: L10n.PreferencesAdvanced.configSyncStatusTitle,
            keywords: ["dotfiles", "file"]),
      .init(.advanced, section: backup, title: L10n.PreferencesAdvanced.openConfigButton,
            keywords: ["dotfiles", "edit"], anchored: false),
      .init(.advanced, section: integration, title: L10n.PreferencesAdvanced.urlSchemeTitle,
            detail: L10n.PreferencesAdvanced.urlSchemeDescription, keywords: ["deep link", "automation", "raycast"]),
      .init(.advanced, section: diagnostics, title: L10n.PreferencesAdvanced.diagnosticLoggingTitle,
            detail: L10n.PreferencesAdvanced.diagnosticLoggingDescription, keywords: ["debug", "verbose"]),
      .init(.advanced, section: diagnostics, title: L10n.PreferencesAdvanced.logRetentionTitle,
            keywords: ["retention", "days", "cleanup"]),
      .init(.advanced, section: diagnostics, title: L10n.PreferencesAdvanced.logFilesTitle,
            keywords: ["debug", "folder", "size"]),
    ]
  }

  // MARK: - About

  private static var about: [PreferencesSearchEntry] {
    [
      .init(.about, section: nil, title: L10n.PreferencesAbout.checkForUpdates,
            keywords: ["version", "upgrade", "sparkle"], anchored: false),
      .init(.about, section: nil, title: L10n.PreferencesAbout.updateChannelTitle,
            detail: L10n.PreferencesAbout.updateChannelDescription, keywords: ["beta", "stable", "prerelease"],
            anchored: false),
      .init(.about, section: nil, title: L10n.PreferencesAbout.specialThanks,
            keywords: ["contributors", "credits"], anchored: false),
      .init(.about, section: L10n.PreferencesAbout.support, title: L10n.PreferencesAbout.website,
            keywords: ["homepage"], anchored: false),
      .init(.about, section: L10n.PreferencesAbout.support, title: L10n.PreferencesAbout.github,
            keywords: ["source code", "repository"], anchored: false),
      .init(.about, section: L10n.PreferencesAbout.support, title: L10n.PreferencesAbout.reportBug,
            keywords: ["issue", "feedback"], anchored: false),
      .init(.about, section: L10n.PreferencesAbout.support, title: L10n.PreferencesAbout.discordCommunity,
            keywords: ["chat", "community"], anchored: false),
      .init(.about, section: L10n.PreferencesAbout.support, title: L10n.PreferencesAbout.supportTitle,
            keywords: ["sponsor", "donate"], anchored: false),
    ]
  }
}
