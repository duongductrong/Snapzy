//
//  SnapzyConfigurationImporter.swift
//  Snapzy
//
//  Applies validated TOML config to Snapzy stores.
//

import AppKit
import Foundation
import Sparkle

@MainActor
enum SnapzyConfigurationImporter {
  private struct PreparedImport {
    let issues: [SnapzyConfigurationIssue]
    let mutations: [() -> Void]
  }

  static func validateTOML(_ source: String, defaults: UserDefaults = .standard) -> [SnapzyConfigurationIssue] {
    prepareImport(source, defaults: defaults).issues
  }

  static func importTOML(_ source: String, defaults: UserDefaults = .standard) -> SnapzyConfigurationImportResult {
    let preparedImport = prepareImport(source, defaults: defaults)

    guard !preparedImport.issues.contains(where: { $0.severity == .error }) else {
      return SnapzyConfigurationImportResult(appliedChangeCount: 0, issues: preparedImport.issues)
    }

    preparedImport.mutations.forEach { $0() }
    KeyboardShortcutManager.shared.refreshShortcutRegistration()
    CloudManager.shared.reloadStateFromDefaults()
    defaults.synchronize()

    return SnapzyConfigurationImportResult(
      appliedChangeCount: preparedImport.mutations.count,
      issues: preparedImport.issues
    )
  }

  private static func prepareImport(_ source: String, defaults: UserDefaults) -> PreparedImport {
    let document: SimpleTOMLDocument
    do {
      document = try SimpleTOMLParser.parse(source)
    } catch {
      return PreparedImport(
        issues: [SnapzyConfigurationIssue(severity: .error, message: error.localizedDescription)],
        mutations: []
      )
    }

    var reader = SnapzyConfigurationReader(document: document)
    var mutations: [() -> Void] = []

    validateSchema(&reader)
    collectGeneral(&reader, defaults: defaults, mutations: &mutations)
    collectMenuBar(&reader, mutations: &mutations)
    collectCapture(&reader, defaults: defaults, mutations: &mutations)
    collectRecording(&reader, defaults: defaults, mutations: &mutations)
    collectQuickAccess(&reader, mutations: &mutations)
    collectHistory(&reader, defaults: defaults, mutations: &mutations)
    collectCloud(&reader, defaults: defaults, mutations: &mutations)
    collectAnnotate(&reader, defaults: defaults, mutations: &mutations)
    collectShortcuts(&reader, mutations: &mutations)

    return PreparedImport(issues: reader.issues, mutations: mutations)
  }

  private static func validateSchema(_ reader: inout SnapzyConfigurationReader) {
    guard let schemaVersion = reader.int("schema_version") else { return }
    if schemaVersion != 1 {
      reader.error("Unsupported schema_version \(schemaVersion). Snapzy currently supports schema_version 1.")
    }
  }

  private static func collectGeneral(
    _ reader: inout SnapzyConfigurationReader,
    defaults: UserDefaults,
    mutations: inout [() -> Void]
  ) {
    if let language = reader.string("general", "language") {
      let normalized = language == "system" ? "" : AppLanguageManager.normalizedLanguageIdentifier(from: language)
      if normalized == nil, language != "system" {
        reader.error("general.language must be system or a supported language identifier")
      } else {
        mutations.append { AppLanguageManager.shared.selectLanguage(normalized ?? "") }
      }
    }
    if let appearance = reader.string("general", "appearance") {
      guard let mode = appearanceMode(from: appearance) else {
        reader.error("general.appearance must be system, light, or dark")
        return
      }
      mutations.append { ThemeManager.shared.preferredAppearance = mode }
    }
    collectBool(&reader, "general", "play_sounds", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.playSounds)
    }
    collectBool(&reader, "general", "url_scheme_enabled", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.urlSchemeEnabled)
    }
    collectBool(&reader, "general", "show_menu_bar_icon", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.showMenuBarIcon)
      if defaults == UserDefaults.standard {
        AppStatusBarController.shared.setMenuBarIconVisible($0)
      }
    }
    if let startAtLogin = reader.bool("general", "start_at_login") {
      mutations.append { LoginItemManager.setEnabled(startAtLogin) }
    }
    if let exportLocation = reader.string("general", "export_location") {
      mutations.append { defaults.set(expandedPath(exportLocation), forKey: PreferencesKeys.exportLocation) }
    }
    collectBool(&reader, "updates", "check_automatically", mutations: &mutations) {
      UpdaterManager.shared.updater.automaticallyChecksForUpdates = $0
    }
    collectBool(&reader, "updates", "download_automatically", mutations: &mutations) {
      UpdaterManager.shared.updater.automaticallyDownloadsUpdates = $0
    }
    collectEnumString(&reader, "updates", "channel", allowed: UpdateChannel.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.updateChannel)
    }
    collectBool(&reader, "diagnostics", "enabled", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.diagnosticsEnabled)
    }
    collectInt(&reader, "diagnostics", "retention_days", range: LogCleanupScheduler.retentionDaysRange, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.diagnosticsRetentionDays)
    }
  }

  private static func collectMenuBar(
    _ reader: inout SnapzyConfigurationReader,
    mutations: inout [() -> Void]
  ) {
    if let iconStyleStr = reader.string("menu_bar", "icon_style") {
      guard let style = MenuBarIconStyle(rawValue: iconStyleStr) else {
        reader.error("menu_bar.icon_style is invalid")
        return
      }
      mutations.append {
        // The custom PNG file is not portable across machines; fall back to
        // the bundled default when no custom icon exists locally.
        let resolved = (style == .custom && !MenuBarIconRenderer.shared.hasCustomIcon) ? .default : style
        MenuBarCustomizationStore.shared.setIconStyle(resolved)
      }
    }

    let order = reader.stringArray("menu_bar", "item_order")?.compactMap(MenuBarItemKind.init(rawValue:))
    let hidden = reader.stringArray("menu_bar", "hidden_items")?.compactMap(MenuBarItemKind.init(rawValue:))
    if order != nil || hidden != nil {
      mutations.append {
        MenuBarCustomizationStore.shared.applyConfiguration(
          order: order,
          hiddenItems: hidden.map(Set.init),
          iconStyle: nil
        )
      }
    }
  }

  private static func collectCapture(
    _ reader: inout SnapzyConfigurationReader,
    defaults: UserDefaults,
    mutations: inout [() -> Void]
  ) {
    collectBool(&reader, "capture", "hide_desktop_icons", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.hideDesktopIcons)
    }
    collectBool(&reader, "capture", "hide_desktop_widgets", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.hideDesktopWidgets)
    }
    collectString(&reader, "capture", "naming", "screenshot_template", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.screenshotFileNameTemplate)
    }
    collectString(&reader, "capture", "naming", "recording_template", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingFileNameTemplate)
    }
    if let format = reader.string("capture", "screenshot", "format") {
      guard ImageFormatOption(rawValue: format) != nil else {
        reader.error("capture.screenshot.format must be png, jpeg, or webp")
        return
      }
      mutations.append { defaults.set(format, forKey: PreferencesKeys.screenshotFormat) }
    }
    collectBool(&reader, "capture", "screenshot", "include_snapzy", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.screenshotIncludeOwnApp)
    }
    collectBool(&reader, "capture", "screenshot", "show_cursor", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.screenshotShowCursor)
    }
    collectBool(&reader, "capture", "screenshot", "freeze_area", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.screenshotFreezeArea)
    }
    collectBool(&reader, "capture", "screenshot", "show_selection_area_overlay", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay)
    }
    collectBool(&reader, "capture", "screenshot", "reverse_magnifier_zoom_direction", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.screenshotReverseMagnifierZoomDirection)
    }
    collectBool(&reader, "capture", "scrolling", "show_hints", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.scrollingCaptureShowHints)
    }
    collectBool(&reader, "capture", "ocr", "success_notification", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.ocrSuccessNotificationEnabled)
    }
    collectBool(&reader, "capture", "object_cutout", "auto_crop", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.backgroundCutoutAutoCropEnabled)
    }
    collectAfterCapture(&reader, type: .screenshot, mutations: &mutations)
    collectAfterCapture(&reader, type: .recording, mutations: &mutations)
  }

  private static func collectRecording(
    _ reader: inout SnapzyConfigurationReader,
    defaults: UserDefaults,
    mutations: inout [() -> Void]
  ) {
    collectEnumString(&reader, "recording", "format", allowed: VideoFormat.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingFormat)
    }
    collectEnumString(&reader, "recording", "quality", allowed: VideoQuality.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingQuality)
    }
    collectInt(&reader, "recording", "fps", range: 1...120, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingFPS)
    }
    collectEnumString(&reader, "recording", "output_mode", allowed: RecordingOutputMode.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingOutputMode)
    }
    collectBool(&reader, "recording", "capture_system_audio", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingCaptureAudio)
    }
    collectBool(&reader, "recording", "capture_microphone", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingCaptureMicrophone)
    }
    collectString(&reader, "recording", "microphone_device_id", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingMicrophoneDeviceID)
    }
    collectBool(&reader, "recording", "remember_last_area", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingRememberLastArea)
    }
    collectBool(&reader, "recording", "include_snapzy", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingIncludeOwnApp)
    }
    collectBool(&reader, "recording", "show_cursor", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingShowCursor)
    }
    collectBool(&reader, "recording", "dim_non_selected_area", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingDimNonSelectedArea)
    }
    collectBool(&reader, "recording", "highlight_clicks", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingHighlightClicks)
    }
    collectBool(&reader, "recording", "show_keystrokes", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.recordingShowKeystrokes)
    }
    collectDouble(&reader, "recording", "mouse_highlight", "size", range: 20...120, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.mouseHighlightSize)
    }
    collectDouble(&reader, "recording", "mouse_highlight", "animation_duration", range: 0.1...3, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.mouseHighlightAnimationDuration)
    }
    if let colorHex = reader.string("recording", "mouse_highlight", "color") {
      guard let color = SnapzyConfigurationColor.color(from: colorHex),
            let data = try? NSKeyedArchiver.archivedData(
              withRootObject: color,
              requiringSecureCoding: false
            ) else {
        reader.error("recording.mouse_highlight.color must be #RRGGBB or #RRGGBBAA")
        return
      }
      mutations.append { defaults.set(data, forKey: PreferencesKeys.mouseHighlightColor) }
    }
    collectDouble(&reader, "recording", "mouse_highlight", "opacity", range: 0...1, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.mouseHighlightOpacity)
    }
    collectInt(&reader, "recording", "mouse_highlight", "ripple_count", range: 1...6, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.mouseHighlightRippleCount)
    }
    collectDouble(&reader, "recording", "keystrokes", "font_size", range: 10...48, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.keystrokeFontSize)
    }
    collectEnumString(&reader, "recording", "keystrokes", "position", allowed: KeystrokeOverlayPosition.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.keystrokePosition)
    }
    collectDouble(&reader, "recording", "keystrokes", "display_duration", range: 0.3...10, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.keystrokeDisplayDuration)
    }
    collectEnumString(&reader, "recording", "annotation_shortcuts", "modifier", allowed: AnnotationShortcutModifier.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotationShortcutModifier)
      RecordingAnnotationShortcutConfig.shared.modifier = AnnotationShortcutModifier(rawValue: $0) ?? .shift
    }
    collectDouble(&reader, "recording", "annotation_shortcuts", "hold_duration", range: 0.1...5, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotationShortcutHoldDuration)
      RecordingAnnotationShortcutConfig.shared.holdDuration = $0
    }
    collectDouble(&reader, "recording", "video_editor_zoom_transition_duration", range: 0.15...0.75, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.videoEditorZoomTransitionDuration)
    }
  }

  private static func collectQuickAccess(
    _ reader: inout SnapzyConfigurationReader,
    mutations: inout [() -> Void]
  ) {
    let manager = QuickAccessManager.shared
    collectBool(&reader, "quick_access", "enabled", mutations: &mutations) { manager.isEnabled = $0 }
    if let position = reader.string("quick_access", "position") {
      guard let value = QuickAccessPosition(rawValue: position) else {
        reader.error("quick_access.position is invalid")
        return
      }
      mutations.append { manager.position = value }
    }
    collectBool(&reader, "quick_access", "auto_dismiss", mutations: &mutations) { manager.autoDismissEnabled = $0 }
    collectDouble(&reader, "quick_access", "auto_dismiss_delay", range: 3...30, mutations: &mutations) { manager.autoDismissDelay = $0 }
    collectBool(&reader, "quick_access", "pause_countdown_on_hover", mutations: &mutations) { manager.pauseCountdownOnHover = $0 }
    collectDouble(&reader, "quick_access", "overlay_scale", range: 0.75...1.5, mutations: &mutations) { manager.overlayScale = $0 }
    collectBool(&reader, "quick_access", "drag_drop", mutations: &mutations) { manager.dragDropEnabled = $0 }
    collectBool(&reader, "quick_access", "two_finger_swipe_to_dismiss", mutations: &mutations) { manager.twoFingerSwipeToDismissEnabled = $0 }
    collectDouble(&reader, "quick_access", "swipe_sensitivity", range: 0.5...3.0, mutations: &mutations) { manager.swipeSensitivity = $0 }

    if let swipeModeStr = reader.string("quick_access", "trackpad_swipe_mode") {
      guard let mode = QuickAccessTrackpadSwipeMode(rawValue: swipeModeStr) else {
        reader.error("quick_access.trackpad_swipe_mode must be natural or inverted")
        return
      }
      mutations.append {
        QuickAccessTrackpadSwipeModeStore.shared.setMode(mode)
      }
    }

    if let actionStr = reader.string("quick_access", "swipe_left_action") {
      if actionStr == "none" {
        mutations.append {
          QuickAccessSwipeActionStore.shared.setAction(.left, action: nil)
        }
      } else if let action = QuickAccessActionKind(rawValue: actionStr) {
        mutations.append {
          QuickAccessSwipeActionStore.shared.setAction(.left, action: action)
        }
      } else {
        reader.error("quick_access.swipe_left_action is invalid")
      }
    }

    if let actionStr = reader.string("quick_access", "swipe_right_action") {
      if actionStr == "none" {
        mutations.append {
          QuickAccessSwipeActionStore.shared.setAction(.right, action: nil)
        }
      } else if let action = QuickAccessActionKind(rawValue: actionStr) {
        mutations.append {
          QuickAccessSwipeActionStore.shared.setAction(.right, action: action)
        }
      } else {
        reader.error("quick_access.swipe_right_action is invalid")
      }
    }

    collectBool(&reader, "quick_access", "hide_card_when_window_open", mutations: &mutations) {
      manager.hideCardWhenWindowOpen = $0
    }

    if let styleStr = reader.string("quick_access", "animation_style") {
      guard let style = QuickAccessAnimationStyle(rawValue: styleStr) else {
        reader.error("quick_access.animation_style must be slide or scale")
        return
      }
      mutations.append {
        manager.animationStyle = style
      }
    }

    let order = reader.stringArray("quick_access", "actions_order")?.compactMap(QuickAccessActionKind.init(rawValue:))
    let enabled = reader.stringArray("quick_access", "enabled_actions")?.compactMap(QuickAccessActionKind.init(rawValue:))
    let slots = quickAccessSlots(from: &reader)
    if order != nil || enabled != nil || slots != nil {
      mutations.append {
        QuickAccessActionConfigurationStore.shared.applyConfiguration(
          order: order,
          enabledActions: enabled.map(Set.init),
          slotAssignments: slots
        )
      }
    }
  }

  private static func collectHistory(
    _ reader: inout SnapzyConfigurationReader,
    defaults: UserDefaults,
    mutations: inout [() -> Void]
  ) {
    collectBool(&reader, "history", "enabled", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.historyEnabled)
    }
    collectInt(&reader, "history", "retention_days", range: 0...90, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.historyRetentionDays)
    }
    collectInt(&reader, "history", "max_count", range: 0...1000, mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.historyMaxCount)
    }
    collectEnumString(&reader, "history", "background_style", allowed: HistoryBackgroundStyle.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.historyBackgroundStyle)
    }
    collectBool(&reader, "history", "open_on_launch", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.historyOpenOnLaunch)
    }

    let manager = HistoryFloatingManager.shared
    collectBool(&reader, "history", "floating", "enabled", mutations: &mutations) { manager.isEnabled = $0 }
    collectEnumString(&reader, "history", "floating", "position", allowed: ["topCenter", "bottomCenter", "center"], mutations: &mutations) {
      manager.position = HistoryPanelPosition(rawValue: $0) ?? .topCenter
    }
    if let filter = reader.string("history", "floating", "default_filter") {
      let value = filter == "all" ? nil : CaptureHistoryType(rawValue: filter)
      if value == nil, filter != "all" {
        reader.error("history.floating.default_filter is invalid")
      } else {
        mutations.append { manager.defaultFilter = value }
      }
    }
    collectInt(&reader, "history", "floating", "max_displayed_items", range: 3...20, mutations: &mutations) {
      manager.maxDisplayedItems = $0
    }
    collectDouble(&reader, "history", "floating", "scale", range: HistoryFloatingLayout.scaleRange, mutations: &mutations) {
      manager.panelScale = $0
    }
    collectInt(&reader, "history", "floating", "auto_clear_days", range: 0...365, mutations: &mutations) {
      manager.autoClearDays = $0
    }
  }

  private static func collectCloud(
    _ reader: inout SnapzyConfigurationReader,
    defaults: UserDefaults,
    mutations: inout [() -> Void]
  ) {
    collectEnumString(&reader, "cloud", "provider", allowed: CloudProviderType.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudProviderType)
    }
    collectString(&reader, "cloud", "bucket", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudBucket)
    }
    collectString(&reader, "cloud", "folder_name", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudBucket)
    }
    collectString(&reader, "cloud", "region", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudRegion)
    }
    collectString(&reader, "cloud", "endpoint", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudEndpoint)
    }
    collectString(&reader, "cloud", "custom_domain", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudCustomDomain)
    }
    collectEnumString(&reader, "cloud", "expire_time", allowed: CloudExpireTime.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudExpireTime)
    }
    collectEnumString(&reader, "cloud", "uploads_window_position", allowed: CloudUploadFloatingPosition.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.cloudUploadsFloatingPosition)
    }
  }

  private static func collectAnnotate(
    _ reader: inout SnapzyConfigurationReader,
    defaults: UserDefaults,
    mutations: inout [() -> Void]
  ) {
    collectEnumString(&reader, "annotate", "clipboard_image_open_behavior", allowed: AnnotateClipboardImageBehavior.allCases.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateClipboardImageOpenBehavior)
    }
    collectEnumString(&reader, "annotate", "default_tool", allowed: AnnotationToolType.inlineAnnotateTools.map(\.rawValue), mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateDefaultTool)
    }
    collectBool(&reader, "annotate", "remember_last_tool", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateRememberLastTool)
    }
    collectBool(&reader, "annotate", "close_after_drag", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateCloseAfterDrag)
    }
    collectBool(&reader, "annotate", "bring_forward_after_drag", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateBringForwardAfterDrag)
    }
    collectBool(&reader, "annotate", "quick_properties_sync", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    }
    collectBool(&reader, "annotate", "combine_save_as_edit", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateCombineSaveAsEdit)
    }
    collectBool(&reader, "annotate", "crop_snap_to_edges", mutations: &mutations) {
      defaults.set($0, forKey: PreferencesKeys.annotateCropSnapToEdgesEnabled)
    }
  }

  private static func collectAfterCapture(
    _ reader: inout SnapzyConfigurationReader,
    type: CaptureType,
    mutations: inout [() -> Void]
  ) {
    let mapping: [(String, AfterCaptureAction)] = [
      ("save", .save),
      ("quick_access", .showQuickAccess),
      ("copy_file", .copyFile),
      ("open_annotate", .openAnnotate),
    ]

    for (key, action) in mapping {
      collectBool(&reader, "capture", "after", type.rawValue, key, mutations: &mutations) {
        PreferencesManager.shared.setAction(action, for: type, enabled: $0)
      }
    }
  }

  private static func collectBool(
    _ reader: inout SnapzyConfigurationReader,
    _ path: String...,
    mutations: inout [() -> Void],
    apply: @escaping (Bool) -> Void
  ) {
    guard let value = reader.bool(path) else { return }
    mutations.append { apply(value) }
  }

  private static func collectString(
    _ reader: inout SnapzyConfigurationReader,
    _ path: String...,
    mutations: inout [() -> Void],
    apply: @escaping (String) -> Void
  ) {
    guard let value = reader.string(path) else { return }
    mutations.append { apply(value) }
  }

  private static func collectEnumString(
    _ reader: inout SnapzyConfigurationReader,
    _ path: String...,
    allowed: [String],
    mutations: inout [() -> Void],
    apply: @escaping (String) -> Void
  ) {
    guard let value = reader.string(path) else { return }
    guard allowed.contains(value) else {
      reader.error("\(path.joined(separator: ".")) must be one of: \(allowed.joined(separator: ", "))")
      return
    }
    mutations.append { apply(value) }
  }

  private static func collectInt(
    _ reader: inout SnapzyConfigurationReader,
    _ path: String...,
    range: ClosedRange<Int>,
    mutations: inout [() -> Void],
    apply: @escaping (Int) -> Void
  ) {
    guard let value = reader.int(path) else { return }
    guard range.contains(value) else {
      reader.error("\(path.joined(separator: ".")) must be in \(range.lowerBound)...\(range.upperBound)")
      return
    }
    mutations.append { apply(value) }
  }

  private static func collectDouble(
    _ reader: inout SnapzyConfigurationReader,
    _ path: String...,
    range: ClosedRange<Double>,
    mutations: inout [() -> Void],
    apply: @escaping (Double) -> Void
  ) {
    guard let value = reader.double(path) else { return }
    guard range.contains(value) else {
      reader.error("\(path.joined(separator: ".")) must be in \(range.lowerBound)...\(range.upperBound)")
      return
    }
    mutations.append { apply(value) }
  }

  private static func appearanceMode(from value: String) -> AppearanceMode? {
    switch value.lowercased() {
    case "system": return .system
    case "light": return .light
    case "dark": return .dark
    default: return AppearanceMode(rawValue: value)
    }
  }

  private static func expandedPath(_ path: String) -> String {
    SnapzyConfigurationPaths.expandedUserPath(path)
  }
}
