//
//  L10n+Automations.swift
//  Snapzy
//
//  Strings for automations: presets, steps, run results and Settings.
//

import Foundation

extension L10n {
  nonisolated enum Automations {
    // MARK: Canvas editor
    static let canvasSaved = string(
      "automations.canvas.saved",
      defaultValue: "Saved",
      comment: "Canvas: no unsaved changes"
    )
    static let canvasUnsaved = string(
      "automations.canvas.unsaved",
      defaultValue: "Unsaved changes",
      comment: "Canvas: tooltip of the unsaved-changes dot"
    )
    static let canvasShowMinimap = string(
      "automations.canvas.show-minimap",
      defaultValue: "Show Minimap",
      comment: "Canvas menu toggle"
    )
    static let canvasMinimap = string(
      "automations.canvas.minimap",
      defaultValue: "Overview: click or drag to move around",
      comment: "Tooltip of the canvas minimap"
    )
    static let canvasDeletedTitle = string(
      "automations.canvas.deleted-title",
      defaultValue: "This automation was deleted",
      comment: "Alert title: saving a canvas whose automation was deleted in Settings"
    )
    static let canvasDeletedMessage = string(
      "automations.canvas.deleted-message",
      defaultValue: "It was removed in Settings while this window was open, so there is nothing to save it to.",
      comment: "Alert message for the deleted automation"
    )
    static let editorStyleLabel = string(
      "automations.editor-style.label",
      defaultValue: "Editor",
      comment: "Label of the picker choosing which automation editor opens"
    )
    static let editorStyleList = string(
      "automations.editor-style.list",
      defaultValue: "List",
      comment: "Automation editor option: steps as a list in a sheet"
    )
    static let editorStyleCanvas = string(
      "automations.editor-style.canvas",
      defaultValue: "Canvas",
      comment: "Automation editor option: node canvas in its own window"
    )
    static let editorStyleHelp = string(
      "automations.editor-style.help",
      defaultValue: "Choose what Edit and New open: the list editor or the node canvas.",
      comment: "Tooltip of the editor style picker"
    )
    static let canvasOpenInCanvas = string(
      "automations.canvas.open-in-canvas",
      defaultValue: "Open in Canvas",
      comment: "Menu item / button: edit this automation in the node canvas window"
    )
    static let canvasOpenInCanvasHelp = string(
      "automations.canvas.open-in-canvas-help",
      defaultValue: "Continue editing this automation as connected nodes in a separate window.",
      comment: "Tooltip of the Open in Canvas button in the list editor"
    )
    static let canvasOpenInList = string(
      "automations.canvas.open-in-list",
      defaultValue: "Open in List Editor",
      comment: "Menu item: edit this automation in the list editor sheet"
    )
    static let canvasTriggerNode = string(
      "automations.canvas.trigger-node",
      defaultValue: "Trigger",
      comment: "Title of the canvas node that starts the automation"
    )
    static let canvasTriggerCaption = string(
      "automations.canvas.trigger-caption",
      defaultValue: "Start",
      comment: "Small caption above the trigger node"
    )
    static let canvasAfterCapture = string(
      "automations.canvas.after-capture",
      defaultValue: "After every capture",
      comment: "Trigger node subtitle of a default after-capture automation"
    )
    static let canvasTriggerMenuBar = string(
      "automations.canvas.trigger.menu-bar",
      defaultValue: "Menu bar",
      comment: "Trigger node: listed in the menu bar"
    )
    static let canvasTriggerQuickAccess = string(
      "automations.canvas.trigger.quick-access",
      defaultValue: "Quick Access",
      comment: "Trigger node: listed in Quick Access"
    )
    static let canvasTriggerHistory = string(
      "automations.canvas.trigger.history",
      defaultValue: "History",
      comment: "Trigger node: listed in History"
    )
    static let canvasTriggerFinder = string(
      "automations.canvas.trigger.finder",
      defaultValue: "Finder",
      comment: "Trigger node: offered by the Finder service"
    )
    static let canvasTriggerCaptureToolbar = string(
      "automations.canvas.trigger.capture-toolbar",
      defaultValue: "Capture toolbar",
      comment: "Trigger node: a button in the capture toolbar"
    )
    static let canvasTriggerExternal = string(
      "automations.canvas.trigger.external",
      defaultValue: "Other apps",
      comment: "Trigger node: other apps may run it (URL scheme, CLI, Shortcuts)"
    )
    static let canvasTriggerNone = string(
      "automations.canvas.trigger.none",
      defaultValue: "No trigger yet",
      comment: "Trigger node subtitle when nothing runs the automation"
    )
    static let canvasStepDisabled = string(
      "automations.canvas.step-disabled",
      defaultValue: "Step is off",
      comment: "Tooltip on a disabled step node"
    )
    static let canvasDetachedHelp = string(
      "automations.canvas.detached-help",
      defaultValue: "Not connected: this step won’t run until you link it into the chain.",
      comment: "Tooltip / banner on a step node not linked from the source"
    )
    static let canvasConnectHelp = string(
      "automations.canvas.connect-help",
      defaultValue: "Drag to another node to connect, or onto empty space to add a step",
      comment: "Tooltip on a node's output handle"
    )
    static let canvasOtherwise = string(
      "automations.canvas.otherwise",
      defaultValue: "Otherwise",
      comment: "Label on the dashed jump a condition takes when it does not hold"
    )
    static let canvasEnd = string(
      "automations.canvas.end",
      defaultValue: "End",
      comment: "Label: the run ends here"
    )
    static let canvasInsertStep = string(
      "automations.canvas.insert-step",
      defaultValue: "Insert Step",
      comment: "Button on a link: add a step between two nodes"
    )
    static let canvasDisconnect = string(
      "automations.canvas.disconnect",
      defaultValue: "Disconnect",
      comment: "Button / menu item: remove the link after a node"
    )
    static let canvasEnableStep = string(
      "automations.canvas.enable-step",
      defaultValue: "Turn Step On",
      comment: "Context menu: enable a step node"
    )
    static let canvasDisableStep = string(
      "automations.canvas.disable-step",
      defaultValue: "Turn Step Off",
      comment: "Context menu: disable a step node"
    )
    static let canvasSearchSteps = string(
      "automations.canvas.search-steps",
      defaultValue: "Search steps",
      comment: "Placeholder of the canvas add-step search field"
    )
    static let canvasNoMatchingSteps = string(
      "automations.canvas.no-matching-steps",
      defaultValue: "No matching steps",
      comment: "Shown when the step search finds nothing"
    )
    static let canvasAddStepHelp = string(
      "automations.canvas.add-step-help",
      defaultValue: "Add a step after the selected node (Tab)",
      comment: "Tooltip of the canvas Add Step button"
    )
    static let canvasTidyUp = string(
      "automations.canvas.tidy-up",
      defaultValue: "Tidy Up",
      comment: "Toolbar button: lay the nodes out in rows"
    )
    static let canvasToggleInspector = string(
      "automations.canvas.toggle-inspector",
      defaultValue: "Show or Hide Inspector",
      comment: "Toolbar button tooltip"
    )
    static let canvasZoomIn = string(
      "automations.canvas.zoom-in",
      defaultValue: "Zoom In",
      comment: "Canvas zoom button"
    )
    static let canvasZoomOut = string(
      "automations.canvas.zoom-out",
      defaultValue: "Zoom Out",
      comment: "Canvas zoom button"
    )
    static let canvasActualSize = string(
      "automations.canvas.actual-size",
      defaultValue: "Actual Size",
      comment: "Canvas zoom: reset to 100 %"
    )
    static let canvasZoomToFit = string(
      "automations.canvas.zoom-to-fit",
      defaultValue: "Zoom to Fit",
      comment: "Canvas zoom: show every node"
    )
    static let canvasInspectorHint = string(
      "automations.canvas.inspector-hint",
      defaultValue: "Select a node to edit it. Drag a node’s handle onto another node to connect them, or press Tab to add a step.",
      comment: "Inspector placeholder when nothing is selected on the canvas"
    )
    static let canvasHint = string(
      "automations.canvas.hint",
      defaultValue: "Drag to pan · Pinch or ⌘-scroll to zoom",
      comment: "Canvas footer hint"
    )
    static func canvasDetachedCount(_ count: Int) -> String {
      format(
        "automations.canvas.detached-count",
        defaultValue: "%d step(s) not connected",
        comment: "Canvas footer; %d is the number of unconnected steps",
        count
      )
    }
    static func canvasDiscardTitle(_ name: String) -> String {
      format(
        "automations.canvas.discard-title",
        defaultValue: "Save changes to “%@”?",
        comment: "Alert when closing the canvas with unsaved edits; %@ is the automation name",
        name
      )
    }
    static let canvasDiscardMessage = string(
      "automations.canvas.discard-message",
      defaultValue: "Your edits in the canvas haven’t been saved.",
      comment: "Alert message when closing the canvas with unsaved edits"
    )
    static let canvasDiscard = string(
      "automations.canvas.discard",
      defaultValue: "Discard Changes",
      comment: "Alert button: close the canvas without saving"
    )
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

    // MARK: - Milestone 5: control steps, picker, Finder & menu bar drop

    static let stepCondition = string(
      "automations.step.condition",
      defaultValue: "Condition",
      comment: "Step: continue only when a condition holds"
    )
    static let stepStop = string(
      "automations.step.stop",
      defaultValue: "Stop",
      comment: "Step: end the run here"
    )
    static let stepRunAutomation = string(
      "automations.step.run-automation",
      defaultValue: "Run Automation",
      comment: "Step: run another automation's steps"
    )
    static let stepAsk = string(
      "automations.step.ask",
      defaultValue: "Ask",
      comment: "Step: show a picker and let the user choose what happens"
    )
    static let describeCondition = string(
      "automations.describe.condition",
      defaultValue: "Continues only when the run matches. Otherwise the run stops or skips the next steps, so “condition · A · stop · B” runs A or B.",
      comment: "Inspector description of the Condition step"
    )
    static let describeStop = string(
      "automations.describe.stop",
      defaultValue: "Ends the run here, successfully. In an automation run by another one, returns to it.",
      comment: "Inspector description of the Stop step"
    )
    static let describeRunAutomation = string(
      "automations.describe.run-automation",
      defaultValue: "Runs another automation’s steps on the current file, then continues. Its source and triggers are ignored.",
      comment: "Inspector description of the Run Automation step"
    )
    static let describeAsk = string(
      "automations.describe.ask",
      defaultValue: "Shows a picker at the pointer. The chosen automation runs on the current file and ends this run; “Continue” goes on with the next step.",
      comment: "Inspector description of the Ask step"
    )
    static func errorAutomationUnavailable(_ name: String) -> String {
      format(
        "automations.error.automation-unavailable",
        defaultValue: "“%@” isn’t available (deleted, turned off or waiting for review).",
        comment: "Run error; %@ is an automation name",
        name
      )
    }
    static let errorRecursionLimit = string(
      "automations.error.recursion-limit",
      defaultValue: "Automations run each other in a loop or nest too deeply.",
      comment: "Run error: Run Automation / Ask cycle or depth limit"
    )
    static let errorNoChoices = string(
      "automations.error.no-choices",
      defaultValue: "None of the choices can run right now.",
      comment: "Run error: Ask step has no available choices"
    )
    static let unknownAutomation = string(
      "automations.unknown-automation",
      defaultValue: "Missing automation",
      comment: "Label for a referenced automation that no longer exists"
    )
    static let askContinue = string(
      "automations.ask.continue",
      defaultValue: "Continue",
      comment: "Ask choice: go on with the next step"
    )
    static let askStop = string(
      "automations.ask.stop",
      defaultValue: "Stop Here",
      comment: "Ask choice: end the run"
    )
    static let waitingForChoice = string(
      "automations.waiting-for-choice",
      defaultValue: "Waiting for choice",
      comment: "Run HUD status while the Ask picker is open"
    )
    static let logSkippedByCondition = string(
      "automations.log.skipped-by-condition",
      defaultValue: "Skipped by condition",
      comment: "Activity: step skipped by a condition"
    )
    static let logConditionMet = string(
      "automations.log.condition-met",
      defaultValue: "Condition met",
      comment: "Activity: condition held"
    )
    static let logConditionNotMet = string(
      "automations.log.condition-not-met",
      defaultValue: "Condition not met",
      comment: "Activity: condition did not hold"
    )
    static let logChoiceCancelled = string(
      "automations.log.choice-cancelled",
      defaultValue: "Choice cancelled",
      comment: "Activity: user dismissed the Ask picker"
    )
    static let issueAutomation = string(
      "automations.issue.automation",
      defaultValue: "Choose an automation",
      comment: "Chain issue: Run Automation/Ask target missing"
    )
    static let issueChoices = string(
      "automations.issue.choices",
      defaultValue: "Add at least one choice",
      comment: "Chain issue: Ask without choices"
    )
    static let issueCondition = string(
      "automations.issue.condition",
      defaultValue: "Pick a value for each condition",
      comment: "Chain issue: predicate without values"
    )
    static let issueSkipRange = string(
      "automations.issue.skip-range",
      defaultValue: "Skips past the last step",
      comment: "Chain issue: otherwise-skip count beyond the end"
    )
    static let issueRecursion = string(
      "automations.issue.recursion",
      defaultValue: "Runs itself in a loop or nests more than 3 levels",
      comment: "Chain issue: cycle or depth"
    )
    static let issueTargetCannotRun = string(
      "automations.issue.target-cannot-run",
      defaultValue: "The chosen automation can’t run on this input",
      comment: "Chain issue: target automation has blocking issues for the current kinds"
    )
    static let conditionAlways = string(
      "automations.condition.always",
      defaultValue: "Always",
      comment: "Condition sentence with no predicates"
    )
    static let conditionAnd = string(
      "automations.condition.and",
      defaultValue: " and ",
      comment: "Separator between predicates (match all); keep spaces"
    )
    static let conditionOr = string(
      "automations.condition.or",
      defaultValue: " or ",
      comment: "Separator between predicates or values (match any); keep spaces"
    )
    static let conditionElseStop = string(
      "automations.condition.else-stop",
      defaultValue: "else stop",
      comment: "Condition sentence suffix"
    )
    static func conditionElseSkip(_ count: Int) -> String {
      format(
        "automations.condition.else-skip",
        defaultValue: "else skip %lld",
        comment: "Condition sentence suffix; %lld is a step count",
        count
      )
    }
    static func conditionAppIs(_ names: String) -> String {
      format(
        "automations.condition.app-is",
        defaultValue: "App is %@",
        comment: "Predicate sentence; %@ is app names",
        names
      )
    }
    static func conditionAppIsNot(_ names: String) -> String {
      format(
        "automations.condition.app-is-not",
        defaultValue: "App is not %@",
        comment: "Predicate sentence; %@ is app names",
        names
      )
    }
    static func conditionCaptureIs(_ modes: String) -> String {
      format(
        "automations.condition.capture-is",
        defaultValue: "Capture is %@",
        comment: "Predicate sentence; %@ is capture modes",
        modes
      )
    }
    static func conditionStartedFrom(_ names: String) -> String {
      format(
        "automations.condition.started-from",
        defaultValue: "Started from %@",
        comment: "Predicate sentence; %@ is trigger names",
        names
      )
    }
    static func conditionFileIs(_ kinds: String) -> String {
      format(
        "automations.condition.file-is",
        defaultValue: "File is %@",
        comment: "Predicate sentence; %@ is file kinds",
        kinds
      )
    }
    static let conditionFileSize = string(
      "automations.condition.file-size",
      defaultValue: "File size",
      comment: "Predicate sentence prefix before > / < and a size"
    )
    static let conditionHasText = string(
      "automations.condition.has-text",
      defaultValue: "Has recognized text",
      comment: "Predicate sentence"
    )
    static func conditionTextContains(_ text: String) -> String {
      format(
        "automations.condition.text-contains",
        defaultValue: "Text contains “%@”",
        comment: "Predicate sentence; %@ is the searched text",
        text
      )
    }
    static let dimensionWidth = string(
      "automations.dimension.width",
      defaultValue: "Width",
      comment: "Pixel size predicate dimension"
    )
    static let dimensionHeight = string(
      "automations.dimension.height",
      defaultValue: "Height",
      comment: "Pixel size predicate dimension"
    )
    static let dimensionLongest = string(
      "automations.dimension.longest",
      defaultValue: "Longest edge",
      comment: "Pixel size predicate dimension"
    )
    static let fileKindImage = string(
      "automations.file-kind.image",
      defaultValue: "Image",
      comment: "File kind"
    )
    static let fileKindVideo = string(
      "automations.file-kind.video",
      defaultValue: "Video",
      comment: "File kind"
    )
    static let invocationHotkey = string(
      "automations.invocation.hotkey",
      defaultValue: "Shortcut",
      comment: "Name of a way an automation was started"
    )
    static let invocationURLScheme = string(
      "automations.invocation.url-scheme",
      defaultValue: "URL scheme",
      comment: "Name of a way an automation was started"
    )
    static let invocationCLI = string(
      "automations.invocation.cli",
      defaultValue: "Command line",
      comment: "Name of a way an automation was started"
    )
    static let invocationMenuBar = string(
      "automations.invocation.menu-bar",
      defaultValue: "Menu bar",
      comment: "Name of a way an automation was started"
    )
    static let invocationQuickAccess = string(
      "automations.invocation.quick-access",
      defaultValue: "Quick Access",
      comment: "Name of a way an automation was started"
    )
    static let invocationHistory = string(
      "automations.invocation.history",
      defaultValue: "History",
      comment: "Name of a way an automation was started"
    )
    static let invocationShortcuts = string(
      "automations.invocation.shortcuts",
      defaultValue: "Shortcuts app",
      comment: "Name of a way an automation was started"
    )
    static let invocationRetry = string(
      "automations.invocation.retry",
      defaultValue: "Retry",
      comment: "Name of a way an automation was started"
    )
    static let invocationMenuBarDrop = string(
      "automations.invocation.menu-bar-drop",
      defaultValue: "Drop on menu bar icon",
      comment: "Name of a way an automation was started"
    )
    static let predicateApp = string(
      "automations.predicate.app",
      defaultValue: "App",
      comment: "Condition type in the editor"
    )
    static let predicateCaptureMode = string(
      "automations.predicate.capture-mode",
      defaultValue: "Capture mode",
      comment: "Condition type in the editor"
    )
    static let predicateInvocation = string(
      "automations.predicate.invocation",
      defaultValue: "Started from",
      comment: "Condition type in the editor"
    )
    static let predicateFileKind = string(
      "automations.predicate.file-kind",
      defaultValue: "File type",
      comment: "Condition type in the editor"
    )
    static let predicatePixelSize = string(
      "automations.predicate.pixel-size",
      defaultValue: "Pixel size",
      comment: "Condition type in the editor"
    )
    static let predicateFileSize = string(
      "automations.predicate.file-size",
      defaultValue: "File size",
      comment: "Condition type in the editor"
    )
    static let predicateHasText = string(
      "automations.predicate.has-text",
      defaultValue: "Recognized text",
      comment: "Condition type in the editor"
    )
    static let conditionHeader = string(
      "automations.condition.header",
      defaultValue: "Continue when",
      comment: "Condition inspector section header"
    )
    static let conditionMatchLabel = string(
      "automations.condition.match",
      defaultValue: "Match",
      comment: "Picker: all or any predicate"
    )
    static let conditionMatchAll = string(
      "automations.condition.match-all",
      defaultValue: "All",
      comment: "Match every predicate"
    )
    static let conditionMatchAny = string(
      "automations.condition.match-any",
      defaultValue: "Any",
      comment: "Match at least one predicate"
    )
    static let conditionAdd = string(
      "automations.condition.add",
      defaultValue: "Add Condition",
      comment: "Menu adding a predicate"
    )
    static let conditionOtherwiseLabel = string(
      "automations.condition.otherwise",
      defaultValue: "Otherwise",
      comment: "Picker: what happens when the condition fails"
    )
    static let conditionOtherwiseStop = string(
      "automations.condition.otherwise-stop",
      defaultValue: "Stop the run",
      comment: "Otherwise option"
    )
    static let conditionOtherwiseSkip = string(
      "automations.condition.otherwise-skip",
      defaultValue: "Skip next steps",
      comment: "Otherwise option"
    )
    static func conditionSkipCount(_ count: Int) -> String {
      format(
        "automations.condition.skip-count",
        defaultValue: "Skip %lld step(s)",
        comment: "Stepper label; %lld is a step count",
        count
      )
    }
    static let conditionTextContainsPlaceholder = string(
      "automations.condition.text-contains-placeholder",
      defaultValue: "Contains (optional)",
      comment: "Text field placeholder"
    )
    static let conditionChoose = string(
      "automations.condition.choose",
      defaultValue: "Choose…",
      comment: "Placeholder when no value is selected"
    )
    static let conditionAppIsLabel = string(
      "automations.condition.app-is-label",
      defaultValue: "is",
      comment: "Segment: app is"
    )
    static let conditionAppIsNotLabel = string(
      "automations.condition.app-is-not-label",
      defaultValue: "is not",
      comment: "Segment: app is not"
    )
    static let conditionAddApp = string(
      "automations.condition.add-app",
      defaultValue: "Add App",
      comment: "Menu adding an app to a condition"
    )
    static let comparisonGreater = string(
      "automations.comparison.greater",
      defaultValue: "more than",
      comment: "Comparison option"
    )
    static let comparisonLess = string(
      "automations.comparison.less",
      defaultValue: "less than",
      comment: "Comparison option"
    )
    static let runAutomationTarget = string(
      "automations.run-automation.target",
      defaultValue: "Automation",
      comment: "Picker label"
    )
    static let runAutomationDisabledWarning = string(
      "automations.run-automation.disabled",
      defaultValue: "This automation is turned off; the step will fail until it’s turned on.",
      comment: "Warning under the Run Automation picker"
    )
    static let askPromptLabel = string(
      "automations.ask.prompt",
      defaultValue: "Title",
      comment: "Ask picker title field"
    )
    static let askPromptPlaceholder = string(
      "automations.ask.prompt-placeholder",
      defaultValue: "Automation name",
      comment: "Placeholder: empty title uses the automation's name"
    )
    static let askChoicesHeader = string(
      "automations.ask.choices",
      defaultValue: "Choices",
      comment: "Ask inspector section header"
    )
    static let askChoicesFooter = string(
      "automations.ask.choices-footer",
      defaultValue: "Number keys 1–9 pick a choice, Esc cancels. Turned-off automations are hidden.",
      comment: "Ask inspector footer"
    )
    static let askAddChoice = string(
      "automations.ask.add-choice",
      defaultValue: "Add Choice",
      comment: "Menu adding an Ask choice"
    )
    static let pickerSearch = string(
      "automations.picker.search",
      defaultValue: "Search",
      comment: "Picker search field"
    )
    static let pickerNoMatches = string(
      "automations.picker.no-matches",
      defaultValue: "No matches",
      comment: "Picker with no search results"
    )
    static let pickerHint = string(
      "automations.picker.hint",
      defaultValue: "1–9 or ↑↓ ↩ to pick · Esc to cancel",
      comment: "Picker keyboard hint"
    )
    static func pickerNumberHint(_ number: Int) -> String {
      format(
        "automations.picker.number-hint",
        defaultValue: "Press %lld",
        comment: "VoiceOver hint; %lld is the number key",
        number
      )
    }
    static let fileTriggerNoSupportedFiles = string(
      "automations.file-trigger.no-files",
      defaultValue: "No image, video or GIF to run an automation on.",
      comment: "Toast: dropped/Finder files unsupported"
    )
    static let fileTriggerNoAutomations = string(
      "automations.file-trigger.no-automations",
      defaultValue: "No automation fits these files. Turn on “Show in Finder & menu bar drop” for one in Settings → Automations.",
      comment: "Toast: no eligible automations"
    )
    static func fileTriggerTitle(_ count: Int) -> String {
      format(
        "automations.file-trigger.title",
        defaultValue: "Run Automation on %lld Files",
        comment: "Picker title for several files; %lld is the count",
        count
      )
    }
    static let showInFinder = string(
      "automations.show-in.finder",
      defaultValue: "Finder & menu bar drop",
      comment: "Toggle: list in Finder service and menu bar icon drops"
    )
    static let runSingleDirectlyToggle = string(
      "automations.advanced.run-single-directly",
      defaultValue: "Skip the picker when one automation fits",
      comment: "Advanced toggle"
    )
    static let runSingleDirectlyDescription = string(
      "automations.advanced.run-single-directly-description",
      defaultValue: "Finder’s “Run Snapzy Automation…” and files dropped on the menu bar icon then run it right away.",
      comment: "Advanced toggle description"
    )
    static let routeByApp = string(
      "automations.route.title",
      defaultValue: "Route by App…",
      comment: "Button/sheet title: insert a per-app condition block"
    )
    static let routeAppsHeader = string(
      "automations.route.apps",
      defaultValue: "When the app is",
      comment: "Sheet section header"
    )
    static let routeStepsHeader = string(
      "automations.route.steps",
      defaultValue: "Run these steps",
      comment: "Sheet section header"
    )
    static let routeFooter = string(
      "automations.route.footer",
      defaultValue: "Then stop. Other apps skip them and run the steps below the block.",
      comment: "Sheet footer"
    )
    static let routeInsert = string(
      "automations.route.insert",
      defaultValue: "Insert",
      comment: "Sheet confirm button"
    )
    static let stepInSkipRangeHint = string(
      "automations.step.in-skip-range",
      defaultValue: "Runs only when the condition above holds",
      comment: "VoiceOver hint for a step inside a condition's skip range"
    )
    static let presetShareMenu = string(
      "automations.preset.share-menu",
      defaultValue: "Share Menu",
      comment: "Built-in automation: capture an area, then pick Quick Copy, Cloud Share or Docs Shot"
    )
    static let presetDesignRouter = string(
      "automations.preset.design-router",
      defaultValue: "Design Router",
      comment: "Built-in automation: save Figma/Sketch windows to a design folder, others to the export folder"
    )

    // MARK: - Milestone 6: default after-capture automations

    static let systemDefaultScreenshotName = string(
      "automations.system-default.screenshot.name",
      defaultValue: "Default after screenshot",
      comment: "Name of the built-in automation every standard screenshot runs"
    )
    static let systemDefaultRecordingName = string(
      "automations.system-default.recording.name",
      defaultValue: "Default after recording",
      comment: "Name of the built-in automation every standard recording runs"
    )
    static let invocationAfterCapture = string(
      "automations.invocation.after-capture",
      defaultValue: "After capture",
      comment: "Name of a way an automation was started: a normal capture ran its default automation"
    )
    static let systemDefaultSection = string(
      "automations.system-default.section",
      defaultValue: "Default after capture",
      comment: "Settings section listing the two default after-capture automations"
    )
    static let systemDefaultSectionFooter = string(
      "automations.system-default.section-footer",
      defaultValue: "Every screenshot or recording not started by an automation runs these steps. The After Capture options in Capture settings edit the same pipelines.",
      comment: "Footer of the default after-capture section"
    )
    static let systemDefaultCustomize = string(
      "automations.system-default.customize",
      defaultValue: "Customize Pipeline…",
      comment: "Button: open the default after-capture automation in the full editor"
    )
    static let systemDefaultEdit = string(
      "automations.system-default.edit",
      defaultValue: "Edit…",
      comment: "Button: edit a custom default after-capture pipeline"
    )
    static let systemDefaultReset = string(
      "automations.system-default.reset",
      defaultValue: "Reset to Simple",
      comment: "Button: turn a custom default after-capture pipeline back into the simple checkbox form"
    )
    static let systemDefaultResetConfirm = string(
      "automations.system-default.reset-confirm",
      defaultValue: "Steps the checkboxes can't show are removed.",
      comment: "Confirmation message before resetting a custom after-capture pipeline"
    )
    static let systemDefaultCustomBadge = string(
      "automations.system-default.custom-badge",
      defaultValue: "Custom",
      comment: "Badge: this capture type runs a custom after-capture pipeline"
    )
    static func systemDefaultCustomSummary(_ kind: String) -> String {
      format(
        "automations.system-default.custom-summary",
        defaultValue: "%@ runs a custom pipeline",
        comment: "Row in After Capture settings. %@ = Screenshot or Recording",
        kind
      )
    }
    static let systemDefaultNoSteps = string(
      "automations.system-default.no-steps",
      defaultValue: "Save only",
      comment: "Summary of a default after-capture automation with no steps"
    )
    static let systemDefaultEditorNote = string(
      "automations.system-default.editor-note",
      defaultValue: "Runs after every capture that no automation started. Its Save option is in Capture settings.",
      comment: "Banner in the editor for a default after-capture automation"
    )

    // MARK: - Milestone 6: AI steps (redact, AI describe)

    static let stepRedact = string(
      "automations.step.redact",
      defaultValue: "Redact",
      comment: "Step name: cover sensitive data (emails, tokens, faces) in the image"
    )
    static let stepAIAnnotate = string(
      "automations.step.ai-annotate",
      defaultValue: "AI Describe",
      comment: "Step name: an AI provider writes text about the image (alt text, summary)"
    )
    static let describeRedact = string(
      "automations.step.redact.describe",
      defaultValue: "Finds emails, phone numbers, card numbers, tokens, faces or people on this Mac and covers them. Put it before any upload.",
      comment: "Inspector description of the Redact step"
    )
    static let describeAIAnnotate = string(
      "automations.step.ai-annotate.describe",
      defaultValue: "Sends the image and your prompt to your AI provider. Its answer becomes {text} for Copy Text, Save or a webhook.",
      comment: "Inspector description of the AI Describe step"
    )
    static let redactCategoriesLabel = string(
      "automations.redact.categories",
      defaultValue: "Cover",
      comment: "Redact inspector section header: which kinds of data to cover"
    )
    static let redactEmails = string(
      "automations.redact.emails",
      defaultValue: "Email addresses",
      comment: "Redact category"
    )
    static let redactPhoneNumbers = string(
      "automations.redact.phone-numbers",
      defaultValue: "Phone numbers",
      comment: "Redact category"
    )
    static let redactURLs = string(
      "automations.redact.urls",
      defaultValue: "Links",
      comment: "Redact category"
    )
    static let redactPaymentCards = string(
      "automations.redact.payment-cards",
      defaultValue: "Payment cards",
      comment: "Redact category: card numbers, expiry dates, cardholder names"
    )
    static let redactCredentials = string(
      "automations.redact.credentials",
      defaultValue: "Passwords & tokens",
      comment: "Redact category: passwords, API keys, access tokens"
    )
    static let redactFaces = string(
      "automations.redact.faces",
      defaultValue: "Faces",
      comment: "Redact category"
    )
    static let redactPeople = string(
      "automations.redact.people",
      defaultValue: "People",
      comment: "Redact category: whole bodies"
    )
    static let redactStyleLabel = string(
      "automations.redact.style",
      defaultValue: "Style",
      comment: "Redact inspector picker label"
    )
    static let redactStylePixelate = string(
      "automations.redact.style.pixelate",
      defaultValue: "Pixelate",
      comment: "Redact style"
    )
    static let redactStyleBlur = string(
      "automations.redact.style.blur",
      defaultValue: "Blur",
      comment: "Redact style"
    )
    static let redactStyleSolid = string(
      "automations.redact.style.solid",
      defaultValue: "Black box",
      comment: "Redact style: solid black rectangle"
    )
    static let redactPrivacyNote = string(
      "automations.redact.privacy-note",
      defaultValue: "Detection runs on this Mac. Nothing is sent anywhere, and the run log keeps only how many areas were covered.",
      comment: "Redact inspector footer"
    )
    static let redactNothing = string(
      "automations.redact.nothing",
      defaultValue: "Nothing selected",
      comment: "Redact step summary when no category is on"
    )
    static let aiPromptLabel = string(
      "automations.ai.prompt",
      defaultValue: "Prompt",
      comment: "AI Describe inspector field"
    )
    static let aiProviderLabel = string(
      "automations.ai.provider",
      defaultValue: "AI provider",
      comment: "AI Describe inspector picker"
    )
    static let aiProviderSettings = string(
      "automations.ai.provider.settings",
      defaultValue: "As in AI settings",
      comment: "AI Describe provider choice: the provider chosen in Settings"
    )
    static let aiPrivacyNote = string(
      "automations.ai.privacy-note",
      defaultValue: "The image leaves this Mac. Snapzy asks once per provider before sending; runs from the CLI or Shortcuts fail until you have agreed.",
      comment: "AI Describe inspector footer"
    )
    static let aiOutputNote = string(
      "automations.ai.output-note",
      defaultValue: "Apple Intelligence can't see images, so pick an AI endpoint or agent CLI.",
      comment: "AI Describe inspector footer"
    )
    static let errorAINotConfigured = string(
      "automations.error.ai-not-configured",
      defaultValue: "No AI provider can look at images. Add an AI endpoint or agent CLI in Settings → AI.",
      comment: "Run error of the AI Describe step"
    )
    static let issueRedactAfterNetwork = string(
      "automations.issue.redact-after-network",
      defaultValue: "Runs after the image was already sent; move Redact up",
      comment: "Editor warning: the Redact step comes after an upload or webhook"
    )
    static func logRedactedCount(_ count: Int) -> String {
      format(
        "automations.log.redacted-count",
        defaultValue: "%lld areas covered",
        comment: "Run log detail of the Redact step. %lld = number of covered areas",
        count
      )
    }
    static func errorAIConsent(_ name: String) -> String {
      format(
        "automations.error.ai-consent",
        defaultValue: "Sending images to %@ isn't allowed yet. Run this automation from Snapzy once to agree.",
        comment: "Run error of the AI Describe step. %@ = provider name",
        name
      )
    }
    static func aiConsentTitle(_ name: String) -> String {
      format(
        "automations.ai.consent.title",
        defaultValue: "Send captures to %@?",
        comment: "Consent alert title. %@ = AI provider name",
        name
      )
    }
    static func aiConsentMessage(_ host: String) -> String {
      format(
        "automations.ai.consent.message",
        defaultValue: "This automation sends each capture it runs on, with your prompt, to %@. Only agree if you trust that service with your screenshots.",
        comment: "Consent alert message. %@ = host name",
        host
      )
    }
    static func aiConsentMessageCLI(_ name: String) -> String {
      format(
        "automations.ai.consent.message-cli",
        defaultValue: "This automation hands each capture it runs on, with your prompt, to %@, which forwards it to its own model provider and may load your MCP servers and hooks.",
        comment: "Consent alert message for agent CLIs. %@ = CLI name",
        name
      )
    }
    static let invocationCaptureToolbar = string(
      "automations.invocation.capture-toolbar",
      defaultValue: "Capture toolbar",
      comment: "Name of a way an automation was started: a capture toolbar button"
    )
    static let showInCaptureToolbar = string(
      "automations.trigger.capture-toolbar",
      defaultValue: "Capture toolbar",
      comment: "Trigger toggle: show this automation as a capture toolbar button"
    )
    static func importURLConfirmTitle(_ host: String) -> String {
      format(
        "automations.import.url-confirm.title",
        defaultValue: "Download automations from %@?",
        comment: "Alert before importing a recipe from a link. %@ = host name",
        host
      )
    }
    static let importURLConfirmMessage = string(
      "automations.import.url-confirm.message",
      defaultValue: "Snapzy downloads the file and shows what it contains. Nothing is added or turned on until you choose to import.",
      comment: "Alert message before importing a recipe from a link"
    )
    static let importURLConfirmButton = string(
      "automations.import.url-confirm.button",
      defaultValue: "Download",
      comment: "Alert button: download the recipe file"
    )
    static let presetSafeShare = string(
      "automations.preset.safe-share",
      defaultValue: "Safe Share",
      comment: "Built-in automation: capture an area, cover sensitive data, upload and copy the link"
    )

    // MARK: - Milestone 6: recipe gallery & sharing

    static let personaSharing = string(
      "automations.persona.sharing",
      defaultValue: "Chat & sharing",
      comment: "Gallery group: recipes for sharing captures in chats"
    )
    static let personaDocsDesign = string(
      "automations.persona.docs-design",
      defaultValue: "Docs & design",
      comment: "Gallery group"
    )
    static let personaSupport = string(
      "automations.persona.support",
      defaultValue: "Support & QA",
      comment: "Gallery group"
    )
    static let personaReading = string(
      "automations.persona.reading",
      defaultValue: "Reading & translation",
      comment: "Gallery group"
    )
    static let personaPrivacy = string(
      "automations.persona.privacy",
      defaultValue: "Privacy",
      comment: "Gallery group"
    )
    static let galleryQuickCopy = string(
      "automations.gallery.quick-copy",
      defaultValue: "Capture an area and copy the image, ready to paste in a chat.",
      comment: "Gallery description"
    )
    static let galleryCloudShare = string(
      "automations.gallery.cloud-share",
      defaultValue: "Copy the image, upload it and copy its link.",
      comment: "Gallery description"
    )
    static let galleryDocsShot = string(
      "automations.gallery.docs-shot",
      defaultValue: "Window capture with your canvas preset, resized to 1600 px, saved as WebP to your docs folder with a Markdown link copied.",
      comment: "Gallery description"
    )
    static let galleryGIFShare = string(
      "automations.gallery.gif-share",
      defaultValue: "Record an area as a GIF, upload it and copy the link.",
      comment: "Gallery description"
    )
    static let galleryTranslateSnip = string(
      "automations.gallery.translate-snip",
      defaultValue: "Read the text in an area, translate it and copy the result.",
      comment: "Gallery description"
    )
    static let galleryShareMenu = string(
      "automations.gallery.share-menu",
      defaultValue: "One shortcut, then pick Quick Copy, Cloud Share or Docs Shot after capturing.",
      comment: "Gallery description"
    )
    static let galleryDesignRouter = string(
      "automations.gallery.design-router",
      defaultValue: "Figma and Sketch windows go to your design folder, everything else to the export folder.",
      comment: "Gallery description"
    )
    static let gallerySafeShare = string(
      "automations.gallery.safe-share",
      defaultValue: "Cover emails, phone and card numbers and tokens on this Mac, then upload and copy the link.",
      comment: "Gallery description"
    )
    static let galleryTitle = string(
      "automations.gallery.title",
      defaultValue: "Gallery",
      comment: "Sheet title: built-in automation recipes"
    )
    static let galleryButton = string(
      "automations.gallery.button",
      defaultValue: "Gallery…",
      comment: "Button: open the built-in recipe gallery"
    )
    static let galleryAdd = string(
      "automations.gallery.add",
      defaultValue: "Add",
      comment: "Gallery button: add this recipe as a new automation"
    )
    static let galleryAdded = string(
      "automations.gallery.added",
      defaultValue: "Added",
      comment: "Gallery label: this recipe is already in the list"
    )
    static let galleryNeedsSetupNote = string(
      "automations.gallery.needs-setup",
      defaultValue: "Added off until you choose a folder",
      comment: "Gallery note under recipes that need a folder"
    )
    static let importButton = string(
      "automations.import.button",
      defaultValue: "Import…",
      comment: "Button: import automations from a .snapzyautomation file"
    )
    static let importTitle = string(
      "automations.import.title",
      defaultValue: "Import Automations",
      comment: "Import sheet title"
    )
    static let importConfirm = string(
      "automations.import.confirm",
      defaultValue: "Import",
      comment: "Import sheet confirm button"
    )
    static let importNeedsSetup = string(
      "automations.import.needs-setup",
      defaultValue: "Needs setup",
      comment: "Import sheet badge: a folder, uploader or secret must be chosen first"
    )
    static let importNeedsReview = string(
      "automations.import.needs-review",
      defaultValue: "Review before use",
      comment: "Import sheet badge: webhook, script or AI steps must be reviewed in the editor"
    )
    static let importDisabledNote = string(
      "automations.import.disabled-note",
      defaultValue: "Imported automations from a link start turned off.",
      comment: "Import sheet footer for URL imports"
    )
    static let importOverCap = string(
      "automations.import.over-cap",
      defaultValue: "Only the first ones fit: you can have up to 20 automations.",
      comment: "Import sheet warning"
    )
    static let trustLocal = string(
      "automations.trust.local",
      defaultValue: "On this Mac",
      comment: "Trust badge: all steps run locally"
    )
    static let trustNetwork = string(
      "automations.trust.network",
      defaultValue: "Uses the network",
      comment: "Trust badge: uploads, webhooks or AI"
    )
    static let trustCode = string(
      "automations.trust.code",
      defaultValue: "Runs code",
      comment: "Trust badge: scripts or Shortcuts"
    )
    static let exportButton = string(
      "automations.export.button",
      defaultValue: "Export…",
      comment: "Menu item: save the automation as a .snapzyautomation file"
    )
    static let copyTOML = string(
      "automations.export.copy-toml",
      defaultValue: "Copy as TOML",
      comment: "Menu item: copy the automation as a config-file snippet"
    )
    static let copiedTOML = string(
      "automations.export.copied-toml",
      defaultValue: "TOML copied",
      comment: "Toast after copying a TOML snippet"
    )
    static let exportAll = string(
      "automations.export.all",
      defaultValue: "Export All…",
      comment: "Button: save every automation in one .snapzyautomation file"
    )
    static let recipeErrorNotARecipe = string(
      "automations.recipe.error.not-a-recipe",
      defaultValue: "This isn't a Snapzy automation file.",
      comment: "Import error"
    )
    static let recipeErrorEmpty = string(
      "automations.recipe.error.empty",
      defaultValue: "The file has no automations this version of Snapzy can read.",
      comment: "Import error"
    )
    static let recipeErrorTooLarge = string(
      "automations.recipe.error.too-large",
      defaultValue: "The file is too large (links: 256 KB, files: 1 MB).",
      comment: "Import error"
    )
    static let recipeErrorInsecureURL = string(
      "automations.recipe.error.insecure-url",
      defaultValue: "Automations can only be imported from https:// links.",
      comment: "Import error"
    )
    static func recipeErrorVersion(_ version: Int) -> String {
      format(
        "automations.recipe.error.version",
        defaultValue: "This file needs a newer Snapzy (format %lld).",
        comment: "Import error. %lld = file format version",
        version
      )
    }
    // MARK: Event triggers (milestone 7)
    static let eventsHeader = string(
      "automations.events.header",
      defaultValue: "Run Automatically",
      comment: "Editor section: triggers that run by themselves"
    )
    static let eventCaptureSaved = string(
      "automations.events.capture-saved",
      defaultValue: "When a Snapzy capture is saved",
      comment: "Toggle: run after every standard Snapzy capture"
    )
    static let eventCaptureKinds = string(
      "automations.events.capture-kinds",
      defaultValue: "Captures",
      comment: "Picker label: which captures fire the trigger"
    )
    static let eventCaptureScreenshots = string(
      "automations.events.capture-screenshots",
      defaultValue: "Screenshots",
      comment: "Segment: screenshots only"
    )
    static let eventCaptureRecordings = string(
      "automations.events.capture-recordings",
      defaultValue: "Recordings",
      comment: "Segment: recordings only"
    )
    static let eventCaptureBoth = string(
      "automations.events.capture-both",
      defaultValue: "Both",
      comment: "Segment: screenshots and recordings"
    )
    static let eventClipboard = string(
      "automations.events.clipboard",
      defaultValue: "When an image is copied",
      comment: "Toggle: run when another app copies an image"
    )
    static let eventClipboardDescription = string(
      "automations.events.clipboard-description",
      defaultValue: "Runs on images other apps copy. Snapzy’s own copies and password managers are ignored.",
      comment: "Caption under the clipboard event toggle"
    )
    static let eventFolder = string(
      "automations.events.folder",
      defaultValue: "When a file is added to a folder",
      comment: "Toggle: run when a file is added to a watched folder"
    )
    static let eventFolderChange = string(
      "automations.events.folder-change",
      defaultValue: "Change…",
      comment: "Button: pick another watched folder"
    )
    static let eventFolderNone = string(
      "automations.events.folder-none",
      defaultValue: "No folder chosen",
      comment: "No watched folder chosen yet"
    )
    static let eventFolderMissing = string(
      "automations.events.folder-missing",
      defaultValue: "Folder not found. Choose it again.",
      comment: "Watched folder no longer exists"
    )
    static let eventsFooter = string(
      "automations.events.footer",
      defaultValue: "Runs in the background on the new file. Files Snapzy saves itself are skipped, and an automation that fires too often is paused until you edit it. Script and Shortcut steps never run from clipboard or folder events.",
      comment: "Footer of the event triggers section"
    )
    static let eventsPausedGlobally = string(
      "automations.events.paused-globally",
      defaultValue: "Event triggers are paused in Settings → Automations → Advanced.",
      comment: "Editor note: all event triggers are paused in Advanced"
    )
    static let invocationCaptureSaved = string(
      "automations.invocation.capture-saved",
      defaultValue: "Capture saved",
      comment: "Name of a way an automation was started"
    )
    static let invocationClipboardChange = string(
      "automations.invocation.clipboard-change",
      defaultValue: "Image copied",
      comment: "Name of a way an automation was started"
    )
    static let invocationFolderWatch = string(
      "automations.invocation.folder-watch",
      defaultValue: "File added to folder",
      comment: "Name of a way an automation was started"
    )
    static func canvasTriggerFolder(_ value: String) -> String {
      format(
        "automations.canvas.trigger-folder",
        defaultValue: "Folder: %@",
        comment: "Canvas trigger node summary; %@ is the watched folder name",
        value
      )
    }
    static let rejectionEventCode = string(
      "automations.rejection.event-code",
      defaultValue: "Script and Shortcut steps don’t run from clipboard or folder events.",
      comment: "Launch refused: clipboard / folder event reached a script step"
    )
    static func eventTriggersBurstPaused(_ value: String) -> String {
      format(
        "automations.events.burst-paused",
        defaultValue: "“%@” ran too often and its event triggers were paused. Edit it to turn them back on.",
        comment: "Toast: an automation's event triggers were paused; %@ is its name",
        value
      )
    }
    static let pauseEventsToggle = string(
      "automations.advanced.pause-events",
      defaultValue: "Pause event triggers",
      comment: "Advanced toggle"
    )
    static let pauseEventsDescription = string(
      "automations.advanced.pause-events-description",
      defaultValue: "Stops automations that run by themselves when a capture is saved, an image is copied or a file is added to a folder.",
      comment: "Caption under the pause event triggers toggle"
    )
  }

  nonisolated enum CaptureToolbar {
    static let screenshot = L10n.string(
      "automations.toolbar.screenshot",
      defaultValue: "Screenshot",
      comment: "Capture toolbar button: keep the capture and run the default after-capture steps"
    )
    static let copy = L10n.string(
      "automations.toolbar.copy",
      defaultValue: "Copy",
      comment: "Capture toolbar button"
    )
    static let save = L10n.string(
      "automations.toolbar.save",
      defaultValue: "Save",
      comment: "Capture toolbar button"
    )
    static let upload = L10n.string(
      "automations.toolbar.upload",
      defaultValue: "Upload",
      comment: "Capture toolbar button"
    )
    static let pin = L10n.string(
      "automations.toolbar.pin",
      defaultValue: "Pin",
      comment: "Capture toolbar button"
    )
    static let annotate = L10n.string(
      "automations.toolbar.annotate",
      defaultValue: "Annotate",
      comment: "Capture toolbar button"
    )
    static let text = L10n.string(
      "automations.toolbar.text",
      defaultValue: "Text",
      comment: "Capture toolbar button: recognize and copy the text"
    )
    static let record = L10n.string(
      "automations.toolbar.record",
      defaultValue: "Record",
      comment: "Capture toolbar button: record this area"
    )
    static let scroll = L10n.string(
      "automations.toolbar.scroll",
      defaultValue: "Scroll",
      comment: "Capture toolbar button: scrolling capture of this area"
    )
    static let cancelHelp = L10n.string(
      "automations.toolbar.cancel-help",
      defaultValue: "Cancel (Esc)",
      comment: "Capture toolbar close button tooltip"
    )
    static let accessibilityLabel = L10n.string(
      "automations.toolbar.accessibility",
      defaultValue: "Capture actions",
      comment: "VoiceOver label of the capture toolbar"
    )
    static let shortcutTitle = L10n.string(
      "automations.toolbar.shortcut",
      defaultValue: "Capture with Toolbar",
      comment: "Shortcut / menu name: select an area, then pick an action from a toolbar"
    )
    static let settingsSection = L10n.string(
      "automations.toolbar.settings.section",
      defaultValue: "Capture toolbar",
      comment: "Capture settings section title"
    )
    static let settingsDescription = L10n.string(
      "automations.toolbar.settings.description",
      defaultValue: "Select an area, then pick what to do from a toolbar under it. Press a button's letter, Return for the first one, or Esc to cancel.",
      comment: "Capture settings section description"
    )
    static let showForArea = L10n.string(
      "automations.toolbar.settings.show-for-area",
      defaultValue: "Also use the toolbar for Capture Area",
      comment: "Toggle: the area shortcut ends in the toolbar too"
    )
    static let doubleClickLabel = L10n.string(
      "automations.toolbar.settings.double-click",
      defaultValue: "Double-click in selection",
      comment: "Picker label: what double-clicking inside the selection does"
    )
    static let doubleClickNone = L10n.string(
      "automations.toolbar.settings.double-click-none",
      defaultValue: "Nothing",
      comment: "Double-click action choice"
    )
    static let itemsHeader = L10n.string(
      "automations.toolbar.settings.items",
      defaultValue: "Buttons",
      comment: "Settings list header"
    )
    static let acceleratorLabel = L10n.string(
      "automations.toolbar.settings.accelerator",
      defaultValue: "Key",
      comment: "Column / field: single-key accelerator"
    )
    static let acceleratorTaken = L10n.string(
      "automations.toolbar.settings.accelerator-taken",
      defaultValue: "Already used by another button",
      comment: "Validation message"
    )
    static let automationsNote = L10n.string(
      "automations.toolbar.settings.automations-note",
      defaultValue: "Automations appear here when “Capture toolbar” is on in their triggers.",
      comment: "Settings footer"
    )
    static let resetButton = L10n.string(
      "automations.toolbar.settings.reset",
      defaultValue: "Reset Toolbar",
      comment: "Button: restore the default toolbar"
    )
    static func acceleratorHint(_ key: String) -> String {
      L10n.format(
        "automations.toolbar.accelerator-hint",
        defaultValue: "Press %@",
        comment: "VoiceOver hint. %@ = key",
        key
      )
    }
  }
}
