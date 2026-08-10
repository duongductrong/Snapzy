//
//  SnapzyConfigurationShortcutsExporter.swift
//  Snapzy
//
//  Shortcut TOML export helpers.
//

import Foundation

@MainActor
extension SnapzyConfigurationExporter {
  static func writeShortcuts(_ writer: inout SimpleTOMLWriter) {
    let manager = KeyboardShortcutManager.shared
    writer.section("shortcuts")
    writer.value("enabled", manager.isEnabled)

    for kind in GlobalShortcutKind.allCases {
      writeGlobalShortcut(&writer, kind: kind, manager: manager)
    }

    writeOverlayShortcut(
      &writer,
      section: "shortcuts.overlay.area_application_capture",
      shortcut: CaptureOverlayShortcutSettings.applicationCaptureShortcut
    )
    writeOverlayShortcut(
      &writer,
      section: "shortcuts.overlay.recording_application_capture",
      shortcut: CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
    )

    writeQuickAccessShortcut(&writer)
    writeQuickAccessCardActionShortcuts(&writer)
    writeAnnotateToolShortcuts(&writer)
    writeAnnotateActionShortcuts(&writer)
  }

  private static func writeQuickAccessCardActionShortcuts(_ writer: inout SimpleTOMLWriter) {
    let store = QuickAccessActionShortcutStore.shared
    writer.section("shortcuts.quick_access.card_actions")
    writer.value("enabled", store.isEnabled)

    for action in QuickAccessActionKind.defaultOrder {
      writer.section("shortcuts.quick_access.card_actions.\(action.configKey)")
      writer.value("enabled", store.isEnabled(for: action))
      guard let shortcut = store.shortcut(for: action) else {
        writer.value("key", "")
        writer.stringArray("modifiers", [])
        continue
      }
      writer.value("key", SnapzyConfigurationShortcutCodec.exportKey(shortcut))
      writer.stringArray("modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(shortcut))
    }
  }

  private static func writeQuickAccessShortcut(_ writer: inout SimpleTOMLWriter) {
    let manager = QuickAccessManager.shared
    writer.section("shortcuts.quick_access.edit_latest_capture")
    writer.value("enabled", manager.openEditorShortcutEnabled)
    guard let shortcut = manager.openEditorShortcut else {
      writer.value("key", "")
      writer.stringArray("modifiers", [])
      return
    }
    writer.value("key", SnapzyConfigurationShortcutCodec.exportKey(shortcut))
    writer.stringArray("modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(shortcut))
  }

  private static func writeGlobalShortcut(
    _ writer: inout SimpleTOMLWriter,
    kind: GlobalShortcutKind,
    manager: KeyboardShortcutManager
  ) {
    writer.section("shortcuts.global.\(kind.configKey)")
    writer.value("enabled", manager.isShortcutEnabled(for: kind))

    guard let shortcut = manager.shortcut(for: kind) else {
      writer.value("key", "")
      writer.stringArray("modifiers", [])
      return
    }

    writer.value("key", SnapzyConfigurationShortcutCodec.exportKey(shortcut))
    writer.stringArray("modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(shortcut))
  }

  private static func writeOverlayShortcut(
    _ writer: inout SimpleTOMLWriter,
    section: String,
    shortcut: CaptureOverlayShortcut?
  ) {
    writer.section(section)
    guard let shortcut else {
      writer.value("enabled", false)
      writer.value("key", "")
      writer.stringArray("modifiers", [])
      return
    }

    writer.value("enabled", true)
    let config = ShortcutConfig(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    writer.value("key", SnapzyConfigurationShortcutCodec.exportKey(config))
    writer.stringArray("modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(config))
  }

  private static func writeAnnotateToolShortcuts(_ writer: inout SimpleTOMLWriter) {
    let manager = AnnotateShortcutManager.shared
    writer.section("shortcuts.annotate_tools")
    writer.stringArray(
      "disabled",
      AnnotateShortcutManager.configurableTools
        .filter { !manager.isShortcutEnabled(for: $0) }
        .map(\.rawValue)
        .sorted()
    )
    for tool in AnnotateShortcutManager.configurableTools {
      writer.value(String(tool.rawValue), manager.shortcut(for: tool).map(String.init) ?? "")
    }
  }

  private static func writeAnnotateActionShortcuts(_ writer: inout SimpleTOMLWriter) {
    let manager = AnnotateShortcutManager.shared
    writer.section("shortcuts.annotate_actions")
    writer.stringArray(
      "disabled",
      AnnotateActionShortcutKind.allCases
        .filter { !manager.isActionShortcutEnabled(for: $0) }
        .map(\.rawValue)
        .sorted()
    )

    for kind in AnnotateActionShortcutKind.allCases {
      writer.section("shortcuts.annotate_actions.\(kind.configKey)")
      writer.value("enabled", manager.isActionShortcutEnabled(for: kind))
      guard let shortcut = manager.shortcut(for: kind) else {
        writer.value("key", "")
        writer.stringArray("modifiers", [])
        continue
      }
      writer.value("key", SnapzyConfigurationShortcutCodec.exportKey(shortcut))
      writer.stringArray("modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(shortcut))
    }
  }
}

extension GlobalShortcutKind {
  var configKey: String {
    switch self {
    case .fullscreen: return "fullscreen"
    case .area: return "area"
    case .repeatArea: return "repeat_area"
    case .areaAnnotate: return "area_annotate"
    case .activeWindow: return "active_window"
    case .scrollingCapture: return "scrolling_capture"
    case .recording: return "recording"
    case .pauseResumeRecording: return "pause_resume_recording"
    case .togglePenRecording: return "toggle_pen_recording"
    case .restartRecording: return "restart_recording"
    case .deleteRecording: return "delete_recording"
    case .annotate: return "annotate"
    case .videoEditor: return "video_editor"
    case .cloudUploads: return "cloud_uploads"
    case .shortcutList: return "shortcut_list"
    case .ocr: return "ocr"
    case .smartElement: return "smart_element"
    case .objectCutout: return "object_cutout"
    case .history: return "history"
    }
  }
}

extension QuickAccessActionKind {
  var configKey: String {
    switch self {
    case .copy: return "copy"
    case .saveOrOpen: return "save_or_open"
    case .dismiss: return "dismiss"
    case .delete: return "delete"
    case .edit: return "edit"
    case .uploadToCloud: return "upload_to_cloud"
    case .pinToScreen: return "pin_to_screen"
    }
  }
}

extension AnnotateActionShortcutKind {
  var configKey: String {
    switch self {
    case .copyAndClose: return "copy_and_close"
    case .toggleSidebar: return "toggle_sidebar"
    case .togglePin: return "toggle_pin"
    case .cloudUpload: return "cloud_upload"
    case .autoRedactSensitiveData: return "auto_redact_sensitive_data"
    }
  }
}
