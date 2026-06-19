//
//  ShortcutOverlayModels.swift
//  Snapzy
//
//  Data models and section builders for keyboard shortcut overlay.
//

import Foundation

struct ShortcutOverlaySection: Identifiable {
  let id: String
  let title: String
  let items: [ShortcutOverlayItem]
}

struct ShortcutOverlayItem: Identifiable {
  enum ShortcutDisplay {
    case keycaps([String])
    case text(String)
  }

  let id: String
  let icon: String
  let title: String
  let subtitle: String?
  let isEnabled: Bool
  let display: ShortcutDisplay
}

enum ShortcutOverlayContentBuilder {
  static func buildSections() -> [ShortcutOverlaySection] {
    let keyboard = KeyboardShortcutManager.shared
    let annotate = AnnotateShortcutManager.shared

    return [
      ShortcutOverlaySection(
        id: "capture",
        title: L10n.ShortcutOverlay.captureSection,
        items: captureItems(manager: keyboard)
      ),
      ShortcutOverlaySection(
        id: "recording",
        title: L10n.Onboarding.recordingSection,
        items: recordingItems(manager: keyboard)
      ),
      ShortcutOverlaySection(
        id: "tools",
        title: L10n.ShortcutOverlay.toolsSection,
        items: [
          globalItem(kind: .annotate, icon: "pencil.and.scribble", manager: keyboard),
          globalItem(kind: .videoEditor, icon: "film", manager: keyboard),
          globalItem(kind: .cloudUploads, icon: "icloud.and.arrow.up", manager: keyboard),
          globalItem(kind: .shortcutList, icon: "list.bullet.rectangle", manager: keyboard),
        ]
      ),
      ShortcutOverlaySection(
        id: "annotate-actions",
        title: L10n.ShortcutOverlay.annotateActions,
        items: AnnotateActionShortcutKind.allCases.map { kind in
          let (title, icon) = annotateActionMetadata(kind)
          let shortcut = annotate.shortcut(for: kind)
          return ShortcutOverlayItem(
            id: "annotate-action-\(kind.rawValue)",
            icon: icon,
            title: title,
            subtitle: L10n.ShortcutOverlay.insideAnnotateEditor,
            isEnabled: annotate.isActionShortcutEnabled(for: kind),
            display: shortcut.map { .keycaps($0.displayParts) } ?? .text(L10n.Common.none)
          )
        }
      ),
      ShortcutOverlaySection(
        id: "annotate-tools",
        title: L10n.ShortcutOverlay.annotateToolKeys,
        items: AnnotateShortcutManager.configurableTools.map { tool in
          let display = annotate.shortcut(for: tool)
            .map { ShortcutOverlayItem.ShortcutDisplay.keycaps([String($0).uppercased()]) }
            ?? .text(L10n.Common.none)
          return ShortcutOverlayItem(
            id: "annotate-tool-\(tool.rawValue)",
            icon: tool.icon,
            title: tool.displayName,
            subtitle: toolContextSubtitle(for: tool),
            isEnabled: annotate.isShortcutEnabled(for: tool),
            display: display
          )
        }
      ),
      ShortcutOverlaySection(
        id: "annotate-reference",
        title: L10n.ShortcutOverlay.annotateReference,
        items: [
          ShortcutOverlayItem(id: "annotate-ref-save", icon: "square.and.arrow.down", title: L10n.ShortcutOverlay.saveDone, subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "S"])),
          ShortcutOverlayItem(id: "annotate-ref-save-as", icon: "square.and.arrow.down.on.square", title: L10n.ShortcutOverlay.saveAs, subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "⇧", "S"])),
          ShortcutOverlayItem(id: "annotate-ref-undo", icon: "arrow.uturn.backward", title: L10n.ShortcutOverlay.undo, subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "Z"])),
          ShortcutOverlayItem(id: "annotate-ref-redo", icon: "arrow.uturn.forward", title: L10n.ShortcutOverlay.redo, subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "⇧", "Z"])),
          ShortcutOverlayItem(id: "annotate-ref-delete", icon: "trash", title: L10n.ShortcutOverlay.deleteAnnotation, subtitle: nil, isEnabled: true, display: .keycaps(["⌫"])),
          ShortcutOverlayItem(id: "annotate-ref-cancel", icon: "escape", title: L10n.ShortcutOverlay.cancelDeselect, subtitle: nil, isEnabled: true, display: .keycaps(["⎋"])),
          ShortcutOverlayItem(id: "annotate-ref-confirm-crop", icon: "return", title: L10n.ShortcutOverlay.confirmCrop, subtitle: nil, isEnabled: true, display: .keycaps(["↩"])),
          ShortcutOverlayItem(id: "annotate-ref-nudge", icon: "arrow.up.arrow.down.arrow.left.arrow.right", title: L10n.ShortcutOverlay.nudgeAnnotation, subtitle: nil, isEnabled: true, display: .text("← → ↑ ↓")),
          ShortcutOverlayItem(id: "annotate-ref-nudge-10", icon: "arrow.up.arrow.down.arrow.left.arrow.right", title: L10n.ShortcutOverlay.nudgeTenPixels, subtitle: nil, isEnabled: true, display: .text("⇧ ← → ↑ ↓")),
        ]
      ),
    ]
  }

  private static func globalItem(
    kind: GlobalShortcutKind,
    icon: String,
    manager: KeyboardShortcutManager
  ) -> ShortcutOverlayItem {
    let config = manager.shortcut(for: kind)
    return ShortcutOverlayItem(
      id: "global-\(kind.rawValue)",
      icon: icon,
      title: kind.displayName,
      subtitle: nil,
      isEnabled: manager.isShortcutEnabled(for: kind),
      display: config.map { .keycaps($0.displayParts) } ?? .text(L10n.Common.none)
    )
  }

  private static func captureItems(manager: KeyboardShortcutManager) -> [ShortcutOverlayItem] {
    let areaConfig = manager.shortcut(for: .area)
    var items: [ShortcutOverlayItem] = [
      globalItem(kind: .fullscreen, icon: "rectangle.dashed.and.paperclip", manager: manager),
      ShortcutOverlayItem(
        id: "global-\(GlobalShortcutKind.area.rawValue)",
        icon: "rectangle.dashed",
        title: GlobalShortcutKind.area.displayName,
        subtitle: L10n.ShortcutOverlay.applicationCapture(
          CaptureOverlayShortcutSettings.effectiveApplicationCaptureDisplay(parentShortcut: areaConfig)
        ),
        isEnabled: manager.isShortcutEnabled(for: .area),
        display: areaConfig.map { .keycaps($0.displayParts) } ?? .text(L10n.Common.none)
      ),
      globalItem(kind: .areaAnnotate, icon: "pencil.and.scribble", manager: manager),
      globalItem(kind: .activeWindow, icon: "macwindow", manager: manager),
      globalItem(kind: .scrollingCapture, icon: "arrow.up.and.down", manager: manager),
    ]

    items.append(globalItem(kind: .objectCutout, icon: "person.crop.rectangle", manager: manager))
    items.append(globalItem(kind: .ocr, icon: "text.viewfinder", manager: manager))
    return items
  }

  private static func recordingItems(manager: KeyboardShortcutManager) -> [ShortcutOverlayItem] {
    let recordingConfig = manager.shortcut(for: .recording)
    return [
      ShortcutOverlayItem(
        id: "global-\(GlobalShortcutKind.recording.rawValue)",
        icon: "record.circle",
        title: GlobalShortcutKind.recording.displayName,
        subtitle: L10n.ShortcutOverlay.applicationRecording(
          CaptureOverlayShortcutSettings.effectiveRecordingApplicationCaptureDisplay(parentShortcut: recordingConfig)
        ),
        isEnabled: manager.isShortcutEnabled(for: .recording),
        display: recordingConfig.map { .keycaps($0.displayParts) } ?? .text(L10n.Common.none)
      ),
    ]
  }

  private static func annotateActionMetadata(_ kind: AnnotateActionShortcutKind) -> (title: String, icon: String) {
    switch kind {
    case .copyAndClose:
      return (L10n.ShortcutOverlay.copyAndClose, "doc.on.doc")
    case .toggleSidebar:
      return (L10n.AnnotateUI.toggleSidebar, "rectangle.on.rectangle")
    case .togglePin:
      return (L10n.ShortcutOverlay.togglePin, "pin")
    case .cloudUpload:
      return (L10n.ShortcutOverlay.cloudUpload, "icloud.and.arrow.up")
    case .autoRedactSensitiveData:
      return (L10n.ShortcutOverlay.autoRedactSensitiveData, "shield.lefthalf.filled")
    }
  }

  private static func toolContextSubtitle(for tool: AnnotationToolType) -> String {
    let recordingTools: Set<AnnotationToolType> = [
      .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter,
    ]
    let screenshotTools: Set<AnnotationToolType> = [
      .selection, .rectangle, .oval, .arrow, .line, .text,
      .highlighter, .blur, .counter, .pencil,
    ]

    let inScreenshot = screenshotTools.contains(tool)
    let inRecording = recordingTools.contains(tool)

    if inScreenshot && inRecording { return L10n.ShortcutOverlay.screenshotAndRecording }
    if inRecording { return L10n.ShortcutOverlay.recordingOnly }
    return L10n.ShortcutOverlay.screenshotOnly
  }
}
