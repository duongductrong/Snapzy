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

    // MARK: - Milestone 3: transform & deliver steps, editor, activity

    static let presetDocsShot = string(
      "automations.preset.docs-shot",
      defaultValue: "Docs Shot",
      comment: "Built-in automation: capture a window, resize, convert to WebP, save to a docs folder and copy Markdown"
    )
    static let presetGIFShare = string(
      "automations.preset.gif-share",
      defaultValue: "GIF Share",
      comment: "Built-in automation: record an area as a GIF, upload it and copy the link"
    )
    static let presetTranslateSnip = string(
      "automations.preset.translate-snip",
      defaultValue: "Translate Snip",
      comment: "Built-in automation: capture an area, recognize text, translate it and copy the translation"
    )
    static let modeRecordingArea = string(
      "automations.mode.recording-area",
      defaultValue: "Record Area",
      comment: "Automation source: record a screen area"
    )
    static let modeRecordingWindow = string(
      "automations.mode.recording-window",
      defaultValue: "Record Window",
      comment: "Automation source: record a window"
    )
    static let modeScrolling = string(
      "automations.mode.scrolling",
      defaultValue: "Scrolling Capture",
      comment: "Automation source: scrolling (long) screenshot"
    )
    static let recordingOutputLabel = string(
      "automations.recording-output.label",
      defaultValue: "Recording output",
      comment: "Editor picker: whether a recording source hands the steps a video or a GIF"
    )
    static let recordingOutputVideo = string(
      "automations.recording-output.video",
      defaultValue: "Video",
      comment: "Recording output option: video file"
    )
    static let recordingOutputGIF = string(
      "automations.recording-output.gif",
      defaultValue: "GIF",
      comment: "Recording output option: animated GIF"
    )
    static let sourceScreenshotSection = string(
      "automations.source.screenshot-section",
      defaultValue: "Screenshot",
      comment: "Source menu section header for screenshot sources"
    )
    static let sourceRecordingSection = string(
      "automations.source.recording-section",
      defaultValue: "Recording",
      comment: "Source menu section header for recording sources"
    )
    static let sourceClipboard = string(
      "automations.source.clipboard",
      defaultValue: "Clipboard Image",
      comment: "Automation source: the image currently on the clipboard"
    )
    static let sourceClipboardDescription = string(
      "automations.source.clipboard-description",
      defaultValue: "Runs the steps on the image currently on the clipboard. It is saved as a new capture first.",
      comment: "Editor caption for the clipboard image source"
    )
    static let stepApplyCanvasPreset = string(
      "automations.step.apply-canvas-preset",
      defaultValue: "Apply canvas preset",
      comment: "Automation step: apply an Annotate canvas preset (background, padding, shadow)"
    )
    static let stepResize = string(
      "automations.step.resize",
      defaultValue: "Resize",
      comment: "Automation step: scale the image down"
    )
    static let stepConvert = string(
      "automations.step.convert",
      defaultValue: "Convert / optimize",
      comment: "Automation step: re-encode the image (format, quality, file size)"
    )
    static let stepStripMetadata = string(
      "automations.step.strip-metadata",
      defaultValue: "Remove metadata",
      comment: "Automation step: drop EXIF/GPS and other metadata from the image"
    )
    static let stepOCR = string(
      "automations.step.ocr",
      defaultValue: "Recognize text",
      comment: "Automation step: OCR the image into text"
    )
    static let stepTranslate = string(
      "automations.step.translate",
      defaultValue: "Translate text",
      comment: "Automation step: translate recognized text"
    )
    static let stepConvertToGIF = string(
      "automations.step.convert-to-gif",
      defaultValue: "Convert to GIF",
      comment: "Automation step: turn a video into an animated GIF"
    )
    static let stepUpload = string(
      "automations.step.upload",
      defaultValue: "Upload",
      comment: "Automation step: upload the file to the configured cloud"
    )
    static let stepCopyLink = string(
      "automations.step.copy-link",
      defaultValue: "Copy link",
      comment: "Automation step: copy the uploaded link (URL, Markdown, HTML, …)"
    )
    static let stepCopyText = string(
      "automations.step.copy-text",
      defaultValue: "Copy text",
      comment: "Automation step: copy text built from a template"
    )
    static let stepSaveToFolder = string(
      "automations.step.save-to-folder",
      defaultValue: "Save to folder",
      comment: "Automation step: save a copy of the file into a chosen folder"
    )
    static let stepReveal = string(
      "automations.step.reveal",
      defaultValue: "Show in Finder",
      comment: "Automation step: reveal the file in Finder"
    )
    static let stepPin = string(
      "automations.step.pin",
      defaultValue: "Pin to screen",
      comment: "Automation step: pin the image as a floating window"
    )
    static let stepEnabled = string(
      "automations.step.enabled",
      defaultValue: "Step enabled",
      comment: "Accessibility label of a step's on/off switch"
    )
    static let describeCanvasPreset = string(
      "automations.describe.canvas-preset",
      defaultValue: "Adds the background, padding and shadow of an Annotate canvas preset.",
      comment: "Inspector description of the Apply canvas preset step"
    )
    static let describeResize = string(
      "automations.describe.resize",
      defaultValue: "Scales the image down. Images are never enlarged.",
      comment: "Inspector description of the Resize step"
    )
    static let describeConvert = string(
      "automations.describe.convert",
      defaultValue: "Re-encodes the image with a format, quality and size limit, or a Quick Access Optimize preset.",
      comment: "Inspector description of the Convert step"
    )
    static let describeStripMetadata = string(
      "automations.describe.strip-metadata",
      defaultValue: "Removes EXIF, GPS and other metadata. The color profile is kept.",
      comment: "Inspector description of the Remove metadata step"
    )
    static let describeOCR = string(
      "automations.describe.ocr",
      defaultValue: "Recognizes the text in the image so later steps can copy or translate it.",
      comment: "Inspector description of the Recognize text step"
    )
    static let describeTranslate = string(
      "automations.describe.translate",
      defaultValue: "Translates the recognized text with the engine chosen for Snip to Translate.",
      comment: "Inspector description of the Translate step"
    )
    static let describeConvertToGIF = string(
      "automations.describe.convert-to-gif",
      defaultValue: "Turns a recording into an animated GIF.",
      comment: "Inspector description of the Convert to GIF step"
    )
    static let describeUpload = string(
      "automations.describe.upload",
      defaultValue: "Uploads the file to your cloud. Add Copy link to put the link on the clipboard.",
      comment: "Inspector description of the Upload step"
    )
    static let describeCopyLink = string(
      "automations.describe.copy-link",
      defaultValue: "Copies the uploaded link in the format you pick.",
      comment: "Inspector description of the Copy link step"
    )
    static let describeCopyText = string(
      "automations.describe.copy-text",
      defaultValue: "Copies text built from a template, such as the recognized text or a Markdown image link.",
      comment: "Inspector description of the Copy text step"
    )
    static let describeSaveToFolder = string(
      "automations.describe.save-to-folder",
      defaultValue: "Saves a copy of the result. The original capture is never changed.",
      comment: "Inspector description of the Save to folder step"
    )
    static let describeReveal = string(
      "automations.describe.reveal",
      defaultValue: "Shows the saved file (or the capture) in Finder.",
      comment: "Inspector description of the Show in Finder step"
    )
    static let describePin = string(
      "automations.describe.pin",
      defaultValue: "Pins the image on screen as a floating window.",
      comment: "Inspector description of the Pin step"
    )
    static let describeNotify = string(
      "automations.describe.notify",
      defaultValue: "Shows a notification with the result when the run ends.",
      comment: "Inspector description of the Notify step"
    )
    static let describeCopyImage = string(
      "automations.describe.copy-image",
      defaultValue: "Copies the image, or the file for recordings and GIFs.",
      comment: "Inspector description of the Copy image step"
    )
    static let triggersRow = string(
      "automations.editor.triggers-row",
      defaultValue: "Source & Triggers",
      comment: "Editor list row that shows source options and triggers"
    )
    static let inspectorEmpty = string(
      "automations.editor.inspector-empty",
      defaultValue: "Select a step to edit it.",
      comment: "Editor placeholder when nothing is selected"
    )
    static let addStep = string(
      "automations.editor.add-step",
      defaultValue: "Add Step",
      comment: "Editor button / menu that adds a step"
    )
    static let moveUp = string(
      "automations.editor.move-up",
      defaultValue: "Move Up",
      comment: "Editor action: move the selected step up"
    )
    static let moveDown = string(
      "automations.editor.move-down",
      defaultValue: "Move Down",
      comment: "Editor action: move the selected step down"
    )
    static let groupTransform = string(
      "automations.editor.group-transform",
      defaultValue: "Transform",
      comment: "Add Step menu section: steps that change the file"
    )
    static let groupDeliver = string(
      "automations.editor.group-deliver",
      defaultValue: "Deliver",
      comment: "Add Step menu section: steps that copy, save or share"
    )
    static let groupControl = string(
      "automations.editor.group-control",
      defaultValue: "Control",
      comment: "Add Step menu section: notification and flow steps"
    )
    static let failureLabel = string(
      "automations.editor.failure-label",
      defaultValue: "If this step fails",
      comment: "Picker: what happens when a step fails"
    )
    static let failureStop = string(
      "automations.editor.failure-stop",
      defaultValue: "Stop",
      comment: "Failure policy: stop the run"
    )
    static let failureContinue = string(
      "automations.editor.failure-continue",
      defaultValue: "Continue",
      comment: "Failure policy: run the next steps anyway"
    )
    static let saveBlockedHelp = string(
      "automations.editor.save-blocked-help",
      defaultValue: "A step has nothing to work on. Fix the marked steps to save.",
      comment: "Tooltip on the disabled Save button"
    )
    static func issuesSummary(_ a0: Int, _ a1: String) -> String {
      format(
        "automations.editor.issues-summary",
        defaultValue: "%1$d issue(s): %2$@",
        comment: "Editor footer; %1$d is the number of issues, %2$@ the first issue",
        a0, a1
      )
    }
    static let issueNeedsText = string(
      "automations.issue.needs-text",
      defaultValue: "Needs text: add Recognize text before this step.",
      comment: "Validation issue: step needs OCR text first"
    )
    static let issueNeedsLink = string(
      "automations.issue.needs-link",
      defaultValue: "Needs a link: add Upload before this step.",
      comment: "Validation issue: step needs an uploaded link first"
    )
    static let issueNeedsVideo = string(
      "automations.issue.needs-video",
      defaultValue: "Needs a video: use a video recording source.",
      comment: "Validation issue: step needs a video"
    )
    static let issueNeedsImage = string(
      "automations.issue.needs-image",
      defaultValue: "Needs an image: this source gives a video or GIF.",
      comment: "Validation issue: step needs an image"
    )
    static let issueNeedsFile = string(
      "automations.issue.needs-file",
      defaultValue: "Needs a file to work on.",
      comment: "Validation issue: step needs a file"
    )
    static let issueFolder = string(
      "automations.issue.folder",
      defaultValue: "Choose a folder",
      comment: "Validation issue / placeholder: Save to folder has no folder"
    )
    static let issueTemplate = string(
      "automations.issue.template",
      defaultValue: "The template is empty.",
      comment: "Validation issue: an empty text or link template"
    )
    static let issueCanvasPreset = string(
      "automations.issue.canvas-preset",
      defaultValue: "The canvas preset was deleted.",
      comment: "Validation issue: the chosen canvas preset no longer exists"
    )
    static let needsSetupBadge = string(
      "automations.needs-setup",
      defaultValue: "Needs setup",
      comment: "Settings row badge: a step still needs a setting such as a folder"
    )
    static let setUpButton = string(
      "automations.set-up",
      defaultValue: "Set Up…",
      comment: "Settings row button that opens the editor to finish setup"
    )
    static let tokensHelp = string(
      "automations.tokens.help",
      defaultValue: "Template tokens",
      comment: "Popover listing {tokens} usable in templates"
    )
    static let templateLabel = string(
      "automations.template.label",
      defaultValue: "Template",
      comment: "Text field label for a text/link template"
    )
    static let previewLabel = string(
      "automations.template.preview",
      defaultValue: "Preview",
      comment: "Label of a template preview"
    )
    static let previewSampleText = string(
      "automations.template.sample-text",
      defaultValue: "Recognized text",
      comment: "Sample value shown for {text} in template previews"
    )
    static let textTemplateFooter = string(
      "automations.template.text-footer",
      defaultValue: "{text} is the recognized or translated text. Use {saved.relativePath} after Save to folder for Markdown image links.",
      comment: "Footer of the Copy text template field; keep tokens in braces unchanged"
    )
    static let linkStyleCustom = string(
      "automations.link-style.custom",
      defaultValue: "Custom",
      comment: "Link format option: user-written template"
    )
    static let canvasPresetLabel = string(
      "automations.canvas-preset.label",
      defaultValue: "Preset",
      comment: "Picker label for the canvas preset"
    )
    static let canvasPresetDefault = string(
      "automations.canvas-preset.default",
      defaultValue: "Default preset",
      comment: "Canvas preset option: whichever preset is marked default"
    )
    static let resizeModeLabel = string(
      "automations.resize.mode",
      defaultValue: "Resize by",
      comment: "Segmented picker label: max dimension or percentage"
    )
    static let resizeModeMax = string(
      "automations.resize.mode-max",
      defaultValue: "Longest edge",
      comment: "Resize mode: limit the longest edge in pixels"
    )
    static let resizeModePercent = string(
      "automations.resize.mode-percent",
      defaultValue: "Percentage",
      comment: "Resize mode: scale by a percentage"
    )
    static let resizeMaxLabel = string(
      "automations.resize.max-label",
      defaultValue: "Longest edge (px)",
      comment: "Text field label: max pixel size of the longest edge"
    )
    static let resizePercentLabel = string(
      "automations.resize.percent-label",
      defaultValue: "Scale",
      comment: "Stepper label for the resize percentage"
    )
    static let resizeNoUpscale = string(
      "automations.resize.no-upscale",
      defaultValue: "Smaller images are left as they are.",
      comment: "Resize footer: images are never enlarged"
    )
    static func resizeSummaryMax(_ a0: Int) -> String {
      format(
        "automations.resize.summary-max",
        defaultValue: "Max %d px",
        comment: "Step summary for Resize; %d is the max pixel size",
        a0
      )
    }
    static let convertPresetLabel = string(
      "automations.convert.preset",
      defaultValue: "Settings",
      comment: "Picker: custom settings or a Quick Access Optimize preset"
    )
    static let convertCustom = string(
      "automations.convert.custom",
      defaultValue: "Custom",
      comment: "Convert option: use the settings below"
    )
    static let convertFormatLabel = string(
      "automations.convert.format",
      defaultValue: "Format",
      comment: "Picker label for the output format"
    )
    static let convertQualityLabel = string(
      "automations.convert.quality",
      defaultValue: "Quality",
      comment: "Slider label for lossy quality"
    )
    static let convertMaxSizeLabel = string(
      "automations.convert.max-size",
      defaultValue: "File size limit",
      comment: "Picker label for the maximum file size"
    )
    static let convertNoLimit = string(
      "automations.convert.no-limit",
      defaultValue: "No limit",
      comment: "File size limit option: none"
    )
    static let ocrIncludeQR = string(
      "automations.ocr.include-qr",
      defaultValue: "Include QR codes",
      comment: "Toggle: also decode QR codes in the image"
    )
    static let ocrIncludesQR = string(
      "automations.ocr.includes-qr",
      defaultValue: "With QR codes",
      comment: "Step summary when the OCR step includes QR codes"
    )
    static let translateTargetLabel = string(
      "automations.translate.target",
      defaultValue: "Translate to",
      comment: "Picker label for the target language"
    )
    static let translateDefaultTarget = string(
      "automations.translate.default-target",
      defaultValue: "Snip to Translate language",
      comment: "Target option: same as the Snip to Translate setting"
    )
    static let translateEngineNote = string(
      "automations.translate.engine-note",
      defaultValue: "Uses Apple Translation on macOS 15 or later, or the endpoint chosen for Snip to Translate.",
      comment: "Footer of the Translate step settings"
    )
    static let gifFPSLabel = string(
      "automations.gif.fps",
      defaultValue: "Frame rate",
      comment: "Picker label for GIF frames per second"
    )
    static let gifWidthLabel = string(
      "automations.gif.width",
      defaultValue: "Max width",
      comment: "Picker label for the GIF max width"
    )
    static let folderLabel = string(
      "automations.folder.label",
      defaultValue: "Folder",
      comment: "Label of the destination folder row"
    )
    static let folderExport = string(
      "automations.folder.export",
      defaultValue: "Export folder",
      comment: "Folder option: the export folder from Settings → General"
    )
    static let chooseFolderButton = string(
      "automations.folder.choose-button",
      defaultValue: "Change",
      comment: "Menu button to pick the destination folder"
    )
    static let chooseFolderMenuItem = string(
      "automations.folder.choose-menu-item",
      defaultValue: "Choose Folder…",
      comment: "Menu item that opens a folder picker"
    )
    static let chooseFolderPrompt = string(
      "automations.folder.choose-prompt",
      defaultValue: "Use Folder",
      comment: "Open panel confirm button for picking a folder"
    )
    static let nameTemplateLabel = string(
      "automations.folder.name-template",
      defaultValue: "File name",
      comment: "Text field: file name template without extension"
    )
    static let conflictLabel = string(
      "automations.folder.conflict",
      defaultValue: "If the file exists",
      comment: "Picker: what to do when a file with that name exists"
    )
    static let conflictUniquify = string(
      "automations.folder.conflict-uniquify",
      defaultValue: "Keep both",
      comment: "Conflict option: add a number to the new file"
    )
    static let conflictOverwrite = string(
      "automations.folder.conflict-overwrite",
      defaultValue: "Replace",
      comment: "Conflict option: replace the existing file"
    )
    static let resultCancelled = string(
      "automations.result.cancelled",
      defaultValue: "Cancelled",
      comment: "Run result: the user cancelled the run"
    )
    static let resultTextCopied = string(
      "automations.result.text-copied",
      defaultValue: "Text copied",
      comment: "Run result: text was copied"
    )
    static func resultSavedTo(_ a0: String) -> String {
      format(
        "automations.result.saved-to",
        defaultValue: "Saved %@",
        comment: "Run result; %@ is the saved file name",
        a0
      )
    }
    static func resultStepFailed(_ a0: String, _ a1: String) -> String {
      format(
        "automations.result.step-failed",
        defaultValue: "%1$@ failed: %2$@",
        comment: "Run result; %1$@ is the step name, %2$@ the reason",
        a0, a1
      )
    }
    static let errorCloudNotConfigured = string(
      "automations.error.cloud-not-configured",
      defaultValue: "Cloud upload is not configured",
      comment: "Step error: no cloud provider set up"
    )
    static let errorNoFile = string(
      "automations.error.no-file",
      defaultValue: "No file to work on",
      comment: "Step error: the step had no file"
    )
    static let errorNoText = string(
      "automations.error.no-text",
      defaultValue: "No text to work on",
      comment: "Step error: no recognized text"
    )
    static let errorNoLink = string(
      "automations.error.no-link",
      defaultValue: "No uploaded link",
      comment: "Step error: no link to copy"
    )
    static let errorNoTextFound = string(
      "automations.error.no-text-found",
      defaultValue: "No text found",
      comment: "Step error: OCR found no text"
    )
    static let errorCanvasPresetMissing = string(
      "automations.error.canvas-preset-missing",
      defaultValue: "The canvas preset no longer exists",
      comment: "Step error: canvas preset deleted"
    )
    static let errorRenderFailed = string(
      "automations.error.render-failed",
      defaultValue: "The image couldn’t be written",
      comment: "Step error: encoding or rendering failed"
    )
    static let errorFolderUnavailable = string(
      "automations.error.folder-unavailable",
      defaultValue: "Folder unavailable",
      comment: "Step error: the destination folder is missing or not accessible"
    )
    static let errorOptimizePresetMissing = string(
      "automations.error.optimize-preset-missing",
      defaultValue: "The Optimize preset no longer exists",
      comment: "Step error: optimize preset deleted"
    )
    static let errorPinFailed = string(
      "automations.error.pin-failed",
      defaultValue: "The image couldn’t be pinned",
      comment: "Step error: pin failed"
    )
    static let errorRetryFilesMissing = string(
      "automations.error.retry-files-missing",
      defaultValue: "The files of that run no longer exist.",
      comment: "Toast when Retry finds no input files"
    )
    static let errorTranslationNoTarget = string(
      "automations.error.translation-no-target",
      defaultValue: "Choose a target language for this step or for Snip to Translate",
      comment: "Step error: no translation target"
    )
    static let errorTranslationRequiresMacOS15 = string(
      "automations.error.translation-requires-macos15",
      defaultValue: "Apple Translation needs macOS 15. Choose a translation endpoint in Settings → Capture.",
      comment: "Step error: Apple Translation unavailable"
    )
    static let errorTranslationTimedOut = string(
      "automations.error.translation-timed-out",
      defaultValue: "Translation timed out. Download the language in System Settings → General → Language & Region → Translation Languages.",
      comment: "Step error: Apple Translation did not answer in time"
    )
    static let errorTranslationUnsupportedPair = string(
      "automations.error.translation-unsupported-pair",
      defaultValue: "Apple Translation can’t translate between these languages",
      comment: "Step error: unsupported language pair"
    )
    static let errorTranslationUnknownLanguage = string(
      "automations.error.translation-unknown-language",
      defaultValue: "The language of the text couldn’t be detected",
      comment: "Step error: source language unknown"
    )
    static let errorTranslationDownload = string(
      "automations.error.translation-download",
      defaultValue: "Download the language in System Settings → General → Language & Region → Translation Languages",
      comment: "Step error: language pack not installed"
    )
    static let warningPNGFallback = string(
      "automations.warning.png-fallback",
      defaultValue: "This Mac can’t write that format, so PNG is used.",
      comment: "Warning: encoder unavailable, PNG fallback"
    )
    static let warningFileSizeLimit = string(
      "automations.warning.file-size-limit",
      defaultValue: "The file is still larger than the size limit.",
      comment: "Warning: file size limit not met"
    )
    static let rejectionClipboardEmpty = string(
      "automations.rejection.clipboard-empty",
      defaultValue: "The clipboard holds no image.",
      comment: "Launch rejection: clipboard source without an image"
    )
    static let rejectionInvalidChain = string(
      "automations.rejection.invalid-chain",
      defaultValue: "A step of this automation has nothing to work on. Fix it in Settings → Automations.",
      comment: "Launch rejection: invalid step chain"
    )
    static let notificationRetry = string(
      "automations.notification.retry",
      defaultValue: "Retry",
      comment: "Notification button: run the automation again"
    )
    static let notificationOpenActivity = string(
      "automations.notification.open-activity",
      defaultValue: "Open Activity",
      comment: "Notification button: open the automation activity log"
    )
    static let notificationOpenLink = string(
      "automations.notification.open-link",
      defaultValue: "Open Link",
      comment: "Notification button: open the uploaded link"
    )
    static let pageAutomations = string(
      "automations.page.automations",
      defaultValue: "Automations",
      comment: "Settings segment: list of automations"
    )
    static let pageActivity = string(
      "automations.page.activity",
      defaultValue: "Activity",
      comment: "Settings segment: recent automation runs"
    )
    static let activityDescription = string(
      "automations.activity.description",
      defaultValue: "The last 100 runs with step timings. No images are stored; text is shortened.",
      comment: "Activity section description"
    )
    static let activityEnabled = string(
      "automations.activity.enabled",
      defaultValue: "Keep activity log",
      comment: "Toggle: record automation runs"
    )
    static let activityEmpty = string(
      "automations.activity.empty",
      defaultValue: "No runs yet.",
      comment: "Activity placeholder"
    )
    static let activityClear = string(
      "automations.activity.clear",
      defaultValue: "Clear Activity",
      comment: "Button that deletes the activity log"
    )
    static let activityRevealInput = string(
      "automations.activity.reveal-input",
      defaultValue: "Show Input",
      comment: "Activity action: reveal the run's input files"
    )
    static let activityRevealSaved = string(
      "automations.activity.reveal-saved",
      defaultValue: "Show Saved File",
      comment: "Activity action: reveal the saved file"
    )
    static let activityCopyLink = string(
      "automations.activity.copy-link",
      defaultValue: "Copy Link",
      comment: "Activity action: copy the run's link"
    )
    static let activityRunAgain = string(
      "automations.activity.run-again",
      defaultValue: "Run Again",
      comment: "Activity action: re-run on the same input"
    )
    static let outcomeSucceeded = string(
      "automations.outcome.succeeded",
      defaultValue: "Succeeded",
      comment: "Run outcome"
    )
    static let outcomePartial = string(
      "automations.outcome.partial",
      defaultValue: "Partly succeeded",
      comment: "Run outcome: a step failed but later steps ran"
    )
    static let outcomeFailed = string(
      "automations.outcome.failed",
      defaultValue: "Failed",
      comment: "Run outcome"
    )
    static let outcomeCancelled = string(
      "automations.outcome.cancelled",
      defaultValue: "Cancelled",
      comment: "Run outcome"
    )
    static let groupIntegrations = string(
      "automations.group.integrations",
      defaultValue: "Integrations",
      comment: "Step picker group: webhook, script, Shortcut, share, open in app"
    )
    static let stepWebhook = string(
      "automations.step.webhook",
      defaultValue: "Send Webhook",
      comment: "Step: send an HTTP request"
    )
    static let stepRunScript = string(
      "automations.step.run-script",
      defaultValue: "Run Shell Script",
      comment: "Step: run a shell script"
    )
    static let stepRunShortcut = string(
      "automations.step.run-shortcut",
      defaultValue: "Run Shortcut",
      comment: "Step: run an Apple Shortcut"
    )
    static let stepShareSheet = string(
      "automations.step.share-sheet",
      defaultValue: "Share",
      comment: "Step: open the share sheet / AirDrop"
    )
    static let stepOpenInApp = string(
      "automations.step.open-in-app",
      defaultValue: "Open in App",
      comment: "Step: open the file in another app"
    )
    static let describeWebhook = string(
      "automations.describe.webhook",
      defaultValue: "Sends an HTTP request, for example the link to a Slack or Discord channel.",
      comment: "Inspector description of the webhook step"
    )
    static let describeRunScript = string(
      "automations.describe.run-script",
      defaultValue: "Runs a shell script with the file and values as environment variables.",
      comment: "Inspector description of the script step"
    )
    static let describeRunShortcut = string(
      "automations.describe.run-shortcut",
      defaultValue: "Runs a shortcut from the Shortcuts app with the file, link or text.",
      comment: "Inspector description of the Shortcut step"
    )
    static let describeShareSheet = string(
      "automations.describe.share-sheet",
      defaultValue: "Opens the share menu or AirDrop with the file (or the link).",
      comment: "Inspector description of the share step"
    )
    static let describeOpenInApp = string(
      "automations.describe.open-in-app",
      defaultValue: "Opens the file in the app you choose.",
      comment: "Inspector description of the open in app step"
    )
    static let errorUploaderMissing = string(
      "automations.error.uploader-missing",
      defaultValue: "The custom uploader no longer exists.",
      comment: "Run error: upload step points at a deleted custom uploader"
    )
    static let errorCodeStepsDisabled = string(
      "automations.error.code-steps-disabled",
      defaultValue: "Script and Shortcut steps are turned off.",
      comment: "Run error"
    )
    static let errorInvalidWebhookURL = string(
      "automations.error.invalid-webhook-url",
      defaultValue: "The webhook URL must start with https://.",
      comment: "Run error"
    )
    static func errorHTTPStatus(_ status: Int) -> String {
      format(
        "automations.error.http-status",
        defaultValue: "The server answered HTTP %lld",
        comment: "Run error; %lld is the HTTP status code",
        status
      )
    }
    static func errorTimedOut(_ seconds: Int) -> String {
      format(
        "automations.error.timed-out",
        defaultValue: "Timed out after %lld s.",
        comment: "Run error; %lld is seconds",
        seconds
      )
    }
    static func errorExitStatus(_ status: Int) -> String {
      format(
        "automations.error.exit-status",
        defaultValue: "Exited with status %lld",
        comment: "Run error; %lld is the process exit status",
        status
      )
    }
    static func errorShortcutNotFound(_ name: String) -> String {
      format(
        "automations.error.shortcut-not-found",
        defaultValue: "Couldn’t find the shortcut “%@”.",
        comment: "Run error; %@ is the shortcut name",
        name
      )
    }
    static let errorShareUnavailable = string(
      "automations.error.share-unavailable",
      defaultValue: "This sharing service isn’t available for this item.",
      comment: "Run error"
    )
    static let errorShareBusy = string(
      "automations.error.share-busy",
      defaultValue: "Another share menu is already open.",
      comment: "Run error"
    )
    static func errorAppNotFound(_ name: String) -> String {
      format(
        "automations.error.app-not-found",
        defaultValue: "Couldn’t find the app “%@”.",
        comment: "Run error; %@ is the app name",
        name
      )
    }
    static let errorOutputFileInvalid = string(
      "automations.error.output-file-invalid",
      defaultValue: "The step didn’t produce a usable file.",
      comment: "Run error: script/Shortcut output file missing"
    )
    static let errorScriptEmpty = string(
      "automations.error.script-empty",
      defaultValue: "The script is empty.",
      comment: "Run error"
    )
    static func errorWebhookNoLink(_ path: String) -> String {
      format(
        "automations.error.webhook-no-link",
        defaultValue: "The response has no link at “%@”.",
        comment: "Run error; %@ is a JSON path",
        path
      )
    }
    static let issueUploader = string(
      "automations.issue.uploader",
      defaultValue: "Choose a custom uploader",
      comment: "Step needs setup"
    )
    static let issueWebhookURL = string(
      "automations.issue.webhook-url",
      defaultValue: "Enter an https:// URL",
      comment: "Step needs setup"
    )
    static let issueScript = string(
      "automations.issue.script",
      defaultValue: "Write a script",
      comment: "Step needs setup"
    )
    static let issueShortcut = string(
      "automations.issue.shortcut",
      defaultValue: "Choose a shortcut",
      comment: "Step needs setup"
    )
    static let issueApp = string(
      "automations.issue.app",
      defaultValue: "Choose an app",
      comment: "Step needs setup"
    )
    static func issueSecret(_ name: String) -> String {
      format(
        "automations.issue.secret",
        defaultValue: "Add the secret “%@”",
        comment: "Step needs setup; %@ is a secret name",
        name
      )
    }
    static let rejectionNeedsReview = string(
      "automations.rejection.needs-review",
      defaultValue: "This automation was imported with network or script steps. Open it and save it to allow it to run.",
      comment: "Launch refused"
    )
    static let rejectionCodeStepsDisabled = string(
      "automations.rejection.code-steps-disabled",
      defaultValue: "This automation runs a script or Shortcut, and those steps are turned off in Settings → Automations.",
      comment: "Launch refused"
    )
    static let rejectionExternalCode = string(
      "automations.rejection.external-code",
      defaultValue: "This automation runs a script and can’t be started from another app.",
      comment: "Launch refused (URL scheme / Shortcuts)"
    )
    static let secretErrorInvalidName = string(
      "automations.secret.error.invalid-name",
      defaultValue: "Use letters, digits, “_”, “-” or “.” (up to 64 characters).",
      comment: "Secret name validation"
    )
    static let secretErrorDuplicate = string(
      "automations.secret.error.duplicate",
      defaultValue: "A secret with this name already exists.",
      comment: "Secret name validation"
    )
    static let secretErrorEmptyValue = string(
      "automations.secret.error.empty-value",
      defaultValue: "Enter a value.",
      comment: "Secret value validation"
    )
    static func secretErrorLimit(_ limit: Int) -> String {
      format(
        "automations.secret.error.limit",
        defaultValue: "You can store up to %lld secrets.",
        comment: "Secret limit; %lld is the limit",
        limit
      )
    }
    static func secretErrorNotFound(_ name: String) -> String {
      format(
        "automations.secret.error.not-found",
        defaultValue: "There is no secret named “%@”.",
        comment: "Run/validation error; %@ is a secret name",
        name
      )
    }
    static let shareServicePicker = string(
      "automations.share-service.picker",
      defaultValue: "Share Menu",
      comment: "Share step service: system share picker"
    )
    static let shareServiceMessages = string(
      "automations.share-service.messages",
      defaultValue: "Messages",
      comment: "Share step service (the Messages app)"
    )
    static let shareServiceMail = string(
      "automations.share-service.mail",
      defaultValue: "Mail",
      comment: "Share step service (the Mail app)"
    )
    static let timeoutLabel = string(
      "automations.inspector.timeout",
      defaultValue: "Timeout",
      comment: "Inspector: request / process timeout"
    )
    static func secondsValue(_ seconds: Int) -> String {
      format(
        "automations.inspector.seconds",
        defaultValue: "%lld s",
        comment: "Duration in seconds; %lld is the number",
        seconds
      )
    }
    static let outputLabel = string(
      "automations.inspector.output",
      defaultValue: "Output",
      comment: "Inspector: what a script/Shortcut output becomes"
    )
    static let outputIgnore = string(
      "automations.inspector.output.ignore",
      defaultValue: "Ignore",
      comment: "Output option"
    )
    static let outputText = string(
      "automations.inspector.output.text",
      defaultValue: "Text → {text}",
      comment: "Output option; {text} is a token, keep it"
    )
    static let outputLink = string(
      "automations.inspector.output.link",
      defaultValue: "Link → {link} (first line)",
      comment: "Output option; {link} is a token, keep it"
    )
    static let outputFileFromScript = string(
      "automations.inspector.output.file-path",
      defaultValue: "File (path on the last line)",
      comment: "Script output option"
    )
    static let outputFile = string(
      "automations.inspector.output.file",
      defaultValue: "File",
      comment: "Shortcut output / input option"
    )
    static let codeStepsOffBanner = string(
      "automations.inspector.code-off",
      defaultValue: "Script and Shortcut steps are off. This step won’t run until you allow them.",
      comment: "Inspector banner for script/Shortcut steps"
    )
    static let allowInSettings = string(
      "automations.inspector.allow-in-settings",
      defaultValue: "Allow…",
      comment: "Button opening the setting that allows script steps"
    )
    static let insertSecret = string(
      "automations.inspector.insert-secret",
      defaultValue: "Insert Secret",
      comment: "Menu that inserts {secret:NAME}"
    )
    static let manageSecrets = string(
      "automations.inspector.manage-secrets",
      defaultValue: "Manage Secrets…",
      comment: "Menu item opening the secrets list"
    )
    static let uploadDestinationLabel = string(
      "automations.inspector.upload.destination",
      defaultValue: "Upload To",
      comment: "Upload step destination picker"
    )
    static let uploadDestinationDefault = string(
      "automations.inspector.upload.default",
      defaultValue: "Cloud (from Settings)",
      comment: "Upload destination: the provider set in Settings → Cloud"
    )
    static let manageUploaders = string(
      "automations.inspector.upload.manage",
      defaultValue: "Manage Uploaders…",
      comment: "Button opening Settings → Cloud"
    )
    static let webhookPresetLabel = string(
      "automations.inspector.webhook.preset",
      defaultValue: "Template",
      comment: "Webhook body template picker"
    )
    static let webhookPresetSlack = string(
      "automations.inspector.webhook.preset.slack",
      defaultValue: "Slack Incoming Webhook",
      comment: "Webhook template"
    )
    static let webhookPresetDiscord = string(
      "automations.inspector.webhook.preset.discord",
      defaultValue: "Discord Webhook",
      comment: "Webhook template"
    )
    static let webhookPresetGeneric = string(
      "automations.inspector.webhook.preset.generic",
      defaultValue: "Generic JSON",
      comment: "Webhook template"
    )
    static let methodLabel = string(
      "automations.inspector.webhook.method",
      defaultValue: "Method",
      comment: "HTTP method picker"
    )
    static let urlLabel = string(
      "automations.inspector.webhook.url",
      defaultValue: "URL",
      comment: "Webhook URL field"
    )
    static let headersLabel = string(
      "automations.inspector.webhook.headers",
      defaultValue: "Headers",
      comment: "HTTP headers list"
    )
    static let addHeader = string(
      "automations.inspector.webhook.add-header",
      defaultValue: "Add Header",
      comment: "Button"
    )
    static let fieldsLabel = string(
      "automations.inspector.webhook.fields",
      defaultValue: "Fields",
      comment: "Form fields list"
    )
    static let addField = string(
      "automations.inspector.webhook.add-field",
      defaultValue: "Add Field",
      comment: "Button"
    )
    static let keyPlaceholder = string(
      "automations.inspector.webhook.key",
      defaultValue: "Name",
      comment: "Placeholder for a header / field name"
    )
    static let valuePlaceholder = string(
      "automations.inspector.webhook.value",
      defaultValue: "Value",
      comment: "Placeholder for a header / field value"
    )
    static let removeRow = string(
      "automations.inspector.webhook.remove",
      defaultValue: "Remove",
      comment: "Accessibility label of the remove-row button"
    )
    static let bodyLabel = string(
      "automations.inspector.webhook.body",
      defaultValue: "Body",
      comment: "HTTP body kind picker"
    )
    static let bodyNone = string(
      "automations.inspector.webhook.body.none",
      defaultValue: "None",
      comment: "Body kind"
    )
    static let bodyJSON = string(
      "automations.inspector.webhook.body.json",
      defaultValue: "JSON",
      comment: "Body kind"
    )
    static let bodyForm = string(
      "automations.inspector.webhook.body.form",
      defaultValue: "Form",
      comment: "Body kind (URL-encoded form)"
    )
    static let bodyMultipart = string(
      "automations.inspector.webhook.body.multipart",
      defaultValue: "Form with File",
      comment: "Body kind (multipart with the file)"
    )
    static let fileFieldLabel = string(
      "automations.inspector.webhook.file-field",
      defaultValue: "File Field",
      comment: "Name of the multipart file field"
    )
    static let jsonInvalid = string(
      "automations.inspector.webhook.json-invalid",
      defaultValue: "Not valid JSON with sample values.",
      comment: "Validation hint under the JSON template"
    )
    static let responseToText = string(
      "automations.inspector.webhook.response-text",
      defaultValue: "Use the response as {text}",
      comment: "Toggle; {text} is a token, keep it"
    )
    static let responseLinkPath = string(
      "automations.inspector.webhook.response-link",
      defaultValue: "Link from Response",
      comment: "JSON path field read into {link}"
    )
    static let webhookFooter = string(
      "automations.inspector.webhook.footer",
      defaultValue: "Values are JSON-escaped in a JSON body. Put tokens in a secret and write {secret:NAME} so they stay out of your config file.",
      comment: "Webhook inspector footer; {secret:NAME} is syntax, keep it"
    )
    static let webhookTestDescription = string(
      "automations.inspector.webhook.test.description",
      defaultValue: "Sends this webhook once with sample values.",
      comment: "Explains what the webhook Test button sends"
    )
    static let scriptLabel = string(
      "automations.inspector.script",
      defaultValue: "Script",
      comment: "Script editor label"
    )
    static let shellLabel = string(
      "automations.inspector.script.shell",
      defaultValue: "Shell",
      comment: "Shell picker"
    )
    static let loginShell = string(
      "automations.inspector.script.login-shell",
      defaultValue: "Use login shell (PATH from your profile)",
      comment: "Toggle"
    )
    static let scriptVariablesHelp = string(
      "automations.inspector.script.variables",
      defaultValue: "Values reach the script only as environment variables — $SNAPZY_FILE, $SNAPZY_FILES (one per line), $SNAPZY_LINK, $SNAPZY_TEXT, $SNAPZY_AUTOMATION, $SNAPZY_RUN_ID, $SNAPZY_WORK_DIR — and the files as $1, $2… They are never inserted into the script text.",
      comment: "Script inspector footer; variable names are code, keep them"
    )
    static let shortcutNone = string(
      "automations.inspector.shortcut.none",
      defaultValue: "Choose…",
      comment: "Shortcut picker placeholder"
    )
    static let refreshShortcuts = string(
      "automations.inspector.shortcut.refresh",
      defaultValue: "Refresh List",
      comment: "Button reloading the Shortcuts list"
    )
    static let openInShortcuts = string(
      "automations.inspector.shortcut.open",
      defaultValue: "Open in Shortcuts",
      comment: "Button"
    )
    static let inputLabel = string(
      "automations.inspector.shortcut.input",
      defaultValue: "Input",
      comment: "What the shortcut receives"
    )
    static let inputText = string(
      "automations.inspector.shortcut.input.text",
      defaultValue: "Text",
      comment: "Shortcut input option"
    )
    static let inputLink = string(
      "automations.inspector.shortcut.input.link",
      defaultValue: "Link",
      comment: "Shortcut input option"
    )
    static let inputNone = string(
      "automations.inspector.shortcut.input.none",
      defaultValue: "Nothing",
      comment: "Shortcut input option"
    )
    static let shortcutFooter = string(
      "automations.inspector.shortcut.footer",
      defaultValue: "The first run may ask you to allow the shortcut to use the file.",
      comment: "Shortcut inspector footer"
    )
    static let serviceLabel = string(
      "automations.inspector.share.service",
      defaultValue: "Service",
      comment: "Share step service picker"
    )
    static let appLabel = string(
      "automations.inspector.app",
      defaultValue: "App",
      comment: "Open in app: app label"
    )
    static let chooseApp = string(
      "automations.inspector.app.choose",
      defaultValue: "Choose…",
      comment: "Button opening an app chooser"
    )
    static let externalCodeToggle = string(
      "automations.external.code-toggle",
      defaultValue: "Let other apps run its script steps",
      comment: "Second opt-in toggle in Run from other apps"
    )
    static let externalCodeDescription = string(
      "automations.external.code-description",
      defaultValue: "A snapzy:// link or a shortcut could then run this script. Turn on only if you trust everything that can open links on this Mac.",
      comment: "Warning under the second opt-in"
    )
    static let reviewBadge = string(
      "automations.review.badge",
      defaultValue: "Imported — review before it can run",
      comment: "Row status for imported automations with network/script steps"
    )
    static let reviewButton = string(
      "automations.review.button",
      defaultValue: "Review",
      comment: "Button opening the editor for review"
    )
    static let reviewBanner = string(
      "automations.review.banner",
      defaultValue: "Imported with network or script steps. Check what each step sends or runs, then save to allow this automation.",
      comment: "Editor banner for an automation that needs review"
    )
    static let advancedHeader = string(
      "automations.advanced.header",
      defaultValue: "Advanced",
      comment: "Settings → Automations section"
    )
    static let allowCodeStepsToggle = string(
      "automations.advanced.allow-code",
      defaultValue: "Allow script & Shortcut steps",
      comment: "Toggle"
    )
    static let allowCodeStepsDescription = string(
      "automations.advanced.allow-code-description",
      defaultValue: "Scripts and shortcuts can do anything your user account can. Only run automations you wrote or trust. Never turned on by an imported config file.",
      comment: "Warning under the toggle"
    )
    static let secretsHeader = string(
      "automations.secrets.header",
      defaultValue: "Secrets",
      comment: "Secrets list title"
    )
    static let secretsDescription = string(
      "automations.secrets.description",
      defaultValue: "Tokens for webhooks and custom uploaders, kept in your Keychain. Write {secret:NAME} to use one; values are never exported or logged.",
      comment: "Secrets section description; {secret:NAME} is syntax"
    )
    static let secretsEmpty = string(
      "automations.secrets.empty",
      defaultValue: "No secrets yet.",
      comment: "Secrets list placeholder"
    )
    static let addSecret = string(
      "automations.secrets.add",
      defaultValue: "Add Secret…",
      comment: "Button"
    )
    static let replaceSecretValue = string(
      "automations.secrets.replace",
      defaultValue: "Replace Value…",
      comment: "Button"
    )
    static let secretNameLabel = string(
      "automations.secrets.name",
      defaultValue: "Name",
      comment: "Secret sheet field"
    )
    static let secretValueLabel = string(
      "automations.secrets.value",
      defaultValue: "Value",
      comment: "Secret sheet field"
    )
    static let copySecretReference = string(
      "automations.secrets.copy-reference",
      defaultValue: "Copy {secret:…}",
      comment: "Button copying the reference token"
    )
    static let shortcutPickerLabel = string(
      "automations.inspector.shortcut-picker",
      defaultValue: "Shortcut",
      comment: "Shortcut picker label"
    )
  }
}
