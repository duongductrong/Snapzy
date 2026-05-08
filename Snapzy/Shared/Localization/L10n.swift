//
//  L10n.swift
//  Snapzy
//
//  Small localization helper for AppKit and shared string surfaces.
//

import Foundation

enum L10n {
  private nonisolated static let tableMappings: [(prefix: String, tableName: String)] = [
    ("action.", "Common"),
    ("menu.", "Menubar"),
    ("common.", "Common"),
    ("appearance.", "Common"),
    ("splash.", "Onboarding"),
    ("app-identity.", "Common"),
    ("permission-row.", "Permissions"),
    ("crash-report.", "Errors"),
    ("onboarding.", "Onboarding"),
    ("sponsor.", "Onboarding"),
    ("preferences.tab.", "Settings"),
    ("preferences-general.", "Settings"),
    ("preferences-capture.", "Capture"),
    ("preferences-shortcuts.", "Shortcuts"),
    ("preferences-cloud-history.", "Cloud"),
    ("preferences-about.", "Settings"),
    ("preferences-quick-access.", "QuickAccess"),
    ("preferences-history.", "Settings"),
    ("preferences-permissions.", "Permissions"),
    ("history-background-style.", "Settings"),
    ("history-panel-position.", "Settings"),
    ("after-capture.", "Capture"),
    ("capture-kind.", "Capture"),
    ("capture-storage.", "Capture"),
    ("file-access.", "Permissions"),
    ("foreground-cutout.", "Capture"),
    ("ocr.", "Capture"),
    ("screen-capture.", "Capture"),
    ("scrolling-capture.", "Capture"),
    ("scrolling-capture-status.", "Capture"),
    ("gif.", "Recording"),
    ("keystroke-position.", "Recording"),
    ("microphone.", "Recording"),
    ("recording.", "Recording"),
    ("recording-annotation.", "Recording"),
    ("recording-toolbar.", "Recording"),
    ("annotate.", "Annotate"),
    ("annotate-context.", "Annotate"),
    ("quick-access.", "QuickAccess"),
    ("video-editor.", "VideoEditor"),
    ("video-editor-timeline.", "VideoEditor"),
    ("video-export.", "VideoEditor"),
    ("zoom-compositor.", "VideoEditor"),
    ("cloud-expire.", "Cloud"),
    ("cloud-operation.", "Cloud"),
    ("cloud-password.", "Cloud"),
    ("cloud-provider.", "Cloud"),
    ("cloud-settings.", "Cloud"),
    ("cloud-transfer.", "Cloud"),
    ("cloud-usage.", "Cloud"),
    ("shortcut-overlay.", "Shortcuts"),
    ("shortcut-recorder.", "Shortcuts"),
    ("shortcut-validation.", "Shortcuts"),
    ("system-shortcuts.", "Shortcuts"),
  ]

  private nonisolated static func tableName(for key: String) -> String? {
    for mapping in tableMappings where key.hasPrefix(mapping.prefix) {
      return mapping.tableName
    }

    assertionFailure("Missing localization table mapping for key: \(key)")
    return nil
  }

  private nonisolated static func bundle(for localeIdentifier: String) -> Bundle {
    guard
      !localeIdentifier.isEmpty,
      let resourcePath = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
      let bundle = Bundle(path: resourcePath)
    else {
      return .main
    }

    return bundle
  }

  nonisolated static func string(_ key: String, defaultValue: String, comment: String) -> String {
    NSLocalizedString(
      key,
      tableName: tableName(for: key),
      bundle: .main,
      value: defaultValue,
      comment: comment
    )
  }

  nonisolated static func string(
    _ key: String,
    defaultValue: String,
    localeIdentifier: String,
    comment: String
  ) -> String {
    let lookupBundle = bundle(for: localeIdentifier)
    return lookupBundle.localizedString(
      forKey: key,
      value: defaultValue,
      table: tableName(for: key)
    )
  }

  nonisolated static func format(
    _ key: String,
    defaultValue: String,
    comment: String,
    _ arguments: CVarArg...
  ) -> String {
    let format = string(key, defaultValue: defaultValue, comment: comment)
    return String(format: format, locale: Locale.current, arguments: arguments)
  }

  nonisolated static func format(
    _ key: String,
    defaultValue: String,
    localeIdentifier: String,
    comment: String,
    _ arguments: CVarArg...
  ) -> String {
    let format = string(
      key,
      defaultValue: defaultValue,
      localeIdentifier: localeIdentifier,
      comment: comment
    )
    return String(
      format: format,
      locale: Locale(identifier: localeIdentifier),
      arguments: arguments
    )
  }

  enum Preferences {
    static let generalTab = string(
      "preferences.tab.general",
      defaultValue: "General",
      comment: "Preferences tab title"
    )
    static let captureTab = string(
      "preferences.tab.capture",
      defaultValue: "Capture",
      comment: "Preferences tab title"
    )
    static let quickAccessTab = string(
      "preferences.tab.quick-access",
      defaultValue: "Quick Access",
      comment: "Preferences tab title"
    )
    static let historyTab = string(
      "preferences.tab.history",
      defaultValue: "History",
      comment: "Preferences tab title"
    )
    static let shortcutsTab = string(
      "preferences.tab.shortcuts",
      defaultValue: "Shortcuts",
      comment: "Preferences tab title"
    )
    static let permissionsTab = string(
      "preferences.tab.permissions",
      defaultValue: "Permissions",
      comment: "Preferences tab title"
    )
    static let cloudTab = string(
      "preferences.tab.cloud",
      defaultValue: "Cloud",
      comment: "Preferences tab title"
    )
    static let aboutTab = string(
      "preferences.tab.about",
      defaultValue: "About",
      comment: "Preferences tab title"
    )
  }

  enum Actions {
    static let captureArea = string(
      "action.capture-area",
      defaultValue: "Capture Area",
      comment: "Action title for area screenshot capture"
    )
    static let captureFullscreen = string(
      "action.capture-fullscreen",
      defaultValue: "Capture Fullscreen",
      comment: "Action title for fullscreen screenshot capture"
    )
    static let scrollingCapture = string(
      "action.scrolling-capture",
      defaultValue: "Scrolling Capture",
      comment: "Action title for scrolling screenshot capture"
    )
    static let captureTextOCR = string(
      "action.capture-text-ocr",
      defaultValue: "Capture Text (OCR)",
      comment: "Action title for OCR capture"
    )
    static let captureSubject = string(
      "action.capture-subject",
      defaultValue: "Capture Subject",
      comment: "Action title for subject cutout capture"
    )
    static let recordVideo = string(
      "action.record-video",
      defaultValue: "Record Video",
      comment: "Action title for video recording shortcut"
    )
    static let openAnnotate = string(
      "action.open-annotate",
      defaultValue: "Open Annotate",
      comment: "Action title for opening annotate"
    )
    static let openVideoEditor = string(
      "action.open-video-editor",
      defaultValue: "Open Video Editor",
      comment: "Action title for opening the video editor"
    )
    static let cloudUploads = string(
      "action.cloud-uploads",
      defaultValue: "Cloud Uploads",
      comment: "Action title for opening cloud uploads"
    )
    static let showShortcutList = string(
      "action.show-shortcut-list",
      defaultValue: "Show Shortcut List",
      comment: "Action title for showing shortcut list"
    )
    static let showQuickAccessOverlay = string(
      "action.show-quick-access-overlay",
      defaultValue: "Show Quick Access Overlay",
      comment: "Action title for showing the quick access overlay"
    )
    static let openHistory = string(
      "action.open-history",
      defaultValue: "Open History",
      comment: "Action title for opening capture history"
    )
  }

  enum Menu {
    static func stopRecording(_ duration: String) -> String {
      format(
        "menu.stop-recording",
        defaultValue: "Stop Recording (%@)",
        comment: "Status bar menu item title while recording. %@ is the formatted recording duration.",
        duration
      )
    }

    static let recordScreen = string(
      "menu.record-screen",
      defaultValue: "Record Screen",
      comment: "Status bar menu item title for screen recording"
    )
    static let editVideo = string(
      "menu.edit-video",
      defaultValue: "Edit Video...",
      comment: "Status bar menu item title for opening the video editor"
    )
    static let keyboardShortcuts = string(
      "menu.keyboard-shortcuts",
      defaultValue: "Keyboard Shortcuts",
      comment: "Status bar menu item title for shortcut list"
    )
    static let grantPermission = string(
      "menu.grant-permission",
      defaultValue: "Grant Permission...",
      comment: "Status bar menu item title to request missing permissions"
    )
    static let checkForUpdates = string(
      "menu.check-for-updates",
      defaultValue: "Check for Updates...",
      comment: "Status bar menu item title for update checking"
    )
    static let preferences = string(
      "menu.preferences",
      defaultValue: "Preferences...",
      comment: "Status bar menu item title for opening preferences"
    )
    static let quitSnapzy = string(
      "menu.quit-snapzy",
      defaultValue: "Quit Snapzy",
      comment: "Status bar menu item title for quitting the app"
    )
  }

  enum Common {
    static let next = string(
      "common.next",
      defaultValue: "Next",
      comment: "Primary next action button title"
    )
    static let continueAction = string(
      "common.continue",
      defaultValue: "Continue",
      comment: "Generic continue button title"
    )
    static let close = string(
      "common.close",
      defaultValue: "Close",
      comment: "Generic close button title"
    )
    static let off = string(
      "common.off",
      defaultValue: "Off",
      comment: "Label shown when a shortcut or feature is turned off"
    )
    static let preferences = string(
      "common.preferences",
      defaultValue: "Preferences",
      comment: "Generic label for preferences without an ellipsis"
    )
    static let width = string(
      "common.width",
      defaultValue: "Width",
      comment: "Generic label for width"
    )
    static let height = string(
      "common.height",
      defaultValue: "Height",
      comment: "Generic label for height"
    )
    static let on = string(
      "common.on",
      defaultValue: "On",
      comment: "Label shown when a shortcut or feature is turned on"
    )
    static let cancel = string(
      "common.cancel",
      defaultValue: "Cancel",
      comment: "Generic cancel button title"
    )
    static let ok = string(
      "common.ok",
      defaultValue: "OK",
      comment: "Generic confirmation button title"
    )
    static let notGranted = string(
      "common.not-granted",
      defaultValue: "Not Granted",
      comment: "Status label shown when a permission or access has not been granted"
    )
    static let openSettings = string(
      "common.open-settings",
      defaultValue: "Open Settings",
      comment: "Generic button title to open System Settings"
    )
    static let refresh = string(
      "common.refresh",
      defaultValue: "Refresh",
      comment: "Generic refresh button title"
    )
    static let disable = string(
      "common.disable",
      defaultValue: "Disable",
      comment: "Generic destructive disable button title"
    )
    static let openSystemSettings = string(
      "common.open-system-settings",
      defaultValue: "Open System Settings",
      comment: "Generic button title to open System Settings"
    )
    static let resetToDefault = string(
      "common.reset-to-default",
      defaultValue: "Reset to Default",
      comment: "Generic button title to reset a setting to its default value"
    )
    static let importAction = string(
      "common.import",
      defaultValue: "Import",
      comment: "Generic import button title"
    )
    static let exportAction = string(
      "common.export",
      defaultValue: "Export",
      comment: "Generic export button title"
    )
    static let share = string(
      "common.share",
      defaultValue: "Share",
      comment: "Generic share button title"
    )
    static let saveAs = string(
      "common.save-as",
      defaultValue: "Save as...",
      comment: "Generic save as button title"
    )
    static let save = string(
      "common.save",
      defaultValue: "Save",
      comment: "Generic save button title"
    )
    static let none = string(
      "common.none",
      defaultValue: "None",
      comment: "Generic none option label"
    )
    static let more = string(
      "common.more",
      defaultValue: "More",
      comment: "Generic more button title"
    )
    static let reset = string(
      "common.reset",
      defaultValue: "Reset",
      comment: "Generic reset button title"
    )
    static let done = string(
      "common.done",
      defaultValue: "Done",
      comment: "Generic done button title"
    )
    static let apply = string(
      "common.apply",
      defaultValue: "Apply",
      comment: "Generic apply button title"
    )
    static let deleteAction = string(
      "common.delete",
      defaultValue: "Delete",
      comment: "Generic delete button title"
    )
    static let overwrite = string(
      "common.overwrite",
      defaultValue: "Overwrite",
      comment: "Generic overwrite button title"
    )
    static let undo = string(
      "common.undo",
      defaultValue: "Undo",
      comment: "Generic undo button title"
    )
    static let redo = string(
      "common.redo",
      defaultValue: "Redo",
      comment: "Generic redo button title"
    )
    static let copyToClipboard = string(
      "common.copy-to-clipboard",
      defaultValue: "Copy to Clipboard",
      comment: "Generic copy to clipboard button title"
    )
    static let copiedToClipboard = string(
      "common.copied-to-clipboard",
      defaultValue: "Copied to clipboard",
      comment: "Generic toast shown after copying content to the clipboard"
    )
    static let copy = string(
      "common.copy",
      defaultValue: "Copy",
      comment: "Generic copy button title"
    )
    static let open = string(
      "common.open",
      defaultValue: "Open",
      comment: "Generic open button title"
    )
    static let restore = string(
      "common.restore",
      defaultValue: "Restore",
      comment: "Generic restore button title"
    )
    static let openInFinder = string(
      "common.open-in-finder",
      defaultValue: "Open in Finder",
      comment: "Generic button or tooltip title for opening a file in Finder"
    )
    static let renameFile = string(
      "common.rename-file",
      defaultValue: "Rename file",
      comment: "Generic tooltip or label for renaming a file"
    )
    static let preview = string(
      "common.preview",
      defaultValue: "Preview",
      comment: "Generic preview section title"
    )
    static let file = string(
      "common.file",
      defaultValue: "File",
      comment: "Generic file section title"
    )
    static let name = string(
      "common.name",
      defaultValue: "Name",
      comment: "Generic name field label"
    )
    static let path = string(
      "common.path",
      defaultValue: "Path",
      comment: "Generic path field label"
    )
    static let size = string(
      "common.size",
      defaultValue: "Size",
      comment: "Generic size field label"
    )
    static let format = string(
      "common.format",
      defaultValue: "Format",
      comment: "Generic format field label"
    )
    static let resolution = string(
      "common.resolution",
      defaultValue: "Resolution",
      comment: "Generic resolution field label"
    )
    static let aspectRatio = string(
      "common.aspect-ratio",
      defaultValue: "Aspect Ratio",
      comment: "Generic aspect ratio field label"
    )
    static let duration = string(
      "common.duration",
      defaultValue: "Duration",
      comment: "Generic duration field label"
    )
    static let created = string(
      "common.created",
      defaultValue: "Created",
      comment: "Generic created date field label"
    )
    static let modified = string(
      "common.modified",
      defaultValue: "Modified",
      comment: "Generic modified date field label"
    )
    static let status = string(
      "common.status",
      defaultValue: "Status",
      comment: "Generic status field label"
    )
    static let currentSize = string(
      "common.current-size",
      defaultValue: "Current Size",
      comment: "Generic current file size label"
    )
    static let estimated = string(
      "common.estimated",
      defaultValue: "Estimated",
      comment: "Generic estimated value label"
    )
    static let estimatedSize = string(
      "common.estimated-size",
      defaultValue: "Estimated Size",
      comment: "Generic estimated file size label"
    )
    static let quality = string(
      "common.quality",
      defaultValue: "Quality",
      comment: "Generic quality section title"
    )
    static let dimensions = string(
      "common.dimensions",
      defaultValue: "Dimensions",
      comment: "Generic dimensions section title"
    )
    static let audio = string(
      "common.audio",
      defaultValue: "Audio",
      comment: "Generic audio section title"
    )
    static let video = string(
      "common.video",
      defaultValue: "Video",
      comment: "Generic video section title"
    )
    static let background = string(
      "common.background",
      defaultValue: "Background",
      comment: "Generic background section title"
    )
    static let colors = string(
      "common.colors",
      defaultValue: "Colors",
      comment: "Generic colors section title"
    )
    static let gradients = string(
      "common.gradients",
      defaultValue: "Gradients",
      comment: "Generic gradients section title"
    )
    static let wallpapers = string(
      "common.wallpapers",
      defaultValue: "Wallpapers",
      comment: "Generic wallpapers section title"
    )
    static let padding = string(
      "common.padding",
      defaultValue: "Padding",
      comment: "Generic padding setting label"
    )
    static let inset = string(
      "common.inset",
      defaultValue: "Inset",
      comment: "Generic inset setting label"
    )
    static let shadow = string(
      "common.shadow",
      defaultValue: "Shadow",
      comment: "Generic shadow setting label"
    )
    static let corners = string(
      "common.corners",
      defaultValue: "Corners",
      comment: "Generic corners setting label"
    )
    static let rotation = string(
      "common.rotation",
      defaultValue: "Rotation",
      comment: "Generic rotation section title"
    )
    static let perspective = string(
      "common.perspective",
      defaultValue: "Perspective",
      comment: "Generic perspective section title"
    )
    static let style = string(
      "common.style",
      defaultValue: "Style",
      comment: "Generic style setting label"
    )
    static let fill = string(
      "common.fill",
      defaultValue: "Fill",
      comment: "Generic fill setting label"
    )
    static let text = string(
      "common.text",
      defaultValue: "Text",
      comment: "Generic text label"
    )
    static let color = string(
      "common.color",
      defaultValue: "Color",
      comment: "Generic color label"
    )
    static let stroke = string(
      "common.stroke",
      defaultValue: "Stroke",
      comment: "Generic stroke setting label"
    )
    static let solid = string(
      "common.solid",
      defaultValue: "Solid",
      comment: "Generic solid color label"
    )
    static let free = string(
      "common.free",
      defaultValue: "Free",
      comment: "Generic free-form option label"
    )
    static let dates = string(
      "common.dates",
      defaultValue: "Dates",
      comment: "Generic dates section title"
    )
    static let low = string(
      "common.low",
      defaultValue: "Low",
      comment: "Generic low option label"
    )
    static let medium = string(
      "common.medium",
      defaultValue: "Medium",
      comment: "Generic medium option label"
    )
    static let high = string(
      "common.high",
      defaultValue: "High",
      comment: "Generic high option label"
    )
    static let original = string(
      "common.original",
      defaultValue: "Original",
      comment: "Generic original option label"
    )
    static let custom = string(
      "common.custom",
      defaultValue: "Custom",
      comment: "Generic custom option label"
    )
    static let unsaved = string(
      "common.unsaved",
      defaultValue: "Unsaved",
      comment: "Generic unsaved status label"
    )
    static let active = string(
      "common.active",
      defaultValue: "Active",
      comment: "Generic active status label"
    )
    static let ready = string(
      "common.ready",
      defaultValue: "Ready",
      comment: "Generic ready status label"
    )
    static let enabled = string(
      "common.enabled",
      defaultValue: "Enabled",
      comment: "Generic enabled state label"
    )
    static let disabled = string(
      "common.disabled",
      defaultValue: "Disabled",
      comment: "Generic disabled state label"
    )
    static func withShortcut(_ title: String, _ shortcut: String) -> String {
      L10n.format(
        "common.with-shortcut",
        defaultValue: "%@ (%@)",
        comment: "Generic label that appends a keyboard shortcut hint to a title. First %@ is the title, second %@ is the shortcut.",
        title,
        shortcut
      )
    }
  }

  enum CaptureKind {
    static let screenshot = string(
      "capture-kind.screenshot",
      defaultValue: "Screenshot",
      comment: "Generic label for screenshot capture type"
    )
    static let recording = string(
      "capture-kind.recording",
      defaultValue: "Recording",
      comment: "Generic label for recording capture type"
    )
  }

  enum Appearance {
    static let system = string(
      "appearance.system",
      defaultValue: "System",
      comment: "Appearance mode label"
    )
    static let light = string(
      "appearance.light",
      defaultValue: "Light",
      comment: "Appearance mode label"
    )
    static let dark = string(
      "appearance.dark",
      defaultValue: "Dark",
      comment: "Appearance mode label"
    )
  }

  enum Splash {
    static let welcomeTitle = string(
      "splash.welcome-title",
      defaultValue: "Welcome to Snapzy",
      comment: "Splash screen welcome title"
    )
    static let welcomeSubtitle = string(
      "splash.welcome-subtitle",
      defaultValue: "Screenshot & recording, simplified.",
      comment: "Splash screen welcome subtitle"
    )
    static let pressEnter = string(
      "splash.press-enter",
      defaultValue: "Press Enter ↵",
      comment: "Hint shown on splash and onboarding completion to press Enter"
    )
    static let doNotShowAgain = string(
      "splash.do-not-show-again",
      defaultValue: "Do not show again",
      comment: "Checkbox label on splash screen"
    )
  }

  enum PermissionRow {
    static let required = string(
      "permission-row.required",
      defaultValue: "Required",
      comment: "Badge shown for required permissions"
    )
    static let optional = string(
      "permission-row.optional",
      defaultValue: "Optional",
      comment: "Badge shown for optional permissions"
    )
    static let granted = string(
      "permission-row.granted",
      defaultValue: "Granted",
      comment: "Status badge shown when a permission is granted"
    )
  }

  enum Sponsor {
    static let recurringSupport = string(
      "sponsor.recurring-support",
      defaultValue: "Recurring support",
      comment: "Subtitle for GitHub Sponsors option"
    )
    static let oneTimeTip = string(
      "sponsor.one-time-tip",
      defaultValue: "One-time tip",
      comment: "Subtitle for Ko-fi option"
    )
    static let directSupport = string(
      "sponsor.direct-support",
      defaultValue: "Direct support",
      comment: "Subtitle for PayPal option"
    )
  }

  enum Onboarding {
    static let welcomeSubtitle = string(
      "onboarding.welcome.subtitle",
      defaultValue: "A powerful screenshot & screen recording app for macOS",
      comment: "Welcome onboarding subtitle"
    )
    static let welcomeFeatureCapture = string(
      "onboarding.welcome.feature-capture",
      defaultValue: "Capture area or fullscreen screenshots",
      comment: "Welcome onboarding feature highlight"
    )
    static let welcomeFeatureRecord = string(
      "onboarding.welcome.feature-record",
      defaultValue: "Record screen with audio",
      comment: "Welcome onboarding feature highlight"
    )
    static let welcomeFeatureAnnotate = string(
      "onboarding.welcome.feature-annotate",
      defaultValue: "Annotate and edit captures",
      comment: "Welcome onboarding feature highlight"
    )
    static let letsDoIt = string(
      "onboarding.welcome.cta",
      defaultValue: "Let's do it!",
      comment: "Primary call to action on onboarding welcome screen"
    )
    static let languageTitle = string(
      "onboarding.language.title",
      defaultValue: "Choose your language",
      comment: "Onboarding language step title"
    )
    static let languageSubtitle = string(
      "onboarding.language.subtitle",
      defaultValue: "Snapzy can follow your Mac or preview a specific app language during setup.",
      comment: "Onboarding language step subtitle"
    )
    static let languageAutoTitle = string(
      "onboarding.language.auto-title",
      defaultValue: "Auto",
      comment: "Auto language option title shown during onboarding"
    )
    static func languageAutoDescription(_ languageName: String) -> String {
      format(
        "onboarding.language.auto-description",
        defaultValue: "Follow macOS. Currently %@.",
        comment: "Description for the onboarding auto language option. %@ is the resolved language display name.",
        languageName
      )
    }
    static let languageApplyLater = string(
      "onboarding.language.apply-later",
      defaultValue: "Continue and Apply on Finish",
      comment: "Primary button title when onboarding language changes will be applied after completing onboarding"
    )
    static let languagePreferencesHint = string(
      "onboarding.language.preferences-hint",
      defaultValue: "You can change this anytime in Preferences -> General.",
      comment: "Hint shown below the onboarding language picker"
    )

    static let permissionsTitle = string(
      "onboarding.permissions.title",
      defaultValue: "Grant Permissions",
      comment: "Onboarding permissions step title"
    )
    static let permissionsSubtitle = string(
      "onboarding.permissions.subtitle",
      defaultValue: "Snapzy needs permissions for capture, audio, and save location.",
      comment: "Onboarding permissions step subtitle"
    )
    static let screenRecording = string(
      "onboarding.permissions.screen-recording",
      defaultValue: "Screen Recording",
      comment: "Screen recording permission label"
    )
    static let saveFolder = string(
      "onboarding.permissions.save-folder",
      defaultValue: "Save Folder",
      comment: "Save folder permission label"
    )
    static let microphone = string(
      "onboarding.permissions.microphone",
      defaultValue: "Microphone",
      comment: "Microphone permission label"
    )
    static let accessibility = string(
      "onboarding.permissions.accessibility",
      defaultValue: "Accessibility",
      comment: "Accessibility permission label"
    )
    static let requiredForCaptures = string(
      "onboarding.permissions.required-for-captures",
      defaultValue: "Required for screenshots and recordings",
      comment: "Permission description for required capture-related permissions"
    )
    static let optionalForVoiceRecording = string(
      "onboarding.permissions.optional-voice-recording",
      defaultValue: "Optional for voice recording",
      comment: "Permission description for microphone access"
    )
    static let optionalForGlobalShortcuts = string(
      "onboarding.permissions.optional-global-shortcuts",
      defaultValue: "Optional for global shortcuts",
      comment: "Permission description for accessibility access"
    )
    static let grantAccess = string(
      "onboarding.permissions.grant-access",
      defaultValue: "Grant Access",
      comment: "Button title to grant permission or folder access"
    )
    static let refreshStatus = string(
      "onboarding.permissions.refresh-status",
      defaultValue: "Refresh Status",
      comment: "Button title to refresh permission or identity status"
    )
    static let unavailable = string(
      "onboarding.permissions.unavailable",
      defaultValue: "Unavailable",
      comment: "Badge shown when permission is unavailable due to app identity state"
    )
    static let buildIdentityNeedsAttention = string(
      "onboarding.permissions.identity-attention",
      defaultValue: "Build Identity Needs Attention",
      comment: "Warning title when app identity health issues block permission usage"
    )
    static let quit = string(
      "onboarding.permissions.quit",
      defaultValue: "Quit",
      comment: "Quit button title in onboarding permissions step"
    )
    static let chooseFolderMessage = string(
      "onboarding.permissions.choose-folder-message",
      defaultValue: "Choose a folder for Snapzy captures (default: Desktop/Snapzy)",
      comment: "Open panel message for selecting export directory during onboarding"
    )
    static let screenRecordingIdentityBlocked = string(
      "onboarding.permissions.identity-blocked-description",
      defaultValue: "Granted in System Settings, but this build cannot use the permission until the identity issues below are fixed.",
      comment: "Description shown when screen recording permission exists but app identity prevents using it"
    )

    static let shortcutsTitle = string(
      "onboarding.shortcuts.title",
      defaultValue: "Set as default screenshot tool?",
      comment: "Onboarding shortcuts step title"
    )
    static let shortcutsSubtitle = string(
      "onboarding.shortcuts.subtitle",
      defaultValue: "Assign system shortcuts to Snapzy for quick access.",
      comment: "Onboarding shortcuts step subtitle"
    )
    static let recordingSection = string(
      "onboarding.shortcuts.section-recording",
      defaultValue: "Recording",
      comment: "Shortcut group title in onboarding"
    )
    static let toolsSection = string(
      "onboarding.shortcuts.section-tools",
      defaultValue: "Tools",
      comment: "Shortcut group title in onboarding"
    )
    static let resolveShortcutOverlap = string(
      "onboarding.shortcuts.resolve-overlap",
      defaultValue: "Resolve macOS shortcut overlap",
      comment: "Warning title when system screenshot shortcuts overlap with Snapzy shortcuts"
    )
    static let openSettings = string(
      "onboarding.shortcuts.open-settings",
      defaultValue: "Open Settings →",
      comment: "Action hint to open system settings"
    )
    static let guideStep1 = string(
      "onboarding.shortcuts.guide-step-1",
      defaultValue: "Open System Settings → Keyboard → Keyboard Shortcuts",
      comment: "Step 1 in onboarding shortcut conflict resolution guide"
    )
    static let guideStep2 = string(
      "onboarding.shortcuts.guide-step-2",
      defaultValue: "Select Screenshots from the sidebar",
      comment: "Step 2 in onboarding shortcut conflict resolution guide"
    )
    static let guideStep3 = string(
      "onboarding.shortcuts.guide-step-3",
      defaultValue: "Uncheck the macOS screenshot shortcuts that overlap with the Snapzy shortcuts you want to keep on",
      comment: "Step 3 in onboarding shortcut conflict resolution guide"
    )
    static let noConflictDetected = string(
      "onboarding.shortcuts.no-conflict",
      defaultValue: "No overlapping macOS screenshot shortcuts detected — ready to go!",
      comment: "Success message when no system shortcut conflict exists"
    )
    static let customizeHint = string(
      "onboarding.shortcuts.customize-hint",
      defaultValue: "You can customize or turn off shortcuts anytime in Preferences → Shortcuts.",
      comment: "Hint text below shortcut setup card"
    )
    static let noThanks = string(
      "onboarding.shortcuts.no-thanks",
      defaultValue: "No, thanks",
      comment: "Secondary decline button on shortcut setup screen"
    )
    static let enableShortcuts = string(
      "onboarding.shortcuts.enable",
      defaultValue: "Yes, enable shortcuts",
      comment: "Primary accept button on shortcut setup screen"
    )

    static let diagnosticsTitle = string(
      "onboarding.diagnostics.title",
      defaultValue: "Help Us Improve",
      comment: "Diagnostics opt-in title"
    )
    static let diagnosticsDescription = string(
      "onboarding.diagnostics.description",
      defaultValue: "Snapzy can collect anonymous diagnostic logs when something goes wrong. These logs help us find and fix bugs faster.",
      comment: "Diagnostics opt-in description"
    )
    static let enableDiagnosticLogging = string(
      "onboarding.diagnostics.enable-crash-logging",
      defaultValue: "Enable Diagnostic Logging",
      comment: "Diagnostics toggle title"
    )
    static let logsStoredLocally = string(
      "onboarding.diagnostics.logs-stored-locally",
      defaultValue: "Logs are stored locally on your device",
      comment: "Diagnostics toggle description"
    )
    static let diagnosticsPrivacyNote = string(
      "onboarding.diagnostics.privacy-note",
      defaultValue: "No personal data is collected. Nothing is sent without your action.",
      comment: "Diagnostics opt-in privacy note"
    )

    static let skipTitle = string(
      "onboarding.skip.title",
      defaultValue: "Skip remaining setup?",
      comment: "Skip onboarding confirmation title"
    )
    static let skipDescription = string(
      "onboarding.skip.description",
      defaultValue: "All remaining settings will use their defaults. You can always change them later in Preferences.",
      comment: "Skip onboarding confirmation description"
    )
    static let skipShortcutDefaults = string(
      "onboarding.skip.shortcut-defaults",
      defaultValue: "Keyboard shortcuts — system defaults",
      comment: "List item describing what will be skipped during onboarding"
    )
    static let goBack = string(
      "onboarding.skip.go-back",
      defaultValue: "Go Back",
      comment: "Button title to return from skip onboarding confirmation"
    )
    static let skipSetup = string(
      "onboarding.skip.skip-setup",
      defaultValue: "Skip Setup",
      comment: "Button title to confirm skipping onboarding setup"
    )

    static let sponsorTitle = string(
      "onboarding.sponsor.title",
      defaultValue: "Sponsor the Author",
      comment: "Onboarding sponsor step title"
    )
    static let sponsorDescription = string(
      "onboarding.sponsor.description",
      defaultValue: "Snapzy is now open-source. If it saves you time, consider supporting ongoing development.",
      comment: "Onboarding sponsor step description"
    )
    static let sponsorOptionalNote = string(
      "onboarding.sponsor.optional-note",
      defaultValue: "Support is optional. Snapzy remains fully usable without sponsoring.",
      comment: "Note under sponsor options"
    )

    static let completionTitle = string(
      "onboarding.completion.title",
      defaultValue: "You're all set!",
      comment: "Onboarding completion title"
    )
    static let completionDescription = string(
      "onboarding.completion.description",
      defaultValue: "Snapzy is ready. Access it from the menu bar or use your keyboard shortcuts.",
      comment: "Onboarding completion description"
    )
    static let menuBar = string(
      "onboarding.completion.menu-bar",
      defaultValue: "Menu Bar",
      comment: "Completion card title"
    )
    static let menuBarHint = string(
      "onboarding.completion.menu-bar-hint",
      defaultValue: "Look for the camera icon in your menu bar",
      comment: "Completion card description"
    )
    static let shortcutsHint = string(
      "onboarding.completion.shortcuts-hint",
      defaultValue: "Use ⇧⌘3, ⇧⌘4, ⇧⌘5 to capture anytime",
      comment: "Completion card description"
    )
    static let preferencesHint = string(
      "onboarding.completion.preferences-hint",
      defaultValue: "Customize shortcuts, output format, and more",
      comment: "Completion card description"
    )
    static let openPreferences = string(
      "onboarding.completion.open-preferences",
      defaultValue: "Open Preferences",
      comment: "Secondary action on onboarding completion screen"
    )
    static let getStarted = string(
      "onboarding.completion.get-started",
      defaultValue: "Get Started",
      comment: "Primary action on onboarding completion screen"
    )
  }

  enum ShortcutOverlay {
    static let title = string(
      "shortcut-overlay.title",
      defaultValue: "Keyboard Shortcuts",
      comment: "Shortcut overlay title"
    )
    static let subtitle = string(
      "shortcut-overlay.subtitle",
      defaultValue: "Press Esc or click outside to close",
      comment: "Shortcut overlay subtitle"
    )
    static let closeHelp = string(
      "shortcut-overlay.close-help",
      defaultValue: "Close",
      comment: "Tooltip on close button in shortcut overlay"
    )
    static let customizeInSettings = string(
      "shortcut-overlay.customize-in-settings",
      defaultValue: "Customize in Settings…",
      comment: "Button title to open settings from shortcut overlay"
    )
    static let captureSection = string(
      "shortcut-overlay.section-capture",
      defaultValue: "Capture",
      comment: "Shortcut overlay section title"
    )
    static let toolsSection = string(
      "shortcut-overlay.section-tools",
      defaultValue: "Tools",
      comment: "Shortcut overlay section title"
    )
    static let annotateActions = string(
      "shortcut-overlay.annotate-actions",
      defaultValue: "Annotate Actions",
      comment: "Shortcut overlay section title"
    )
    static let annotateToolKeys = string(
      "shortcut-overlay.annotate-tool-keys",
      defaultValue: "Annotate Tool Keys",
      comment: "Shortcut overlay section title"
    )
    static let annotateReference = string(
      "shortcut-overlay.annotate-reference",
      defaultValue: "Annotate Reference",
      comment: "Shortcut overlay section title"
    )
    static let insideAnnotateEditor = string(
      "shortcut-overlay.inside-annotate-editor",
      defaultValue: "Inside annotate editor",
      comment: "Subtitle for annotate action shortcuts in overlay"
    )
    static func applicationCapture(_ shortcut: String) -> String {
      format(
        "shortcut-overlay.application-capture",
        defaultValue: "Application Capture: %@",
        comment: "Subtitle for the Capture Area shortcut row in the overlay. %@ is the current single-key toggle used inside the area capture overlay.",
        shortcut
      )
    }
    static func applicationRecording(_ shortcut: String) -> String {
      format(
        "shortcut-overlay.application-recording",
        defaultValue: "Application Recording: %@",
        comment: "Subtitle for the Record Video shortcut row in the overlay. %@ is the current single-key toggle used inside the recording selection and pre-record toolbar.",
        shortcut
      )
    }
    static let saveDone = string(
      "shortcut-overlay.save-done",
      defaultValue: "Save (Done)",
      comment: "Annotate reference item title"
    )
    static let saveAs = string(
      "shortcut-overlay.save-as",
      defaultValue: "Save As…",
      comment: "Annotate reference item title"
    )
    static let undo = string(
      "shortcut-overlay.undo",
      defaultValue: "Undo",
      comment: "Annotate reference item title"
    )
    static let redo = string(
      "shortcut-overlay.redo",
      defaultValue: "Redo",
      comment: "Annotate reference item title"
    )
    static let deleteAnnotation = string(
      "shortcut-overlay.delete-annotation",
      defaultValue: "Delete Annotation",
      comment: "Annotate reference item title"
    )
    static let cancelDeselect = string(
      "shortcut-overlay.cancel-deselect",
      defaultValue: "Cancel / Deselect",
      comment: "Annotate reference item title"
    )
    static let confirmCrop = string(
      "shortcut-overlay.confirm-crop",
      defaultValue: "Confirm Crop",
      comment: "Annotate reference item title"
    )
    static let nudgeAnnotation = string(
      "shortcut-overlay.nudge-annotation",
      defaultValue: "Nudge Annotation",
      comment: "Annotate reference item title"
    )
    static let nudgeTenPixels = string(
      "shortcut-overlay.nudge-10px",
      defaultValue: "Nudge 10px",
      comment: "Annotate reference item title"
    )
    static let screenshotAndRecording = string(
      "shortcut-overlay.screenshot-and-recording",
      defaultValue: "Screenshot + Recording",
      comment: "Subtitle for annotate tools available in both screenshot and recording contexts"
    )
    static let recordingOnly = string(
      "shortcut-overlay.recording-only",
      defaultValue: "Recording only",
      comment: "Subtitle for annotate tools available only in recording context"
    )
    static let screenshotOnly = string(
      "shortcut-overlay.screenshot-only",
      defaultValue: "Screenshot only",
      comment: "Subtitle for annotate tools available only in screenshot context"
    )
    static let copyAndClose = string(
      "shortcut-overlay.copy-and-close",
      defaultValue: "Copy & Close",
      comment: "Annotate action shortcut title"
    )
    static let togglePin = string(
      "shortcut-overlay.toggle-pin",
      defaultValue: "Toggle Pin",
      comment: "Annotate action shortcut title"
    )
    static let cloudUpload = string(
      "shortcut-overlay.cloud-upload",
      defaultValue: "Cloud Upload",
      comment: "Annotate action shortcut title"
    )
  }

  enum ShortcutRecorder {
    static let pressKeys = string(
      "shortcut-recorder.press-keys",
      defaultValue: "Press keys...",
      comment: "Placeholder text shown while recording a shortcut"
    )
    static let clickToRecord = string(
      "shortcut-recorder.click-to-record",
      defaultValue: "Click to record a shortcut.",
      comment: "Help text for shortcut recorder button"
    )
    static let turnOnToEdit = string(
      "shortcut-recorder.turn-on-to-edit",
      defaultValue: "Turn this shortcut on to edit it.",
      comment: "Help text shown when shortcut recorder is disabled"
    )
    static func usedBy(_ displayName: String) -> String {
      format(
        "shortcut-recorder.used-by",
        defaultValue: "Used by %@",
        comment: "Conflict label for a shortcut already used by another action or tool. %@ is the conflicting action name.",
        displayName
      )
    }
  }

  enum ShortcutValidation {
    static func alreadyUsedBy(_ displayName: String) -> String {
      format(
        "shortcut-validation.already-used-by",
        defaultValue: "Already used by %@.",
        comment: "Validation error for duplicate shortcut. %@ is the conflicting action name.",
        displayName
      )
    }

    static func alreadyUsedByInAnnotate(_ displayName: String) -> String {
      format(
        "shortcut-validation.already-used-by-annotate",
        defaultValue: "Already used by %@ in Annotate Editor.",
        comment: "Validation error for duplicate shortcut in annotate editor. %@ is the conflicting action name.",
        displayName
      )
    }

    static func matchesSystemConflict(_ displayName: String) -> String {
      format(
        "shortcut-validation.matches-system-conflict",
        defaultValue: "Matches %@. macOS may win.",
        comment: "Validation warning when shortcut overlaps with a macOS system shortcut. %@ is the system shortcut description.",
        displayName
      )
    }
  }

  enum PreferencesGeneral {
    static let startupSection = string(
      "preferences-general.section-startup",
      defaultValue: "Startup",
      comment: "General preferences section title"
    )
    static let appearanceSection = string(
      "preferences-general.section-appearance",
      defaultValue: "Appearance",
      comment: "General preferences section title"
    )
    static let storageSection = string(
      "preferences-general.section-storage",
      defaultValue: "Storage",
      comment: "General preferences section title"
    )
    static let updatesSection = string(
      "preferences-general.section-updates",
      defaultValue: "Software Updates",
      comment: "General preferences section title"
    )
    static let diagnosticsSection = string(
      "preferences-general.section-diagnostics",
      defaultValue: "Diagnostics",
      comment: "General preferences section title"
    )
    static let helpSection = string(
      "preferences-general.section-help",
      defaultValue: "Help",
      comment: "General preferences section title"
    )
    static let startAtLoginTitle = string(
      "preferences-general.start-at-login-title",
      defaultValue: "Start at login",
      comment: "General preferences setting title"
    )
    static let startAtLoginDescription = string(
      "preferences-general.start-at-login-description",
      defaultValue: "Launch Snapzy when you log in",
      comment: "General preferences setting description"
    )
    static let playSoundsTitle = string(
      "preferences-general.play-sounds-title",
      defaultValue: "Play sounds",
      comment: "General preferences setting title"
    )
    static let playSoundsDescription = string(
      "preferences-general.play-sounds-description",
      defaultValue: "Audio feedback for captures",
      comment: "General preferences setting description"
    )
    static let themeTitle = string(
      "preferences-general.theme-title",
      defaultValue: "Theme",
      comment: "General preferences setting title"
    )
    static let themeDescription = string(
      "preferences-general.theme-description",
      defaultValue: "Choose your preferred appearance",
      comment: "General preferences setting description"
    )
    static let languageTitle = string(
      "preferences-general.language-title",
      defaultValue: "App Language",
      comment: "General preferences setting title"
    )
    static let languageDescription = string(
      "preferences-general.language-description",
      defaultValue: "Choose the language used across Snapzy",
      comment: "General preferences setting description"
    )
    static let languageSystem = string(
      "preferences-general.language-system",
      defaultValue: "System Default",
      comment: "General preferences picker option that follows the macOS app language"
    )
    static let languageRestartHint = string(
      "preferences-general.language-restart-hint",
      defaultValue: "Language changes apply after relaunch",
      comment: "General preferences helper text shown when a language change is pending"
    )
    static let languageRelaunchConfirmationTitle = string(
      "preferences-general.language-relaunch-confirmation-title",
      defaultValue: "Relaunch Snapzy?",
      comment: "Alert title shown before the app relaunches to apply a language change"
    )
    static let languageRelaunchConfirmationMessage = string(
      "preferences-general.language-relaunch-confirmation-message",
      defaultValue: "Snapzy needs to quit and reopen to apply this language change everywhere.",
      comment: "Alert message shown before the app relaunches to apply a language change"
    )
    static let languageRelaunchConfirmationAction = string(
      "preferences-general.language-relaunch-confirmation-action",
      defaultValue: "Relaunch Snapzy",
      comment: "Alert button title that confirms relaunching the app after changing language"
    )
    static let languageRelaunchErrorTitle = string(
      "preferences-general.language-relaunch-error-title",
      defaultValue: "Could Not Relaunch Snapzy",
      comment: "Alert title shown when the app cannot relaunch after changing language"
    )
    static let saveLocationTitle = string(
      "preferences-general.save-location-title",
      defaultValue: "Save location",
      comment: "General preferences setting title"
    )
    static let saveLocationDescription = string(
      "preferences-general.save-location-description",
      defaultValue: "Where Snapzy stores captures",
      comment: "General preferences setting description"
    )
    static let chooseButton = string(
      "preferences-general.choose-button",
      defaultValue: "Choose...",
      comment: "General preferences button title"
    )
    static let checkAutomaticallyTitle = string(
      "preferences-general.check-automatically-title",
      defaultValue: "Check automatically",
      comment: "General preferences setting title"
    )
    static let checkAutomaticallyDescription = string(
      "preferences-general.check-automatically-description",
      defaultValue: "Look for updates on launch",
      comment: "General preferences setting description"
    )
    static let downloadAutomaticallyTitle = string(
      "preferences-general.download-automatically-title",
      defaultValue: "Download automatically",
      comment: "General preferences setting title"
    )
    static let downloadAutomaticallyDescription = string(
      "preferences-general.download-automatically-description",
      defaultValue: "Download updates in background",
      comment: "General preferences setting description"
    )
    static let lastCheckedTitle = string(
      "preferences-general.last-checked-title",
      defaultValue: "Last checked",
      comment: "General preferences setting title"
    )
    static let never = string(
      "preferences-general.never",
      defaultValue: "Never",
      comment: "Label shown when an event has never happened"
    )
    static let diagnosticLoggingTitle = string(
      "preferences-general.crash-logging-title",
      defaultValue: "Diagnostic Logging",
      comment: "General preferences setting title"
    )
    static let diagnosticLoggingDescription = string(
      "preferences-general.crash-logging-description",
      defaultValue: "Save local logs for app, capture, recording, and crash diagnostics",
      comment: "General preferences setting description"
    )
    static let logFilesTitle = string(
      "preferences-general.log-files-title",
      defaultValue: "Log Files",
      comment: "General preferences setting title"
    )
    static let logRetentionTitle = string(
      "preferences-general.log-retention-title",
      defaultValue: "Keep Logs For",
      comment: "General preferences setting title"
    )
    static func logRetentionDescription(_ days: Int) -> String {
      format(
        "preferences-general.log-retention-description",
        defaultValue: "Keep one diagnostic log file per day for %d days",
        comment: "General preferences setting description. %d is the number of days.",
        days
      )
    }
    static let openFolderButton = string(
      "preferences-general.open-folder-button",
      defaultValue: "Open Folder",
      comment: "General preferences button title"
    )
    static let openReportPageButton = string(
      "preferences-general.open-report-page-button",
      defaultValue: "Open Report Page",
      comment: "General preferences button title"
    )
    static let reportIssueTitle = string(
      "preferences-general.report-issue-title",
      defaultValue: "Report a Problem",
      comment: "General preferences setting title"
    )
    static func reportIssueDescription(_ destination: String) -> String {
      format(
        "preferences-general.report-issue-description",
        defaultValue: "Send a diagnostic log bundle at %@ when something goes wrong",
        comment: "General preferences setting description. %@ is the problem report destination.",
        destination
      )
    }
    static let restartOnboardingTitle = string(
      "preferences-general.restart-onboarding-title",
      defaultValue: "Restart Onboarding",
      comment: "General preferences setting title"
    )
    static let restartOnboardingDescription = string(
      "preferences-general.restart-onboarding-description",
      defaultValue: "Show the welcome tutorial again",
      comment: "General preferences setting description"
    )
    static let restartButton = string(
      "preferences-general.restart-button",
      defaultValue: "Restart",
      comment: "General preferences button title"
    )
    static let calculating = string(
      "preferences-general.calculating",
      defaultValue: "Calculating...",
      comment: "Placeholder while a storage value is being calculated"
    )
    static let noLogs = string(
      "preferences-general.no-logs",
      defaultValue: "No logs",
      comment: "Label shown when there are no diagnostic log files"
    )
    static let defaultSaveLocation = string(
      "preferences-general.default-save-location",
      defaultValue: "Desktop/Snapzy",
      comment: "Default export location display label"
    )
    static func accessNotGranted(_ folderName: String) -> String {
      format(
        "preferences-general.access-not-granted",
        defaultValue: "%@ (Access not granted)",
        comment: "Export folder display when bookmark access is missing. %@ is the folder name.",
        folderName
      )
    }
    static let chooseSaveLocationMessage = string(
      "preferences-general.choose-save-location-message",
      defaultValue: "Choose where Snapzy saves captures",
      comment: "Open panel message for selecting the default export location"
    )
    static let saveHereButton = string(
      "preferences-general.save-here-button",
      defaultValue: "Save Here",
      comment: "Open panel prompt for choosing export location"
    )
  }

  enum PreferencesPermissions {
    static let intro = string(
      "preferences-permissions.intro",
      defaultValue: "Snapzy requires certain permissions to capture your screen and audio.",
      comment: "Introductory text for the permissions preferences tab"
    )
  }

  enum PreferencesQuickAccess {
    static let positionSection = string(
      "preferences-quick-access.section-position",
      defaultValue: "Position",
      comment: "Quick access preferences section title"
    )
    static let appearanceSection = string(
      "preferences-quick-access.section-appearance",
      defaultValue: "Appearance",
      comment: "Quick access preferences section title"
    )
    static let behaviorsSection = string(
      "preferences-quick-access.section-behaviors",
      defaultValue: "Behaviors",
      comment: "Quick access preferences section title"
    )
    static let screenEdgeTitle = string(
      "preferences-quick-access.screen-edge-title",
      defaultValue: "Screen Edge",
      comment: "Quick access preferences setting title"
    )
    static let screenEdgeDescription = string(
      "preferences-quick-access.screen-edge-description",
      defaultValue: "Where the overlay appears",
      comment: "Quick access preferences setting description"
    )
    static let left = string(
      "preferences-quick-access.left",
      defaultValue: "Left",
      comment: "Quick access side label"
    )
    static let right = string(
      "preferences-quick-access.right",
      defaultValue: "Right",
      comment: "Quick access side label"
    )
    static let overlaySizeTitle = string(
      "preferences-quick-access.overlay-size-title",
      defaultValue: "Overlay Size",
      comment: "Quick access preferences setting title"
    )
    static let overlaySizeDescription = string(
      "preferences-quick-access.overlay-size-description",
      defaultValue: "Adjust the floating preview size",
      comment: "Quick access preferences setting description"
    )
    static let floatingOverlayTitle = string(
      "preferences-quick-access.floating-overlay-title",
      defaultValue: "Floating Overlay",
      comment: "Quick access preferences setting title"
    )
    static let floatingOverlayDescription = string(
      "preferences-quick-access.floating-overlay-description",
      defaultValue: "Show preview after capture",
      comment: "Quick access preferences setting description"
    )
    static let autoCloseTitle = string(
      "preferences-quick-access.auto-close-title",
      defaultValue: "Auto-close",
      comment: "Quick access preferences setting title"
    )
    static let closeAfter = string(
      "preferences-quick-access.close-after",
      defaultValue: "Close after",
      comment: "Quick access slider label"
    )
    static let pauseOnHoverTitle = string(
      "preferences-quick-access.pause-on-hover-title",
      defaultValue: "Pause on Hover",
      comment: "Quick access preferences setting title"
    )
    static let pauseOnHoverDescription = string(
      "preferences-quick-access.pause-on-hover-description",
      defaultValue: "Pause countdown when hovering over the card",
      comment: "Quick access preferences setting description"
    )
    static let dragAndDropTitle = string(
      "preferences-quick-access.drag-and-drop-title",
      defaultValue: "Drag & Drop",
      comment: "Quick access preferences setting title"
    )
    static let dragAndDropDescription = string(
      "preferences-quick-access.drag-and-drop-description",
      defaultValue: "Drag captures to other apps",
      comment: "Quick access preferences setting description"
    )
    static func closesAfter(_ seconds: Int) -> String {
      format(
        "preferences-quick-access.closes-after",
        defaultValue: "Closes after %d seconds",
        comment: "Quick access auto-close description. %d is the number of seconds.",
        seconds
      )
    }
    static let keepOpenUntilDismissed = string(
      "preferences-quick-access.keep-open",
      defaultValue: "Keep overlay open until dismissed",
      comment: "Quick access description when auto-close is disabled"
    )
  }

  enum PreferencesCapture {
    static let appWindowsSection = string(
      "preferences-capture.section-app-windows",
      defaultValue: "App Windows",
      comment: "Capture preferences section title"
    )
    static let desktopSection = string(
      "preferences-capture.section-desktop",
      defaultValue: "Desktop",
      comment: "Capture preferences section title"
    )
    static let screenshotFormatSection = string(
      "preferences-capture.section-screenshot-format",
      defaultValue: "Screenshot Format",
      comment: "Capture preferences section title"
    )

    static let scrollingCaptureSection = string(
      "preferences-capture.section-scrolling-capture",
      defaultValue: "Scrolling Capture",
      comment: "Capture preferences section title"
    )
    static let outputNamingSection = string(
      "preferences-capture.section-output-naming",
      defaultValue: "Output Naming",
      comment: "Capture preferences section title"
    )
    static let recordingFormatSection = string(
      "preferences-capture.section-recording-format",
      defaultValue: "Recording Format",
      comment: "Capture preferences section title"
    )
    static let recordingQualitySection = string(
      "preferences-capture.section-recording-quality",
      defaultValue: "Recording Quality",
      comment: "Capture preferences section title"
    )
    static let recordingBehaviorSection = string(
      "preferences-capture.section-recording-behavior",
      defaultValue: "Recording Behavior",
      comment: "Capture preferences section title"
    )
    static let mouseHighlightSection = string(
      "preferences-capture.section-mouse-highlight",
      defaultValue: "Mouse Highlight",
      comment: "Capture preferences section title"
    )
    static let keystrokeOverlaySection = string(
      "preferences-capture.section-keystroke-overlay",
      defaultValue: "Keystroke Overlay",
      comment: "Capture preferences section title"
    )
    static let audioSection = string(
      "preferences-capture.section-audio",
      defaultValue: "Audio",
      comment: "Capture preferences section title"
    )
    static let afterCaptureSection = string(
      "preferences-capture.section-after-capture",
      defaultValue: "After Capture",
      comment: "Capture preferences section title"
    )

    static let includeInScreenshotsTitle = string(
      "preferences-capture.include-in-screenshots-title",
      defaultValue: "Include in Screenshots",
      comment: "Capture preferences setting title"
    )
    static let includeInScreenshotsDescription = string(
      "preferences-capture.include-in-screenshots-description",
      defaultValue: "Show Snapzy windows such as Annotate in captured images",
      comment: "Capture preferences setting description"
    )
    static let includeInRecordingsTitle = string(
      "preferences-capture.include-in-recordings-title",
      defaultValue: "Include in Recordings",
      comment: "Capture preferences setting title"
    )
    static let includeInRecordingsDescription = string(
      "preferences-capture.include-in-recordings-description",
      defaultValue: "Show Snapzy windows such as Annotate in recorded videos",
      comment: "Capture preferences setting description"
    )
    static let hideDesktopIconsTitle = string(
      "preferences-capture.hide-desktop-icons-title",
      defaultValue: "Hide desktop icons",
      comment: "Capture preferences setting title"
    )
    static let hideDesktopIconsDescription = string(
      "preferences-capture.hide-desktop-icons-description",
      defaultValue: "Temporarily hide icons during capture",
      comment: "Capture preferences setting description"
    )
    static let hideDesktopWidgetsTitle = string(
      "preferences-capture.hide-desktop-widgets-title",
      defaultValue: "Hide desktop widgets",
      comment: "Capture preferences setting title"
    )
    static let hideDesktopWidgetsDescription = string(
      "preferences-capture.hide-desktop-widgets-description",
      defaultValue: "Temporarily hide widgets during capture",
      comment: "Capture preferences setting description"
    )
    static let showCursorTitle = string(
      "preferences-capture.show-cursor-title",
      defaultValue: "Show cursor",
      comment: "Capture preferences setting title"
    )
    static let showCursorDescription = string(
      "preferences-capture.show-cursor-description",
      defaultValue: "Include mouse pointer in captured screenshots",
      comment: "Capture preferences setting description"
    )
    static let imageFormatTitle = string(
      "preferences-capture.image-format-title",
      defaultValue: "Image Format",
      comment: "Capture preferences setting title"
    )
    static let imageFormatDescription = string(
      "preferences-capture.image-format-description",
      defaultValue: "Output format for captured screenshots",
      comment: "Capture preferences setting description"
    )
    static let webpWarning = string(
      "preferences-capture.webp-warning",
      defaultValue: "WebP encoding is slower than other formats. For faster capture speed, consider using PNG or JPEG.",
      comment: "Warning shown when WebP screenshot format is selected"
    )
    static let jpegCutoutNote = string(
      "preferences-capture.jpeg-cutout-note",
      defaultValue: "Object cutout captures require transparency. Snapzy will save them as PNG even when JPEG is selected.",
      comment: "Informational note shown when JPEG screenshot format is selected"
    )

    static let showSessionHintsTitle = string(
      "preferences-capture.show-session-hints-title",
      defaultValue: "Show Session Hints",
      comment: "Capture preferences setting title"
    )
    static let showSessionHintsDescription = string(
      "preferences-capture.show-session-hints-description",
      defaultValue: "Keep guidance visible when starting a scrolling capture session",
      comment: "Capture preferences setting description"
    )
    static let scrollingCaptureInfo = string(
      "preferences-capture.scrolling-capture-info",
      defaultValue: "Best results come from selecting only the moving content, then scrolling in one direction at a steady pace.",
      comment: "Informational note for scrolling capture preferences"
    )
    static let screenshotTemplateTitle = string(
      "preferences-capture.screenshot-template-title",
      defaultValue: "Screenshot Template",
      comment: "Capture preferences setting title"
    )
    static let screenshotTemplateDescription = string(
      "preferences-capture.screenshot-template-description",
      defaultValue: "Pattern for auto-saved screenshot filename",
      comment: "Capture preferences setting description"
    )
    static let recordingTemplateTitle = string(
      "preferences-capture.recording-template-title",
      defaultValue: "Recording Template",
      comment: "Capture preferences setting title"
    )
    static let recordingTemplateDescription = string(
      "preferences-capture.recording-template-description",
      defaultValue: "Pattern for auto-saved recording filename",
      comment: "Capture preferences setting description"
    )
    static let availableTokens = string(
      "preferences-capture.available-tokens",
      defaultValue: "Available tokens: {datetime}, {date}, {time}, {ms}, {timestamp}, {type}",
      comment: "Informational text listing available filename template tokens"
    )
    static func screenshotPreview(_ preview: String) -> String {
      format(
        "preferences-capture.screenshot-preview",
        defaultValue: "Screenshot preview: %@",
        comment: "Filename template preview label. %@ is the preview filename.",
        preview
      )
    }
    static func recordingPreview(_ preview: String) -> String {
      format(
        "preferences-capture.recording-preview",
        defaultValue: "Recording preview: %@",
        comment: "Filename template preview label. %@ is the preview filename.",
        preview
      )
    }
    static let resetNamingDefaults = string(
      "preferences-capture.reset-naming-defaults",
      defaultValue: "Reset Naming Defaults",
      comment: "Button title to reset filename templates"
    )
    static let videoFormatTitle = string(
      "preferences-capture.video-format-title",
      defaultValue: "Video Format",
      comment: "Capture preferences setting title"
    )
    static let videoFormatDescription = string(
      "preferences-capture.video-format-description",
      defaultValue: "MOV offers better quality. MP4 provides wider compatibility.",
      comment: "Capture preferences setting description"
    )
    static let frameRateTitle = string(
      "preferences-capture.frame-rate-title",
      defaultValue: "Frame Rate",
      comment: "Capture preferences setting title"
    )
    static let frameRateDescription = string(
      "preferences-capture.frame-rate-description",
      defaultValue: "Higher FPS for smoother motion",
      comment: "Capture preferences setting description"
    )
    static let qualityTitle = string(
      "preferences-capture.quality-title",
      defaultValue: "Quality",
      comment: "Capture preferences setting title"
    )
    static let qualityDescription = string(
      "preferences-capture.quality-description",
      defaultValue: "Higher quality = larger file size",
      comment: "Capture preferences setting description"
    )
    static let rememberLastAreaTitle = string(
      "preferences-capture.remember-last-area-title",
      defaultValue: "Remember Last Area",
      comment: "Capture preferences setting title"
    )
    static let rememberLastAreaDescription = string(
      "preferences-capture.remember-last-area-description",
      defaultValue: "Restore previous recording area on next capture",
      comment: "Capture preferences setting description"
    )
    static let highlightSizeTitle = string(
      "preferences-capture.highlight-size-title",
      defaultValue: "Highlight Size",
      comment: "Capture preferences setting title"
    )
    static func highlightSizeDescription(_ pixels: Int) -> String {
      format(
        "preferences-capture.highlight-size-description",
        defaultValue: "Diameter of ripple effect (%dpx)",
        comment: "Mouse highlight size description. %d is the pixel size.",
        pixels
      )
    }
    static let animationDurationTitle = string(
      "preferences-capture.animation-duration-title",
      defaultValue: "Animation Duration",
      comment: "Capture preferences setting title"
    )
    static func animationDurationDescription(_ seconds: String) -> String {
      format(
        "preferences-capture.animation-duration-description",
        defaultValue: "Ripple expand speed (%@s)",
        comment: "Mouse highlight animation duration description. %@ is the formatted seconds value.",
        seconds
      )
    }
    static let rippleCountTitle = string(
      "preferences-capture.ripple-count-title",
      defaultValue: "Ripple Count",
      comment: "Capture preferences setting title"
    )
    static let rippleCountDescription = string(
      "preferences-capture.ripple-count-description",
      defaultValue: "Number of expanding rings",
      comment: "Capture preferences setting description"
    )
    static let highlightColorTitle = string(
      "preferences-capture.highlight-color-title",
      defaultValue: "Highlight Color",
      comment: "Capture preferences setting title"
    )
    static let highlightColorDescription = string(
      "preferences-capture.highlight-color-description",
      defaultValue: "Color of click rings",
      comment: "Capture preferences setting description"
    )
    static let opacityTitle = string(
      "preferences-capture.opacity-title",
      defaultValue: "Opacity",
      comment: "Capture preferences setting title"
    )
    static func opacityDescription(_ percent: Int) -> String {
      format(
        "preferences-capture.opacity-description",
        defaultValue: "Ring transparency (%d%%)",
        comment: "Mouse highlight opacity description. %d is the percentage.",
        percent
      )
    }
    static let fontSizeTitle = string(
      "preferences-capture.font-size-title",
      defaultValue: "Font Size",
      comment: "Capture preferences setting title"
    )
    static func fontSizeDescription(_ points: Int) -> String {
      format(
        "preferences-capture.font-size-description",
        defaultValue: "Badge text size (%dpt)",
        comment: "Keystroke overlay font size description. %d is the font size in points.",
        points
      )
    }
    static let positionTitle = string(
      "preferences-capture.position-title",
      defaultValue: "Position",
      comment: "Capture preferences setting title"
    )
    static let positionDescription = string(
      "preferences-capture.position-description",
      defaultValue: "Badge placement in recording area",
      comment: "Capture preferences setting description"
    )
    static let displayDurationTitle = string(
      "preferences-capture.display-duration-title",
      defaultValue: "Display Duration",
      comment: "Capture preferences setting title"
    )
    static func displayDurationDescription(_ seconds: String) -> String {
      format(
        "preferences-capture.display-duration-description",
        defaultValue: "Time before badge fades (%@s)",
        comment: "Keystroke overlay display duration description. %@ is the formatted seconds value.",
        seconds
      )
    }
    static let systemAudioTitle = string(
      "preferences-capture.system-audio-title",
      defaultValue: "System Audio",
      comment: "Capture preferences setting title"
    )
    static let systemAudioDescription = string(
      "preferences-capture.system-audio-description",
      defaultValue: "Capture sounds from apps",
      comment: "Capture preferences setting description"
    )
    static let microphoneDescription = string(
      "preferences-capture.microphone-description",
      defaultValue: "Capture your voice",
      comment: "Capture preferences setting description"
    )
    static let microphoneRequiresMacOS = string(
      "preferences-capture.microphone-requires-macos",
      defaultValue: "Requires macOS 15.0+",
      comment: "Capture preferences description when microphone capture is unavailable on the current macOS version"
    )
    static let removeBackground = string(
      "preferences-capture.remove-background",
      defaultValue: "Remove Background",
      comment: "Caption label for background removal settings"
    )
    static let autoCropSubjectTitle = string(
      "preferences-capture.auto-crop-subject-title",
      defaultValue: "Auto-Crop Subject",
      comment: "Capture preferences setting title"
    )
    static let autoCropSubjectDescription = string(
      "preferences-capture.auto-crop-subject-description",
      defaultValue: "Applies to background removal in capture and Annotate",
      comment: "Capture preferences setting description"
    )
    static let ocrSection = string(
      "preferences-capture.section-ocr",
      defaultValue: "OCR (Text Extraction)",
      comment: "Capture preferences section title"
    )
    static let ocrSuccessNotificationTitle = string(
      "preferences-capture.ocr-success-notification-title",
      defaultValue: "Success Notification",
      comment: "Capture preferences setting title"
    )
    static let ocrSuccessNotificationDescription = string(
      "preferences-capture.ocr-success-notification-description",
      defaultValue: "Show a toast when text is copied to clipboard",
      comment: "Capture preferences setting description"
    )
  }

  enum PreferencesShortcuts {
    static let actionRequired = string(
      "preferences-shortcuts.action-required",
      defaultValue: "Action Required",
      comment: "Shortcuts preferences section header"
    )
    static let systemShortcuts = string(
      "preferences-shortcuts.system-shortcuts",
      defaultValue: "System Shortcuts",
      comment: "Shortcuts preferences section header"
    )
    static let systemConflictTitle = string(
      "preferences-shortcuts.system-conflict-title",
      defaultValue: "macOS screenshot shortcuts overlap with Snapzy",
      comment: "Title for system shortcut conflict warning"
    )
    static let systemConflictDescription = string(
      "preferences-shortcuts.system-conflict-description",
      defaultValue: "Turn off the overlapping macOS shortcuts to avoid conflicts with the Snapzy shortcuts you keep enabled.",
      comment: "Description for system shortcut conflict warning"
    )
    static let howToDisable = string(
      "preferences-shortcuts.how-to-disable",
      defaultValue: "HOW TO DISABLE",
      comment: "Caption heading for shortcut conflict resolution steps"
    )
    static let openKeyboardShortcutsSettings = string(
      "preferences-shortcuts.open-keyboard-shortcuts-settings",
      defaultValue: "Open Keyboard Shortcuts Settings",
      comment: "Button title to open macOS keyboard shortcut settings"
    )
    static let noConflictsDetected = string(
      "preferences-shortcuts.no-conflicts-detected",
      defaultValue: "No conflicts detected",
      comment: "Title for success state when there are no system shortcut conflicts"
    )
    static let noConflictsDescription = string(
      "preferences-shortcuts.no-conflicts-description",
      defaultValue: "No overlapping macOS screenshot shortcuts were found for the Snapzy shortcuts you currently have enabled.",
      comment: "Description for success state when there are no system shortcut conflicts"
    )
    static let globalSection = string(
      "preferences-shortcuts.global-section",
      defaultValue: "Global Shortcuts",
      comment: "Shortcuts preferences section title"
    )
    static let globalSectionDescription = string(
      "preferences-shortcuts.global-section-description",
      defaultValue: "Use keyboard shortcuts to capture from anywhere.",
      comment: "Shortcuts preferences section description"
    )
    static let enableShortcutsTitle = string(
      "preferences-shortcuts.enable-shortcuts-title",
      defaultValue: "Enable Shortcuts",
      comment: "Shortcuts preferences setting title"
    )
    static let enableShortcutsDescription = string(
      "preferences-shortcuts.enable-shortcuts-description",
      defaultValue: "Capture from any app",
      comment: "Shortcuts preferences setting description"
    )
    static let disableShortcutsTitle = string(
      "preferences-shortcuts.disable-shortcuts-title",
      defaultValue: "Disable Keyboard Shortcuts?",
      comment: "Alert title for disabling global shortcuts"
    )
    static let disableShortcutsMessage = string(
      "preferences-shortcuts.disable-shortcuts-message",
      defaultValue: "You won't be able to capture screenshots or recordings using keyboard shortcuts from any app. You'll need to open Snapzy manually to use capture features.",
      comment: "Alert message for disabling global shortcuts"
    )
    static let captureSection = string(
      "preferences-shortcuts.capture-section",
      defaultValue: "Capture Shortcuts",
      comment: "Shortcuts preferences section title"
    )
    static let captureFullscreenDescription = string(
      "preferences-shortcuts.capture-fullscreen-description",
      defaultValue: "Capture entire screen instantly",
      comment: "Description for fullscreen capture shortcut"
    )
    static let captureAreaDescription = string(
      "preferences-shortcuts.capture-area-description",
      defaultValue: "Select a region to capture",
      comment: "Description for area capture shortcut"
    )
    static let applicationCaptureTitle = string(
      "preferences-shortcuts.application-capture-title",
      defaultValue: "Application Capture",
      comment: "Title for the single-key shortcut that toggles application capture inside the area capture overlay"
    )
    static let applicationCaptureDescription = string(
      "preferences-shortcuts.application-capture-description",
      defaultValue: "Single key (A) pairs with Capture Area; modifier combo (⇧⌘A)\nworks independently.",
      comment: "Description for the shortcut that toggles or starts application capture"
    )
    static let applicationRecordingTitle = string(
      "preferences-shortcuts.application-recording-title",
      defaultValue: "Application Recording",
      comment: "Title for the single-key shortcut that toggles application window recording inside the recording selection flow"
    )
    static let applicationRecordingDescription = string(
      "preferences-shortcuts.application-recording-description",
      defaultValue: "Single key (A) pairs with Record Screen; modifier combo (⇧⌘A)\nworks independently.",
      comment: "Description for the shortcut that toggles or starts application recording"
    )
    static let captureTextDescription = string(
      "preferences-shortcuts.capture-text-description",
      defaultValue: "Extract text from screen region",
      comment: "Description for OCR capture shortcut"
    )
    static let recordingSection = string(
      "preferences-shortcuts.recording-section",
      defaultValue: "Recording Shortcuts",
      comment: "Shortcuts preferences section title"
    )
    static let recordVideoDescription = string(
      "preferences-shortcuts.record-video-description",
      defaultValue: "Start screen recording",
      comment: "Description for recording shortcut"
    )
    static let toolsSection = string(
      "preferences-shortcuts.tools-section",
      defaultValue: "Tools Shortcuts",
      comment: "Shortcuts preferences section title"
    )
    static let openAnnotateDescription = string(
      "preferences-shortcuts.open-annotate-description",
      defaultValue: "Open image annotation editor",
      comment: "Description for annotate shortcut"
    )
    static let openVideoEditorDescription = string(
      "preferences-shortcuts.open-video-editor-description",
      defaultValue: "Open video editing tools",
      comment: "Description for video editor shortcut"
    )
    static let cloudUploadsDescription = string(
      "preferences-shortcuts.cloud-uploads-description",
      defaultValue: "Toggle cloud upload history",
      comment: "Description for cloud uploads shortcut"
    )
    static let shortcutListDescription = string(
      "preferences-shortcuts.shortcut-list-description",
      defaultValue: "Open keyboard shortcuts overlay",
      comment: "Description for shortcut list shortcut"
    )
    static let recorderHint = string(
      "preferences-shortcuts.recorder-hint",
      defaultValue: "Click a shortcut button to record new keys. Use the row toggle to turn a shortcut off. Press Esc to cancel.",
      comment: "Hint text below editable shortcut recorder rows"
    )
    static let annotateActionsDescription = string(
      "preferences-shortcuts.annotate-actions-description",
      defaultValue: "Shortcuts for common actions inside the annotation editor.",
      comment: "Description for annotate action shortcuts section"
    )
    static let copyAndCloseDescription = string(
      "preferences-shortcuts.copy-and-close-description",
      defaultValue: "Copy annotated image to clipboard and close",
      comment: "Description for annotate copy and close shortcut"
    )
    static let togglePinDescription = string(
      "preferences-shortcuts.toggle-pin-description",
      defaultValue: "Pin or unpin the annotation window",
      comment: "Description for annotate pin shortcut"
    )
    static let cloudUploadDescription = string(
      "preferences-shortcuts.cloud-upload-description",
      defaultValue: "Upload annotated image to cloud",
      comment: "Description for annotate cloud upload shortcut"
    )
    static let annotationToolDescription = string(
      "preferences-shortcuts.annotation-tool-description",
      defaultValue: "Single-key shortcuts for switching tools in the annotation editor.",
      comment: "Description for annotation tool shortcut section"
    )
    static let singleKeyHint = string(
      "preferences-shortcuts.single-key-hint",
      defaultValue: "Click to record. Use Backspace while recording or the row toggle to turn a shortcut off. Esc to cancel.",
      comment: "Hint text below single-key shortcut rows"
    )
    static let referenceDescription = string(
      "preferences-shortcuts.reference-description",
      defaultValue: "Standard macOS shortcuts used in the annotation editor.",
      comment: "Description for read-only annotate shortcut reference section"
    )
    static let resetToDefaults = string(
      "preferences-shortcuts.reset-to-defaults",
      defaultValue: "Reset to Defaults",
      comment: "Button title for resetting shortcut settings"
    )
  }

  enum PreferencesAbout {
    static let appSubtitle = string(
      "preferences-about.app-subtitle",
      defaultValue: "Screenshot & Recording for macOS",
      comment: "About screen app subtitle"
    )
    static func version(_ appVersion: String) -> String {
      format(
        "preferences-about.version",
        defaultValue: "Version %@",
        comment: "About screen version label. %@ is the version and build string.",
        appVersion
      )
    }
    static let checkedLabel = string(
      "preferences-about.checked-label",
      defaultValue: "Checked",
      comment: "About screen label before relative update check time"
    )
    static let reportProblem = string(
      "preferences-about.report-problem",
      defaultValue: "Report a Problem",
      comment: "Button title on the about screen"
    )
    static let checkForUpdates = string(
      "preferences-about.check-for-updates",
      defaultValue: "Check for Updates",
      comment: "Button title on the about screen"
    )
    static let website = string(
      "preferences-about.website",
      defaultValue: "Website",
      comment: "Tooltip for website link"
    )
    static let github = string(
      "preferences-about.github",
      defaultValue: "GitHub",
      comment: "Tooltip for GitHub link"
    )
    static let reportBug = string(
      "preferences-about.report-bug",
      defaultValue: "Report a Bug",
      comment: "Tooltip for issue reporting link"
    )
    static let supportTitle = string(
      "preferences-about.support-title",
      defaultValue: "Support Snapzy",
      comment: "About screen sponsor card title"
    )
    static let supportDescription = string(
      "preferences-about.support-description",
      defaultValue: "Snapzy is open-source. Sponsor ongoing development if it helps your workflow.",
      comment: "About screen sponsor card description"
    )
  }

  enum PreferencesCloudHistory {
    static let windowTitle = string(
      "preferences-cloud-history.window-title",
      defaultValue: "Cloud Upload History",
      comment: "Window title for cloud upload history"
    )
    static let statusAll = string(
      "preferences-cloud-history.status-all",
      defaultValue: "All",
      comment: "Cloud upload history status filter label"
    )
    static let statusActive = string(
      "preferences-cloud-history.status-active",
      defaultValue: "Active",
      comment: "Cloud upload history status filter label"
    )
    static let statusExpired = string(
      "preferences-cloud-history.status-expired",
      defaultValue: "Expired",
      comment: "Cloud upload history status filter label"
    )
    static let newestFirst = string(
      "preferences-cloud-history.newest-first",
      defaultValue: "Newest First",
      comment: "Cloud upload history sort order label"
    )
    static let oldestFirst = string(
      "preferences-cloud-history.oldest-first",
      defaultValue: "Oldest First",
      comment: "Cloud upload history sort order label"
    )
    static let largestFirst = string(
      "preferences-cloud-history.largest-first",
      defaultValue: "Largest First",
      comment: "Cloud upload history sort order label"
    )
    static let smallestFirst = string(
      "preferences-cloud-history.smallest-first",
      defaultValue: "Smallest First",
      comment: "Cloud upload history sort order label"
    )
    static let clearAllTitle = string(
      "preferences-cloud-history.clear-all-title",
      defaultValue: "Clear All Upload History?",
      comment: "Alert title for clearing cloud upload history"
    )
    static let deleteFromCloudAndClear = string(
      "preferences-cloud-history.delete-from-cloud-and-clear",
      defaultValue: "Delete from Cloud & Clear",
      comment: "Button title for deleting cloud files and clearing history"
    )
    static let clearHistoryOnly = string(
      "preferences-cloud-history.clear-history-only",
      defaultValue: "Clear History Only",
      comment: "Button title for clearing local cloud upload history only"
    )
    static let clearAllMessage = string(
      "preferences-cloud-history.clear-all-message",
      defaultValue: "\"Delete from Cloud & Clear\" removes files from cloud storage and local history.\n\"Clear History Only\" removes local records but keeps files on cloud.",
      comment: "Alert message for clearing cloud upload history"
    )
    static let searchUploads = string(
      "preferences-cloud-history.search-uploads",
      defaultValue: "Search uploads...",
      comment: "Placeholder text for cloud upload history search field"
    )
    static let filters = string(
      "preferences-cloud-history.filters",
      defaultValue: "Filters",
      comment: "Tooltip for cloud upload history filter button"
    )
    static func uploadsCount(_ count: Int) -> String {
      format(
        "preferences-cloud-history.uploads-count",
        defaultValue: "%d uploads",
        comment: "Cloud upload history count label. %d is the number of uploads.",
        count
      )
    }
    static let clearAllHistory = string(
      "preferences-cloud-history.clear-all-history",
      defaultValue: "Clear all history",
      comment: "Tooltip for clearing all cloud upload history"
    )
    static let status = string(
      "preferences-cloud-history.status",
      defaultValue: "Status",
      comment: "Cloud upload history filter section title"
    )
    static let provider = string(
      "preferences-cloud-history.provider",
      defaultValue: "Provider",
      comment: "Cloud upload history filter section title"
    )
    static let expireTime = string(
      "preferences-cloud-history.expire-time",
      defaultValue: "Expire Time",
      comment: "Cloud upload history filter section title"
    )
    static let sortBy = string(
      "preferences-cloud-history.sort-by",
      defaultValue: "Sort By",
      comment: "Cloud upload history filter section title"
    )
    static let resetFilters = string(
      "preferences-cloud-history.reset-filters",
      defaultValue: "Reset Filters",
      comment: "Button title for resetting cloud upload history filters"
    )
    static let dismiss = string(
      "preferences-cloud-history.dismiss",
      defaultValue: "Dismiss",
      comment: "Button title for dismissing the cloud upload history error banner"
    )
    static let noUploadsYet = string(
      "preferences-cloud-history.no-uploads-yet",
      defaultValue: "No uploads yet",
      comment: "Empty state title for cloud upload history"
    )
    static let noResultsFound = string(
      "preferences-cloud-history.no-results-found",
      defaultValue: "No results found",
      comment: "Empty state title for cloud upload history when filters remove all matches"
    )
    static func failedToDelete(_ fileName: String, _ message: String) -> String {
      format(
        "preferences-cloud-history.failed-to-delete",
        defaultValue: "Failed to delete %@: %@",
        comment: "Error shown when deleting a cloud upload history record fails. First %@ is the file name. Second %@ is the lower-level error message.",
        fileName,
        message
      )
    }
    static func someFilesCouldNotBeDeleted(_ message: String) -> String {
      format(
        "preferences-cloud-history.some-files-could-not-be-deleted",
        defaultValue: "Some files could not be deleted: %@",
        comment: "Error shown when deleting all cloud upload history records partially fails. %@ is the lower-level error message.",
        message
      )
    }
    static let expired = string(
      "preferences-cloud-history.expired",
      defaultValue: "Expired",
      comment: "Status badge shown for expired cloud uploads"
    )
    static let copyLink = string(
      "preferences-cloud-history.copy-link",
      defaultValue: "Copy link",
      comment: "Tooltip for copying a cloud upload link"
    )
    static let openInBrowser = string(
      "preferences-cloud-history.open-in-browser",
      defaultValue: "Open in browser",
      comment: "Tooltip for opening a cloud upload in the browser"
    )
    static let removeFromHistory = string(
      "preferences-cloud-history.remove-from-history",
      defaultValue: "Remove from history",
      comment: "Tooltip for removing a cloud upload from history"
    )
  }

  enum Microphone {
    static let accessRequiredTitle = string(
      "microphone.access-required-title",
      defaultValue: "Microphone Access Required",
      comment: "Alert title when microphone permission is missing"
    )
    static let preferencesMessage = string(
      "microphone.preferences-message",
      defaultValue: "Snapzy needs microphone permission. Please enable it in System Settings > Privacy & Security > Microphone.",
      comment: "Alert message when microphone permission is missing from preferences or toolbar"
    )
    static let recordingMessage = string(
      "microphone.recording-message",
      defaultValue: "Snapzy needs microphone permission to record audio. Please grant access in System Settings.",
      comment: "Alert message when microphone permission is missing while starting a recording"
    )
    static let continueWithoutMic = string(
      "microphone.continue-without-mic",
      defaultValue: "Continue Without Mic",
      comment: "Alert button title to continue recording without microphone access"
    )
    static let unavailableVersion = string(
      "microphone.unavailable-version",
      defaultValue: "Microphone unavailable on this macOS version",
      comment: "Accessibility label when microphone capture is unavailable on current macOS version"
    )
    static let mute = string(
      "microphone.mute",
      defaultValue: "Mute microphone",
      comment: "Accessibility label for muting the microphone"
    )
    static let unmute = string(
      "microphone.unmute",
      defaultValue: "Unmute microphone",
      comment: "Accessibility label for unmuting the microphone"
    )
    static let on = string(
      "microphone.on",
      defaultValue: "Microphone on",
      comment: "Tooltip when microphone capture is enabled"
    )
    static let off = string(
      "microphone.off",
      defaultValue: "Microphone off",
      comment: "Tooltip when microphone capture is disabled"
    )
    static let doubleTapToToggle = string(
      "microphone.double-tap-toggle",
      defaultValue: "Double-tap to toggle",
      comment: "Accessibility hint for toggling microphone capture"
    )
  }

  enum CloudTransfer {
    static let importTitle = string(
      "cloud-transfer.import-title",
      defaultValue: "Import Cloud Credentials",
      comment: "Title for cloud credential import sheet"
    )
    static let importDescription = string(
      "cloud-transfer.import-description",
      defaultValue: "Unlock the encrypted archive to load its values into the Cloud form.",
      comment: "Description for cloud credential import sheet"
    )
    static let selectedArchive = string(
      "cloud-transfer.selected-archive",
      defaultValue: "Selected Archive",
      comment: "Label for selected archive file"
    )
    static let archivePassphrase = string(
      "cloud-transfer.archive-passphrase",
      defaultValue: "Archive Passphrase",
      comment: "Label for archive passphrase field"
    )
    static let enterArchivePassphrase = string(
      "cloud-transfer.enter-archive-passphrase",
      defaultValue: "Enter archive passphrase",
      comment: "Placeholder for archive passphrase field"
    )
    static let exportTitle = string(
      "cloud-transfer.export-title",
      defaultValue: "Export Cloud Credentials",
      comment: "Title for cloud credential export sheet"
    )
    static let exportDescription = string(
      "cloud-transfer.export-description",
      defaultValue: "Create an encrypted archive you can import on another Mac. Snapzy does not store this archive passphrase.",
      comment: "Description for cloud credential export sheet"
    )
    static let archiveContents = string(
      "cloud-transfer.archive-contents",
      defaultValue: "Archive Contents",
      comment: "Label for archive contents summary"
    )
    static func archiveContentsSummary(_ provider: String, bucket: String) -> String {
      format(
        "cloud-transfer.archive-contents-summary",
        defaultValue: "%@ • Bucket: %@",
        comment: "Archive contents summary. First %@ is provider name, second %@ is bucket name.",
        provider,
        bucket
      )
    }
    static func minimumPassphrase(_ count: Int) -> String {
      format(
        "cloud-transfer.minimum-passphrase",
        defaultValue: "At least %d characters",
        comment: "Placeholder for minimum archive passphrase length. %d is the minimum number of characters.",
        count
      )
    }
    static let confirmPassphrase = string(
      "cloud-transfer.confirm-passphrase",
      defaultValue: "Confirm Passphrase",
      comment: "Label for confirming an archive passphrase"
    )
    static let reenterPassphrase = string(
      "cloud-transfer.reenter-passphrase",
      defaultValue: "Re-enter archive passphrase",
      comment: "Placeholder for confirming an archive passphrase"
    )
    static let chooseDestination = string(
      "cloud-transfer.choose-destination",
      defaultValue: "Choose Destination",
      comment: "Button title to choose an export destination"
    )
    static func passphraseTooShort(_ count: Int) -> String {
      format(
        "cloud-transfer.passphrase-too-short",
        defaultValue: "Passphrase must be at least %d characters.",
        comment: "Validation message when archive passphrase is too short. %d is the minimum number of characters.",
        count
      )
    }
    static let passphrasesDoNotMatch = string(
      "cloud-transfer.passphrases-do-not-match",
      defaultValue: "Passphrases do not match.",
      comment: "Validation message when archive passphrase confirmation does not match"
    )
    static let savePanelMessage = string(
      "cloud-transfer.save-panel-message",
      defaultValue: "Choose where Snapzy should save the encrypted credential archive.",
      comment: "Message shown in the save panel for exporting cloud credentials"
    )
    static let chooserMessage = string(
      "cloud-transfer.chooser-message",
      defaultValue: "Choose a Snapzy encrypted credential archive.",
      comment: "Message shown in the open panel for importing cloud credentials"
    )
    static func archiveSaved(_ path: String) -> String {
      format(
        "cloud-transfer.archive-saved",
        defaultValue: "Encrypted archive saved to %@.",
        comment: "Success message shown after exporting cloud credentials. %@ is the saved archive path.",
        path
      )
    }
    static let importedCredentialsLoaded = string(
      "cloud-transfer.imported-credentials-loaded",
      defaultValue: "Imported credentials loaded. Review the values, then click Save & Test to apply them.",
      comment: "Notice shown after importing encrypted cloud credentials into the preferences form"
    )
    static func exportPassphraseTooShort(_ minimumLength: Int) -> String {
      format(
        "cloud-transfer.error.passphrase-too-short-export",
        defaultValue: "Export passphrase must be at least %d characters.",
        comment: "Error shown when export passphrase is too short. %d is the minimum length.",
        minimumLength
      )
    }
    static let invalidArchive = string(
      "cloud-transfer.error.invalid-archive",
      defaultValue: "The selected file is not a valid Snapzy cloud credential archive.",
      comment: "Error shown when an imported cloud credential archive is invalid"
    )
    static func unsupportedSchemaVersion(_ version: Int) -> String {
      format(
        "cloud-transfer.error.unsupported-schema-version",
        defaultValue: "This archive uses unsupported schema version %d.",
        comment: "Error shown when imported cloud credential archive has an unsupported schema version. %d is the archive schema version.",
        version
      )
    }
    static let unsupportedArchiveFormat = string(
      "cloud-transfer.error.unsupported-archive-format",
      defaultValue: "This archive uses an unsupported encryption format.",
      comment: "Error shown when imported cloud credential archive uses an unsupported encryption format"
    )
    static let unlockFailed = string(
      "cloud-transfer.error.unlock-failed",
      defaultValue: "Couldn't unlock the archive. Check the passphrase or choose a valid archive.",
      comment: "Error shown when a cloud credential archive cannot be decrypted"
    )
    static let randomizationFailed = string(
      "cloud-transfer.error.randomization-failed",
      defaultValue: "Couldn't generate secure random bytes for the archive.",
      comment: "Error shown when secure random bytes cannot be generated for archive encryption"
    )
  }

  enum CloudProvider {
    static let awsS3 = string(
      "cloud-provider.aws-s3",
      defaultValue: "AWS S3",
      comment: "Cloud provider display name"
    )
    static let cloudflareR2 = string(
      "cloud-provider.cloudflare-r2",
      defaultValue: "Cloudflare R2",
      comment: "Cloud provider display name"
    )
  }

  enum CloudExpire {
    static let day1 = string(
      "cloud-expire.1-day",
      defaultValue: "1 day",
      comment: "Cloud file expiration option label"
    )
    static let day3 = string(
      "cloud-expire.3-days",
      defaultValue: "3 days",
      comment: "Cloud file expiration option label"
    )
    static let day7 = string(
      "cloud-expire.7-days",
      defaultValue: "7 days",
      comment: "Cloud file expiration option label"
    )
    static let day14 = string(
      "cloud-expire.14-days",
      defaultValue: "14 days",
      comment: "Cloud file expiration option label"
    )
    static let day30 = string(
      "cloud-expire.30-days",
      defaultValue: "30 days",
      comment: "Cloud file expiration option label"
    )
    static let day60 = string(
      "cloud-expire.60-days",
      defaultValue: "60 days",
      comment: "Cloud file expiration option label"
    )
    static let day90 = string(
      "cloud-expire.90-days",
      defaultValue: "90 days",
      comment: "Cloud file expiration option label"
    )
    static let permanent = string(
      "cloud-expire.permanent",
      defaultValue: "Permanent",
      comment: "Cloud file expiration option label"
    )
  }

  enum CloudOperation {
    static let notConfigured = string(
      "cloud-operation.not-configured",
      defaultValue: "Cloud storage is not configured. Please set up your credentials in Preferences -> Cloud.",
      comment: "Error shown when a cloud operation is attempted without cloud configuration"
    )
    static let invalidCredentials = string(
      "cloud-operation.invalid-credentials",
      defaultValue: "Invalid cloud credentials. Please verify your Access Key and Secret Key.",
      comment: "Error shown when cloud credentials are invalid"
    )
    static func uploadFailed(_ code: Int, message: String) -> String {
      format(
        "cloud-operation.upload-failed",
        defaultValue: "Upload failed (HTTP %d): %@",
        comment: "Error shown when a cloud request fails. %d is the HTTP status code and %@ is the provider-specific message.",
        code,
        message
      )
    }
    static func networkError(_ message: String) -> String {
      format(
        "cloud-operation.network-error",
        defaultValue: "Network error: %@",
        comment: "Error shown when a cloud request encounters a network error. %@ is the underlying network error message.",
        message
      )
    }
    static func fileNotFound(_ fileName: String) -> String {
      format(
        "cloud-operation.file-not-found",
        defaultValue: "File not found: %@",
        comment: "Error shown when a local file for cloud upload cannot be found. %@ is the file name.",
        fileName
      )
    }
    static func signingFailed(_ reason: String) -> String {
      format(
        "cloud-operation.signing-failed",
        defaultValue: "Request signing failed: %@",
        comment: "Error shown when cloud request signing fails. %@ is the lower-level reason.",
        reason
      )
    }
    static let invalidResponse = string(
      "cloud-operation.invalid-response",
      defaultValue: "Invalid response from cloud provider.",
      comment: "Error shown when the cloud provider response is invalid"
    )
    static func keychainError(_ reason: String) -> String {
      format(
        "cloud-operation.keychain-error",
        defaultValue: "Keychain error: %@",
        comment: "Error shown when a cloud-related Keychain operation fails. %@ is the lower-level reason.",
        reason
      )
    }
    static let bucketValidationFailed = string(
      "cloud-operation.bucket-validation-failed",
      defaultValue: "Bucket validation failed",
      comment: "Reason shown when cloud bucket validation fails"
    )
    static func deleteFailed(_ body: String) -> String {
      format(
        "cloud-operation.delete-failed",
        defaultValue: "Delete failed: %@",
        comment: "Reason shown when deleting a cloud object fails. %@ is the provider response body.",
        body
      )
    }
    static func getLifecycleConfigFailed(_ body: String) -> String {
      format(
        "cloud-operation.get-lifecycle-config-failed",
        defaultValue: "Failed to get lifecycle config: %@",
        comment: "Reason shown when fetching cloud lifecycle configuration fails. %@ is the provider response body.",
        body
      )
    }
    static func setLifecycleConfigFailed(_ body: String) -> String {
      format(
        "cloud-operation.set-lifecycle-config-failed",
        defaultValue: "Failed to set lifecycle config: %@",
        comment: "Reason shown when updating cloud lifecycle configuration fails. %@ is the provider response body.",
        body
      )
    }
    static func deleteLifecycleConfigFailed(_ body: String) -> String {
      format(
        "cloud-operation.delete-lifecycle-config-failed",
        defaultValue: "Failed to delete lifecycle config: %@",
        comment: "Reason shown when deleting cloud lifecycle configuration fails. %@ is the provider response body.",
        body
      )
    }
    static let failedToEncodeKeychainValue = string(
      "cloud-operation.failed-to-encode-keychain-value",
      defaultValue: "Failed to encode keychain value",
      comment: "Reason shown when a value cannot be encoded for the Keychain"
    )
    static func secItemUpdateFailed(_ status: Int) -> String {
      format(
        "cloud-operation.sec-item-update-failed",
        defaultValue: "SecItemUpdate failed: %d",
        comment: "Reason shown when a Keychain item update fails. %d is the OSStatus code.",
        status
      )
    }
    static func secItemAddFailed(_ status: Int) -> String {
      format(
        "cloud-operation.sec-item-add-failed",
        defaultValue: "SecItemAdd failed: %d",
        comment: "Reason shown when adding a Keychain item fails. %d is the OSStatus code.",
        status
      )
    }
    static let invalidRequestURLOrMethod = string(
      "cloud-operation.invalid-request-url-or-method",
      defaultValue: "Invalid request URL or method",
      comment: "Reason shown when a cloud request URL or HTTP method is invalid for signing"
    )
    static let invalidURLForPresigning = string(
      "cloud-operation.invalid-url-for-presigning",
      defaultValue: "Invalid URL for presigning",
      comment: "Reason shown when a presigned cloud URL cannot be created because the base URL is invalid"
    )
    static let failedToConstructPresignedURL = string(
      "cloud-operation.failed-to-construct-presigned-url",
      defaultValue: "Failed to construct presigned URL",
      comment: "Reason shown when a presigned cloud URL cannot be constructed"
    )
  }

  enum CloudPassword {
    static let notConfigured = string(
      "cloud-password.not-configured",
      defaultValue: "Protection password is not configured.",
      comment: "Error shown when cloud password verification is requested but no password has been configured"
    )
    static let keychainAccessDenied = string(
      "cloud-password.keychain-access-denied",
      defaultValue: "Keychain access was not granted. Allow access and try again.",
      comment: "Error shown when cloud password verification cannot access the Keychain"
    )
    static let keychainInteractionUnavailable = string(
      "cloud-password.keychain-interaction-unavailable",
      defaultValue: "Keychain interaction is unavailable right now. Unlock your Mac and try again.",
      comment: "Error shown when cloud password verification cannot interact with the Keychain"
    )
    static let couldntReadSavedPassword = string(
      "cloud-password.couldnt-read-saved-password",
      defaultValue: "Couldn't read the saved protection password from Keychain.",
      comment: "Error shown when the saved cloud protection password cannot be read from the Keychain"
    )
  }

  enum CloudUsage {
    static let loadingStats = string(
      "cloud-usage.loading-stats",
      defaultValue: "Loading stats...",
      comment: "Placeholder shown while cloud usage statistics are loading"
    )
    static let storage = string(
      "cloud-usage.storage",
      defaultValue: "Storage",
      comment: "Cloud usage stat label"
    )
    static let objects = string(
      "cloud-usage.objects",
      defaultValue: "Objects",
      comment: "Cloud usage stat label"
    )
    static let lifecycle = string(
      "cloud-usage.lifecycle",
      defaultValue: "Lifecycle",
      comment: "Cloud usage stat label"
    )
    static let estimatedCostPerMonth = string(
      "cloud-usage.estimated-cost-per-month",
      defaultValue: "Est. Cost/mo",
      comment: "Cloud usage stat label"
    )
    static let updatedPrefix = string(
      "cloud-usage.updated-prefix",
      defaultValue: "Updated",
      comment: "Prefix shown before a relative cloud usage timestamp"
    )
    static let agoSuffix = string(
      "cloud-usage.ago-suffix",
      defaultValue: "ago",
      comment: "Suffix shown after a relative cloud usage timestamp"
    )
    static let cloudStatus = string(
      "cloud-usage.cloud-status",
      defaultValue: "Cloud Status",
      comment: "Header title for the cloud usage section in preferences"
    )
    static let none = string(
      "cloud-usage.none",
      defaultValue: "None",
      comment: "Value shown when no cloud lifecycle rule exists"
    )
    static func daysExpire(_ days: Int) -> String {
      format(
        "cloud-usage.days-expire",
        defaultValue: "%dd expire",
        comment: "Short cloud lifecycle label. %d is the number of days before expiration.",
        days
      )
    }
    static let freeTier = string(
      "cloud-usage.free-tier",
      defaultValue: "Free tier",
      comment: "Cloud usage pricing label when estimated storage cost is covered by the free tier"
    )
    static let notConfigured = string(
      "cloud-usage.not-configured",
      defaultValue: "Cloud not configured",
      comment: "Error shown when cloud usage stats cannot be loaded because cloud is not configured"
    )
    static let couldntRefreshShowingCached = string(
      "cloud-usage.couldnt-refresh-showing-cached",
      defaultValue: "Couldn't refresh cloud stats. Showing cached data.",
      comment: "Error shown when refreshing cloud usage stats fails but cached data is still available"
    )
    static let missingBucketListPermission = string(
      "cloud-usage.missing-bucket-list-permission",
      defaultValue: "Cloud status check failed: missing bucket list permission (e.g. s3:ListBucket).",
      comment: "Error shown when cloud usage fetch lacks permission to list bucket objects"
    )
    static let unauthorizedR2 = string(
      "cloud-usage.unauthorized-r2",
      defaultValue: "Cloud status check failed: unauthorized. Verify R2 endpoint and API credentials.",
      comment: "Error shown when R2 cloud usage fetch is unauthorized"
    )
    static let unauthorizedGeneric = string(
      "cloud-usage.unauthorized-generic",
      defaultValue: "Cloud status check failed: unauthorized. Verify endpoint, region, and credentials.",
      comment: "Error shown when S3-compatible cloud usage fetch is unauthorized"
    )
    static func listObjectsFailed(_ body: String) -> String {
      format(
        "cloud-usage.list-objects-failed",
        defaultValue: "ListObjectsV2 failed: %@",
        comment: "Error shown when fetching cloud object listing fails. %@ is the provider response body.",
        body
      )
    }
  }

  enum CloudSettings {
    static let resetConfigurationTitle = string(
      "cloud-settings.reset-configuration-title",
      defaultValue: "Reset Cloud Configuration?",
      comment: "Alert title for resetting cloud configuration"
    )
    static let resetConfigurationMessage = string(
      "cloud-settings.reset-configuration-message",
      defaultValue: "This will remove all cloud credentials, protection password, and settings. This action cannot be undone.",
      comment: "Alert message for resetting cloud configuration"
    )
    static let importCredentialsTitle = string(
      "cloud-settings.import-credentials-title",
      defaultValue: "Import Cloud Credentials?",
      comment: "Alert title for importing cloud credentials over an existing configuration"
    )
    static let importCredentialsMessage = string(
      "cloud-settings.import-credentials-message",
      defaultValue: "Snapzy will load the imported values into the editor. Your current saved configuration stays unchanged until you click Save & Test.",
      comment: "Alert message for importing cloud credentials over an existing configuration"
    )
    static let transferAlertTitle = string(
      "cloud-settings.transfer-alert-title",
      defaultValue: "Cloud Transfer",
      comment: "Alert title for cloud import/export operations"
    )
    static let providerSection = string(
      "cloud-settings.provider-section",
      defaultValue: "Cloud Provider",
      comment: "Section title in cloud preferences"
    )
    static func bucketDescription(_ bucket: String) -> String {
      format(
        "cloud-settings.bucket-description",
        defaultValue: "Bucket: %@",
        comment: "Description shown for configured cloud bucket. %@ is the bucket name.",
        bucket
      )
    }
    static let accessKey = string(
      "cloud-settings.access-key",
      defaultValue: "Access Key",
      comment: "Cloud settings label for access key"
    )
    static let region = string(
      "cloud-settings.region",
      defaultValue: "Region",
      comment: "Cloud settings label for region"
    )
    static let endpoint = string(
      "cloud-settings.endpoint",
      defaultValue: "Endpoint",
      comment: "Cloud settings label for endpoint"
    )
    static let expireTime = string(
      "cloud-settings.expire-time",
      defaultValue: "Expire Time",
      comment: "Cloud settings label for expiration time"
    )
    static let customDomain = string(
      "cloud-settings.custom-domain",
      defaultValue: "Custom Domain",
      comment: "Cloud settings label for custom domain"
    )
    static let uploadsWindowSection = string(
      "cloud-settings.uploads-window-section",
      defaultValue: "Uploads Window",
      comment: "Section title for Cloud Uploads window settings"
    )
    static let uploadsWindowPositionTitle = string(
      "cloud-settings.uploads-window-position-title",
      defaultValue: "Floating Position",
      comment: "Cloud settings title for choosing the Cloud Uploads floating window position"
    )
    static let uploadsWindowPositionDescription = string(
      "cloud-settings.uploads-window-position-description",
      defaultValue: "Choose where Cloud Uploads opens on screen",
      comment: "Cloud settings description for choosing the Cloud Uploads floating window position"
    )
    static let uploadsWindowPositionTop = string(
      "cloud-settings.uploads-window-position-top",
      defaultValue: "Top",
      comment: "Cloud Uploads floating window position option"
    )
    static let uploadsWindowPositionCenter = string(
      "cloud-settings.uploads-window-position-center",
      defaultValue: "Center",
      comment: "Cloud Uploads floating window position option"
    )
    static let uploadsWindowPositionBottom = string(
      "cloud-settings.uploads-window-position-bottom",
      defaultValue: "Bottom",
      comment: "Cloud Uploads floating window position option"
    )
    static let storedSecurelyInKeychain = string(
      "cloud-settings.stored-securely-in-keychain",
      defaultValue: "Stored securely in Keychain",
      comment: "Status text shown when cloud credentials are stored securely in the Keychain"
    )
    static let edit = string(
      "cloud-settings.edit",
      defaultValue: "Edit",
      comment: "Button title for editing cloud settings"
    )
    static let skip = string(
      "cloud-settings.skip",
      defaultValue: "Skip",
      comment: "Button title for skipping a cloud password-related step"
    )
    static let reset = string(
      "cloud-settings.reset",
      defaultValue: "Reset",
      comment: "Button title for resetting cloud settings"
    )
    static let editCredentialsPasswordPrompt = string(
      "cloud-settings.edit-credentials-password-prompt",
      defaultValue: "Enter your protection password to edit cloud credentials.",
      comment: "Password prompt shown before editing protected cloud credentials"
    )
    static let importCredentialsPasswordPrompt = string(
      "cloud-settings.import-credentials-password-prompt",
      defaultValue: "Enter your protection password to import credentials over the current cloud setup.",
      comment: "Password prompt shown before importing protected cloud credentials"
    )
    static let exportCredentialsPasswordPrompt = string(
      "cloud-settings.export-credentials-password-prompt",
      defaultValue: "Enter your protection password to export the current cloud credentials.",
      comment: "Password prompt shown before exporting protected cloud credentials"
    )
    static let passwordRequiredTitle = string(
      "cloud-settings.password-required-title",
      defaultValue: "Password Required",
      comment: "Title for the cloud password gate sheet"
    )
    static let protectionPassword = string(
      "cloud-settings.protection-password",
      defaultValue: "Protection Password",
      comment: "Cloud settings password field title or placeholder"
    )
    static let verify = string(
      "cloud-settings.verify",
      defaultValue: "Verify",
      comment: "Button title for verifying the cloud protection password"
    )
    static let forgotPasswordResetConfiguration = string(
      "cloud-settings.forgot-password-reset-configuration",
      defaultValue: "Forgot Password? Reset Configuration",
      comment: "Button title for resetting cloud configuration when the password is forgotten"
    )
    static func incorrectPasswordAttempts(_ attempts: Int) -> String {
      format(
        "cloud-settings.incorrect-password-attempts",
        defaultValue: "Incorrect password. Please try again. (%d failed attempts)",
        comment: "Error shown when the cloud protection password is incorrect. %d is the number of failed attempts.",
        attempts
      )
    }
    static let protectCredentialsTitle = string(
      "cloud-settings.protect-credentials-title",
      defaultValue: "Protect Your Cloud Credentials",
      comment: "Title for the initial cloud password setup view"
    )
    static let protectCredentialsDescription = string(
      "cloud-settings.protect-credentials-description",
      defaultValue: "Set a password to prevent unauthorized access to your cloud configuration. This password will be required to view or edit your credentials.",
      comment: "Description for the initial cloud password setup view"
    )
    static let confirmPassword = string(
      "cloud-settings.confirm-password",
      defaultValue: "Confirm Password",
      comment: "Cloud settings label for confirming a password"
    )
    static let setPassword = string(
      "cloud-settings.set-password",
      defaultValue: "Set Password",
      comment: "Button title for saving a cloud protection password"
    )
    static let skipForNow = string(
      "cloud-settings.skip-for-now",
      defaultValue: "Skip for Now",
      comment: "Button title for skipping cloud password setup"
    )
    static let forgotPasswordInfo = string(
      "cloud-settings.forgot-password-info",
      defaultValue: "If you forget this password, you will need to reset your cloud configuration and re-enter all credentials.",
      comment: "Informational note about forgetting the cloud protection password"
    )
    static let skipPasswordProtectionTitle = string(
      "cloud-settings.skip-password-protection-title",
      defaultValue: "Skip Password Protection?",
      comment: "Alert title for skipping cloud password protection"
    )
    static let skipPasswordProtectionMessage = string(
      "cloud-settings.skip-password-protection-message",
      defaultValue: "Without a password, anyone with access to your Mac can view and modify your cloud credentials. We strongly recommend setting a password.",
      comment: "Alert message for skipping cloud password protection"
    )
    static let passwordsDoNotMatch = string(
      "cloud-settings.passwords-do-not-match",
      defaultValue: "Passwords do not match.",
      comment: "Validation error when cloud password confirmation does not match"
    )
    static func passwordMinimumLength(_ minimumLength: Int) -> String {
      format(
        "cloud-settings.password-minimum-length",
        defaultValue: "Password must be at least %d characters.",
        comment: "Validation error when cloud password is too short. %d is the minimum length.",
        minimumLength
      )
    }
    static func failedToSavePassword(_ message: String) -> String {
      format(
        "cloud-settings.failed-to-save-password",
        defaultValue: "Failed to save password: %@",
        comment: "Error shown when saving the cloud protection password fails. %@ is the lower-level error message.",
        message
      )
    }
    static let transferSection = string(
      "cloud-settings.transfer-section",
      defaultValue: "Transfer",
      comment: "Section title for cloud credential transfer actions"
    )
    static let importEncryptedArchive = string(
      "cloud-settings.import-encrypted-archive",
      defaultValue: "Import Encrypted Archive",
      comment: "Button title for importing an encrypted cloud credential archive"
    )
    static let importEncryptedArchiveDescription = string(
      "cloud-settings.import-encrypted-archive-description",
      defaultValue: "Load a previously exported Snapzy cloud archive to prefill this form.",
      comment: "Description for importing an encrypted cloud credential archive"
    )
    static let provider = string(
      "cloud-settings.provider",
      defaultValue: "Provider",
      comment: "Cloud settings label for provider selection"
    )
    static let providerTooltip = string(
      "cloud-settings.provider-tooltip",
      defaultValue: "Select your cloud storage provider",
      comment: "Tooltip for the cloud provider picker"
    )
    static let credentialsSection = string(
      "cloud-settings.credentials-section",
      defaultValue: "Credentials",
      comment: "Section title for cloud credentials"
    )
    static let accessKeyID = string(
      "cloud-settings.access-key-id",
      defaultValue: "Access Key ID",
      comment: "Cloud settings label for access key ID"
    )
    static let accessKeyTooltip = string(
      "cloud-settings.access-key-tooltip",
      defaultValue: "Your cloud provider access key",
      comment: "Tooltip for the access key field"
    )
    static let secretAccessKey = string(
      "cloud-settings.secret-access-key",
      defaultValue: "Secret Access Key",
      comment: "Cloud settings label for secret access key"
    )
    static let secretKeyTooltip = string(
      "cloud-settings.secret-key-tooltip",
      defaultValue: "Your cloud provider secret key",
      comment: "Tooltip for the secret key field"
    )
    static let storageSection = string(
      "cloud-settings.storage-section",
      defaultValue: "Storage",
      comment: "Section title for cloud storage configuration"
    )
    static let bucketName = string(
      "cloud-settings.bucket-name",
      defaultValue: "Bucket Name",
      comment: "Cloud settings label for bucket name"
    )
    static let bucketTooltip = string(
      "cloud-settings.bucket-tooltip",
      defaultValue: "S3 or R2 bucket name",
      comment: "Tooltip for the bucket name field"
    )
    static let regionTooltip = string(
      "cloud-settings.region-tooltip",
      defaultValue: "AWS region (e.g. us-east-1)",
      comment: "Tooltip for the cloud region field"
    )
    static let endpointTooltipS3 = string(
      "cloud-settings.endpoint-tooltip-s3",
      defaultValue: "Optional custom S3 endpoint for LocalStack or other S3-compatible storage",
      comment: "Tooltip for the optional S3 endpoint field"
    )
    static let endpointTooltipR2 = string(
      "cloud-settings.endpoint-tooltip-r2",
      defaultValue: "R2 account endpoint URL",
      comment: "Tooltip for the R2 endpoint field"
    )
    static let customDomainTooltip = string(
      "cloud-settings.custom-domain-tooltip",
      defaultValue: "Public access domain (optional)",
      comment: "Tooltip for the custom domain field"
    )
    static let fileExpirationSection = string(
      "cloud-settings.file-expiration-section",
      defaultValue: "File Expiration",
      comment: "Section title for cloud file expiration settings"
    )
    static let noLifecycleRuleWarning = string(
      "cloud-settings.no-lifecycle-rule-warning",
      defaultValue: "No lifecycle rule will be set. Files will remain permanently unless manually deleted.",
      comment: "Warning shown when cloud file expiration is set to permanent"
    )
    static let lifecycleRuleInfo = string(
      "cloud-settings.lifecycle-rule-info",
      defaultValue: "A lifecycle rule will be configured on your bucket to auto-delete files after the selected period. Deletion may take up to 24 hours after expiration.",
      comment: "Informational note shown when cloud file expiration is set to an auto-delete period"
    )
    static let protectionPasswordSection = string(
      "cloud-settings.protection-password-section",
      defaultValue: "Protection Password",
      comment: "Section title for the cloud protection password settings"
    )
    static let password = string(
      "cloud-settings.password",
      defaultValue: "Password",
      comment: "Cloud settings label for password"
    )
    static let passwordTooltip = string(
      "cloud-settings.password-tooltip",
      defaultValue: "Optional password to protect credentials from unauthorized access",
      comment: "Tooltip for the cloud protection password field"
    )
    static let optional = string(
      "cloud-settings.optional",
      defaultValue: "Optional",
      comment: "Placeholder shown for an optional field"
    )
    static let confirmPasswordTooltip = string(
      "cloud-settings.confirm-password-tooltip",
      defaultValue: "Re-enter the protection password",
      comment: "Tooltip for confirming the cloud protection password"
    )
    static let protectionRecommendation = string(
      "cloud-settings.protection-recommendation",
      defaultValue: "We recommend setting a password to protect your cloud credentials from unauthorized access. This password will be required to view or edit your configuration.",
      comment: "Informational note recommending a cloud protection password"
    )
    static let connectionVerifiedSuccessfully = string(
      "cloud-settings.connection-verified-successfully",
      defaultValue: "Connection verified successfully!",
      comment: "Success message shown after validating cloud credentials"
    )
    static let limitedPermissionsWarning = string(
      "cloud-settings.limited-permissions-warning",
      defaultValue: "Connected with limited permissions. Auto-cleanup (lifecycle rules) is unavailable — files will remain until manually deleted.",
      comment: "Warning shown when cloud credentials lack lifecycle management permissions"
    )
    static let testing = string(
      "cloud-settings.testing",
      defaultValue: "Testing...",
      comment: "Button label shown while cloud credentials are being validated"
    )
    static let saveAndTest = string(
      "cloud-settings.save-and-test",
      defaultValue: "Save & Test",
      comment: "Button title for saving and validating cloud credentials"
    )
    static let proceedWithoutPasswordTitle = string(
      "cloud-settings.proceed-without-password-title",
      defaultValue: "Proceed Without Password?",
      comment: "Alert title for proceeding without a cloud protection password"
    )
    static let proceedWithoutPasswordMessage = string(
      "cloud-settings.proceed-without-password-message",
      defaultValue: "Without a password, anyone with access to your Mac can view and modify your cloud credentials. We strongly recommend setting a password to protect your configuration.",
      comment: "Alert message for proceeding without a cloud protection password"
    )
    static let protectionPasswordsDoNotMatch = string(
      "cloud-settings.protection-passwords-do-not-match",
      defaultValue: "Protection passwords do not match.",
      comment: "Validation error when cloud protection passwords do not match"
    )
    static func protectionPasswordMinimumLength(_ minimumLength: Int) -> String {
      format(
        "cloud-settings.protection-password-minimum-length",
        defaultValue: "Protection password must be at least %d characters.",
        comment: "Validation error when cloud protection password is too short. %d is the minimum length.",
        minimumLength
      )
    }
    static func lifecycleRuleFailed(_ message: String) -> String {
      format(
        "cloud-settings.lifecycle-rule-failed",
        defaultValue: "Lifecycle rule failed: %@. Ensure your credentials have lifecycle management permissions.",
        comment: "Validation error shown when applying a cloud lifecycle rule fails. %@ is the lower-level error message.",
        message
      )
    }
    static func configurationSavedButPasswordSetupFailed(_ message: String) -> String {
      format(
        "cloud-settings.configuration-saved-password-setup-failed",
        defaultValue: "Configuration saved, but password setup failed: %@",
        comment: "Validation error shown when cloud configuration is saved but password setup fails. %@ is the lower-level error message.",
        message
      )
    }
  }

  enum AnnotateUI {
    static let cloudNotConfiguredTitle = string(
      "annotate.cloud-not-configured-title",
      defaultValue: "Cloud Not Configured",
      comment: "Alert title shown when annotate cloud upload is unavailable because cloud is not configured"
    )
    static let cloudNotConfiguredMessage = string(
      "annotate.cloud-not-configured-message",
      defaultValue: "Please set up your cloud credentials in Preferences -> Cloud before uploading.",
      comment: "Alert message shown when annotate cloud upload is unavailable because cloud is not configured"
    )
    static let overwriteCloudFileTitle = string(
      "annotate.overwrite-cloud-file-title",
      defaultValue: "Overwrite Cloud File?",
      comment: "Alert title shown before replacing an existing cloud file from annotate"
    )
    static let overwriteCloudFileMessage = string(
      "annotate.overwrite-cloud-file-message",
      defaultValue: "This image was previously uploaded to cloud. Re-uploading will replace the existing file with your changes.",
      comment: "Alert message shown before replacing an existing cloud file from annotate"
    )
    static func fitWithShortcut(_ shortcut: String) -> String {
      format(
        "annotate.fit-with-shortcut",
        defaultValue: "Fit (%@)",
        comment: "Zoom menu item for fitting the annotated image to the canvas. %@ is the keyboard shortcut.",
        shortcut
      )
    }
    static let modeAnnotate = string(
      "annotate.mode-annotate",
      defaultValue: "Annotate",
      comment: "Annotate editor mode label"
    )
    static let modeMockup = string(
      "annotate.mode-mockup",
      defaultValue: "Mockup",
      comment: "Annotate editor mode label"
    )
    static let modePreview = string(
      "annotate.mode-preview",
      defaultValue: "Preview",
      comment: "Annotate editor mode label"
    )
    static let dragToApp = string(
      "annotate.drag-to-app",
      defaultValue: "Drag to app",
      comment: "Annotate drag handle label"
    )
    static let dragToAppHelp = string(
      "annotate.drag-to-app-help",
      defaultValue: "Drag this to another app to share the annotated image",
      comment: "Tooltip shown for the annotate drag handle"
    )
    static let newWindow = string(
      "annotate.new-window",
      defaultValue: "New Annotate Window",
      comment: "Tooltip shown for opening another independent annotate window"
    )
    static let uploadedToCloud = string(
      "annotate.uploaded-to-cloud",
      defaultValue: "Uploaded to Cloud",
      comment: "Tooltip shown when the annotate asset has already been uploaded to cloud"
    )
    static let reuploadToCloud = string(
      "annotate.reupload-to-cloud",
      defaultValue: "Re-upload to Cloud",
      comment: "Tooltip shown when the annotate asset can be re-uploaded to cloud"
    )
    static let uploadToCloud = string(
      "annotate.upload-to-cloud",
      defaultValue: "Upload to Cloud",
      comment: "Tooltip shown when the annotate asset can be uploaded to cloud"
    )
    static let pinWindow = string(
      "annotate.pin-window",
      defaultValue: "Pin window",
      comment: "Tooltip shown for pinning the annotate window"
    )
    static let unpinWindow = string(
      "annotate.unpin-window",
      defaultValue: "Unpin window",
      comment: "Tooltip shown for unpinning the annotate window"
    )
    static let copyToClipboard = string(
      "annotate.copy-to-clipboard",
      defaultValue: "Copy to clipboard",
      comment: "Tooltip shown for copying the annotated image to the clipboard"
    )
    static let deleteScreenshotTitle = string(
      "annotate.delete-screenshot-title",
      defaultValue: "Delete Screenshot",
      comment: "Alert title shown before deleting the source screenshot from annotate"
    )
    static func deleteScreenshotMessage(_ filename: String) -> String {
      format(
        "annotate.delete-screenshot-message",
        defaultValue: "This will move \"%@\" to Trash.",
        comment: "Alert message shown before deleting the source screenshot from annotate. %@ is the file name.",
        filename
      )
    }
    static let backgroundCutoutTitle = string(
      "annotate.background-cutout-title",
      defaultValue: "Background Cutout",
      comment: "Alert title for annotate background cutout errors"
    )
    static let unableToRemoveBackground = string(
      "annotate.unable-to-remove-background",
      defaultValue: "Unable to remove background.",
      comment: "Fallback error shown when background removal fails without a specific localized message"
    )
    static let crop = string(
      "annotate.crop",
      defaultValue: "Crop",
      comment: "Tooltip for entering crop mode in annotate"
    )
    static let toggleSidebar = string(
      "annotate.toggle-sidebar",
      defaultValue: "Toggle sidebar",
      comment: "Tooltip for toggling the annotate sidebar"
    )
    static let backgroundRemovedClickToRestore = string(
      "annotate.background-removed-click-to-restore",
      defaultValue: "Background Removed (Click to restore)",
      comment: "Tooltip shown when background cutout is active and can be restored"
    )
    static let removeBackgroundAutoCropsWhenSafe = string(
      "annotate.remove-background-auto-crops-when-safe",
      defaultValue: "Remove Background (Auto-crops when safe)",
      comment: "Tooltip shown when background cutout will auto-crop after removing the background"
    )
    static let removeBackgroundAutoCropDisabledInSettings = string(
      "annotate.remove-background-auto-crop-disabled",
      defaultValue: "Remove Background (Auto-crop disabled in Settings)",
      comment: "Tooltip shown when background cutout is available but auto-crop is disabled in settings"
    )
    static let requiresMacOS14OrLater = string(
      "annotate.requires-macos-14",
      defaultValue: "Requires macOS 14+",
      comment: "Tooltip shown when background cutout is unavailable on older macOS versions"
    )
    static let dropImageHere = string(
      "annotate.drop-image-here",
      defaultValue: "Drop an image here",
      comment: "Empty state title for annotate when no image is loaded"
    )
    static let captureScreenshotToAnnotate = string(
      "annotate.capture-screenshot-to-annotate",
      defaultValue: "or capture a screenshot to annotate",
      comment: "Empty state subtitle for annotate when no image is loaded"
    )
    static let toggleRuleOfThirdsGrid = string(
      "annotate.toggle-rule-of-thirds-grid",
      defaultValue: "Toggle rule of thirds grid",
      comment: "Tooltip for showing or hiding the crop grid"
    )
    static let toggleCropOrientation = string(
      "annotate.toggle-crop-orientation",
      defaultValue: "Switch crop orientation",
      comment: "Tooltip for switching crop aspect ratio between landscape and portrait"
    )
    static let unsavedChangesTitle = string(
      "annotate.unsaved-changes-title",
      defaultValue: "Unsaved Changes",
      comment: "Alert title shown when closing annotate with unsaved changes"
    )
    static let unsavedChangesMessage = string(
      "annotate.unsaved-changes-message",
      defaultValue: "You have unsaved changes. Do you want to save before closing?",
      comment: "Alert message shown when closing annotate with unsaved changes"
    )
    static let dontSave = string(
      "annotate.dont-save",
      defaultValue: "Don't Save",
      comment: "Button title for discarding annotate changes"
    )
    static let saveFailedTitle = string(
      "annotate.save-failed-title",
      defaultValue: "Save Failed",
      comment: "Alert title shown when annotate save fails"
    )
    static let saveFailedMessage = string(
      "annotate.save-failed-message",
      defaultValue: "Snapzy couldn't write to the selected location. Please choose another folder.",
      comment: "Alert message shown when annotate save fails"
    )
    static let overwriteCloudFileOnSaveMessage = string(
      "annotate.overwrite-cloud-file-on-save-message",
      defaultValue: "This image was previously uploaded to cloud. Saving will replace the cloud file with your changes.",
      comment: "Alert message shown before overwriting a cloud file while saving annotate changes"
    )
    static let defaultAnnotatedFileName = string(
      "annotate.default-annotated-file-name",
      defaultValue: "annotated_image",
      comment: "Default file name for a new annotated image without a source URL"
    )
    static let jpegRemovesTransparencyTitle = string(
      "annotate.jpeg-removes-transparency-title",
      defaultValue: "JPEG Removes Transparency",
      comment: "Alert title shown before saving a transparent cutout image as JPEG"
    )
    static let jpegRemovesTransparencyMessage = string(
      "annotate.jpeg-removes-transparency-message",
      defaultValue: "This image uses a transparent background cutout. Saving as JPEG will flatten transparency to an opaque background. Use PNG or WebP to keep transparency.",
      comment: "Alert message shown before saving a transparent cutout image as JPEG"
    )
    static let saveAsJPEG = string(
      "annotate.save-as-jpeg",
      defaultValue: "Save as JPEG",
      comment: "Button title for confirming JPEG export without transparency"
    )
    static let presets = string(
      "annotate.presets",
      defaultValue: "Presets",
      comment: "Section title for annotate canvas presets"
    )
    static let selectPreset = string(
      "annotate.select-preset",
      defaultValue: "Select preset",
      comment: "Placeholder label for choosing an annotate canvas preset"
    )
    static let resetCanvasEffectsHelp = string(
      "annotate.reset-canvas-effects-help",
      defaultValue: "Reset background, padding, shadow, and corners",
      comment: "Tooltip for resetting annotate canvas effects"
    )
    static let applySavedStylePreset = string(
      "annotate.apply-saved-style-preset",
      defaultValue: "Apply a saved style preset",
      comment: "Tooltip for opening the annotate saved preset picker"
    )
    static let addNewPreset = string(
      "annotate.add-new-preset",
      defaultValue: "Add new preset",
      comment: "Button title for creating a new annotate preset"
    )
    static let noPresetsYet = string(
      "annotate.no-presets-yet",
      defaultValue: "No presets yet",
      comment: "Empty state label when no annotate presets have been saved"
    )
    static let deletePresetHelp = string(
      "annotate.delete-preset-help",
      defaultValue: "Delete preset",
      comment: "Tooltip for deleting an annotate preset"
    )
    static let updatePreset = string(
      "annotate.update-preset",
      defaultValue: "Update preset",
      comment: "Button title for updating the selected annotate preset"
    )
    static let updateSelectedPresetHelp = string(
      "annotate.update-selected-preset-help",
      defaultValue: "Update selected preset with current values",
      comment: "Tooltip for updating the selected annotate preset"
    )
    static let savePresetTitle = string(
      "annotate.save-preset-title",
      defaultValue: "Save Preset",
      comment: "Alert title for saving a new annotate preset"
    )
    static let savePresetMessage = string(
      "annotate.save-preset-message",
      defaultValue: "Enter a name for this canvas preset.",
      comment: "Alert message for saving a new annotate preset"
    )
    static let updatePresetTitle = string(
      "annotate.update-preset-title",
      defaultValue: "Update Preset",
      comment: "Alert title for updating an annotate preset"
    )
    static func updatePresetMessage(_ presetName: String) -> String {
      format(
        "annotate.update-preset-message",
        defaultValue: "Replace \"%@\" with current settings?",
        comment: "Alert message for updating an annotate preset. %@ is the preset name.",
        presetName
      )
    }
    static let deletePresetTitle = string(
      "annotate.delete-preset-title",
      defaultValue: "Delete Preset",
      comment: "Alert title for deleting an annotate preset"
    )
    static func deletePresetMessage(_ presetName: String) -> String {
      format(
        "annotate.delete-preset-message",
        defaultValue: "Delete \"%@\"?",
        comment: "Alert message for deleting an annotate preset. %@ is the preset name.",
        presetName
      )
    }
    static let presetNamePlaceholder = string(
      "annotate.preset-name-placeholder",
      defaultValue: "Preset name",
      comment: "Placeholder text for the annotate preset name field"
    )
    static let presetLimitReachedTitle = string(
      "annotate.preset-limit-reached-title",
      defaultValue: "Preset Limit Reached",
      comment: "Alert title shown when the annotate preset limit is reached"
    )
    static let presetLimitReachedMessage = string(
      "annotate.preset-limit-reached-message",
      defaultValue: "You can save up to 20 presets. Delete one to add a new preset.",
      comment: "Alert message shown when the annotate preset limit is reached"
    )
    static let unableToSavePresetTitle = string(
      "annotate.unable-to-save-preset-title",
      defaultValue: "Unable to Save Preset",
      comment: "Alert title shown when the current annotate canvas style cannot be saved as a preset"
    )
    static let unableToSavePresetMessage = string(
      "annotate.unable-to-save-preset-message",
      defaultValue: "Current canvas style cannot be stored as a preset right now.",
      comment: "Alert message shown when the current annotate canvas style cannot be saved as a preset"
    )
    static let loadingWallpapers = string(
      "annotate.loading-wallpapers",
      defaultValue: "Loading wallpapers...",
      comment: "Loading label shown while annotate wallpapers are being loaded"
    )
    static let removeCustomWallpaper = string(
      "annotate.remove-custom-wallpaper",
      defaultValue: "Remove custom wallpaper",
      comment: "Tooltip for removing a custom annotate wallpaper"
    )
    static let textStyle = string(
      "annotate.text-style",
      defaultValue: "Text Style",
      comment: "Section title for annotate text styling controls"
    )
    static let textColor = string(
      "annotate.text-color",
      defaultValue: "Text Color",
      comment: "Label for annotate text color controls"
    )
    static let annotation = string(
      "annotate.annotation",
      defaultValue: "Annotation",
      comment: "Section title for annotate item properties"
    )
    static let alignment = string(
      "annotate.alignment",
      defaultValue: "Alignment",
      comment: "Section title for annotate image alignment controls"
    )
    static let blurType = string(
      "annotate.blur-type",
      defaultValue: "Blur Type",
      comment: "Section title for annotate blur type controls"
    )
    static let pixelated = string(
      "annotate.pixelated",
      defaultValue: "Pixelated",
      comment: "Label for pixelated blur style"
    )
    static let gaussian = string(
      "annotate.gaussian",
      defaultValue: "Gaussian",
      comment: "Label for gaussian blur style"
    )
    static let pixelatedBlurDescription = string(
      "annotate.pixelated-blur-description",
      defaultValue: "Pixelated blur for redacting sensitive content",
      comment: "Description shown for the pixelated blur style"
    )
    static let gaussianBlurDescription = string(
      "annotate.gaussian-blur-description",
      defaultValue: "Smooth Gaussian blur similar to CSS filter",
      comment: "Description shown for the gaussian blur style"
    )
    static let watermarkSingle = string(
      "annotate.watermark-single",
      defaultValue: "Single",
      comment: "Label for a single watermark style"
    )
    static let watermarkDiagonal = string(
      "annotate.watermark-diagonal",
      defaultValue: "Diagonal",
      comment: "Label for a centered diagonal watermark style"
    )
    static let watermarkTiled = string(
      "annotate.watermark-tiled",
      defaultValue: "Tiled",
      comment: "Label for a repeated tiled watermark style"
    )
    static let watermarkOpacity = string(
      "annotate.watermark-opacity",
      defaultValue: "Opacity",
      comment: "Label for watermark opacity controls"
    )
    static let straight = string(
      "annotate.straight",
      defaultValue: "Straight",
      comment: "Label for the straight arrow style"
    )
    static let elbow = string(
      "annotate.elbow",
      defaultValue: "Elbow",
      comment: "Label for the elbow arrow style"
    )
    static let curve = string(
      "annotate.curve",
      defaultValue: "Curve",
      comment: "Label for the curve arrow style"
    )
    static let straightArrowHelp = string(
      "annotate.straight-arrow-help",
      defaultValue: "Direct line from start to end",
      comment: "Helper text for the straight arrow style"
    )
    static let elbowArrowHelp = string(
      "annotate.elbow-arrow-help",
      defaultValue: "Right-angle callout arrow",
      comment: "Helper text for the elbow arrow style"
    )
    static let curveArrowHelp = string(
      "annotate.curve-arrow-help",
      defaultValue: "Smooth curved callout arrow",
      comment: "Helper text for the curve arrow style"
    )
    static let xAxis = string(
      "annotate.x-axis",
      defaultValue: "X Axis",
      comment: "Label for the X axis rotation slider in mockup controls"
    )
    static let yAxis = string(
      "annotate.y-axis",
      defaultValue: "Y Axis",
      comment: "Label for the Y axis rotation slider in mockup controls"
    )
    static let zAxis = string(
      "annotate.z-axis",
      defaultValue: "Z Axis",
      comment: "Label for the Z axis rotation slider in mockup controls"
    )
    static let depth = string(
      "annotate.depth",
      defaultValue: "Depth",
      comment: "Label for the perspective depth slider in mockup controls"
    )
    static let resetMockup = string(
      "annotate.reset-mockup",
      defaultValue: "Reset Mockup",
      comment: "Button title for resetting mockup controls"
    )
    static let autoBalance = string(
      "annotate.auto-balance",
      defaultValue: "Auto-balance",
      comment: "Toggle label for automatically balancing canvas effects in annotate"
    )
    static let openSidebarForMoreControls = string(
      "annotate.open-sidebar-for-more-controls",
      defaultValue: "Open sidebar for more annotate controls",
      comment: "Tooltip for opening the full annotate sidebar from the quick properties bar"
    )
    static let resetToDefaults = string(
      "annotate.reset-to-defaults",
      defaultValue: "Reset to Defaults",
      comment: "Tooltip for resetting mockup values to defaults"
    )
  }

  enum VideoEditor {
    static let invalidFileTitle = string(
      "video-editor.invalid-file-title",
      defaultValue: "Invalid File",
      comment: "Alert title shown when an invalid file is dropped or selected in the video editor"
    )
    static let dropVideoHereToEdit = string(
      "video-editor.drop-video-here-to-edit",
      defaultValue: "Drop a video here to edit",
      comment: "Empty state title for the video editor"
    )
    static let supportsVideoFormats = string(
      "video-editor.supports-video-formats",
      defaultValue: "Supports MOV, MP4, GIF, and other video formats",
      comment: "Empty state subtitle for the video editor"
    )
    static let browseFiles = string(
      "video-editor.browse-files",
      defaultValue: "Browse Files...",
      comment: "Button title for browsing for a video file"
    )
    static let unsupportedFileType = string(
      "video-editor.unsupported-file-type",
      defaultValue: "Unsupported file type",
      comment: "Error shown when the dropped file type is not supported by the video editor"
    )
    static func failedToLoadFile(_ message: String) -> String {
      format(
        "video-editor.failed-to-load-file",
        defaultValue: "Failed to load file: %@",
        comment: "Error shown when the video editor cannot load a selected file. %@ is the lower-level error message.",
        message
      )
    }
    static let couldNotReadFile = string(
      "video-editor.could-not-read-file",
      defaultValue: "Could not read file",
      comment: "Error shown when the video editor cannot read a dropped file"
    )
    static func failedToPrepareFile(_ message: String) -> String {
      format(
        "video-editor.failed-to-prepare-file",
        defaultValue: "Failed to prepare file: %@",
        comment: "Error shown when the video editor cannot prepare a dropped file for editing. %@ is the lower-level error message.",
        message
      )
    }
    static let fileNotFound = string(
      "video-editor.file-not-found",
      defaultValue: "File not found",
      comment: "Error shown when the selected video file no longer exists"
    )
    static let selectValidVideoOrGIFFile = string(
      "video-editor.select-valid-video-or-gif-file",
      defaultValue: "Please select a valid video or GIF file",
      comment: "Error shown when the selected file is not a supported video or GIF"
    )
    static let exportingVideo = string(
      "video-editor.exporting-video",
      defaultValue: "Exporting Video",
      comment: "Title shown in the video editor export progress overlay"
    )
    static let zoomSettings = string(
      "video-editor.zoom-settings",
      defaultValue: "Zoom Settings",
      comment: "Title shown in the zoom settings popover"
    )
    static let zoomLevel = string(
      "video-editor.zoom-level",
      defaultValue: "Zoom Level",
      comment: "Label for zoom level controls in the video editor"
    )
    static let zoomCenter = string(
      "video-editor.zoom-center",
      defaultValue: "Zoom Center",
      comment: "Label for zoom center controls in the video editor"
    )
    static let topLeft = string(
      "video-editor.top-left",
      defaultValue: "Top Left",
      comment: "Label for the top-left zoom center preset"
    )
    static let topRight = string(
      "video-editor.top-right",
      defaultValue: "Top Right",
      comment: "Label for the top-right zoom center preset"
    )
    static let center = string(
      "video-editor.center",
      defaultValue: "Center",
      comment: "Label for the center zoom preset"
    )
    static let bottomLeft = string(
      "video-editor.bottom-left",
      defaultValue: "Bottom Left",
      comment: "Label for the bottom-left zoom center preset"
    )
    static let bottomRight = string(
      "video-editor.bottom-right",
      defaultValue: "Bottom Right",
      comment: "Label for the bottom-right zoom center preset"
    )
    static let zooms = string(
      "video-editor.zooms",
      defaultValue: "Zooms",
      comment: "Label for the zoom track in the video editor timeline"
    )
    static let addZoomHere = string(
      "video-editor.add-zoom-here",
      defaultValue: "Add Zoom Here",
      comment: "Context menu label for adding a zoom segment at the hovered location"
    )
    static let addZoomAtPlayhead = string(
      "video-editor.add-zoom-at-playhead",
      defaultValue: "Add Zoom at Playhead",
      comment: "Context menu label for adding a zoom segment at the playhead"
    )
    static let disableZoom = string(
      "video-editor.disable-zoom",
      defaultValue: "Disable Zoom",
      comment: "Context menu label for disabling a zoom segment"
    )
    static let enableZoom = string(
      "video-editor.enable-zoom",
      defaultValue: "Enable Zoom",
      comment: "Context menu label for enabling a zoom segment"
    )
    static let editZoom = string(
      "video-editor.edit-zoom",
      defaultValue: "Edit Zoom",
      comment: "Context menu label for editing a zoom segment"
    )
    static let deleteZoom = string(
      "video-editor.delete-zoom",
      defaultValue: "Delete Zoom",
      comment: "Context menu label for deleting a zoom segment"
    )
    static let removeAllZooms = string(
      "video-editor.remove-all-zooms",
      defaultValue: "Remove All Zooms",
      comment: "Context menu label for removing every zoom segment"
    )
    static let clickToAdd = string(
      "video-editor.click-to-add",
      defaultValue: "Click to add",
      comment: "Placeholder label shown on the zoom track"
    )
    static let backgroundTab = string(
      "video-editor.background-tab",
      defaultValue: "Background",
      comment: "Title for the video editor background sidebar tab"
    )
    static let zoomTab = string(
      "video-editor.zoom-tab",
      defaultValue: "Zoom",
      comment: "Title for the video editor zoom sidebar tab"
    )
    static let unknownTab = string(
      "video-editor.unknown-tab",
      defaultValue: "Unknown",
      comment: "Fallback title for an unknown video editor sidebar tab"
    )
    static let zoomItem = string(
      "video-editor.zoom-item",
      defaultValue: "Zoom Item",
      comment: "Header title for the selected zoom item in the video editor sidebar"
    )
    static let followMouse = string(
      "video-editor.follow-mouse",
      defaultValue: "Follow Mouse",
      comment: "Label for the automatic zoom mode that follows the cursor"
    )
    static let manual = string(
      "video-editor.manual",
      defaultValue: "Manual",
      comment: "Label for the manual zoom mode"
    )
    static let auto = string(
      "video-editor.auto",
      defaultValue: "Auto",
      comment: "Label for the automatic zoom mode"
    )
    static let mouseTrackingDataUnavailable = string(
      "video-editor.mouse-tracking-data-unavailable",
      defaultValue: "Mouse tracking data unavailable",
      comment: "Warning title shown when mouse tracking data is not available for follow-mouse zooms"
    )
    static let followMouseOnlyWorksWithSnapzy = string(
      "video-editor.follow-mouse-only-works-with-snapzy",
      defaultValue: "Follow Mouse only works with videos recorded by Snapzy after mouse tracking was added.",
      comment: "Warning message shown when follow-mouse zoom mode is unavailable"
    )
    static let followMouseActiveDescription = string(
      "video-editor.follow-mouse-active-description",
      defaultValue: "Camera position follows the recorded mouse path only while this zoom item is active.",
      comment: "Description shown when follow-mouse zoom mode is active"
    )
    static let manualModeDescription = string(
      "video-editor.manual-mode-description",
      defaultValue: "Manual mode keeps camera framing fixed. Switch to Auto when this zoom item should follow the mouse.",
      comment: "Description shown when manual zoom mode is active and mouse tracking data is available"
    )
    static let noZoomSelected = string(
      "video-editor.no-zoom-selected",
      defaultValue: "No Zoom Selected",
      comment: "Empty state title shown when no zoom segment is selected"
    )
    static let pressZToAddZoom = string(
      "video-editor.press-z-to-add-zoom",
      defaultValue: "Press Z to add a zoom at the playhead, or click a zoom item in the timeline.",
      comment: "Empty state description shown when no zoom segment is selected"
    )
    static let followSpeed = string(
      "video-editor.follow-speed",
      defaultValue: "Follow Speed",
      comment: "Label for the follow speed control"
    )
    static let followSpeedDescription = string(
      "video-editor.follow-speed-description",
      defaultValue: "Lower values feel calmer. Higher values react faster when the cursor changes direction.",
      comment: "Description shown for the follow speed control"
    )
    static let fast = string(
      "video-editor.fast",
      defaultValue: "Fast",
      comment: "Preset label for a fast zoom transition"
    )
    static let balanced = string(
      "video-editor.balanced",
      defaultValue: "Balanced",
      comment: "Preset label for a balanced zoom transition"
    )
    static let smooth = string(
      "video-editor.smooth",
      defaultValue: "Smooth",
      comment: "Preset label for a smooth zoom transition"
    )
    static let transitionSmoothness = string(
      "video-editor.transition-smoothness",
      defaultValue: "Transition Smoothness",
      comment: "Label for the zoom transition smoothness control"
    )
    static let transitionAppliesDescription = string(
      "video-editor.transition-applies-description",
      defaultValue: "Applies to all zoom items in this editor. Higher values feel calmer when entering or leaving zoom.",
      comment: "Description shown for the zoom transition smoothness control"
    )
    static let focusMargin = string(
      "video-editor.focus-margin",
      defaultValue: "Focus Margin",
      comment: "Label for the focus margin control"
    )
    static let focusMarginDescription = string(
      "video-editor.focus-margin-description",
      defaultValue: "Adds a stability zone so tiny cursor motion does not keep nudging the camera.",
      comment: "Description shown for the focus margin control"
    )
    static let manualCameraControlOnlyInManualMode = string(
      "video-editor.manual-camera-control-only-in-manual-mode",
      defaultValue: "Manual camera control is available only in Manual mode.",
      comment: "Description shown below zoom center controls"
    )
    static let save = string(
      "video-editor.save",
      defaultValue: "Save",
      comment: "Primary action title for saving a temp-capture video editor session"
    )
    static let convert = string(
      "video-editor.convert",
      defaultValue: "Convert",
      comment: "Primary action title for converting an existing video editor session"
    )
    static let unsavedChangesTitle = string(
      "video-editor.unsaved-changes-title",
      defaultValue: "Unsaved Changes",
      comment: "Alert title shown when closing the video editor with unsaved changes"
    )
    static let unsavedChangesMessage = string(
      "video-editor.unsaved-changes-message",
      defaultValue: "You have unsaved video edits. Do you want to save before closing?",
      comment: "Alert message shown when closing the video editor with unsaved changes"
    )
    static let dontSave = string(
      "video-editor.dont-save",
      defaultValue: "Don't Save",
      comment: "Button title for discarding video editor changes"
    )
    static let saveEditedVideoTitle = string(
      "video-editor.save-edited-video-title",
      defaultValue: "Save Edited Video",
      comment: "Alert title for choosing how to save an edited video"
    )
    static func saveEditedVideoMessage(_ filename: String) -> String {
      format(
        "video-editor.save-edited-video-message",
        defaultValue: "How would you like to save the edited video \"%@\"?",
        comment: "Alert message for choosing how to save an edited video. %@ is the file name.",
        filename
      )
    }
    static let replaceOriginal = string(
      "video-editor.replace-original",
      defaultValue: "Replace Original",
      comment: "Button title for replacing the original edited video file"
    )
    static let saveAsCopy = string(
      "video-editor.save-as-copy",
      defaultValue: "Save as Copy",
      comment: "Button title for saving an edited video as a copy"
    )
    static let fileAlreadyExistsTitle = string(
      "video-editor.file-already-exists-title",
      defaultValue: "File Already Exists",
      comment: "Alert title shown when a destination file already exists"
    )
    static func fileAlreadyExistsMessage(_ filename: String) -> String {
      format(
        "video-editor.file-already-exists-message",
        defaultValue: "A file named \"%@\" already exists in the destination folder.",
        comment: "Alert message shown when a destination file already exists. %@ is the file name.",
        filename
      )
    }
    static let saveGIFTitle = string(
      "video-editor.save-gif-title",
      defaultValue: "Save GIF",
      comment: "Save panel title for GIF export"
    )
    static let saveVideoTitle = string(
      "video-editor.save-video-title",
      defaultValue: "Save Video",
      comment: "Save panel title for video export"
    )
    static let chooseWhereToSaveFile = string(
      "video-editor.choose-where-to-save-file",
      defaultValue: "Choose where to save the file",
      comment: "Save panel message for video editor export"
    )
    static let chooseWhereToSaveEditedVideo = string(
      "video-editor.choose-where-to-save-edited-video",
      defaultValue: "Choose where to save the edited video",
      comment: "Save panel message for saving an edited video copy"
    )
    static let fileNameLabel = string(
      "video-editor.file-name-label",
      defaultValue: "File Name:",
      comment: "Save panel name field label for video editor export"
    )
    static let preparingSave = string(
      "video-editor.preparing-save",
      defaultValue: "Preparing save...",
      comment: "Progress message shown while preparing to save an edited file"
    )
    static let preparingExport = string(
      "video-editor.preparing-export",
      defaultValue: "Preparing export...",
      comment: "Progress message shown while preparing to export a video"
    )
    static let exporting = string(
      "video-editor.exporting",
      defaultValue: "Exporting...",
      comment: "Generic progress message shown while exporting a video"
    )
    static let resizingFrames = string(
      "video-editor.resizing-frames",
      defaultValue: "Resizing frames...",
      comment: "Progress message shown while resizing GIF frames"
    )
    static let finalizing = string(
      "video-editor.finalizing",
      defaultValue: "Finalizing...",
      comment: "Progress message shown while finalizing an export"
    )
    static let noChangesTitle = string(
      "video-editor.no-changes-title",
      defaultValue: "No Changes",
      comment: "Alert title shown when no video resize changes were made"
    )
    static let gifDimensionsNotChanged = string(
      "video-editor.gif-dimensions-not-changed",
      defaultValue: "The GIF dimensions haven't changed. Select a different size preset to resize.",
      comment: "Alert message shown when no GIF resize changes were made"
    )
    static let saveResizedGIFTitle = string(
      "video-editor.save-resized-gif-title",
      defaultValue: "Save Resized GIF",
      comment: "Alert and save panel title for resized GIF export"
    )
    static func resizeGifMessage(
      _ filename: String,
      _ sourceWidth: Int,
      _ sourceHeight: Int,
      _ targetWidth: Int,
      _ targetHeight: Int
    ) -> String {
      format(
        "video-editor.resize-gif-message",
        defaultValue: "Resize \"%@\" from %d×%d to %d×%d?",
        comment: "Alert message for resizing a GIF. %@ is the file name. The four %d values are source width, source height, target width, and target height.",
        filename,
        sourceWidth,
        sourceHeight,
        targetWidth,
        targetHeight
      )
    }
    static let resizingGIF = string(
      "video-editor.resizing-gif",
      defaultValue: "Resizing GIF...",
      comment: "Progress message shown while resizing a GIF"
    )
    static let saveVideoCopyTitle = string(
      "video-editor.save-video-copy-title",
      defaultValue: "Save Video Copy",
      comment: "Save panel title for saving an edited video copy"
    )
    static let processingVideo = string(
      "video-editor.processing-video",
      defaultValue: "Processing video...",
      comment: "Progress message shown while processing video frames"
    )
    static let applyingEffects = string(
      "video-editor.applying-effects",
      defaultValue: "Applying effects...",
      comment: "Progress message shown while applying video effects"
    )
    static let encodingFrames = string(
      "video-editor.encoding-frames",
      defaultValue: "Encoding frames...",
      comment: "Progress message shown while encoding frames"
    )
    static let completing = string(
      "video-editor.completing",
      defaultValue: "Completing...",
      comment: "Progress message shown at the end of a video export"
    )
    static let exportFailedTitle = string(
      "video-editor.export-failed-title",
      defaultValue: "Export Failed",
      comment: "Alert title shown when video export fails"
    )
    static let cannotReplaceOriginalTitle = string(
      "video-editor.cannot-replace-original-title",
      defaultValue: "Cannot Replace Original",
      comment: "Alert title shown when replacing the original video file is not allowed"
    )
    static func cannotReplaceOriginalMessage(_ details: String) -> String {
      format(
        "video-editor.cannot-replace-original-message",
        defaultValue: "Snapzy doesn't have write access to this file location. Save as a copy instead.\n\n%@",
        comment: "Alert message shown when replacing the original video file is not allowed. %@ is the lower-level error message.",
        details
      )
    }
    static func smallerFileSizeHint(_ reduction: Int) -> String {
      format(
        "video-editor.smaller-file-size-hint",
        defaultValue: "~%d%% smaller file size",
        comment: "Hint shown for the approximate file size reduction after resizing. %d is the percentage reduction.",
        reduction
      )
    }
    static let gifInfo = string(
      "video-editor.gif-info",
      defaultValue: "GIF Info",
      comment: "Section title for GIF metadata in the video editor"
    )
    static func framesCount(_ count: Int) -> String {
      format(
        "video-editor.frames-count",
        defaultValue: "%d frames",
        comment: "Label showing the number of GIF frames. %d is the frame count.",
        count
      )
    }
    static let keepOriginal = string(
      "video-editor.keep-original",
      defaultValue: "Keep Original",
      comment: "Label for keeping the original audio while exporting video"
    )
    static let mute = string(
      "video-editor.mute",
      defaultValue: "Mute",
      comment: "Label for muting audio while exporting video"
    )
    static let customVolume = string(
      "video-editor.custom-volume",
      defaultValue: "Custom Volume",
      comment: "Label for using a custom audio volume while exporting video"
    )
    static let videoDetails = string(
      "video-editor.video-details",
      defaultValue: "Video Details",
      comment: "Title for the video editor metadata sidebar"
    )
    static let zoomEffects = string(
      "video-editor.zoom-effects",
      defaultValue: "Zoom Effects",
      comment: "Section title for zoom effect metadata in the video editor"
    )
    static let smartCamera = string(
      "video-editor.smart-camera",
      defaultValue: "Smart Camera",
      comment: "Section title for smart camera metadata in the video editor"
    )
    static let segments = string(
      "video-editor.segments",
      defaultValue: "Segments",
      comment: "Label for the number of zoom segments in the video editor"
    )
    static let mouseSamples = string(
      "video-editor.mouse-samples",
      defaultValue: "Mouse Samples",
      comment: "Label for the number of mouse tracking samples in the video editor"
    )
    static let sampleRate = string(
      "video-editor.sample-rate",
      defaultValue: "Sample Rate",
      comment: "Label for the mouse sample rate in the video editor"
    )
    static let coordSpace = string(
      "video-editor.coord-space",
      defaultValue: "Coord Space",
      comment: "Label for the coordinate space in the video editor metadata sidebar"
    )
    static let autoSegments = string(
      "video-editor.auto-segments",
      defaultValue: "Auto Segments",
      comment: "Label for the number of auto-generated zoom segments in the video editor"
    )
    static func originalDimensionsLabel(_ width: Int, _ height: Int) -> String {
      format(
        "video-editor.original-dimensions-label",
        defaultValue: "Original (%d×%d)",
        comment: "Label for the original export dimension preset. The two %d values are width and height.",
        width,
        height
      )
    }
    static let showVideoInfoHint = string(
      "video-editor.show-video-info-hint",
      defaultValue: "Show Video Info (I)",
      comment: "Tooltip for showing the video info sidebar in the video editor"
    )
    static let hideVideoInfoHint = string(
      "video-editor.hide-video-info-hint",
      defaultValue: "Hide Video Info (I)",
      comment: "Tooltip for hiding the video info sidebar in the video editor"
    )
    static let filenamePlaceholder = string(
      "video-editor.filename-placeholder",
      defaultValue: "Filename",
      comment: "Placeholder for the rename field in the video editor toolbar"
    )
    static let showSidebarHint = string(
      "video-editor.show-sidebar-hint",
      defaultValue: "Show Sidebar (⌘.)",
      comment: "Tooltip for showing the right sidebar in the video editor"
    )
    static let hideSidebarHint = string(
      "video-editor.hide-sidebar-hint",
      defaultValue: "Hide Sidebar (⌘.)",
      comment: "Tooltip for hiding the right sidebar in the video editor"
    )
    static let undoShortcutHint = string(
      "video-editor.undo-shortcut-hint",
      defaultValue: "Undo (⌘Z)",
      comment: "Tooltip for undo in the video editor toolbar"
    )
    static let redoShortcutHint = string(
      "video-editor.redo-shortcut-hint",
      defaultValue: "Redo (⌘⇧Z)",
      comment: "Tooltip for redo in the video editor toolbar"
    )
    static let aspectRatio = string(
      "video-editor.aspect-ratio",
      defaultValue: "Aspect Ratio",
      comment: "Field label for aspect ratio in the video editor metadata sidebar"
    )
  }

  enum ScrollingCapture {
    static let runtimeReady = string(
      "scrolling-capture.runtime-ready",
      defaultValue: "Ready",
      comment: "Runtime state label for scrolling capture before starting"
    )
    static let runtimeCapturing = string(
      "scrolling-capture.runtime-capturing",
      defaultValue: "Capturing",
      comment: "Runtime state label for active scrolling capture"
    )
    static let runtimeLive = string(
      "scrolling-capture.runtime-live",
      defaultValue: "Live",
      comment: "Runtime state label for live scrolling capture preview"
    )
    static let runtimeProcessing = string(
      "scrolling-capture.runtime-processing",
      defaultValue: "Processing",
      comment: "Runtime state label for processing scrolling capture frames"
    )
    static let runtimePaused = string(
      "scrolling-capture.runtime-paused",
      defaultValue: "Paused",
      comment: "Runtime state label for paused scrolling capture recovery"
    )
    static let runtimeFinishing = string(
      "scrolling-capture.runtime-finishing",
      defaultValue: "Finishing",
      comment: "Runtime state label for finalizing scrolling capture"
    )
    static let runtimeSaving = string(
      "scrolling-capture.runtime-saving",
      defaultValue: "Saving",
      comment: "Runtime state label for saving scrolling capture output"
    )
    static let badgeCaptured = string(
      "scrolling-capture.badge-captured",
      defaultValue: "Captured",
      comment: "Badge label for committed scrolling capture preview"
    )
    static let badgeLive = string(
      "scrolling-capture.badge-live",
      defaultValue: "Live",
      comment: "Badge label for live scrolling capture preview"
    )
    static let badgeSyncing = string(
      "scrolling-capture.badge-syncing",
      defaultValue: "Syncing",
      comment: "Badge label for scrolling capture preview while syncing"
    )
    static let badgePaused = string(
      "scrolling-capture.badge-paused",
      defaultValue: "Paused",
      comment: "Badge label for paused scrolling capture preview"
    )
    static let badgeFinishing = string(
      "scrolling-capture.badge-finishing",
      defaultValue: "Finishing",
      comment: "Badge label for finalizing scrolling capture preview"
    )
    static let badgeSaving = string(
      "scrolling-capture.badge-saving",
      defaultValue: "Saving",
      comment: "Badge label for saving scrolling capture preview"
    )
    static let previewPressStartToBegin = string(
      "scrolling-capture.preview-press-start-to-begin",
      defaultValue: "Press Start Capture to begin.",
      comment: "Preview description shown before scrolling capture starts"
    )
    static let previewShowingLatestStitchedCapture = string(
      "scrolling-capture.preview-showing-latest-stitched-capture",
      defaultValue: "Showing the latest stitched capture.",
      comment: "Preview description shown when the committed stitched capture is displayed"
    )
    static let previewMatchesStitchedCapture = string(
      "scrolling-capture.preview-matches-stitched-capture",
      defaultValue: "Preview matches the stitched capture.",
      comment: "Preview description shown when the live preview matches the stitched output"
    )
    static let previewShowingLatestWhileLockingNewerContent = string(
      "scrolling-capture.preview-showing-latest-while-locking-newer-content",
      defaultValue: "Showing the latest stitched result while Snapzy locks newer content.",
      comment: "Preview description shown while scrolling capture syncs newer content"
    )
    static let previewPausedScrollSlowly = string(
      "scrolling-capture.preview-paused-scroll-slowly",
      defaultValue: "Preview paused - scroll slowly so Snapzy can re-align.",
      comment: "Preview description shown when scrolling capture needs recovery"
    )
    static let previewFinishingSavingCapture = string(
      "scrolling-capture.preview-finishing-saving-capture",
      defaultValue: "Finishing up - saving your capture.",
      comment: "Preview description shown when scrolling capture is finalizing"
    )
    static let previewSavingCapture = string(
      "scrolling-capture.preview-saving-capture",
      defaultValue: "Saving your capture...",
      comment: "Preview description shown while scrolling capture is saving"
    )
    static let guidanceReleaseToLockArea = string(
      "scrolling-capture.guidance-release-to-lock-area",
      defaultValue: "Release to lock area",
      comment: "Selection guidance title shown after moving or resizing the scrolling capture region"
    )
    static let guidanceKeepOnlyScrollingContent = string(
      "scrolling-capture.guidance-keep-only-scrolling-content",
      defaultValue: "Keep only the scrolling content",
      comment: "Selection guidance detail reminding users to frame only scrolling content"
    )
    static let guidanceAreaUpdated = string(
      "scrolling-capture.guidance-area-updated",
      defaultValue: "Area updated",
      comment: "Selection guidance title shown after the scrolling capture region is updated"
    )
    static let guidanceFrameOnlyScrollingContent = string(
      "scrolling-capture.guidance-frame-only-scrolling-content",
      defaultValue: "Frame only the scrolling content",
      comment: "Selection guidance title shown before starting scrolling capture"
    )
    static let guidanceThenPressStartCapture = string(
      "scrolling-capture.guidance-then-press-start-capture",
      defaultValue: "Then press Start Capture",
      comment: "Selection guidance detail shown before starting scrolling capture"
    )
    static let guidanceKeepOneDirection = string(
      "scrolling-capture.guidance-keep-one-direction",
      defaultValue: "Keep one direction",
      comment: "Selection guidance title shown when scrolling direction changes"
    )
    static let guidanceReverseScrollingCanBreakStitch = string(
      "scrolling-capture.guidance-reverse-scrolling-can-break-stitch",
      defaultValue: "Reverse scrolling can break the stitch",
      comment: "Selection guidance detail shown when scrolling direction changes"
    )
    static let guidanceKeepCapturing = string(
      "scrolling-capture.guidance-keep-capturing",
      defaultValue: "Keep capturing",
      comment: "Selection guidance title shown when scrolling capture has no savable result yet"
    )
    static let guidanceThenTryDoneAgain = string(
      "scrolling-capture.guidance-then-try-done-again",
      defaultValue: "Then try Done again",
      comment: "Selection guidance detail shown when scrolling capture has no savable result yet"
    )
    static let guidanceTryDoneAgain = string(
      "scrolling-capture.guidance-try-done-again",
      defaultValue: "Try Done again",
      comment: "Selection guidance title shown when scrolling capture save failed but current result remains available"
    )
    static let guidanceCurrentResultStillReady = string(
      "scrolling-capture.guidance-current-result-still-ready",
      defaultValue: "Current result is still ready",
      comment: "Selection guidance detail shown when scrolling capture save failed but current result remains available"
    )
    static let guidanceHeightLimitReached = string(
      "scrolling-capture.guidance-height-limit-reached",
      defaultValue: "Height limit reached",
      comment: "Selection guidance title shown when scrolling capture reaches the output height limit"
    )
    static let guidancePressDoneToSave = string(
      "scrolling-capture.guidance-press-done-to-save",
      defaultValue: "Press Done to save",
      comment: "Selection guidance detail shown when the current scrolling capture result can be saved"
    )
    static let guidanceNoNewContentDetected = string(
      "scrolling-capture.guidance-no-new-content-detected",
      defaultValue: "No new content was detected",
      comment: "Selection guidance detail shown when scrolling capture reaches the end of content"
    )
    static let guidanceCurrentStitchedResultReady = string(
      "scrolling-capture.guidance-current-stitched-result-ready",
      defaultValue: "Current stitched result is ready",
      comment: "Selection guidance detail shown when scrolling capture can be saved"
    )
    static let guidanceContinueManually = string(
      "scrolling-capture.guidance-continue-manually",
      defaultValue: "Continue manually",
      comment: "Selection guidance title shown when users should keep scrolling manually"
    )
    static let guidancePressDoneWhenReady = string(
      "scrolling-capture.guidance-press-done-when-ready",
      defaultValue: "Press Done when you're ready",
      comment: "Selection guidance detail shown when users should continue scrolling manually"
    )
    static let guidanceHoldSteady = string(
      "scrolling-capture.guidance-hold-steady",
      defaultValue: "Hold steady",
      comment: "Selection guidance title shown while the first scrolling capture frame is locking"
    )
    static let guidanceSnapzyLockingFirstFrame = string(
      "scrolling-capture.guidance-snapzy-locking-first-frame",
      defaultValue: "Snapzy is locking the first frame",
      comment: "Selection guidance detail shown while the first scrolling capture frame is locking"
    )
    static let guidanceSlowDown = string(
      "scrolling-capture.guidance-slow-down",
      defaultValue: "Slow down",
      comment: "Selection guidance title shown when scrolling capture needs slower scrolling"
    )
    static let guidanceKeepOneDirectionSoSnapzyCanRealign = string(
      "scrolling-capture.guidance-keep-one-direction-so-snapzy-can-realign",
      defaultValue: "Keep one direction so Snapzy can re-align",
      comment: "Selection guidance detail shown when scrolling capture needs recovery"
    )
    static let guidanceKeepSteadierPace = string(
      "scrolling-capture.guidance-keep-steadier-pace",
      defaultValue: "Keep a steadier pace",
      comment: "Selection guidance title shown when scrolling capture cannot align a frame"
    )
    static let guidanceStayOnOneDirection = string(
      "scrolling-capture.guidance-stay-on-one-direction",
      defaultValue: "Stay on one direction",
      comment: "Selection guidance detail shown when scrolling capture cannot align a frame"
    )
    static let guidancePreviewNeedsRecovery = string(
      "scrolling-capture.guidance-preview-needs-recovery",
      defaultValue: "Preview needs recovery",
      comment: "Selection guidance title shown when scrolling capture preview refresh fails"
    )
    static let guidanceKeepOneDirectionOrRestart = string(
      "scrolling-capture.guidance-keep-one-direction-or-restart",
      defaultValue: "Keep one direction or restart",
      comment: "Selection guidance detail shown when scrolling capture preview refresh fails"
    )
    static let guidanceKeepScrollingDown = string(
      "scrolling-capture.guidance-keep-scrolling-down",
      defaultValue: "Keep scrolling down",
      comment: "Selection guidance title shown while scrolling capture waits for new content"
    )
    static let guidanceOneDirectionSteadyPace = string(
      "scrolling-capture.guidance-one-direction-steady-pace",
      defaultValue: "One direction, steady pace",
      comment: "Selection guidance detail shown while scrolling capture waits for new content"
    )
    static let guidanceScrollDownSteadily = string(
      "scrolling-capture.guidance-scroll-down-steadily",
      defaultValue: "Scroll down steadily",
      comment: "Selection guidance title shown during active scrolling capture"
    )
    static let guidanceKeepOneDirectionForCleanStitch = string(
      "scrolling-capture.guidance-keep-one-direction-for-clean-stitch",
      defaultValue: "Keep one direction for a clean stitch",
      comment: "Selection guidance detail shown during active scrolling capture"
    )
    static let guidanceSavingCurrentResult = string(
      "scrolling-capture.guidance-saving-current-result",
      defaultValue: "Saving current result",
      comment: "Selection guidance title shown while scrolling capture saves after reaching a limit"
    )
    static let guidanceLockingCurrentCapture = string(
      "scrolling-capture.guidance-locking-current-capture",
      defaultValue: "Locking current capture",
      comment: "Selection guidance title shown while scrolling capture finalizes"
    )
    static let guidanceSnapzySealingStitchedResult = string(
      "scrolling-capture.guidance-snapzy-sealing-stitched-result",
      defaultValue: "Snapzy is sealing the stitched result",
      comment: "Selection guidance detail shown while scrolling capture finalizes"
    )
    static let guidanceSavingLongScreenshot = string(
      "scrolling-capture.guidance-saving-long-screenshot",
      defaultValue: "Saving long screenshot",
      comment: "Selection guidance title shown while scrolling capture saves the final image"
    )
    static let guidancePleaseWait = string(
      "scrolling-capture.guidance-please-wait",
      defaultValue: "Please wait",
      comment: "Selection guidance detail shown while scrolling capture saves the final image"
    )
    static let startCapture = string(
      "scrolling-capture.start-capture",
      defaultValue: "Start Capture",
      comment: "Primary button title for starting scrolling capture"
    )
    static func sectionsCaptured(_ count: Int) -> String {
      format(
        "scrolling-capture.sections-captured",
        defaultValue: "%d section(s) captured",
        comment: "Summary shown in the scrolling capture HUD. %d is the number of captured sections.",
        count
      )
    }
    static let captionStartCaptureToLockFirstFrame = string(
      "scrolling-capture.caption-start-capture-to-lock-first-frame",
      defaultValue: "Start Capture to lock the first frame",
      comment: "Preview caption shown before scrolling capture starts"
    )
    static let captionNoSavableResultReady = string(
      "scrolling-capture.caption-no-savable-result-ready",
      defaultValue: "No savable stitched result is ready yet",
      comment: "Preview caption shown when scrolling capture has no savable result yet"
    )
    static let captionSavingStitchedResult = string(
      "scrolling-capture.caption-saving-stitched-result",
      defaultValue: "Saving stitched result...",
      comment: "Preview caption shown while scrolling capture saves the stitched output"
    )
    static let captionSaveFailedResultStillReady = string(
      "scrolling-capture.caption-save-failed-result-still-ready",
      defaultValue: "Save failed • stitched result is still ready",
      comment: "Preview caption shown when scrolling capture save fails but the result remains ready"
    )
    static func framesStitchedNoNewContent(_ count: Int) -> String {
      format(
        "scrolling-capture.caption-frames-stitched-no-new-content",
        defaultValue: "%d frames stitched • no new content",
        comment: "Preview caption shown when scrolling capture reaches the end of new content. %d is the stitched frame count.",
        count
      )
    }
    static func framesStitchedHeightLimitReached(_ count: Int) -> String {
      format(
        "scrolling-capture.caption-frames-stitched-height-limit-reached",
        defaultValue: "%d frames stitched • height limit reached",
        comment: "Preview caption shown when scrolling capture reaches the height limit. %d is the stitched frame count.",
        count
      )
    }
    static let captionLivePreviewRunning = string(
      "scrolling-capture.caption-live-preview-running",
      defaultValue: "Live preview running while Snapzy locks the stitched frame.",
      comment: "Preview caption shown while the scrolling capture live preview stream is active"
    )
    static let captionFinalizingStitchedResult = string(
      "scrolling-capture.caption-finalizing-stitched-result",
      defaultValue: "Finalizing stitched result...",
      comment: "Preview caption shown while scrolling capture finalizes"
    )
    static let captionFirstFrameLocked = string(
      "scrolling-capture.caption-first-frame-locked",
      defaultValue: "First frame locked",
      comment: "Preview caption shown after the first scrolling capture frame is locked"
    )
    static func framesStitchedDelta(_ count: Int, _ delta: Int) -> String {
      format(
        "scrolling-capture.caption-frames-stitched-delta",
        defaultValue: "%d frames stitched • +%d px",
        comment: "Preview caption shown after appending a scrolling capture frame. %d values are stitched frame count and appended pixel delta.",
        count,
        delta
      )
    }
    static func finalizingFramesLocked(_ count: Int) -> String {
      format(
        "scrolling-capture.caption-finalizing-frames-locked",
        defaultValue: "Finalizing stitched result • %d frames locked",
        comment: "Preview caption shown while finalizing a scrolling capture with locked frames. %d is the stitched frame count.",
        count
      )
    }
    static func finalFrameLocked(_ count: Int, _ delta: Int) -> String {
      format(
        "scrolling-capture.caption-final-frame-locked",
        defaultValue: "Final frame locked • %d frames • +%d px",
        comment: "Preview caption shown when the final scrolling capture frame is locked. %d values are stitched frame count and appended pixel delta.",
        count,
        delta
      )
    }
    static let captionFinalizingCurrentResultNoNewContent = string(
      "scrolling-capture.caption-finalizing-current-result-no-new-content",
      defaultValue: "Finalizing current result • no new content",
      comment: "Preview caption shown when finalizing scrolling capture with no new content"
    )
    static let captionFinalizingCurrentResultLastFrameSkipped = string(
      "scrolling-capture.caption-finalizing-current-result-last-frame-skipped",
      defaultValue: "Finalizing current stitched result • last frame skipped",
      comment: "Preview caption shown when the last scrolling capture frame could not be aligned cleanly"
    )
    static let toastNoStitchedFrameReady = string(
      "scrolling-capture.toast-no-stitched-frame-ready",
      defaultValue: "No stitched frame is ready yet.",
      comment: "Toast shown when scrolling capture cannot save because no stitched frame is ready"
    )
    static let toastSavedStitchedImage = string(
      "scrolling-capture.toast-saved-stitched-image",
      defaultValue: "Scrolling Capture saved the stitched image.",
      comment: "Toast shown after scrolling capture saves successfully"
    )
    static let toastSessionAlreadyActive = string(
      "scrolling-capture.toast-session-already-active",
      defaultValue: "A scrolling capture session is already active.",
      comment: "Toast shown when the user tries to start a second scrolling capture session while one is already active"
    )
  }

  enum RecordingToolbar {
    static let options = string(
      "recording-toolbar.options",
      defaultValue: "Options",
      comment: "Button title for recording toolbar options"
    )
    static let recordingOptionsAccessibility = string(
      "recording-toolbar.options-accessibility",
      defaultValue: "Recording options",
      comment: "Accessibility label for recording toolbar options button"
    )
    static let recordingOptionsHint = string(
      "recording-toolbar.options-hint",
      defaultValue: "Opens settings for format, quality, and audio",
      comment: "Accessibility hint for recording toolbar options button"
    )
    static let settingsTitle = string(
      "recording-toolbar.settings-title",
      defaultValue: "Recording Settings",
      comment: "Popover title for recording toolbar settings"
    )
    static let formatSection = string(
      "recording-toolbar.format-section",
      defaultValue: "Format",
      comment: "Recording toolbar settings section title"
    )
    static let qualitySection = string(
      "recording-toolbar.quality-section",
      defaultValue: "Quality",
      comment: "Recording toolbar settings section title"
    )
    static let audioSection = string(
      "recording-toolbar.audio-section",
      defaultValue: "Audio",
      comment: "Recording toolbar settings section title"
    )
    static let overlaysSection = string(
      "recording-toolbar.overlays-section",
      defaultValue: "Overlays",
      comment: "Recording toolbar settings section title"
    )
    static let systemAudio = string(
      "recording-toolbar.system-audio",
      defaultValue: "System Audio",
      comment: "Recording toolbar setting label"
    )
    static let highlightClicks = string(
      "recording-toolbar.highlight-clicks",
      defaultValue: "Highlight Clicks",
      comment: "Recording toolbar setting label"
    )
    static let showKeystrokes = string(
      "recording-toolbar.show-keystrokes",
      defaultValue: "Show Keystrokes",
      comment: "Recording toolbar setting label"
    )
    static let outputModeAccessibilityPrefix = string(
      "recording-toolbar.output-mode-accessibility-prefix",
      defaultValue: "Output mode",
      comment: "Accessibility label prefix for current output mode"
    )
    static let outputModeHint = string(
      "recording-toolbar.output-mode-hint",
      defaultValue: "Opens output format selection",
      comment: "Accessibility hint for output mode selector"
    )
    static let record = string(
      "recording-toolbar.record",
      defaultValue: "Record",
      comment: "Recording toolbar primary action button title"
    )
    static func startRecordingAs(_ mode: String) -> String {
      format(
        "recording-toolbar.start-recording-as",
        defaultValue: "Start recording as %@",
        comment: "Accessibility label for recording button. %@ is the output mode name.",
        mode
      )
    }
    static let startRecordingHint = string(
      "recording-toolbar.start-recording-hint",
      defaultValue: "Begins screen recording with current settings",
      comment: "Accessibility hint for recording button"
    )
    static let stop = string(
      "recording-toolbar.stop",
      defaultValue: "Stop",
      comment: "Recording status bar stop button title"
    )
    static func stopRecordingAccessibility(_ duration: String) -> String {
      format(
        "recording-toolbar.stop-recording-accessibility",
        defaultValue: "Stop recording - Duration: %@",
        comment: "Accessibility label for stop recording button. %@ is the formatted duration.",
        duration
      )
    }
    static let stopRecordingHint = string(
      "recording-toolbar.stop-recording-hint",
      defaultValue: "Stops and saves the recording",
      comment: "Accessibility hint for stop recording button"
    )
    static let statusBarAccessibility = string(
      "recording-toolbar.status-bar-accessibility",
      defaultValue: "Recording status bar",
      comment: "Accessibility label for recording status bar container"
    )
    static let recordingInProgress = string(
      "recording-toolbar.recording-in-progress",
      defaultValue: "Recording in progress",
      comment: "Accessibility label for recording status indicator while active"
    )
    static let recordingPaused = string(
      "recording-toolbar.recording-paused",
      defaultValue: "Recording paused",
      comment: "Accessibility label for recording status indicator while paused"
    )
    static let resumeRecording = string(
      "recording-toolbar.resume-recording",
      defaultValue: "Resume recording",
      comment: "Accessibility label for resume recording button"
    )
    static let pauseRecording = string(
      "recording-toolbar.pause-recording",
      defaultValue: "Pause recording",
      comment: "Accessibility label for pause recording button"
    )
    static let enableAnnotations = string(
      "recording-toolbar.enable-annotations",
      defaultValue: "Enable annotations",
      comment: "Accessibility label for enabling live annotations during recording"
    )
    static let disableAnnotations = string(
      "recording-toolbar.disable-annotations",
      defaultValue: "Disable annotations",
      comment: "Accessibility label for disabling live annotations during recording"
    )
    static let restartRecording = string(
      "recording-toolbar.restart-recording",
      defaultValue: "Restart recording",
      comment: "Accessibility label for restarting a recording"
    )
    static let deleteRecording = string(
      "recording-toolbar.delete-recording",
      defaultValue: "Delete recording",
      comment: "Accessibility label for deleting a recording"
    )
    static let outputVideo = string(
      "recording-toolbar.output-video",
      defaultValue: "Video",
      comment: "Recording output mode label"
    )
    static let outputGIF = string(
      "recording-toolbar.output-gif",
      defaultValue: "GIF",
      comment: "Recording output mode label"
    )
    static let qualityHigh = string(
      "recording-toolbar.quality-high",
      defaultValue: "High",
      comment: "Recording quality preset label"
    )
    static let qualityMedium = string(
      "recording-toolbar.quality-medium",
      defaultValue: "Medium",
      comment: "Recording quality preset label"
    )
    static let qualityLow = string(
      "recording-toolbar.quality-low",
      defaultValue: "Low",
      comment: "Recording quality preset label"
    )
    static let fullscreenCapture = string(
      "recording-toolbar.fullscreen-capture",
      defaultValue: "Fullscreen capture",
      comment: "Tooltip and accessibility label for fullscreen capture mode"
    )
    static let areaSelection = string(
      "recording-toolbar.area-selection",
      defaultValue: "Area selection",
      comment: "Tooltip for area selection capture mode"
    )
    static let areaSelectionCapture = string(
      "recording-toolbar.area-selection-capture",
      defaultValue: "Area selection capture",
      comment: "Accessibility label for area selection capture mode"
    )
    static let cancelRecording = string(
      "recording-toolbar.cancel-recording",
      defaultValue: "Cancel recording",
      comment: "Accessibility label for cancelling recording before it starts"
    )
    static let captureScreenshot = string(
      "recording-toolbar.capture-screenshot",
      defaultValue: "Capture screenshot",
      comment: "Accessibility label for capturing a screenshot from the recording toolbar"
    )
    static let toolbarAccessibility = string(
      "recording-toolbar.toolbar-accessibility",
      defaultValue: "Recording toolbar",
      comment: "Accessibility label for the recording toolbar container"
    )
  }

  enum KeystrokePosition {
    static let bottomCenter = string(
      "keystroke-position.bottom-center",
      defaultValue: "Bottom Center",
      comment: "Keystroke overlay position label"
    )
    static let bottomLeft = string(
      "keystroke-position.bottom-left",
      defaultValue: "Bottom Left",
      comment: "Keystroke overlay position label"
    )
    static let bottomRight = string(
      "keystroke-position.bottom-right",
      defaultValue: "Bottom Right",
      comment: "Keystroke overlay position label"
    )
    static let topCenter = string(
      "keystroke-position.top-center",
      defaultValue: "Top Center",
      comment: "Keystroke overlay position label"
    )
    static let topLeft = string(
      "keystroke-position.top-left",
      defaultValue: "Top Left",
      comment: "Keystroke overlay position label"
    )
    static let topRight = string(
      "keystroke-position.top-right",
      defaultValue: "Top Right",
      comment: "Keystroke overlay position label"
    )
  }

  enum Recording {
    static let failedTitle = string(
      "recording.failed-title",
      defaultValue: "Recording Failed",
      comment: "Alert title shown when starting or running a recording fails"
    )
    static let screenshotFailedTitle = string(
      "recording.screenshot-failed-title",
      defaultValue: "Screenshot Failed",
      comment: "Alert title shown when taking a screenshot during recording fails"
    )
    static let saveLocationAccessRequiredTitle = string(
      "recording.save-location-access-required-title",
      defaultValue: "Save Location Access Required",
      comment: "Alert title shown when save location access is missing"
    )
    static let saveLocationAccessRequiredMessage = string(
      "recording.save-location-access-required-message",
      defaultValue: "Snapzy needs a save folder permission to continue. Please choose a folder in onboarding or grant it now.",
      comment: "Alert message shown when save location access is missing"
    )
    static let chooseSaveLocationMessage = string(
      "recording.choose-save-location-message",
      defaultValue: "Choose where Snapzy should save screenshots and recordings",
      comment: "Prompt shown when asking for an export directory during recording flows"
    )
    static let screenPermissionDenied = string(
      "recording.error.screen-permission-denied",
      defaultValue: "Screen recording permission denied",
      comment: "Error description when screen recording permission is denied"
    )
    static let microphonePermissionDenied = string(
      "recording.error.microphone-permission-denied",
      defaultValue: "Microphone permission denied",
      comment: "Error description when microphone permission is denied"
    )
    static let noDisplayFound = string(
      "recording.error.no-display-found",
      defaultValue: "No display found",
      comment: "Error description when no display matches the selected recording area"
    )
    static func shareableContentLoadFailed(_ message: String) -> String {
      format(
        "recording.error.shareable-content-load-failed",
        defaultValue: "ScreenCaptureKit could not load shareable content: %@",
        comment: "Error description when ScreenCaptureKit cannot load shareable content. %@ is the underlying error message.",
        message
      )
    }
    static func setupFailed(_ message: String) -> String {
      format(
        "recording.error.setup-failed",
        defaultValue: "Setup failed: %@",
        comment: "Error description when recording setup fails. %@ is the lower-level error message.",
        message
      )
    }
    static let failedToStartWriting = string(
      "recording.error.failed-to-start-writing",
      defaultValue: "Failed to start writing",
      comment: "Error description when the asset writer fails to start"
    )
    static let noOutputURL = string(
      "recording.error.no-output-url",
      defaultValue: "No output URL",
      comment: "Error description when the recording output URL is missing"
    )
    static let cannotAddVideoWriterInput = string(
      "recording.error.cannot-add-video-writer-input",
      defaultValue: "Cannot add video writer input",
      comment: "Error description when the video writer input cannot be added"
    )
    static let cannotAddSystemAudioWriterInput = string(
      "recording.error.cannot-add-system-audio-writer-input",
      defaultValue: "Cannot add system audio writer input",
      comment: "Error description when the system audio writer input cannot be added"
    )
    static let cannotAddMicrophoneWriterInput = string(
      "recording.error.cannot-add-microphone-writer-input",
      defaultValue: "Cannot add microphone writer input",
      comment: "Error description when the microphone writer input cannot be added"
    )
    static let selectionOutsideDisplayBounds = string(
      "recording.error.selection-outside-display-bounds",
      defaultValue: "Selection area is outside display bounds",
      comment: "Error description when the selected recording area is outside the display bounds"
    )
    static func writeFailed(_ message: String) -> String {
      format(
        "recording.error.write-failed",
        defaultValue: "Write failed: %@",
        comment: "Error description when writing recording output fails. %@ is the lower-level error message.",
        message
      )
    }
    static let cancelled = string(
      "recording.error.cancelled",
      defaultValue: "Recording cancelled",
      comment: "Error description when recording is cancelled"
    )
  }

  enum CrashReport {
    static let alertTitle = string(
      "crash-report.alert-title",
      defaultValue: "Report a Problem",
      comment: "Alert title shown when presenting a problem report dialog"
    )
    static let alertMessage = string(
      "crash-report.alert-message",
      defaultValue: "Snapzy bundled your diagnostic logs into one file. Drag the file below to the report page.",
      comment: "Alert message shown when presenting a problem report dialog with a log bundle"
    )
    static let alertMessageNoLogBundle = string(
      "crash-report.alert-message-no-log-bundle",
      defaultValue: "Snapzy could not prepare a diagnostic log bundle. You can still open the report page and describe the problem.",
      comment: "Alert message shown when presenting a problem report dialog without a log bundle"
    )
    static let submit = string(
      "crash-report.submit",
      defaultValue: "Open Report Page",
      comment: "Primary button title for problem report alert"
    )
    static let dismiss = string(
      "crash-report.dismiss",
      defaultValue: "Close",
      comment: "Secondary button title for problem report alert"
    )
    static let accessoryHint = string(
      "crash-report.accessory-hint",
      defaultValue: "Drag log bundle to the report page",
      comment: "Hint shown below the draggable problem report log bundle"
    )
  }

  enum FileAccess {
    nonisolated static let chooseCapturesFolderMessage = string(
      "file-access.choose-captures-folder-message",
      defaultValue: "Choose where Snapzy should save screenshots and recordings",
      comment: "Open panel message shown when Snapzy asks the user to grant access to a save folder"
    )
    nonisolated static let grantAccessPrompt = string(
      "file-access.grant-access-prompt",
      defaultValue: "Grant Access",
      comment: "Open panel prompt shown when Snapzy asks the user to grant folder access"
    )
    nonisolated static let chooseFolderPrompt = string(
      "file-access.choose-folder-prompt",
      defaultValue: "Choose Folder",
      comment: "Open panel prompt shown when Snapzy asks the user to choose a folder"
    )
    nonisolated static let desktopPicturesAccessMessage = string(
      "file-access.desktop-pictures-access-message",
      defaultValue: "Select the Desktop Pictures folder to grant access",
      comment: "Open panel message shown when Snapzy asks for access to the system Desktop Pictures folder"
    )
    static let bookmarkSaveFailedTitle = string(
      "file-access.bookmark-save-failed-title",
      defaultValue: "Folder Access Not Granted",
      comment: "Alert title when security-scoped bookmark persistence fails"
    )
    static let bookmarkSaveFailedMessage = string(
      "file-access.bookmark-save-failed-message",
      defaultValue: "Snapzy could not persist access to this folder. Please choose the folder again and confirm permission.",
      comment: "Alert message when security-scoped bookmark persistence fails"
    )
  }

  enum AfterCapture {
    static let copyFileAction = string(
      "after-capture.copy-file-action",
      defaultValue: "Copy File",
      comment: "After capture action title"
    )
    static let saveAction = string(
      "after-capture.save-action",
      defaultValue: "Save",
      comment: "After capture action title"
    )
    static let openAnnotateAction = string(
      "after-capture.open-annotate-action",
      defaultValue: "Open Annotate Editor",
      comment: "After capture action title"
    )
    static let uploadToCloudAction = string(
      "after-capture.upload-to-cloud-action",
      defaultValue: "Upload to Cloud & Copy Link",
      comment: "After capture action title"
    )
    static let cloudAlertTitle = string(
      "after-capture.cloud-alert-title",
      defaultValue: "Cloud Not Configured",
      comment: "Alert title when cloud action is enabled without cloud credentials"
    )
    static let cloudAlertMessage = string(
      "after-capture.cloud-alert-message",
      defaultValue: "Please set up your cloud credentials in Preferences → Cloud before enabling this option.",
      comment: "Alert message when cloud action is enabled without cloud credentials"
    )
    static let showQuickAccessDescription = string(
      "after-capture.show-quick-access-description",
      defaultValue: "Display overlay with quick actions",
      comment: "After capture action description"
    )
    static let copyFileDescription = string(
      "after-capture.copy-file-description",
      defaultValue: "Copy to clipboard automatically",
      comment: "After capture action description"
    )
    static let saveDescription = string(
      "after-capture.save-description",
      defaultValue: "Save to export location",
      comment: "After capture action description"
    )
    static let openAnnotateDescription = string(
      "after-capture.open-annotate-description",
      defaultValue: "Open annotate editor after capture",
      comment: "After capture action description"
    )
    static let uploadToCloudDescription = string(
      "after-capture.upload-to-cloud-description",
      defaultValue: "Upload captures to cloud & copy link",
      comment: "After capture action description"
    )
    static func accessibilityLabel(_ action: String, captureKind: String) -> String {
      format(
        "after-capture.accessibility-label",
        defaultValue: "%@ for %@",
        comment: "Accessibility label for after-capture action toggle. First %@ is the action label, second %@ is the capture kind.",
        action,
        captureKind
      )
    }
  }

  enum Annotate {
    static let selectionTool = string(
      "annotate.tool.selection",
      defaultValue: "Selection",
      comment: "Annotation tool display name"
    )
    static let cropTool = string(
      "annotate.tool.crop",
      defaultValue: "Crop",
      comment: "Annotation tool display name"
    )
    static let rectangleTool = string(
      "annotate.tool.rectangle",
      defaultValue: "Rectangle",
      comment: "Annotation tool display name"
    )
    static let filledRectangleTool = string(
      "annotate.tool.filled-rectangle",
      defaultValue: "Filled Rectangle",
      comment: "Annotation tool display name"
    )
    static let ovalTool = string(
      "annotate.tool.oval",
      defaultValue: "Oval",
      comment: "Annotation tool display name"
    )
    static let arrowTool = string(
      "annotate.tool.arrow",
      defaultValue: "Arrow",
      comment: "Annotation tool display name"
    )
    static let lineTool = string(
      "annotate.tool.line",
      defaultValue: "Line",
      comment: "Annotation tool display name"
    )
    static let textTool = string(
      "annotate.tool.text",
      defaultValue: "Text",
      comment: "Annotation tool display name"
    )
    static let highlighterTool = string(
      "annotate.tool.highlighter",
      defaultValue: "Highlighter",
      comment: "Annotation tool display name"
    )
    static let blurTool = string(
      "annotate.tool.blur",
      defaultValue: "Blur",
      comment: "Annotation tool display name"
    )
    static let counterTool = string(
      "annotate.tool.counter",
      defaultValue: "Counter",
      comment: "Annotation tool display name"
    )
    static let watermarkTool = string(
      "annotate.tool.watermark",
      defaultValue: "Watermark",
      comment: "Annotation tool display name"
    )
    static let pencilTool = string(
      "annotate.tool.pencil",
      defaultValue: "Pencil",
      comment: "Annotation tool display name"
    )
    static let mockupTool = string(
      "annotate.tool.mockup",
      defaultValue: "Mockup",
      comment: "Annotation tool display name"
    )
  }

  enum QuickAccess {
    static let editVideo = string(
      "quick-access.edit-video",
      defaultValue: "Edit Video",
      comment: "Quick Access tooltip for opening the video editor"
    )
  }

  enum AnnotateContext {
    static func selected(_ toolName: String) -> String {
      format(
        "annotate-context.selected",
        defaultValue: "Selected %@",
        comment: "Quick properties title for a selected annotation. %@ is the localized tool name.",
        toolName
      )
    }

    static func defaults(_ toolName: String) -> String {
      format(
        "annotate-context.defaults",
        defaultValue: "%@ Defaults",
        comment: "Quick properties title for annotation tool defaults. %@ is the localized tool name.",
        toolName
      )
    }

    static let wallpaperOcean = string(
      "annotate-context.wallpaper-ocean",
      defaultValue: "Ocean",
      comment: "Wallpaper preset name in annotate and video editor"
    )
    static let wallpaperSunset = string(
      "annotate-context.wallpaper-sunset",
      defaultValue: "Sunset",
      comment: "Wallpaper preset name in annotate and video editor"
    )
    static let wallpaperForest = string(
      "annotate-context.wallpaper-forest",
      defaultValue: "Forest",
      comment: "Wallpaper preset name in annotate and video editor"
    )
  }

  enum RecordingAnnotation {
    static func autoClear(_ toolName: String) -> String {
      format(
        "recording-annotation.auto-clear",
        defaultValue: "Auto-clear: %@",
        comment: "Menu header for annotation auto-clear settings during recording. %@ is the localized tool name.",
        toolName
      )
    }

    static let persist = string(
      "recording-annotation.persist",
      defaultValue: "Persist",
      comment: "Annotation auto-clear option that keeps annotations until manually cleared"
    )
    static func lastCount(_ count: Int) -> String {
      format(
        "recording-annotation.last-count",
        defaultValue: "Last %d",
        comment: "Annotation auto-clear option that keeps the last N annotations. %d is the number of annotations to keep.",
        count
      )
    }
    static let modifierShift = string(
      "recording-annotation.modifier-shift",
      defaultValue: "Shift (⇧)",
      comment: "Modifier key option for recording annotation shortcuts"
    )
    static let modifierControl = string(
      "recording-annotation.modifier-control",
      defaultValue: "Control (⌃)",
      comment: "Modifier key option for recording annotation shortcuts"
    )
    static let modifierOption = string(
      "recording-annotation.modifier-option",
      defaultValue: "Option (⌥)",
      comment: "Modifier key option for recording annotation shortcuts"
    )
  }

  enum SystemShortcuts {
    static let macOSCaptureArea = string(
      "system-shortcuts.macos-capture-area",
      defaultValue: "macOS Capture Area",
      comment: "Human-readable label for the macOS system shortcut that captures a selected area"
    )
    static let macOSCopyArea = string(
      "system-shortcuts.macos-copy-area",
      defaultValue: "macOS Copy Area",
      comment: "Human-readable label for the macOS system shortcut that copies a selected area to the clipboard"
    )
    static let macOSCaptureFullscreen = string(
      "system-shortcuts.macos-capture-fullscreen",
      defaultValue: "macOS Capture Fullscreen",
      comment: "Human-readable label for the macOS system shortcut that captures the full screen"
    )
    static let macOSCopyFullscreen = string(
      "system-shortcuts.macos-copy-fullscreen",
      defaultValue: "macOS Copy Fullscreen",
      comment: "Human-readable label for the macOS system shortcut that copies the full screen to the clipboard"
    )
    static let macOSScreenshotOptions = string(
      "system-shortcuts.macos-screenshot-options",
      defaultValue: "macOS Screenshot & Recording Options",
      comment: "Human-readable label for the macOS system shortcut that opens the screenshot and recording options"
    )
  }

  enum ScreenCapture {
    static let permissionDenied = string(
      "screen-capture.permission-denied",
      defaultValue: "Screen capture permission denied",
      comment: "Error shown when screenshot capture is attempted without screen recording permission"
    )
    static let noDisplayFound = string(
      "screen-capture.no-display-found",
      defaultValue: "No display found to capture",
      comment: "Error shown when no display matches the selected screenshot target"
    )
    nonisolated static let saveLocationPermissionRequired = string(
      "screen-capture.save-location-permission-required",
      defaultValue: "Save location permission is required.",
      comment: "Error shown when Snapzy cannot save a screenshot because folder access has not been granted"
    )
    nonisolated static let unableToCaptureSelectedArea = string(
      "screen-capture.unable-to-capture-selected-area",
      defaultValue: "Unable to capture the selected area.",
      comment: "Error shown when Snapzy cannot capture the selected screenshot area"
    )
    nonisolated static let failedToCropCapturedImage = string(
      "screen-capture.failed-to-crop-captured-image",
      defaultValue: "Failed to crop the captured image",
      comment: "Error shown when Snapzy captures an image but fails to crop it to the selected area"
    )
    nonisolated static func couldNotCreateDirectory(_ message: String) -> String {
      format(
        "screen-capture.could-not-create-directory",
        defaultValue: "Could not create the save folder: %@",
        comment: "Error shown when Snapzy cannot create the selected save folder. %@ is the underlying filesystem error.",
        message
      )
    }
    nonisolated static let webpEncodingFailed = string(
      "screen-capture.webp-encoding-failed",
      defaultValue: "WebP encoding failed",
      comment: "Error shown when Snapzy cannot encode a screenshot as WebP"
    )
    nonisolated static let couldNotCreateImageDestination = string(
      "screen-capture.could-not-create-image-destination",
      defaultValue: "Could not create the image destination",
      comment: "Error shown when Snapzy cannot create an image writer for the screenshot"
    )
    nonisolated static let failedToWriteImageToDisk = string(
      "screen-capture.failed-to-write-image-to-disk",
      defaultValue: "Failed to write the image to disk",
      comment: "Error shown when Snapzy fails while writing a screenshot to disk"
    )
    nonisolated static func fileWriteVerificationFailed(_ fileName: String) -> String {
      format(
        "screen-capture.file-write-verification-failed",
        defaultValue: "File write verification failed for %@",
        comment: "Error shown when Snapzy writes a screenshot file but cannot verify it afterward. %@ is the file name.",
        fileName
      )
    }
    nonisolated static let selectionOutsideDisplayBounds = string(
      "screen-capture.selection-outside-display-bounds",
      defaultValue: "The selected area is outside the display bounds",
      comment: "Error shown when the screenshot selection falls outside the active display bounds"
    )
    nonisolated static let failedToCreateImageFromFrame = string(
      "screen-capture.failed-to-create-image-from-frame",
      defaultValue: "Failed to create an image from the captured frame",
      comment: "Error shown when Snapzy cannot convert a captured stream frame into an image"
    )
    nonisolated static let selectedWindowUnavailable = string(
      "screen-capture.selected-window-unavailable",
      defaultValue: "The selected window is no longer available",
      comment: "Error shown when application mode resolves a window target that disappeared before capture"
    )
    static func applicationModeHint(_ shortcut: String) -> String {
      format(
        "screen-capture.application-mode-hint",
        defaultValue: "Press %@ to select an app window",
        comment: "Hint shown in screenshot area selection when manual mode is active and application mode can be toggled on. %@ is the current single-key shortcut.",
        shortcut
      )
    }
    static func manualModeHint(_ shortcut: String) -> String {
      format(
        "screen-capture.manual-mode-hint",
        defaultValue: "Press %@ for manual area selection",
        comment: "Hint shown in screenshot area selection when application mode is active and manual mode can be toggled on. %@ is the current single-key shortcut.",
        shortcut
      )
    }
    static func captureFailed(_ reason: String) -> String {
      format(
        "screen-capture.capture-failed",
        defaultValue: "Capture failed: %@",
        comment: "Error shown when screenshot capture fails. %@ is the lower-level reason.",
        reason
      )
    }
    static func saveFailed(_ reason: String) -> String {
      format(
        "screen-capture.save-failed",
        defaultValue: "Failed to save screenshot: %@",
        comment: "Error shown when saving a screenshot fails. %@ is the lower-level reason.",
        reason
      )
    }
    static let cancelled = string(
      "screen-capture.cancelled",
      defaultValue: "Capture was cancelled",
      comment: "Error shown when screenshot capture is cancelled"
    )
  }

  enum OCR {
    static let extractingContent = string(
      "ocr.extracting-content",
      defaultValue: "Extracting content...",
      comment: "Progress toast shown while OCR is extracting text or QR content from the selected area"
    )
    static let imageConversionFailed = string(
      "ocr.image-conversion-failed",
      defaultValue: "Failed to convert image for OCR processing",
      comment: "Error shown when OCR cannot convert an image into a processable format"
    )
    static let noTextFound = string(
      "ocr.no-text-found",
      defaultValue: "No text found in the selected area",
      comment: "Error shown when OCR cannot detect text in the selected area"
    )
    static let qrCodesLabel = string(
      "ocr.qr-codes-label",
      defaultValue: "QR Codes",
      comment: "Clipboard section title shown before multiple QR code payloads copied from OCR capture"
    )
    static let qrTextOnlyUnsupported = string(
      "ocr.qr-text-only-unsupported",
      defaultValue: "QR code detected, but Snapzy can only copy text-based QR content.",
      comment: "Warning shown when OCR capture detects a QR code whose content cannot be represented as text"
    )
    static func recognitionFailed(_ message: String) -> String {
      format(
        "ocr.recognition-failed",
        defaultValue: "OCR recognition failed: %@",
        comment: "Error shown when OCR recognition fails. %@ is the underlying error message.",
        message
      )
    }
  }

  enum GIF {
    static let invalidVideo = string(
      "gif.invalid-video",
      defaultValue: "Invalid or empty video file",
      comment: "Error shown when converting an invalid video to GIF"
    )
    static let noFramesFromVideo = string(
      "gif.no-frames-from-video",
      defaultValue: "Could not extract any frames from video",
      comment: "Error shown when converting a video to GIF but no frames can be extracted"
    )
    static let cannotReadSource = string(
      "gif.cannot-read-source",
      defaultValue: "Cannot read GIF file",
      comment: "Error shown when a GIF source file cannot be read"
    )
    static let noFramesInGIF = string(
      "gif.no-frames-in-gif",
      defaultValue: "GIF contains no frames",
      comment: "Error shown when a GIF file contains no frames"
    )
    static let cannotCreateOutputFile = string(
      "gif.cannot-create-output-file",
      defaultValue: "Failed to create GIF output file",
      comment: "Error shown when a GIF destination file cannot be created"
    )
    static let finalizeFailed = string(
      "gif.finalize-failed",
      defaultValue: "Failed to finalize GIF file",
      comment: "Error shown when GIF generation or resizing cannot be finalized"
    )
    static let finalizeResizedFailed = string(
      "gif.finalize-resized-failed",
      defaultValue: "Failed to finalize resized GIF",
      comment: "Error shown when a resized GIF cannot be finalized"
    )
  }

  enum ForegroundCutout {
    static let unsupportedOS = string(
      "foreground-cutout.unsupported-os",
      defaultValue: "Background cutout requires macOS 14 or newer.",
      comment: "Error shown when foreground cutout is unavailable on the current macOS version"
    )
    static let noSubjectDetected = string(
      "foreground-cutout.no-subject-detected",
      defaultValue: "No foreground subject was detected in the selected area.",
      comment: "Error shown when no foreground subject can be detected for background removal"
    )
    static let noSubjectDetectedTryTighterArea = string(
      "foreground-cutout.no-subject-detected-try-tighter-area",
      defaultValue: "No subject detected. Try selecting a tighter area around the subject.",
      comment: "Toast shown when background removal cannot find a subject and the user should tighten the selection"
    )
    static func cutoutFailed(_ message: String) -> String {
      format(
        "foreground-cutout.cutout-failed",
        defaultValue: "Background cutout failed: %@",
        comment: "Error shown when background removal fails. %@ is the lower-level error message.",
        message
      )
    }
    static let imageConversionFailed = string(
      "foreground-cutout.image-conversion-failed",
      defaultValue: "Unable to convert cutout result to image.",
      comment: "Error shown when the cutout result cannot be converted back to an image"
    )
    static let unableToProcessImageTryAgain = string(
      "foreground-cutout.unable-to-process-image-try-again",
      defaultValue: "Unable to process the cutout image. Please try again.",
      comment: "Toast shown when background removal fails while processing the cutout image"
    )
    static let genericFailure = string(
      "foreground-cutout.generic-failure",
      defaultValue: "Background cutout failed. Please try again.",
      comment: "Generic toast shown when background removal fails for an unknown reason"
    )
  }

  enum CaptureStorage {
    static let empty = string(
      "capture-storage.empty",
      defaultValue: "Empty",
      comment: "Label shown when the capture cache is empty"
    )
    static let operationInProgress = string(
      "capture-storage.operation-in-progress",
      defaultValue: "Cannot clear cache while a capture or recording is in progress.",
      comment: "Error shown when cache cleanup is attempted while a capture or recording is active"
    )
  }

  enum VideoEditorTimeline {
    static let extractingFrames = string(
      "video-editor-timeline.extracting-frames",
      defaultValue: "Extracting frames...",
      comment: "Loading label shown while the video timeline frame strip is extracting thumbnails"
    )
  }

  enum VideoExport {
    nonisolated static let sessionCreationFailed = string(
      "video-export.session-creation-failed",
      defaultValue: "Failed to create export session",
      comment: "Error shown when the video editor cannot create an export session"
    )
    nonisolated static let exportFailed = string(
      "video-export.export-failed",
      defaultValue: "Video export failed",
      comment: "Error shown when exporting a video fails"
    )
  }

  enum ZoomCompositor {
    static let noVideoTrack = string(
      "zoom-compositor.no-video-track",
      defaultValue: "Video file format is incompatible or corrupted. Please try re-recording.",
      comment: "Error shown when the video editor export cannot find a usable video track"
    )
    static let compositionFailed = string(
      "zoom-compositor.composition-failed",
      defaultValue: "Failed to apply zoom effects. The video may be corrupted or in an unsupported format.",
      comment: "Error shown when applying zoom effects during video export fails"
    )
    static func trackMismatch(_ expected: String, _ available: String) -> String {
      format(
        "zoom-compositor.track-mismatch",
        defaultValue: "Track ID mismatch: expected %@, available: %@. Please try re-exporting.",
        comment: "Error shown when the compositor cannot find the expected track. First %@ is the expected track id, second %@ is the list of available track ids.",
        expected,
        available
      )
    }
  }

  enum ScrollingCaptureStatus {
    static let adjustRegion = string(
      "scrolling-capture-status.adjust-region",
      defaultValue: "Adjust the region so only the moving content stays inside, then press Start Capture. Press Esc to cancel.",
      comment: "Status shown before a scrolling capture starts"
    )
    static let releaseToLockUpdatedRegion = string(
      "scrolling-capture-status.release-to-lock-updated-region",
      defaultValue: "Release to lock the updated scrolling region.",
      comment: "Status shown while dragging or resizing the scrolling capture region"
    )
    static let regionUpdated = string(
      "scrolling-capture-status.region-updated",
      defaultValue: "Region updated. Keep only the moving content inside, then press Start Capture. Press Esc to cancel.",
      comment: "Status shown after updating the scrolling capture region"
    )
    static let capturingFirstFrame = string(
      "scrolling-capture-status.capturing-first-frame",
      defaultValue: "Capturing the first frame. After that, keep scrolling downward at a steady pace.",
      comment: "Status shown when the scrolling capture session starts"
    )
    static let noSavableResultReady = string(
      "scrolling-capture-status.no-savable-result-ready",
      defaultValue: "Snapzy couldn't lock a savable stitched image yet. You can keep capturing, try Done again, or Cancel.",
      comment: "Status shown when Done is pressed before a savable stitched result exists"
    )
    static let savingStitchedImage = string(
      "scrolling-capture-status.saving-stitched-image",
      defaultValue: "Saving the stitched long image.",
      comment: "Status shown while saving a scrolling capture result"
    )
    static let saveFailedResultStillReady = string(
      "scrolling-capture-status.save-failed-result-still-ready",
      defaultValue: "Save failed. The stitched result is frozen, so you can try Done again or Cancel.",
      comment: "Status shown when saving a scrolling capture result fails but the stitched image is still available"
    )
    static let directionChanged = string(
      "scrolling-capture-status.direction-changed",
      defaultValue: "Direction changed. Keep scrolling the same way or restart the session.",
      comment: "Status shown when the user reverses scrolling direction during scrolling capture"
    )
    static let aligningLatestContent = string(
      "scrolling-capture-status.aligning-latest-content",
      defaultValue: "Capturing and aligning the latest visible content...",
      comment: "Status shown while the live preview is being aligned into the stitched result"
    )
    static let mixedDirectionsFinalizing = string(
      "scrolling-capture-status.mixed-directions-finalizing",
      defaultValue: "Finalizing the current stitched result after mixed scroll directions.",
      comment: "Status shown when finalizing after mixed scroll directions were detected"
    )
    static let mixedDirectionsDetected = string(
      "scrolling-capture-status.mixed-directions-detected",
      defaultValue: "Mixed scroll directions detected. Keep one direction so Snapzy can align.",
      comment: "Status shown when mixed scroll directions are detected during scrolling capture"
    )
    static let couldntCaptureLastFrame = string(
      "scrolling-capture-status.couldnt-capture-last-frame",
      defaultValue: "Couldn't capture the last frame. Snapzy will save the current stitched result.",
      comment: "Status shown when the final scrolling capture frame cannot be captured"
    )
    static let unableToCaptureArea = string(
      "scrolling-capture-status.unable-to-capture-area",
      defaultValue: "Unable to capture the selected area.",
      comment: "Status shown when the selected scrolling capture area cannot be captured"
    )
    static let couldntRefreshLastFrame = string(
      "scrolling-capture-status.couldnt-refresh-last-frame",
      defaultValue: "Couldn't refresh the last frame. Snapzy will save the current stitched result.",
      comment: "Status shown when the final scrolling capture refresh fails"
    )
    static let unableToRenderPreview = string(
      "scrolling-capture-status.unable-to-render-preview",
      defaultValue: "Unable to render the stitched preview.",
      comment: "Status shown when the scrolling capture preview cannot be rendered"
    )
    static let firstFrameLocked = string(
      "scrolling-capture-status.first-frame-locked",
      defaultValue: "First frame locked. Keep the pointer over the highlighted region and scroll downward steadily.",
      comment: "Status shown after the first scrolling capture frame is locked"
    )
    static func sessionActive(_ frameCount: Int, _ outputHeight: Int) -> String {
      format(
        "scrolling-capture-status.session-active",
        defaultValue: "Session active. %d frames stitched into %d px.",
        comment: "Status shown while a scrolling capture session is actively stitching frames. First %d is the frame count, second %d is the output height in pixels.",
        frameCount,
        outputHeight
      )
    }
    static let endReachedNoNewContent = string(
      "scrolling-capture-status.end-reached-no-new-content",
      defaultValue: "No new content detected. You're probably at the end of the scrollable content. Press Done to save.",
      comment: "Status shown when the end of scrollable content is likely reached"
    )
    static let waitingForNewContent = string(
      "scrolling-capture-status.waiting-for-new-content",
      defaultValue: "Waiting for new content. Keep the scroll moving in one direction.",
      comment: "Status shown while waiting for the next scrollable content to appear"
    )
    static let alignmentPaused = string(
      "scrolling-capture-status.alignment-paused",
      defaultValue: "Alignment paused. Slow down and keep one direction so Snapzy can recover.",
      comment: "Status shown when scrolling capture pauses to recover alignment"
    )
    static let couldntAlignFrame = string(
      "scrolling-capture-status.couldnt-align-frame",
      defaultValue: "Couldn't align that frame. Keep the same direction and a steadier pace.",
      comment: "Status shown when a scrolling capture frame cannot be aligned"
    )
    static func heightLimitReached(_ maxHeight: Int) -> String {
      format(
        "scrolling-capture-status.height-limit-reached",
        defaultValue: "Reached the %d px output limit. Press Done to save the current result.",
        comment: "Status shown when a scrolling capture reaches the output height limit. %d is the maximum output height in pixels.",
        maxHeight
      )
    }
    static let previewRefreshFailed = string(
      "scrolling-capture-status.preview-refresh-failed",
      defaultValue: "Preview refresh failed. You can Cancel and try again.",
      comment: "Status shown when a scrolling capture preview refresh fails"
    )
    static let finalizingCurrentCapture = string(
      "scrolling-capture-status.finalizing-current-capture",
      defaultValue: "Finalizing the current capture. Snapzy is locking the latest stitched result before saving.",
      comment: "Status shown when the scrolling capture result is being finalized"
    )
    static func finalizingFrames(_ count: Int) -> String {
      format(
        "scrolling-capture-status.finalizing-frames",
        defaultValue: "Locking the current capture. Snapzy is sealing %d stitched frames before saving.",
        comment: "Status shown while finalizing a scrolling capture with stitched frames. %d is the number of stitched frames.",
        count
      )
    }
    static let finalizingNoNewContent = string(
      "scrolling-capture-status.finalizing-no-new-content",
      defaultValue: "No new content was detected. Snapzy is saving the current stitched result.",
      comment: "Status shown while finalizing a scrolling capture after reaching the end of content"
    )
    static let finalizingCouldntAlignLastFrame = string(
      "scrolling-capture-status.finalizing-couldnt-align-last-frame",
      defaultValue: "Couldn't align the last frame cleanly. Snapzy will save the current stitched result.",
      comment: "Status shown while finalizing when the last frame could not be aligned"
    )
    static let finalizingHeightLimitReached = string(
      "scrolling-capture-status.finalizing-height-limit-reached",
      defaultValue: "Height limit reached. Snapzy is saving the current stitched result.",
      comment: "Status shown while finalizing after the scrolling capture reaches the height limit"
    )
    static let readyHintToast = string(
      "scrolling-capture-status.ready-hint-toast",
      defaultValue: "Select only the moving content, press Start Capture, then keep scrolling in one direction at a steady pace.",
      comment: "Toast shown when a scrolling capture session first appears"
    )
  }

  enum AppIdentity {
    static func unexpectedBundleIdentifier(_ currentIdentifier: String) -> String {
      format(
        "app-identity.unexpected-bundle-id",
        defaultValue: "Expected bundle ID %@, found %@.",
        comment: "Identity issue message. First %@ is expected bundle identifier. Second %@ is current bundle identifier.",
        AppBundleIdentity.expected,
        currentIdentifier
      )
    }

    static let invalidSignature = string(
      "app-identity.invalid-signature",
      defaultValue: "This app bundle does not pass macOS code-signature validation.",
      comment: "Identity issue message when bundle signature validation fails"
    )

    static func outsideApplications(_ bundlePath: String) -> String {
      format(
        "app-identity.outside-applications",
        defaultValue: "Install Snapzy in /Applications before granting permissions. Current path: %@",
        comment: "Identity issue message. %@ is the current app bundle path.",
        bundlePath
      )
    }

    static let quarantined = string(
      "app-identity.quarantined",
      defaultValue: "This app still has the macOS quarantine flag. Reinstall with the installer script or remove quarantine before granting permissions.",
      comment: "Identity issue message when app is quarantined"
    )

    static let healthy = string(
      "app-identity.healthy",
      defaultValue: "App identity is healthy.",
      comment: "Identity summary when no issues exist"
    )
  }

  enum PreferencesHistory {
    static let floatingPanelSection = string(
      "preferences-history.floating-panel-section",
      defaultValue: "Floating Panel",
      comment: "History settings section title for floating panel"
    )
    static let floatingPanelTitle = string(
      "preferences-history.floating-panel-title",
      defaultValue: "Enable Floating Panel",
      comment: "History settings toggle for floating panel"
    )
    static let floatingPanelDescription = string(
      "preferences-history.floating-panel-description",
      defaultValue: "Show a floating panel for quick access to recent captures",
      comment: "History settings description for floating panel"
    )
    static let panelPositionTitle = string(
      "preferences-history.panel-position-title",
      defaultValue: "Panel Position",
      comment: "History settings title for panel position"
    )
    static let panelPositionDescription = string(
      "preferences-history.panel-position-description",
      defaultValue: "Choose where the floating panel appears on screen",
      comment: "History settings description for panel position"
    )
    static let displaySection = string(
      "preferences-history.display-section",
      defaultValue: "Display",
      comment: "History settings section title for display options"
    )
    static let backgroundStyleTitle = string(
      "preferences-history.background-style-title",
      defaultValue: "Background Style",
      comment: "History settings title for choosing the History background style"
    )
    static let backgroundStyleDescription = string(
      "preferences-history.background-style-description",
      defaultValue: "Applies to the History window and floating panel",
      comment: "History settings description for choosing the History background style"
    )
    static let defaultFilterTitle = string(
      "preferences-history.default-filter-title",
      defaultValue: "Default Filter",
      comment: "History settings title for default filter"
    )
    static let defaultFilterDescription = string(
      "preferences-history.default-filter-description",
      defaultValue: "Filter shown when opening the floating panel",
      comment: "History settings description for default filter"
    )
    static let defaultFilterAll = string(
      "preferences-history.default-filter-all",
      defaultValue: "All",
      comment: "History settings default filter option for all capture types"
    )
    static let defaultFilterScreenshots = string(
      "preferences-history.default-filter-screenshots",
      defaultValue: "Screenshots",
      comment: "History settings default filter option for screenshots"
    )
    static let defaultFilterVideos = string(
      "preferences-history.default-filter-videos",
      defaultValue: "Videos",
      comment: "History settings default filter option for videos"
    )
    static let defaultFilterGifs = string(
      "preferences-history.default-filter-gifs",
      defaultValue: "GIFs",
      comment: "History settings default filter option for GIFs"
    )
    static let maxItemsTitle = string(
      "preferences-history.max-items-title",
      defaultValue: "Max Displayed Items",
      comment: "History settings title for max displayed items"
    )
    static let panelSizeTitle = string(
      "preferences-history.panel-size-title",
      defaultValue: "Panel Size",
      comment: "History settings title for floating panel size"
    )
    static let panelSizeDescription = string(
      "preferences-history.panel-size-description",
      defaultValue: "Resize the floating panel and its preview cards",
      comment: "History settings description for floating panel size"
    )
    static let panelSizeSmall = string(
      "preferences-history.panel-size-small",
      defaultValue: "S",
      comment: "History settings short label for the small end of the panel size slider"
    )
    static let panelSizeLarge = string(
      "preferences-history.panel-size-large",
      defaultValue: "L",
      comment: "History settings short label for the large end of the panel size slider"
    )
    static let maxItemsDescription = string(
      "preferences-history.max-items-description",
      defaultValue: "Maximum number of items shown in the floating panel",
      comment: "History settings description for max displayed items"
    )
    static let retentionSection = string(
      "preferences-history.retention-section",
      defaultValue: "Retention",
      comment: "History settings section title for retention"
    )
    static let retentionDaysTitle = string(
      "preferences-history.retention-days-title",
      defaultValue: "Auto-Clear After",
      comment: "History settings title for retention days"
    )
    static func deleteAfterDays(_ days: Int) -> String {
      format(
        "preferences-history.delete-after-days",
        defaultValue: "Delete captures older than %d days",
        comment: "History settings description for retention days. %d is the number of days.",
        days
      )
    }
    static let keepForever = string(
      "preferences-history.keep-forever",
      defaultValue: "Keep captures forever",
      comment: "History settings description when retention is disabled"
    )
    static let maxCountTitle = string(
      "preferences-history.max-count-title",
      defaultValue: "Max Stored Items",
      comment: "History settings title for max stored items"
    )
    static let maxCountDescription = string(
      "preferences-history.max-count-description",
      defaultValue: "Maximum number of captures stored in history",
      comment: "History settings description for max stored items"
    )
    static let storageSection = string(
      "preferences-history.storage-section",
      defaultValue: "Storage",
      comment: "History settings section title for storage"
    )
    static let captureStorageTitle = string(
      "preferences-history.capture-storage-title",
      defaultValue: "Capture Storage",
      comment: "History settings title for local capture storage"
    )
    static let openCaptureStorageButton = string(
      "preferences-history.open-capture-storage-button",
      defaultValue: "Open Folder",
      comment: "History settings button for opening local capture storage in Finder"
    )
    static let clearHistoryTitle = string(
      "preferences-history.clear-history-title",
      defaultValue: "Clear All History",
      comment: "History settings title for clearing history"
    )
    static let clearHistoryDescription = string(
      "preferences-history.clear-history-description",
      defaultValue: "Move all captures to Trash and clear History",
      comment: "History settings description for clearing history"
    )
    static let clearHistoryButton = string(
      "preferences-history.clear-history-button",
      defaultValue: "Clear History",
      comment: "History settings button for clearing history"
    )
    static let clearHistoryAlertTitle = string(
      "preferences-history.clear-history-alert-title",
      defaultValue: "Clear All History?",
      comment: "Alert title when clearing history"
    )
    static let clearHistoryAlertMessage = string(
      "preferences-history.clear-history-alert-message",
      defaultValue: "This will move all capture files to Trash and remove them from History. This action cannot be undone in Snapzy.",
      comment: "Alert message when clearing history"
    )
    static let clearHistoryConfirm = string(
      "preferences-history.clear-history-confirm",
      defaultValue: "Clear",
      comment: "Confirm button for clearing history"
    )
    static func selectedCaptures(_ count: Int) -> String {
      format(
        "preferences-history.selected-captures",
        defaultValue: "%d selected",
        comment: "History browser selection count label. %d is the number of selected captures.",
        count
      )
    }
    static let selectAll = string(
      "preferences-history.select-all",
      defaultValue: "Select All",
      comment: "Button title for selecting all visible history captures"
    )
    static let clearSelection = string(
      "preferences-history.clear-selection",
      defaultValue: "Clear",
      comment: "Button title for clearing selected history captures"
    )
    static let deleteSelectedAlertTitle = string(
      "preferences-history.delete-selected-alert-title",
      defaultValue: "Delete Selected Captures?",
      comment: "Alert title when deleting selected capture history items"
    )
    static func deleteSelectedAlertMessage(_ count: Int) -> String {
      format(
        "preferences-history.delete-selected-alert-message",
        defaultValue: "Move %d selected capture item(s) to Trash and remove them from History.",
        comment: "Alert message when deleting selected capture history items. %d is the number of selected captures.",
        count
      )
    }
    static func deletedCaptures(_ count: Int) -> String {
      format(
        "preferences-history.deleted-captures",
        defaultValue: "Deleted %d capture item(s)",
        comment: "Toast shown after deleting capture history items. %d is the number of deleted captures.",
        count
      )
    }
  }

  enum HistoryPanelPosition {
    static let topCenter = string(
      "history-panel-position.top-center",
      defaultValue: "Top Center",
      comment: "History panel position option"
    )
    static let bottomCenter = string(
      "history-panel-position.bottom-center",
      defaultValue: "Bottom Center",
      comment: "History panel position option"
    )
    static let center = string(
      "history-panel-position.center",
      defaultValue: "Center",
      comment: "History panel position option"
    )
  }

  enum HistoryBackgroundStyle {
    static let hud = string(
      "history-background-style.hud",
      defaultValue: "HUD",
      comment: "History background style option"
    )
    static let solid = string(
      "history-background-style.solid",
      defaultValue: "Solid",
      comment: "History background style option"
    )
    static let glass = string(
      "history-background-style.glass",
      defaultValue: "Glass",
      comment: "History background style option"
    )
    static let gradient = string(
      "history-background-style.gradient",
      defaultValue: "Gradient",
      comment: "History background style option"
    )
  }
}
