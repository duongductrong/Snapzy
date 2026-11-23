//
//  L10n+Automations.swift
//  Snapzy
//
//  Strings for automations: presets, steps, run results and Settings.
//

import Foundation

extension L10n {
  nonisolated enum Automations {
    static let defaultName = string(
      "automations.default-name",
      defaultValue: "Automation",
      comment: "Fallback name for an automation whose name is empty"
    )
    static func copyName(_ name: String) -> String {
      format(
        "automations.copy-name",
        defaultValue: "%@ Copy",
        comment: "Name of a duplicated automation; %@ is the original name",
        name
      )
    }
    static let presetQuickCopy = string(
      "automations.preset.quick-copy",
      defaultValue: "Quick Copy",
      comment: "Built-in automation: capture an area and copy the image"
    )
    static let presetCloudShare = string(
      "automations.preset.cloud-share",
      defaultValue: "Cloud Share",
      comment: "Built-in automation: capture an area, upload it and copy the link"
    )
    static let modeArea = string(
      "automations.mode.area",
      defaultValue: "Area",
      comment: "Automation capture mode: select an area"
    )
    static let modeFullscreen = string(
      "automations.mode.fullscreen",
      defaultValue: "Fullscreen",
      comment: "Automation capture mode: the whole screen"
    )
    static let modeActiveWindow = string(
      "automations.mode.active-window",
      defaultValue: "Active Window",
      comment: "Automation capture mode: the focused window"
    )
    static let modeApplicationWindow = string(
      "automations.mode.application-window",
      defaultValue: "Window",
      comment: "Automation capture mode: pick a window"
    )
    static let stepCopyImage = string(
      "automations.step.copy-image",
      defaultValue: "Copy image",
      comment: "Automation step: copy the captured image"
    )
    static let stepUploadCopyLink = string(
      "automations.step.upload-copy-link",
      defaultValue: "Upload and copy link",
      comment: "Automation step: upload to cloud and copy the public link"
    )
    static let stepShowQuickAccess = string(
      "automations.step.show-quick-access",
      defaultValue: "Show Quick Access",
      comment: "Automation step: show the Quick Access card"
    )
    static let stepOpenAnnotate = string(
      "automations.step.open-annotate",
      defaultValue: "Open in Annotate",
      comment: "Automation step: open the capture in Annotate"
    )
    static let stepNotify = string(
      "automations.step.notify",
      defaultValue: "Show a notification",
      comment: "Automation step: show a notification with the result"
    )
    static let linkFormatURL = string(
      "automations.link-format.url",
      defaultValue: "URL",
      comment: "Copied link format: plain URL"
    )
    static let linkFormatMarkdown = string(
      "automations.link-format.markdown",
      defaultValue: "Markdown",
      comment: "Copied link format: Markdown image"
    )
    static let resultImageCopied = string(
      "automations.result.image-copied",
      defaultValue: "Image copied to the clipboard.",
      comment: "Automation notification: the image is on the clipboard"
    )
    static let resultLinkCopied = string(
      "automations.result.link-copied",
      defaultValue: "Link copied to the clipboard.",
      comment: "Automation notification: the uploaded link is on the clipboard"
    )
    static let resultLinkReady = string(
      "automations.result.link-ready",
      defaultValue: "Uploaded. The link is in Cloud Uploads.",
      comment: "Automation notification: uploaded, but the clipboard changed meanwhile so the link was not copied"
    )
    static let resultUploadFailed = string(
      "automations.result.upload-failed",
      defaultValue: "Upload failed. The image is on the clipboard; retry from Quick Access.",
      comment: "Automation notification: upload failed, image copied instead"
    )
    static let resultCloudNotConfigured = string(
      "automations.result.cloud-not-configured",
      defaultValue: "Cloud upload isn’t set up. The image is on the clipboard.",
      comment: "Automation notification: cloud upload not set up, image copied instead"
    )
    static let resultCaptureSaved = string(
      "automations.result.capture-saved",
      defaultValue: "Capture saved.",
      comment: "Automation notification: capture saved, nothing copied"
    )
    static let heroSubtitle = string(
      "automations.hero-subtitle",
      defaultValue: "Capture and share with one shortcut. Each automation captures, then runs its steps in order.",
      comment: "Automations settings page subtitle"
    )
    static let listTitle = string(
      "automations.list-title",
      defaultValue: "Your Automations",
      comment: "Automations settings section title"
    )
    static let listDescription = string(
      "automations.list-description",
      defaultValue: "Give an automation a shortcut to run it. Its captures skip the after-capture actions and follow its steps instead.",
      comment: "Automations settings section description"
    )
    static let newButton = string(
      "automations.new-button",
      defaultValue: "New Automation",
      comment: "Button: create a new automation"
    )
    static let restorePresets = string(
      "automations.restore-presets",
      defaultValue: "Restore Built-in Automations",
      comment: "Button: re-add deleted built-in automations"
    )
    static func limitReached(_ count: Int) -> String {
      format(
        "automations.limit-reached",
        defaultValue: "You can have up to %d automations.",
        comment: "Shown when the automation limit is reached; %d is the limit",
        count
      )
    }
    static let emptyList = string(
      "automations.empty",
      defaultValue: "No automations yet.",
      comment: "Automations list placeholder"
    )
    static let duplicate = string(
      "automations.duplicate",
      defaultValue: "Duplicate",
      comment: "Menu item: duplicate an automation"
    )
    static let moreActions = string(
      "automations.more-actions",
      defaultValue: "More actions",
      comment: "Accessibility label of the automation row menu button"
    )
    static func deleteConfirmTitle(_ name: String) -> String {
      format(
        "automations.delete-confirm-title",
        defaultValue: "Delete “%@”?",
        comment: "Delete confirmation title; %@ is the automation name",
        name
      )
    }
    static let deleteConfirmMessage = string(
      "automations.delete-confirm-message",
      defaultValue: "The automation and its shortcut will be removed.",
      comment: "Delete confirmation message"
    )
    static let cloudWarning = string(
      "automations.cloud-warning",
      defaultValue: "Cloud upload isn’t set up, so this copies the image instead.",
      comment: "Warning on automations that upload while cloud upload is not set up"
    )
    static let openCloudSettings = string(
      "automations.open-cloud-settings",
      defaultValue: "Set Up Cloud…",
      comment: "Button: open the Cloud settings page"
    )
    static let unsupported = string(
      "automations.unsupported",
      defaultValue: "Made with a newer version of Snapzy. Update to run it.",
      comment: "Shown on an automation made by a newer Snapzy that this version cannot run"
    )
    static let noSteps = string(
      "automations.no-steps",
      defaultValue: "No steps",
      comment: "Automation row summary when no step is enabled"
    )
    static let editorNewTitle = string(
      "automations.editor.title-new",
      defaultValue: "New Automation",
      comment: "Automation editor title when creating"
    )
    static let editorEditTitle = string(
      "automations.editor.title-edit",
      defaultValue: "Edit Automation",
      comment: "Automation editor title when editing"
    )
    static let nameLabel = string(
      "automations.editor.name",
      defaultValue: "Name",
      comment: "Automation editor field label"
    )
    static let saveToFolderLabel = string(
      "automations.editor.save-to-folder",
      defaultValue: "Save to export folder",
      comment: "Automation editor toggle"
    )
    static let saveToFolderDescription = string(
      "automations.editor.save-to-folder-description",
      defaultValue: "When off, the capture stays in Snapzy’s temporary folder, like turning off Save after capture.",
      comment: "Automation editor toggle description"
    )
    static let stepsLabel = string(
      "automations.editor.steps",
      defaultValue: "Then",
      comment: "Automation editor section title for the ordered steps"
    )
    static let stepsDescription = string(
      "automations.editor.steps-description",
      defaultValue: "Steps run in this order. Copy image runs before the upload, so a failed upload still leaves the image to paste.",
      comment: "Automation editor steps section description"
    )
    static let linkFormatLabel = string(
      "automations.editor.link-format",
      defaultValue: "Link format",
      comment: "Automation editor picker label for the copied link format"
    )
    static let shortcutLabel = string(
      "automations.editor.shortcut",
      defaultValue: "Shortcut",
      comment: "Automation editor shortcut row label"
    )
    static func shortcutUsedByAutomation(_ name: String) -> String {
      format(
        "automations.validation.used-by",
        defaultValue: "Already used by the “%@” automation",
        comment: "Shortcut conflict with an automation; %@ is its name",
        name
      )
    }
    static let shortcutNeedsModifier = string(
      "automations.validation.needs-modifier",
      defaultValue: "Add a modifier key such as ⌘, ⌥, ⌃ or ⇧.",
      comment: "Automation shortcut must include a modifier key"
    )

    // MARK: - Milestone 2: triggers, external invocation, launch rejections

    static let resultFileCopied = string(
      "automations.result.file-copied",
      defaultValue: "File copied to the clipboard.",
      comment: "Automation notification: a video or several files were copied to the clipboard"
    )
    static let sourceLabel = string(
      "automations.editor.source",
      defaultValue: "Source",
      comment: "Automation editor picker label: what the automation runs on (a capture mode or a file)"
    )
    static let sourceInput = string(
      "automations.source.input",
      defaultValue: "Run on a File",
      comment: "Automation source option: run on a file handed in by Quick Access, History, the CLI or Shortcuts"
    )
    static let sourceInputShort = string(
      "automations.source.input-short",
      defaultValue: "File",
      comment: "Automation row summary for an automation that runs on a file"
    )
    static let sourceInputDescription = string(
      "automations.source.input-description",
      defaultValue: "Runs on the file it’s given: from a Quick Access card, History, the command line or Shortcuts. It has no shortcut because there’s nothing to capture.",
      comment: "Automation editor: explains the Run on a File source"
    )
    static let duplicateNameWarning = string(
      "automations.editor.duplicate-name",
      defaultValue: "Another automation has this name. Use the id to run it from the command line or a URL.",
      comment: "Automation editor warning: another automation has the same name"
    )
    static let showInLabel = string(
      "automations.show-in.title",
      defaultValue: "Show In",
      comment: "Automation editor section title: where the automation is listed"
    )
    static let showInMenuBar = string(
      "automations.show-in.menu-bar",
      defaultValue: "Menu bar",
      comment: "Automation editor toggle: list in the menu bar Automations submenu"
    )
    static let showInQuickAccess = string(
      "automations.show-in.quick-access",
      defaultValue: "Quick Access card menu",
      comment: "Automation editor toggle: list in a Quick Access card's Run Automation menu"
    )
    static let showInHistory = string(
      "automations.show-in.history",
      defaultValue: "History item menu",
      comment: "Automation editor toggle: list in a History item's Run Automation menu"
    )
    static let showInDescription = string(
      "automations.show-in.description",
      defaultValue: "From Quick Access and History, it runs on that item’s file instead of capturing.",
      comment: "Automation editor footer for the Show In section of a capturing automation"
    )
    static let showInInputDescription = string(
      "automations.show-in.input-description",
      defaultValue: "Runs on the selected item’s file. The menu bar needs an automation that captures.",
      comment: "Automation editor footer for the Show In section of a Run on a File automation"
    )
    static let externalLabel = string(
      "automations.external.title",
      defaultValue: "Run from Other Apps",
      comment: "Automation editor section title: run from the URL scheme, command line and Shortcuts"
    )
    static let externalToggle = string(
      "automations.external.toggle",
      defaultValue: "Allow URL scheme, command line and Shortcuts",
      comment: "Automation editor toggle: allow URL scheme, command line and Shortcuts to run this automation"
    )
    static let externalDescription = string(
      "automations.external.description",
      defaultValue: "Other apps and scripts can start this automation, including capturing your screen and uploading. Turn this on only for automations you want to start that way.",
      comment: "Automation editor: risk explanation under the external invocation toggle"
    )
    static let externalURLLabel = string(
      "automations.external.url",
      defaultValue: "URL",
      comment: "Label above the copyable snapzy:// URL that runs the automation"
    )
    static let externalCLILabel = string(
      "automations.external.cli",
      defaultValue: "Command line",
      comment: "Label above the copyable command line that runs the automation"
    )
    static let externalURLSchemeOff = string(
      "automations.external.url-scheme-off",
      defaultValue: "The URL scheme is turned off.",
      comment: "Automation editor note: the global URL scheme setting is off"
    )
    static let openAdvancedSettings = string(
      "automations.external.open-advanced",
      defaultValue: "Open Advanced Settings…",
      comment: "Button: open Settings → Advanced"
    )
    static let copyToClipboard = string(
      "automations.copy",
      defaultValue: "Copy",
      comment: "Button / accessibility label: copy the URL or command to the clipboard"
    )
    static let externalBadge = string(
      "automations.external.badge",
      defaultValue: "Can be run from other apps",
      comment: "Help text of the badge on automations that other apps can run"
    )
    static let menuTitle = string(
      "automations.menu.title",
      defaultValue: "Automations",
      comment: "Menu bar submenu title listing automations"
    )
    static let manageAutomations = string(
      "automations.menu.manage",
      defaultValue: "Manage Automations…",
      comment: "Menu item: open Settings → Automations"
    )
    static let runAutomationMenu = string(
      "automations.menu.run",
      defaultValue: "Run Automation",
      comment: "Context menu (Quick Access card, History item): submenu of automations to run on the item"
    )
    static let intentCancelled = string(
      "automations.intent.cancelled",
      defaultValue: "The capture was cancelled.",
      comment: "Shortcuts error: the automation's capture was cancelled"
    )
    static let rejectionNotFound = string(
      "automations.rejection.not-found",
      defaultValue: "No automation matches that name or id.",
      comment: "Automation could not be started: no automation matches"
    )
    static let rejectionAmbiguous = string(
      "automations.rejection.ambiguous",
      defaultValue: "Several automations have that name. Use the automation’s id instead.",
      comment: "Automation could not be started: several automations share the name"
    )
    static let rejectionDisabled = string(
      "automations.rejection.disabled",
      defaultValue: "This automation is turned off.",
      comment: "Automation could not be started: it is turned off"
    )
    static let rejectionExternalNotAllowed = string(
      "automations.rejection.external-not-allowed",
      defaultValue: "This automation can’t be run from other apps. Allow it in Settings → Automations.",
      comment: "Automation could not be started: it does not allow other apps"
    )
    static let rejectionURLSchemeDisabled = string(
      "automations.rejection.url-scheme-disabled",
      defaultValue: "The Snapzy URL scheme is turned off in Settings → Advanced.",
      comment: "Automation could not be started: the URL scheme is off"
    )
    static let rejectionUnsupportedSource = string(
      "automations.rejection.unsupported-source",
      defaultValue: "This automation was made with a newer version of Snapzy.",
      comment: "Automation could not be started: made by a newer Snapzy"
    )
    static let rejectionNeedsFile = string(
      "automations.rejection.needs-file",
      defaultValue: "This automation runs on a file. Pass a file to run it.",
      comment: "Automation could not be started: it runs on a file and none was given"
    )
    static func rejectionUnsupportedFile(_ value: String) -> String {
      format(
        "automations.rejection.unsupported-file",
        defaultValue: "“%@” isn’t an image, video or GIF.",
        comment: "Automation could not be started: the file is not an image, video or GIF; %@ is the file name",
        value
      )
    }
    static let rejectionNoStepAcceptsFile = string(
      "automations.rejection.no-step-accepts-file",
      defaultValue: "None of this automation’s steps work with this kind of file.",
      comment: "Automation could not be started: none of its steps work with this kind of file"
    )
    static func rejectionFileMissing(_ value: String) -> String {
      format(
        "automations.rejection.file-missing",
        defaultValue: "“%@” wasn’t found.",
        comment: "Automation could not be started: the file does not exist; %@ is the file name",
        value
      )
    }
    static let rejectionPermissionRequired = string(
      "automations.rejection.permission-required",
      defaultValue: "Snapzy needs Screen Recording permission to capture.",
      comment: "Automation could not be started: Screen Recording permission missing"
    )
    static let rejectionCaptureInProgress = string(
      "automations.rejection.capture-in-progress",
      defaultValue: "Another capture is in progress.",
      comment: "Automation could not be started: another capture is running"
    )
  }
}
