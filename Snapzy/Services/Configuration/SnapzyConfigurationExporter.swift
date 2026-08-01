//
//  SnapzyConfigurationExporter.swift
//  Snapzy
//
//  Builds deterministic TOML from current app configuration.
//

import AppKit
import Foundation
import Sparkle

@MainActor
enum SnapzyConfigurationExporter {
  static func exportTOML(defaults: UserDefaults = .standard) -> String {
    var writer = SimpleTOMLWriter()
    writer.root("schema_version", 1)
    writer.root("snapzy_min_version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.20.0")

    writeGeneral(&writer, defaults: defaults)
    writeMenuBar(&writer)
    writeCapture(&writer, defaults: defaults)
    writeRecording(&writer, defaults: defaults)
    writeQuickAccess(&writer)
    writeHistory(&writer, defaults: defaults)
    writeCloud(&writer, defaults: defaults)
    writeAnnotate(&writer, defaults: defaults)
    writeShortcuts(&writer)

    return writer.output
  }

  private static func writeGeneral(_ writer: inout SimpleTOMLWriter, defaults: UserDefaults) {
    writer.section("general")
    writer.value("language", language(defaults: defaults))
    writer.value("appearance", appearance(defaults: defaults))
    writer.value("play_sounds", defaults.object(forKey: PreferencesKeys.playSounds) as? Bool ?? true)
    writer.value("url_scheme_enabled", defaults.object(forKey: PreferencesKeys.urlSchemeEnabled) as? Bool ?? true)
    writer.value("show_menu_bar_icon", defaults.object(forKey: PreferencesKeys.showMenuBarIcon) as? Bool ?? true)
    writer.value("start_at_login", LoginItemManager.isEnabled)
    writer.value("export_location", SnapzyConfigurationPaths.collapsingHomePath(SandboxFileAccessManager.shared.exportLocationPath))

    writer.section("updates")
    let updater = UpdaterManager.shared.updater
    writer.value("check_automatically", updater.automaticallyChecksForUpdates)
    writer.value("download_automatically", updater.automaticallyDownloadsUpdates)
    writer.value("channel", UpdaterManager.channel.rawValue)

    writer.section("diagnostics")
    writer.value("enabled", defaults.object(forKey: PreferencesKeys.diagnosticsEnabled) as? Bool ?? true)
    writer.value(
      "retention_days",
      defaults.object(forKey: PreferencesKeys.diagnosticsRetentionDays) as? Int
        ?? LogCleanupScheduler.defaultRetentionDays
    )
  }

  private static func writeMenuBar(_ writer: inout SimpleTOMLWriter) {
    let store = MenuBarCustomizationStore.shared

    writer.section("menu_bar")
    writer.value("icon_style", store.iconStyle.rawValue)
    writer.stringArray("item_order", store.itemOrder.map(\.rawValue))
    writer.stringArray("hidden_items", store.hiddenItems.map(\.rawValue).sorted())
  }

  private static func writeCapture(_ writer: inout SimpleTOMLWriter, defaults: UserDefaults) {
    writer.section("capture")
    writer.value("hide_desktop_icons", defaults.boolValue(PreferencesKeys.hideDesktopIcons, default: false))
    writer.value("hide_desktop_widgets", defaults.boolValue(PreferencesKeys.hideDesktopWidgets, default: false))

    writer.section("capture.naming")
    writer.value("screenshot_template", CaptureOutputNaming.resolvedTemplate(for: .screenshot, defaults: defaults))
    writer.value("recording_template", CaptureOutputNaming.resolvedTemplate(for: .recording, defaults: defaults))

    writer.section("capture.screenshot")
    writer.value("format", defaults.string(forKey: PreferencesKeys.screenshotFormat) ?? ImageFormatOption.png.rawValue)
    writer.value("include_snapzy", defaults.boolValue(PreferencesKeys.screenshotIncludeOwnApp, default: false))
    writer.value("show_cursor", defaults.boolValue(PreferencesKeys.screenshotShowCursor, default: false))
    writer.value("freeze_area", defaults.boolValue(PreferencesKeys.screenshotFreezeArea, default: false))
    writer.value("show_selection_area_overlay", defaults.boolValue(PreferencesKeys.screenshotShowSelectionAreaOverlay, default: true))
    writer.value("reverse_magnifier_zoom_direction", defaults.boolValue(PreferencesKeys.screenshotReverseMagnifierZoomDirection, default: false))

    writer.section("capture.scrolling")
    writer.value("show_hints", defaults.boolValue(PreferencesKeys.scrollingCaptureShowHints, default: true))

    writer.section("capture.ocr")
    writer.value("success_notification", defaults.boolValue(PreferencesKeys.ocrSuccessNotificationEnabled, default: false))

    writer.section("capture.object_cutout")
    writer.value("auto_crop", defaults.boolValue(PreferencesKeys.backgroundCutoutAutoCropEnabled, default: true))

    writeAfterCapture(&writer, type: .screenshot)
    writeAfterCapture(&writer, type: .recording)
  }

  private static func writeRecording(_ writer: inout SimpleTOMLWriter, defaults: UserDefaults) {
    writer.section("recording")
    writer.value("format", RecordingToolbarPreferences.selectedFormat(defaults: defaults).rawValue)
    writer.value("quality", RecordingToolbarPreferences.selectedQuality(defaults: defaults).rawValue)
    writer.value("fps", defaults.integerValue(PreferencesKeys.recordingFPS, default: 30))
    writer.value("output_mode", RecordingToolbarPreferences.outputMode(defaults: defaults).rawValue)
    writer.value("capture_system_audio", RecordingToolbarPreferences.captureAudio(defaults: defaults))
    writer.value("capture_microphone", RecordingToolbarPreferences.captureMicrophone(defaults: defaults))
    writer.value("microphone_device_id", RecordingToolbarPreferences.microphoneDeviceID(defaults: defaults))
    writer.value("remember_last_area", defaults.boolValue(PreferencesKeys.recordingRememberLastArea, default: true))
    writer.value("include_snapzy", defaults.boolValue(PreferencesKeys.recordingIncludeOwnApp, default: false))
    writer.value("show_cursor", RecordingToolbarPreferences.showCursor(defaults: defaults))
    writer.value("dim_non_selected_area", RecordingToolbarPreferences.dimNonSelectedArea(defaults: defaults))
    writer.value("highlight_clicks", RecordingToolbarPreferences.highlightClicks(defaults: defaults))
    writer.value("show_keystrokes", RecordingToolbarPreferences.showKeystrokes(defaults: defaults))
    writer.value("video_editor_zoom_transition_duration", defaults.doubleValue(PreferencesKeys.videoEditorZoomTransitionDuration, default: 0.4))

    writer.section("recording.mouse_highlight")
    let color = storedMouseColor(defaults: defaults)
    writer.value("size", defaults.doubleValue(PreferencesKeys.mouseHighlightSize, default: 50))
    writer.value("animation_duration", defaults.doubleValue(PreferencesKeys.mouseHighlightAnimationDuration, default: 0.7))
    writer.value("color", SnapzyConfigurationColor.hexString(from: color))
    writer.value("opacity", defaults.doubleValue(PreferencesKeys.mouseHighlightOpacity, default: 0.5))
    writer.value("ripple_count", defaults.integerValue(PreferencesKeys.mouseHighlightRippleCount, default: 3))

    writer.section("recording.keystrokes")
    writer.value("font_size", defaults.doubleValue(PreferencesKeys.keystrokeFontSize, default: 16))
    writer.value("position", defaults.string(forKey: PreferencesKeys.keystrokePosition) ?? KeystrokeOverlayPosition.bottomCenter.rawValue)
    writer.value("display_duration", defaults.doubleValue(PreferencesKeys.keystrokeDisplayDuration, default: 1.5))

    writer.section("recording.annotation_shortcuts")
    writer.value(
      "modifier",
      defaults.string(forKey: PreferencesKeys.annotationShortcutModifier)
        ?? AnnotationShortcutModifier.shift.rawValue
    )
    writer.value("hold_duration", defaults.doubleValue(PreferencesKeys.annotationShortcutHoldDuration, default: 0.3))
  }

  private static func writeQuickAccess(_ writer: inout SimpleTOMLWriter) {
    let manager = QuickAccessManager.shared
    let actionStore = QuickAccessActionConfigurationStore.shared

    writer.section("quick_access")
    writer.value("enabled", manager.isEnabled)
    writer.value("position", manager.position.rawValue)
    writer.value("auto_dismiss", manager.autoDismissEnabled)
    writer.value("auto_dismiss_delay", manager.autoDismissDelay)
    writer.value("pause_countdown_on_hover", manager.pauseCountdownOnHover)
    writer.value("overlay_scale", manager.overlayScale)
    writer.value("drag_drop", manager.dragDropEnabled)
    writer.value("two_finger_swipe_to_dismiss", manager.twoFingerSwipeToDismissEnabled)
    writer.value("swipe_sensitivity", manager.swipeSensitivity)
    writer.value("trackpad_swipe_mode", QuickAccessTrackpadSwipeModeStore.shared.mode.rawValue)
    writer.value("swipe_left_action", QuickAccessSwipeActionStore.shared.swipeLeftAction?.rawValue ?? "none")
    writer.value("swipe_right_action", QuickAccessSwipeActionStore.shared.swipeRightAction?.rawValue ?? "none")
    writer.value("hide_card_when_window_open", manager.hideCardWhenWindowOpen)
    writer.value("animation_style", manager.animationStyle.rawValue)
    writer.stringArray("actions_order", actionStore.actionOrder.map(\.rawValue))
    writer.stringArray("enabled_actions", actionStore.enabledActions.map(\.rawValue).sorted())

    writer.section("quick_access.slots")
    for slot in QuickAccessActionSlot.allCases {
      writer.value(slot.configKey, actionStore.slotAssignments[slot]?.rawValue ?? "")
    }
  }

  private static func writeHistory(_ writer: inout SimpleTOMLWriter, defaults: UserDefaults) {
    let manager = HistoryFloatingManager.shared
    writer.section("history")
    writer.value("enabled", defaults.boolValue(PreferencesKeys.historyEnabled, default: true))
    writer.value("retention_days", defaults.integerValue(PreferencesKeys.historyRetentionDays, default: 30))
    writer.value("max_count", defaults.integerValue(PreferencesKeys.historyMaxCount, default: 500))
    writer.value("background_style", HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults).rawValue)
    writer.value("open_on_launch", defaults.boolValue(PreferencesKeys.historyOpenOnLaunch, default: false))

    writer.section("history.floating")
    writer.value("enabled", manager.isEnabled)
    writer.value("position", manager.position.rawValue)
    writer.value("default_filter", manager.defaultFilter?.rawValue ?? "all")
    writer.value("max_displayed_items", manager.maxDisplayedItems)
    writer.value("scale", manager.panelScale)
    writer.value("auto_clear_days", manager.autoClearDays)
  }

  private static func writeCloud(_ writer: inout SimpleTOMLWriter, defaults: UserDefaults) {
    writer.section("cloud")
    let providerRaw = defaults.string(forKey: PreferencesKeys.cloudProviderType) ?? CloudProviderType.awsS3.rawValue
    writer.value("provider", providerRaw)

    if providerRaw == CloudProviderType.googleDrive.rawValue {
      writer.value("folder_name", defaults.string(forKey: PreferencesKeys.cloudBucket) ?? "Snapzy")
    } else {
      writer.value("bucket", defaults.string(forKey: PreferencesKeys.cloudBucket) ?? "")
      writer.value("region", defaults.string(forKey: PreferencesKeys.cloudRegion) ?? "us-east-1")
      writer.value("endpoint", defaults.string(forKey: PreferencesKeys.cloudEndpoint) ?? "")
      writer.value("custom_domain", defaults.string(forKey: PreferencesKeys.cloudCustomDomain) ?? "")
      writer.value("expire_time", defaults.string(forKey: PreferencesKeys.cloudExpireTime) ?? CloudExpireTime.day7.rawValue)
    }
    writer.value("uploads_window_position", CloudUploadFloatingPosition.stored(userDefaults: defaults).rawValue)
  }

  private static func writeAnnotate(_ writer: inout SimpleTOMLWriter, defaults: UserDefaults) {
    writer.section("annotate")
    writer.value("clipboard_image_open_behavior", AnnotateClipboardImageBehavior.stored(userDefaults: defaults).rawValue)
    writer.value("default_tool", AnnotateToolPreference.defaultTool(userDefaults: defaults).rawValue)
    writer.value("remember_last_tool", AnnotateToolPreference.remembersLastTool(userDefaults: defaults))
    writer.value("close_after_drag", defaults.boolValue(PreferencesKeys.annotateCloseAfterDrag, default: true))
    writer.value("bring_forward_after_drag", defaults.boolValue(PreferencesKeys.annotateBringForwardAfterDrag, default: false))
    writer.value("quick_properties_sync", AnnotateQuickPropertiesSyncPreference.isEnabled(userDefaults: defaults))
    writer.value("combine_save_as_edit", CombineSaveAsEditPreference.isEnabled(userDefaults: defaults))
    writer.value("crop_snap_to_edges", defaults.boolValue(PreferencesKeys.annotateCropSnapToEdgesEnabled, default: true))
  }

  private static func language(defaults: UserDefaults) -> String {
    guard
      let languages = defaults.array(forKey: "AppleLanguages") as? [String],
      let first = languages.first,
      let normalized = AppLanguageManager.normalizedLanguageIdentifier(from: first)
    else {
      return "system"
    }
    return normalized
  }

  private static func appearance(defaults: UserDefaults) -> String {
    switch defaults.string(forKey: PreferencesKeys.appearanceMode) {
    case AppearanceMode.light.rawValue: return "light"
    case AppearanceMode.dark.rawValue: return "dark"
    default: return "system"
    }
  }

  private static func writeAfterCapture(_ writer: inout SimpleTOMLWriter, type: CaptureType) {
    writer.section("capture.after.\(type.rawValue)")
    let manager = PreferencesManager.shared
    writer.value("save", manager.isActionEnabled(.save, for: type))
    writer.value("quick_access", manager.isActionEnabled(.showQuickAccess, for: type))
    writer.value("copy_file", manager.isActionEnabled(.copyFile, for: type))
    writer.value("open_annotate", manager.isActionEnabled(.openAnnotate, for: type))
  }

  private static func storedMouseColor(defaults: UserDefaults) -> NSColor {
    guard let data = defaults.data(forKey: PreferencesKeys.mouseHighlightColor),
          let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
      return MouseHighlightConfiguration.defaultHighlightColor
    }
    return color
  }
}

private extension UserDefaults {
  func boolValue(_ key: String, default defaultValue: Bool) -> Bool {
    object(forKey: key) as? Bool ?? defaultValue
  }

  func integerValue(_ key: String, default defaultValue: Int) -> Int {
    object(forKey: key) as? Int ?? defaultValue
  }

  func doubleValue(_ key: String, default defaultValue: Double) -> Double {
    object(forKey: key) as? Double ?? defaultValue
  }
}
