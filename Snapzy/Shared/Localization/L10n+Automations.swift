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
    static let captureLabel = string(
      "automations.editor.capture",
      defaultValue: "Capture",
      comment: "Automation editor field label: which capture mode to start"
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
  }
}
