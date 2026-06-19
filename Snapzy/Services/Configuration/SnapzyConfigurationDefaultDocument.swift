//
//  SnapzyConfigurationDefaultDocument.swift
//  Snapzy
//
//  Builds a complete default TOML configuration for restore-defaults flows.
//

import AppKit
import Foundation

@MainActor
enum SnapzyConfigurationDefaultDocument {
  static func toml() -> String {
    var writer = SimpleTOMLWriter()
    writer.root("schema_version", 1)
    writer.root("snapzy_min_version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.20.0")

    writeGeneral(&writer)
    writeCapture(&writer)
    writeRecording(&writer)
    writeQuickAccess(&writer)
    writeHistory(&writer)
    writeCloud(&writer)
    writeAnnotate(&writer)
    writeShortcuts(&writer)

    return writer.output
  }

  private static func writeGeneral(_ writer: inout SimpleTOMLWriter) {
    writer.section("general")
    writer.value("language", "system")
    writer.value("appearance", "system")
    writer.value("play_sounds", true)
    writer.value("start_at_login", false)
    writer.value("export_location", SandboxFileAccessManager.shared.defaultExportDirectory.path)

    writer.section("updates")
    writer.value("check_automatically", true)
    writer.value("download_automatically", false)

    writer.section("diagnostics")
    writer.value("enabled", true)
    writer.value("retention_days", LogCleanupScheduler.defaultRetentionDays)
  }

  private static func writeCapture(_ writer: inout SimpleTOMLWriter) {
    writer.section("capture")
    writer.value("hide_desktop_icons", false)
    writer.value("hide_desktop_widgets", false)

    writer.section("capture.naming")
    writer.value("screenshot_template", CaptureOutputKind.screenshot.defaultTemplate)
    writer.value("recording_template", CaptureOutputKind.recording.defaultTemplate)

    writer.section("capture.screenshot")
    writer.value("format", ImageFormatOption.png.rawValue)
    writer.value("include_snapzy", false)
    writer.value("show_cursor", false)

    writer.section("capture.scrolling")
    writer.value("show_hints", true)

    writer.section("capture.ocr")
    writer.value("success_notification", false)

    writer.section("capture.object_cutout")
    writer.value("auto_crop", true)

    writeAfterCapture(&writer, type: .screenshot)
    writeAfterCapture(&writer, type: .recording)
  }

  private static func writeRecording(_ writer: inout SimpleTOMLWriter) {
    writer.section("recording")
    writer.value("format", VideoFormat.mov.rawValue)
    writer.value("quality", VideoQuality.high.rawValue)
    writer.value("fps", 30)
    writer.value("output_mode", RecordingOutputMode.video.rawValue)
    writer.value("capture_system_audio", true)
    writer.value("capture_microphone", false)
    writer.value("microphone_device_id", "")
    writer.value("remember_last_area", true)
    writer.value("include_snapzy", false)
    writer.value("show_cursor", true)
    writer.value("highlight_clicks", false)
    writer.value("show_keystrokes", false)

    writer.section("recording.mouse_highlight")
    writer.value("size", 50)
    writer.value("animation_duration", 0.7)
    writer.value("color", SnapzyConfigurationColor.hexString(from: MouseHighlightConfiguration.defaultHighlightColor))
    writer.value("opacity", 0.5)
    writer.value("ripple_count", 3)

    writer.section("recording.keystrokes")
    writer.value("font_size", Double(KeystrokeOverlayConfiguration.defaultFontSize))
    writer.value("position", KeystrokeOverlayConfiguration.defaultPosition.rawValue)
    writer.value("display_duration", KeystrokeOverlayConfiguration.defaultDisplayDuration)

    writer.section("recording.annotation_shortcuts")
    writer.value("modifier", RecordingAnnotationShortcutConfig.defaultModifier.rawValue)
    writer.value("hold_duration", RecordingAnnotationShortcutConfig.defaultHoldDuration)
  }

  private static func writeQuickAccess(_ writer: inout SimpleTOMLWriter) {
    writer.section("quick_access")
    writer.value("enabled", true)
    writer.value("position", QuickAccessPosition.bottomRight.rawValue)
    writer.value("auto_dismiss", true)
    writer.value("auto_dismiss_delay", 10)
    writer.value("pause_countdown_on_hover", true)
    writer.value("overlay_scale", 1.0)
    writer.value("drag_drop", true)
    writer.value("two_finger_swipe_to_dismiss", true)
    writer.value("swipe_sensitivity", 1.0)
    writer.stringArray("actions_order", QuickAccessActionKind.defaultOrder.map(\.rawValue))
    writer.stringArray("enabled_actions", QuickAccessActionKind.defaultEnabledActions.map(\.rawValue).sorted())

    writer.section("quick_access.slots")
    for slot in QuickAccessActionSlot.allCases {
      writer.value(slot.configKey, QuickAccessActionSlot.defaultAssignments[slot]?.rawValue ?? "")
    }
  }

  private static func writeHistory(_ writer: inout SimpleTOMLWriter) {
    writer.section("history")
    writer.value("enabled", true)
    writer.value("retention_days", 30)
    writer.value("max_count", 500)
    writer.value("background_style", HistoryBackgroundStyle.defaultStyle.rawValue)
    writer.value("open_on_launch", false)

    writer.section("history.floating")
    writer.value("enabled", true)
    writer.value("position", HistoryPanelPosition.topCenter.rawValue)
    writer.value("default_filter", "all")
    writer.value("max_displayed_items", 10)
    writer.value("scale", HistoryFloatingLayout.defaultScale)
    writer.value("auto_clear_days", 0)
  }

  private static func writeCloud(_ writer: inout SimpleTOMLWriter) {
    writer.section("cloud")
    writer.value("provider", CloudProviderType.awsS3.rawValue)
    writer.value("bucket", "")
    writer.value("region", "us-east-1")
    writer.value("endpoint", "")
    writer.value("custom_domain", "")
    writer.value("expire_time", CloudExpireTime.day7.rawValue)
    writer.value("uploads_window_position", CloudUploadFloatingPosition.defaultPosition.rawValue)
  }

  private static func writeAnnotate(_ writer: inout SimpleTOMLWriter) {
    writer.section("annotate")
    writer.value("clipboard_image_open_behavior", AnnotateClipboardImageBehavior.ask.rawValue)
    writer.value("close_after_drag", true)
    writer.value("bring_forward_after_drag", false)
    writer.value("quick_properties_sync", true)
  }

  private static func writeShortcuts(_ writer: inout SimpleTOMLWriter) {
    writer.section("shortcuts")
    writer.value("enabled", false)

    for kind in GlobalShortcutKind.allCases {
      writeGlobalShortcut(&writer, kind: kind)
    }

    writeOverlayShortcut(
      &writer,
      section: "shortcuts.overlay.area_application_capture",
      shortcut: CaptureOverlayShortcutSettings.defaultApplicationCaptureShortcut
    )
    writeOverlayShortcut(
      &writer,
      section: "shortcuts.overlay.recording_application_capture",
      shortcut: CaptureOverlayShortcutSettings.defaultRecordingApplicationCaptureShortcut
    )

    writer.section("shortcuts.annotate_tools")
    writer.stringArray("disabled", [])
    for tool in AnnotateShortcutManager.configurableTools {
      writer.value(String(tool.rawValue), String(tool.defaultShortcut))
    }

    writer.section("shortcuts.annotate_actions")
    writer.stringArray("disabled", [])
    for kind in AnnotateActionShortcutKind.allCases {
      writer.section("shortcuts.annotate_actions.\(kind.configKey)")
      writer.value("enabled", true)
      writeShortcutValues(&writer, shortcut: annotateActionShortcut(for: kind))
    }
  }

  private static func writeAfterCapture(_ writer: inout SimpleTOMLWriter, type: CaptureType) {
    writer.section("capture.after.\(type.rawValue)")
    writer.value("save", true)
    writer.value("quick_access", true)
    writer.value("copy_file", true)
    writer.value("open_annotate", false)
    writer.value("upload_to_cloud", false)
  }

  private static func writeGlobalShortcut(_ writer: inout SimpleTOMLWriter, kind: GlobalShortcutKind) {
    writer.section("shortcuts.global.\(kind.configKey)")
    writer.value("enabled", true)
    writeShortcutValues(&writer, shortcut: globalShortcut(for: kind))
  }

  private static func writeOverlayShortcut(
    _ writer: inout SimpleTOMLWriter,
    section: String,
    shortcut: CaptureOverlayShortcut
  ) {
    writer.section(section)
    writer.value("enabled", true)
    let shortcutConfig = ShortcutConfig(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    writeShortcutValues(&writer, shortcut: shortcutConfig)
  }

  private static func writeShortcutValues(_ writer: inout SimpleTOMLWriter, shortcut: ShortcutConfig?) {
    guard let shortcut else {
      writer.value("key", "")
      writer.stringArray("modifiers", [])
      return
    }

    writer.value("key", SnapzyConfigurationShortcutCodec.exportKey(shortcut))
    writer.stringArray("modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(shortcut))
  }

  private static func globalShortcut(for kind: GlobalShortcutKind) -> ShortcutConfig {
    switch kind {
    case .fullscreen: return .defaultFullscreen
    case .area: return .defaultArea
    case .areaAnnotate: return .defaultAreaAnnotate
    case .activeWindow: return .defaultActiveWindowCapture
    case .scrollingCapture: return .defaultScrollingCapture
    case .recording: return .defaultRecording
    case .annotate: return .defaultAnnotate
    case .videoEditor: return .defaultVideoEditor
    case .cloudUploads: return .defaultCloudUploads
    case .shortcutList: return .defaultShortcutList
    case .ocr: return .defaultOCR
    case .objectCutout: return .defaultObjectCutout
    case .history: return .defaultHistory
    }
  }

  private static func annotateActionShortcut(for kind: AnnotateActionShortcutKind) -> ShortcutConfig? {
    switch kind {
    case .copyAndClose: return AnnotateShortcutManager.defaultCopyAndClose
    case .toggleSidebar: return AnnotateShortcutManager.defaultToggleSidebar
    case .togglePin: return AnnotateShortcutManager.defaultTogglePin
    case .cloudUpload: return AnnotateShortcutManager.defaultCloudUpload
    case .autoRedactSensitiveData: return AnnotateShortcutManager.defaultAutoRedactSensitiveData
    }
  }
}
