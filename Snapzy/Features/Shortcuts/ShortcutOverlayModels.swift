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
        items: [
          globalItem(kind: .recording, icon: "record.circle", manager: keyboard),
        ]
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
            display: .keycaps(shortcut.displayParts)
          )
        }
      ),
      ShortcutOverlaySection(
        id: "annotate-tools",
        title: L10n.ShortcutOverlay.annotateToolKeys,
        items: AnnotateShortcutManager.configurableTools.map { tool in
          let singleKey = annotate.shortcut(for: tool).map { String($0).uppercased() } ?? "-"
          return ShortcutOverlayItem(
            id: "annotate-tool-\(tool.rawValue)",
            icon: tool.icon,
            title: tool.displayName,
            subtitle: toolContextSubtitle(for: tool),
            isEnabled: annotate.isShortcutEnabled(for: tool),
            display: .keycaps([singleKey])
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
      display: .keycaps(config.displayParts)
    )
  }

  private static func captureItems(manager: KeyboardShortcutManager) -> [ShortcutOverlayItem] {
    var items: [ShortcutOverlayItem] = [
      globalItem(kind: .fullscreen, icon: "rectangle.dashed.and.paperclip", manager: manager),
      globalItem(kind: .area, icon: "rectangle.dashed", manager: manager),
      globalItem(kind: .scrollingCapture, icon: "arrow.up.and.down", manager: manager),
    ]

    items.append(globalItem(kind: .objectCutout, icon: "person.crop.rectangle", manager: manager))
    items.append(globalItem(kind: .ocr, icon: "text.viewfinder", manager: manager))
    return items
  }

  private static func annotateActionMetadata(_ kind: AnnotateActionShortcutKind) -> (title: String, icon: String) {
    switch kind {
    case .copyAndClose:
      return (L10n.ShortcutOverlay.copyAndClose, "doc.on.doc")
    case .togglePin:
      return (L10n.ShortcutOverlay.togglePin, "pin")
    case .cloudUpload:
      return (L10n.ShortcutOverlay.cloudUpload, "icloud.and.arrow.up")
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
