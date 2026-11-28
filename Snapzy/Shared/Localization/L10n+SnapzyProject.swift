//
//  L10n+SnapzyProject.swift
//  Snapzy
//
//  Localized strings for `.snapzy` Video Editor project packages.
//

import Foundation

extension L10n.VideoEditor {
  // MARK: - .snapzy Project Package UI

  nonisolated static let projectToolbarSave = L10n.string(
    "video-editor.project-toolbar-save",
    defaultValue: "Save .snapzy",
    comment: "Toolbar button label for saving the current Video Editor session as a .snapzy project package"
  )

  nonisolated static let projectToolbarSaved = L10n.string(
    "video-editor.project-toolbar-saved",
    defaultValue: "Saved",
    comment: "Transient toolbar badge shown right after saving a .snapzy project package"
  )

  nonisolated static let projectToolbarOpen = L10n.string(
    "video-editor.project-toolbar-open",
    defaultValue: "Open .snapzy",
    comment: "Toolbar pull-down menu button label for opening or saving .snapzy project packages"
  )

  nonisolated static let projectMenuSave = L10n.string(
    "video-editor.project-menu-save",
    defaultValue: "Save Project (.snapzy)",
    comment: "Menu item for saving the current Video Editor project in place"
  )

  nonisolated static let projectMenuSaveEllipsis = L10n.string(
    "video-editor.project-menu-save-ellipsis",
    defaultValue: "Save Project (.snapzy)…",
    comment: "Menu item for saving a new Video Editor project with a file save dialog"
  )

  nonisolated static let projectMenuSaveAs = L10n.string(
    "video-editor.project-menu-save-as",
    defaultValue: "Save Project As (.snapzy)…",
    comment: "Menu item for saving a copy of the current Video Editor project to a new .snapzy path"
  )

  nonisolated static let projectMenuOpenOrVideo = L10n.string(
    "video-editor.project-menu-open-or-video",
    defaultValue: "Open Project or Video…",
    comment: "Menu item for opening a .snapzy project package or video file"
  )

  nonisolated static let projectUnsavedCloseTitle = L10n.string(
    "video-editor.project-unsaved-close-title",
    defaultValue: "Save project before closing?",
    comment: "Alert title shown when closing a Video Editor window with unsaved changes"
  )

  nonisolated static let projectUnsavedCloseMessage = L10n.string(
    "video-editor.project-unsaved-close-message",
    defaultValue: "You have unsaved changes. Save as a self-contained .snapzy project package to preserve all source media, captions, and timeline edits.",
    comment: "Alert message explaining that saving as .snapzy preserves non-destructive project state"
  )

  nonisolated static let projectSavePanelTitle = L10n.string(
    "video-editor.project-save-panel-title",
    defaultValue: "Save Snapzy Project (.snapzy)",
    comment: "NSSavePanel title when saving a .snapzy project package"
  )

  nonisolated static let projectSavePanelMessage = L10n.string(
    "video-editor.project-save-panel-message",
    defaultValue: "Bundles source media, inserted clips, metadata, and timeline layers into a single portable .snapzy file.",
    comment: "NSSavePanel message when saving a .snapzy project package"
  )

  nonisolated static let projectOpenPanelTitle = L10n.string(
    "video-editor.project-open-panel-title",
    defaultValue: "Open Project (.snapzy) or Video",
    comment: "NSOpenPanel title when opening a .snapzy project package or video file"
  )

  nonisolated static let projectOpenFailedTitle = L10n.string(
    "video-editor.project-open-failed-title",
    defaultValue: "Could Not Open .snapzy Project",
    comment: "Error alert title when a .snapzy project package fails to open"
  )

  nonisolated static let projectSaveFailedTitle = L10n.string(
    "video-editor.project-save-failed-title",
    defaultValue: "Could Not Save .snapzy Project",
    comment: "Error alert title when saving a .snapzy project package fails"
  )

  nonisolated static let projectRestoreFailedTitle = L10n.string(
    "video-editor.project-restore-failed-title",
    defaultValue: "Project Timeline Could Not Be Restored",
    comment: "Warning alert title when a .snapzy project's saved timeline fails validation against its media"
  )

  nonisolated static let projectRestoreFailedMessage = L10n.string(
    "video-editor.project-restore-failed-message",
    defaultValue: "Saved timeline clips did not match the media inside this .snapzy package. In-place Save is locked so the original project file is not overwritten — use Save Project As to save a new copy.",
    comment: "Warning alert message explaining that in-place Save is blocked after a session restore failure"
  )
}
