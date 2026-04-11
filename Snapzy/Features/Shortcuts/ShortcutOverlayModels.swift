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
        title: "Capture",
        items: captureItems(manager: keyboard)
      ),
      ShortcutOverlaySection(
        id: "recording",
        title: "Recording",
        items: [
          globalItem(kind: .recording, icon: "record.circle", manager: keyboard),
        ]
      ),
      ShortcutOverlaySection(
        id: "tools",
        title: "Tools",
        items: [
          globalItem(kind: .annotate, icon: "pencil.and.scribble", manager: keyboard),
          globalItem(kind: .videoEditor, icon: "film", manager: keyboard),
          globalItem(kind: .cloudUploads, icon: "icloud.and.arrow.up", manager: keyboard),
          globalItem(kind: .shortcutList, icon: "list.bullet.rectangle", manager: keyboard),
        ]
      ),
      ShortcutOverlaySection(
        id: "annotate-actions",
        title: "Annotate Actions",
        items: AnnotateActionShortcutKind.allCases.map { kind in
          let (title, icon) = annotateActionMetadata(kind)
          let shortcut = annotate.shortcut(for: kind)
          return ShortcutOverlayItem(
            id: "annotate-action-\(kind.rawValue)",
            icon: icon,
            title: title,
            subtitle: "Inside annotate editor",
            isEnabled: annotate.isActionShortcutEnabled(for: kind),
            display: .keycaps(shortcut.displayParts)
          )
        }
      ),
      ShortcutOverlaySection(
        id: "annotate-tools",
        title: "Annotate Tool Keys",
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
        title: "Annotate Reference",
        items: [
          ShortcutOverlayItem(id: "annotate-ref-save", icon: "square.and.arrow.down", title: "Save (Done)", subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "S"])),
          ShortcutOverlayItem(id: "annotate-ref-save-as", icon: "square.and.arrow.down.on.square", title: "Save As…", subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "⇧", "S"])),
          ShortcutOverlayItem(id: "annotate-ref-undo", icon: "arrow.uturn.backward", title: "Undo", subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "Z"])),
          ShortcutOverlayItem(id: "annotate-ref-redo", icon: "arrow.uturn.forward", title: "Redo", subtitle: nil, isEnabled: true, display: .keycaps(["⌘", "⇧", "Z"])),
          ShortcutOverlayItem(id: "annotate-ref-delete", icon: "trash", title: "Delete Annotation", subtitle: nil, isEnabled: true, display: .keycaps(["⌫"])),
          ShortcutOverlayItem(id: "annotate-ref-cancel", icon: "escape", title: "Cancel / Deselect", subtitle: nil, isEnabled: true, display: .keycaps(["⎋"])),
          ShortcutOverlayItem(id: "annotate-ref-confirm-crop", icon: "return", title: "Confirm Crop", subtitle: nil, isEnabled: true, display: .keycaps(["↩"])),
          ShortcutOverlayItem(id: "annotate-ref-nudge", icon: "arrow.up.arrow.down.arrow.left.arrow.right", title: "Nudge Annotation", subtitle: nil, isEnabled: true, display: .text("← → ↑ ↓")),
          ShortcutOverlayItem(id: "annotate-ref-nudge-10", icon: "arrow.up.arrow.down.arrow.left.arrow.right", title: "Nudge 10px", subtitle: nil, isEnabled: true, display: .text("⇧ ← → ↑ ↓")),
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
      return ("Copy & Close", "doc.on.doc")
    case .togglePin:
      return ("Toggle Pin", "pin")
    case .cloudUpload:
      return ("Cloud Upload", "icloud.and.arrow.up")
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

    if inScreenshot && inRecording { return "Screenshot + Recording" }
    if inRecording { return "Recording only" }
    return "Screenshot only"
  }
}
