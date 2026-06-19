//
//  SnapzyConfigurationShortcutsImporter.swift
//  Snapzy
//
//  Shortcut import helpers for TOML configuration.
//

import Foundation

@MainActor
extension SnapzyConfigurationImporter {
  static func collectShortcuts(
    _ reader: inout SnapzyConfigurationReader,
    mutations: inout [() -> Void]
  ) {
    if let enabled = reader.bool("shortcuts", "enabled") {
      mutations.append {
        enabled ? KeyboardShortcutManager.shared.enable() : KeyboardShortcutManager.shared.disable()
      }
    }

    for kind in GlobalShortcutKind.allCases {
      collectGlobalShortcut(&reader, kind: kind, mutations: &mutations)
    }

    collectOverlayShortcut(
      &reader,
      path: ["shortcuts", "overlay", "area_application_capture"],
      mutations: &mutations
    ) {
      CaptureOverlayShortcutSettings.setApplicationCaptureShortcut($0)
    }
    collectOverlayShortcut(
      &reader,
      path: ["shortcuts", "overlay", "recording_application_capture"],
      mutations: &mutations
    ) {
      CaptureOverlayShortcutSettings.setRecordingApplicationCaptureShortcut($0)
    }

    collectAnnotateTools(&reader, mutations: &mutations)
    collectAnnotateActions(&reader, mutations: &mutations)
  }

  static func quickAccessSlots(
    from reader: inout SnapzyConfigurationReader
  ) -> [QuickAccessActionSlot: QuickAccessActionKind]? {
    var assignments: [QuickAccessActionSlot: QuickAccessActionKind] = [:]
    var sawValue = false

    for slot in QuickAccessActionSlot.allCases {
      guard let raw = reader.string(["quick_access", "slots", slot.configKey]) else { continue }
      sawValue = true
      if raw.isEmpty { continue }
      guard let action = QuickAccessActionKind(rawValue: raw) else {
        reader.error("quick_access.slots.\(slot.configKey) is not a known Quick Access action")
        continue
      }
      assignments[slot] = action
    }

    return sawValue ? assignments : nil
  }

  private static func collectGlobalShortcut(
    _ reader: inout SnapzyConfigurationReader,
    kind: GlobalShortcutKind,
    mutations: inout [() -> Void]
  ) {
    let path = ["shortcuts", "global", kind.configKey]
    let key = reader.string(path + ["key"])
    let modifiers = reader.stringArray(path + ["modifiers"])
    let enabled = reader.bool(path + ["enabled"])

    guard key != nil || modifiers != nil || enabled != nil else { return }
    guard key != nil || modifiers == nil else {
      reader.error("shortcuts.global.\(kind.configKey).modifiers requires key")
      return
    }

    if let key, key.isEmpty {
      mutations.append {
        KeyboardShortcutManager.shared.setShortcut(nil, for: kind)
        KeyboardShortcutManager.shared.setShortcutEnabled(false, for: kind)
      }
      return
    }

    if let key {
      guard let shortcut = SnapzyConfigurationShortcutCodec.shortcut(
        key: key,
        modifiers: modifiers ?? [],
        requireModifier: true
      ) else {
        reader.error("shortcuts.global.\(kind.configKey) has an invalid shortcut")
        return
      }
      mutations.append { KeyboardShortcutManager.shared.setShortcut(shortcut, for: kind) }
    }

    if let enabled {
      mutations.append { KeyboardShortcutManager.shared.setShortcutEnabled(enabled, for: kind) }
    }
  }

  private static func collectOverlayShortcut(
    _ reader: inout SnapzyConfigurationReader,
    path: [String],
    mutations: inout [() -> Void],
    apply: @escaping (CaptureOverlayShortcut?) -> Void
  ) {
    let enabled = reader.bool(path + ["enabled"])
    let key = reader.string(path + ["key"])
    let modifiers = reader.stringArray(path + ["modifiers"])
    guard enabled != nil || key != nil || modifiers != nil else { return }

    if enabled == false || key == "" {
      mutations.append { apply(nil) }
      return
    }

    guard key != nil || modifiers == nil else {
      reader.error("\(path.joined(separator: ".")).modifiers requires key")
      return
    }

    guard let key,
          let shortcut = SnapzyConfigurationShortcutCodec.overlayShortcut(
            key: key,
            modifiers: modifiers ?? []
          ) else {
      reader.error("\(path.joined(separator: ".")) has an invalid shortcut")
      return
    }

    mutations.append { apply(shortcut) }
  }

  private static func collectAnnotateTools(
    _ reader: inout SnapzyConfigurationReader,
    mutations: inout [() -> Void]
  ) {
    let disabled = disabledAnnotateTools(from: &reader)

    for tool in AnnotateShortcutManager.configurableTools {
      if let key = reader.string("shortcuts", "annotate_tools", tool.rawValue) {
        mutations.append {
          AnnotateShortcutManager.shared.setShortcut(key.first, for: tool)
        }
      }
      if let disabled {
        mutations.append {
          AnnotateShortcutManager.shared.setShortcutEnabled(!disabled.contains(tool), for: tool)
        }
      }
    }
  }

  private static func collectAnnotateActions(
    _ reader: inout SnapzyConfigurationReader,
    mutations: inout [() -> Void]
  ) {
    let disabled = disabledAnnotateActions(from: &reader)

    for kind in AnnotateActionShortcutKind.allCases {
      collectAnnotateAction(&reader, kind: kind, disabled: disabled, mutations: &mutations)
    }
  }

  private static func collectAnnotateAction(
    _ reader: inout SnapzyConfigurationReader,
    kind: AnnotateActionShortcutKind,
    disabled: Set<AnnotateActionShortcutKind>?,
    mutations: inout [() -> Void]
  ) {
    let path = ["shortcuts", "annotate_actions", kind.configKey]
    let key = reader.string(path + ["key"])
    let modifiers = reader.stringArray(path + ["modifiers"])
    let explicitEnabled = reader.bool(path + ["enabled"])

    guard key != nil || modifiers != nil || explicitEnabled != nil || disabled != nil else { return }
    guard key != nil || modifiers == nil else {
      reader.error("shortcuts.annotate_actions.\(kind.configKey).modifiers requires key")
      return
    }

    if let key, key.isEmpty {
      mutations.append {
        AnnotateShortcutManager.shared.setShortcut(nil, for: kind)
      }
      mutations.append {
        let enabled = explicitEnabled ?? (disabled.map { !$0.contains(kind) } ?? false)
        AnnotateShortcutManager.shared.setActionShortcutEnabled(enabled, for: kind)
      }
      return
    }

    if let key {
      guard let shortcut = SnapzyConfigurationShortcutCodec.shortcut(
        key: key,
        modifiers: modifiers ?? [],
        requireModifier: true
      ) else {
        reader.error("shortcuts.annotate_actions.\(kind.configKey) has an invalid shortcut")
        return
      }
      mutations.append { AnnotateShortcutManager.shared.setShortcut(shortcut, for: kind) }
    }

    if explicitEnabled != nil || disabled != nil {
      let enabled = explicitEnabled ?? !(disabled?.contains(kind) ?? false)
      mutations.append {
        AnnotateShortcutManager.shared.setActionShortcutEnabled(enabled, for: kind)
      }
    }
  }

  private static func disabledAnnotateTools(
    from reader: inout SnapzyConfigurationReader
  ) -> Set<AnnotationToolType>? {
    guard let rawValues = reader.stringArray("shortcuts", "annotate_tools", "disabled") else { return nil }
    var disabled: Set<AnnotationToolType> = []

    for rawValue in rawValues {
      guard let tool = AnnotationToolType(rawValue: rawValue) else {
        reader.error("shortcuts.annotate_tools.disabled contains unknown tool \(rawValue)")
        continue
      }
      disabled.insert(tool)
    }

    return disabled
  }

  private static func disabledAnnotateActions(
    from reader: inout SnapzyConfigurationReader
  ) -> Set<AnnotateActionShortcutKind>? {
    guard let rawValues = reader.stringArray("shortcuts", "annotate_actions", "disabled") else { return nil }
    var disabled: Set<AnnotateActionShortcutKind> = []

    for rawValue in rawValues {
      guard let kind = AnnotateActionShortcutKind(rawValue: rawValue) else {
        reader.error("shortcuts.annotate_actions.disabled contains unknown action \(rawValue)")
        continue
      }
      disabled.insert(kind)
    }

    return disabled
  }
}

extension QuickAccessActionSlot {
  var configKey: String {
    switch self {
    case .centerTop: return "center_top"
    case .centerBottom: return "center_bottom"
    case .topTrailing: return "top_trailing"
    case .topLeading: return "top_leading"
    case .bottomLeading: return "bottom_leading"
    case .bottomTrailing: return "bottom_trailing"
    }
  }
}

@MainActor
private extension KeyboardShortcutManager {
  func setShortcut(_ config: ShortcutConfig?, for kind: GlobalShortcutKind) {
    switch kind {
    case .fullscreen:
      setFullscreenShortcut(config)
    case .area:
      setAreaShortcut(config)
    case .areaAnnotate:
      setAreaAnnotateShortcut(config)
    case .activeWindow:
      setActiveWindowShortcut(config)
    case .scrollingCapture:
      setScrollingCaptureShortcut(config)
    case .recording:
      setRecordingShortcut(config)
    case .annotate:
      setAnnotateShortcut(config)
    case .videoEditor:
      setVideoEditorShortcut(config)
    case .cloudUploads:
      setCloudUploadsShortcut(config)
    case .shortcutList:
      setShortcutListShortcut(config)
    case .ocr:
      setOCRShortcut(config)
    case .objectCutout:
      setObjectCutoutShortcut(config)
    case .history:
      setHistoryShortcut(config)
    }
  }
}

@MainActor
private extension AnnotateShortcutManager {
  func setShortcut(_ config: ShortcutConfig?, for kind: AnnotateActionShortcutKind) {
    switch kind {
    case .copyAndClose:
      setCopyAndCloseShortcut(config)
    case .toggleSidebar:
      setToggleSidebarShortcut(config)
    case .togglePin:
      setTogglePinShortcut(config)
    case .cloudUpload:
      setCloudUploadShortcut(config)
    case .autoRedactSensitiveData:
      setAutoRedactSensitiveDataShortcut(config)
    }
  }
}
