//
//  L10nPlugins.swift
//  Snapzy
//
//  Localized copy for Settings > Plugins and the plugin consent surfaces.
//
//  The consent sentences live here on purpose: they are *generated* from a
//  capability id and its scope, never written by a plugin author, and the
//  Plugins tab and the consent alerts must read identically.
//

import Foundation

extension L10n {
  enum PreferencesPlugins {
    // MARK: - Tab chrome

    static let intro = string(
      "preferences-plugins.intro",
      defaultValue: "Plugins add extra tools to Snapzy. Each one runs locked away from the rest of your Mac and has to ask before it can read your capture, use the internet, or change anything.",
      comment: "Plugins settings introduction shown at the top of the tab"
    )
    static let segmentInstalled = string(
      "preferences-plugins.segment-installed",
      defaultValue: "Installed",
      comment: "Plugins settings segmented control option showing installed plugins"
    )
    static let segmentDiscover = string(
      "preferences-plugins.segment-discover",
      defaultValue: "Discover",
      comment: "Plugins settings segmented control option showing plugins available to install"
    )

    // MARK: - Installed

    static let installedSection = string(
      "preferences-plugins.installed-section",
      defaultValue: "Your Plugins",
      comment: "Plugins settings section title listing installed plugins"
    )
    static let emptyTitle = string(
      "preferences-plugins.empty-title",
      defaultValue: "No plugins yet",
      comment: "Plugins settings empty state title"
    )
    static let emptyMessage = string(
      "preferences-plugins.empty-message",
      defaultValue: "Add one from Discover to give Snapzy extra tools.",
      comment: "Plugins settings empty state message"
    )
    static let emptyAction = string(
      "preferences-plugins.empty-action",
      defaultValue: "Browse Plugins",
      comment: "Plugins settings empty state button that switches to the Discover list"
    )
    static let detailsButton = string(
      "preferences-plugins.details-button",
      defaultValue: "Show details",
      comment: "Plugins settings accessibility label for the button opening a plugin's details"
    )
    static let enableHelp = string(
      "preferences-plugins.enable-help",
      defaultValue: "Turn this plugin on or off",
      comment: "Plugins settings tooltip for the per-plugin on/off switch"
    )

    // MARK: - Updates

    static let updatesSection = string(
      "preferences-plugins.updates-section",
      defaultValue: "Updates",
      comment: "Plugins settings section title for the update check"
    )
    static let checkUpdates = string(
      "preferences-plugins.check-updates",
      defaultValue: "Check for Updates",
      comment: "Plugins settings button that refreshes installed plugins and the online list"
    )
    static let checkUpdatesDescription = string(
      "preferences-plugins.check-updates-description",
      defaultValue: "Look for newer versions of the plugins you have installed.",
      comment: "Plugins settings description for the update check button"
    )
    static let checking = string(
      "preferences-plugins.checking",
      defaultValue: "Checking…",
      comment: "Plugins settings status while the update check is running"
    )
    static let checkedJustNow = string(
      "preferences-plugins.checked-just-now",
      defaultValue: "Everything is up to date.",
      comment: "Plugins settings status after an update check found nothing new"
    )

    // MARK: - Discover

    static let discoverSection = string(
      "preferences-plugins.discover-section",
      defaultValue: "Available Plugins",
      comment: "Plugins settings section title for the online plugin list"
    )
    static let discoverLoading = string(
      "preferences-plugins.discover-loading",
      defaultValue: "Loading plugins…",
      comment: "Plugins settings status while the online plugin list downloads"
    )
    static let discoverOffline = string(
      "preferences-plugins.discover-offline",
      defaultValue: "You're offline. This is the list Snapzy downloaded last time.",
      comment: "Plugins settings banner shown when the online plugin list could not be refreshed"
    )
    static func discoverFailed(_ reason: String) -> String {
      format(
        "preferences-plugins.discover-failed",
        defaultValue: "Couldn't load the plugin list: %@",
        comment: "Plugins settings error when the online plugin list fails to load. %@ is the reason.",
        reason
      )
    }
    static let discoverEmpty = string(
      "preferences-plugins.discover-empty",
      defaultValue: "No plugins are available right now.",
      comment: "Plugins settings message when the online plugin list is empty"
    )
    static let discoverRetry = string(
      "preferences-plugins.discover-retry",
      defaultValue: "Try Again",
      comment: "Plugins settings button retrying the online plugin list download"
    )
    static let install = string(
      "preferences-plugins.install",
      defaultValue: "Install",
      comment: "Plugins settings button installing a plugin"
    )
    static let installing = string(
      "preferences-plugins.installing",
      defaultValue: "Installing…",
      comment: "Plugins settings status while a plugin installs"
    )
    static let installed = string(
      "preferences-plugins.installed",
      defaultValue: "Installed",
      comment: "Plugins settings label for a plugin that is already installed"
    )
    static let update = string(
      "preferences-plugins.update",
      defaultValue: "Update",
      comment: "Plugins settings button updating an installed plugin"
    )
    static func installFailed(_ reason: String) -> String {
      format(
        "preferences-plugins.install-failed",
        defaultValue: "Couldn't install: %@",
        comment: "Plugins settings error when installing fails. %@ is the reason.",
        reason
      )
    }
    static let installSucceeded = string(
      "preferences-plugins.install-succeeded",
      defaultValue: "Installed.",
      comment: "Plugins settings confirmation after a plugin installs"
    )
    static let withdrawn = string(
      "preferences-plugins.withdrawn",
      defaultValue: "Withdrawn",
      comment: "Plugins settings badge for a plugin that was pulled from the online list"
    )
    static let withdrawnMessage = string(
      "preferences-plugins.withdrawn-message",
      defaultValue: "Snapzy pulled this plugin. It can't be installed.",
      comment: "Plugins settings explanation for a withdrawn plugin"
    )

    // MARK: - Detail

    static let permissionsTitle = string(
      "preferences-plugins.permissions-title",
      defaultValue: "What it can do",
      comment: "Plugin details section title listing what the plugin is allowed to do"
    )
    static let permissionsNone = string(
      "preferences-plugins.permissions-none",
      defaultValue: "This plugin doesn't ask for anything sensitive.",
      comment: "Plugin details message when a plugin declares no capabilities"
    )
    static let commandsTitle = string(
      "preferences-plugins.commands-title",
      defaultValue: "What it adds",
      comment: "Plugin details section title listing the commands a plugin contributes"
    )
    static let commandsNone = string(
      "preferences-plugins.commands-none",
      defaultValue: "This plugin doesn't add any commands.",
      comment: "Plugin details message when a plugin contributes no commands"
    )
    static let commandsWhere = string(
      "preferences-plugins.commands-where",
      defaultValue: "Right-click a capture in Annotate to run these.",
      comment: "Plugin details hint explaining where plugin commands appear"
    )
    static let problemTitle = string(
      "preferences-plugins.problem-title",
      defaultValue: "Needs your attention",
      comment: "Plugin details section title for the reason a plugin cannot run"
    )
    static let warningsTitle = string(
      "preferences-plugins.warnings-title",
      defaultValue: "Good to know",
      comment: "Plugin details section title for non-blocking warnings"
    )
    static let locationTitle = string(
      "preferences-plugins.location-title",
      defaultValue: "Location",
      comment: "Plugin details section title for the plugin's folder on disk"
    )
    static func version(_ value: String) -> String {
      format(
        "preferences-plugins.version",
        defaultValue: "Version %@",
        comment: "Plugin details version line. %@ is the version number.",
        value
      )
    }
    static let sandboxNote = string(
      "preferences-plugins.sandbox-note",
      defaultValue: "Every plugin is locked away from the rest of your Mac in the same way, whoever made it.",
      comment: "Plugin details reassurance shown next to the trust badge"
    )
    static let resetPermissions = string(
      "preferences-plugins.reset-permissions",
      defaultValue: "Ask Me Again",
      comment: "Plugin details button clearing recorded consent"
    )
    static let resetPermissionsDescription = string(
      "preferences-plugins.reset-permissions-description",
      defaultValue: "Forget what you allowed, so Snapzy asks the next time this plugin runs.",
      comment: "Plugin details description for the consent reset button"
    )
    static let resetPermissionsDone = string(
      "preferences-plugins.reset-permissions-done",
      defaultValue: "Snapzy will ask for permission again next time.",
      comment: "Plugin details confirmation after consent is reset"
    )
    static let remove = string(
      "preferences-plugins.remove",
      defaultValue: "Remove Plugin…",
      comment: "Plugin details button removing the plugin"
    )
    static func removeAlertTitle(_ name: String) -> String {
      format(
        "preferences-plugins.remove-alert-title",
        defaultValue: "Remove “%@”?",
        comment: "Plugin removal confirmation title. %@ is the plugin name.",
        name
      )
    }
    static let removeAlertMessage = string(
      "preferences-plugins.remove-alert-message",
      defaultValue: "This deletes the plugin along with its settings and anything it saved, including passwords it stored. You can't undo this.",
      comment: "Plugin removal confirmation message"
    )
    static let removeConfirm = string(
      "preferences-plugins.remove-confirm",
      defaultValue: "Remove",
      comment: "Plugin removal confirmation button"
    )
    static let done = string(
      "preferences-plugins.done",
      defaultValue: "Done",
      comment: "Plugin details button closing the sheet"
    )

    // MARK: - Developer tools

    static let developerSection = string(
      "preferences-plugins.developer-section",
      defaultValue: "Developer Tools",
      comment: "Plugins settings collapsed section holding plugin-authoring tools"
    )
    static let developerDescription = string(
      "preferences-plugins.developer-description",
      defaultValue: "For people building plugins. You don't need any of this to use Snapzy.",
      comment: "Plugins settings description for the developer tools section"
    )
    static let loadFolder = string(
      "preferences-plugins.load-folder",
      defaultValue: "Load Plugin from Folder…",
      comment: "Plugins settings button loading a plugin from a local folder"
    )
    static let loadFolderPrompt = string(
      "preferences-plugins.load-folder-prompt",
      defaultValue: "Load Plugin",
      comment: "Open panel confirmation button when loading a plugin folder"
    )
    static func loadFolderSucceeded(_ name: String) -> String {
      format(
        "preferences-plugins.load-folder-succeeded",
        defaultValue: "Loaded %@.",
        comment: "Plugins settings confirmation after loading a local plugin. %@ is the plugin name.",
        name
      )
    }
    static func loadFolderFailed(_ reason: String) -> String {
      format(
        "preferences-plugins.load-folder-failed",
        defaultValue: "Couldn't load: %@",
        comment: "Plugins settings error after loading a local plugin fails. %@ is the reason.",
        reason
      )
    }
    static let developmentNote = string(
      "preferences-plugins.development-note",
      defaultValue: "Plugins loaded from a folder reload themselves whenever you rebuild them.",
      comment: "Plugins settings note about live reload for development plugins"
    )
    static let activityLog = string(
      "preferences-plugins.activity-log",
      defaultValue: "Activity Log",
      comment: "Plugins settings title for the log of host calls made by plugins"
    )
    static let activityLogDescription = string(
      "preferences-plugins.activity-log-description",
      defaultValue: "Everything plugins asked Snapzy to do. Passwords and other secrets are stripped out, so it's safe to paste into a bug report.",
      comment: "Plugins settings description for the activity log"
    )
    static let activityLogEmpty = string(
      "preferences-plugins.activity-log-empty",
      defaultValue: "Nothing yet. Run a plugin command and its requests show up here.",
      comment: "Plugins settings empty state for the activity log"
    )
    static let refresh = string(
      "preferences-plugins.refresh",
      defaultValue: "Refresh",
      comment: "Plugins settings button reloading the activity log"
    )
    static let copy = string(
      "preferences-plugins.copy",
      defaultValue: "Copy",
      comment: "Plugins settings button copying the activity log"
    )
    static let copied = string(
      "preferences-plugins.copied",
      defaultValue: "Copied",
      comment: "Plugins settings confirmation after copying the activity log"
    )

    // MARK: - Status

    static let statusReady = string(
      "preferences-plugins.status-ready",
      defaultValue: "Ready",
      comment: "Plugin status: the plugin is set up and working"
    )
    static let statusNeedsSetup = string(
      "preferences-plugins.status-needs-setup",
      defaultValue: "Needs setup",
      comment: "Plugin status: the plugin needs something from the user before it can run"
    )
    static let statusOff = string(
      "preferences-plugins.status-off",
      defaultValue: "Off",
      comment: "Plugin status: the user turned the plugin off"
    )
    static let statusNotWorking = string(
      "preferences-plugins.status-not-working",
      defaultValue: "Not working",
      comment: "Plugin status: the plugin is broken or was rejected"
    )
    static let statusNeedsUpdate = string(
      "preferences-plugins.status-needs-update",
      defaultValue: "Needs a newer Snapzy",
      comment: "Plugin status: the plugin requires a newer app version"
    )
    static let statusDeveloper = string(
      "preferences-plugins.status-developer",
      defaultValue: "Developer",
      comment: "Plugin status: the plugin was loaded from a folder for development"
    )
    static let statusBlocked = string(
      "preferences-plugins.status-blocked",
      defaultValue: "Blocked",
      comment: "Plugin status: the plugin was quarantined and cannot run"
    )

    // MARK: - Trust tiers

    static let tierOfficial = string(
      "preferences-plugins.tier-official",
      defaultValue: "Made by Snapzy",
      comment: "Plugin trust tier: published by the Snapzy team"
    )
    static let tierVerified = string(
      "preferences-plugins.tier-verified",
      defaultValue: "Known developer",
      comment: "Plugin trust tier: the publisher is verified but the code is not audited"
    )
    static let tierCommunity = string(
      "preferences-plugins.tier-community",
      defaultValue: "Community",
      comment: "Plugin trust tier: unreviewed community plugin"
    )
    static let tierDevelopment = string(
      "preferences-plugins.tier-development",
      defaultValue: "Loaded from a folder",
      comment: "Plugin trust tier: sideloaded during development"
    )

    // MARK: - Capability names

    static let capabilityNetwork = string(
      "preferences-plugins.capability-network",
      defaultValue: "Internet",
      comment: "Friendly name for the network capability"
    )
    static let capabilityAssetRead = string(
      "preferences-plugins.capability-asset-read",
      defaultValue: "Your capture",
      comment: "Friendly name for the asset-read capability"
    )
    static let capabilityDocumentWrite = string(
      "preferences-plugins.capability-document-write",
      defaultValue: "Editing",
      comment: "Friendly name for the document-write capability"
    )
    static let capabilityClipboardWrite = string(
      "preferences-plugins.capability-clipboard-write",
      defaultValue: "Clipboard",
      comment: "Friendly name for the clipboard-write capability"
    )
    static let capabilitySecrets = string(
      "preferences-plugins.capability-secrets",
      defaultValue: "Saved password",
      comment: "Friendly name for the secrets capability"
    )
    static let capabilityOCR = string(
      "preferences-plugins.capability-ocr",
      defaultValue: "Text recognition",
      comment: "Friendly name for the OCR capability"
    )
    static let capabilityImage = string(
      "preferences-plugins.capability-image",
      defaultValue: "Image editing",
      comment: "Friendly name for the image processing capability"
    )
    static let capabilityMedia = string(
      "preferences-plugins.capability-media",
      defaultValue: "Video",
      comment: "Friendly name for the media capability"
    )
    static let capabilityUI = string(
      "preferences-plugins.capability-ui",
      defaultValue: "Questions",
      comment: "Friendly name for the UI capability"
    )
    static let capabilityStorage = string(
      "preferences-plugins.capability-storage",
      defaultValue: "Its own settings",
      comment: "Friendly name for the storage capability"
    )
    static let capabilityNotify = string(
      "preferences-plugins.capability-notify",
      defaultValue: "Notifications",
      comment: "Friendly name for the notification capability"
    )
    static let capabilityOther = string(
      "preferences-plugins.capability-other",
      defaultValue: "Other",
      comment: "Friendly name for a capability Snapzy has no specific copy for"
    )

    // MARK: - Consent sentences

    /// These read as the predicate of “<Plugin name> …”, so they stay
    /// lowercase and verb-first in English.
    static func consentNetwork(_ hosts: String) -> String {
      format(
        "preferences-plugins.consent-network",
        defaultValue: "can send data to %@",
        comment: "Consent sentence for network access. %@ is a comma-separated host list.",
        hosts
      )
    }
    static let consentNetworkGeneric = string(
      "preferences-plugins.consent-network-generic",
      defaultValue: "can send data over the internet",
      comment: "Consent sentence for network access with no declared hosts"
    )
    static func consentAssetRead(_ kinds: String) -> String {
      format(
        "preferences-plugins.consent-asset-read",
        defaultValue: "can read %@",
        comment: "Consent sentence for reading the capture. %@ is a comma-separated list of file kinds.",
        kinds
      )
    }
    static let consentAssetReadGeneric = string(
      "preferences-plugins.consent-asset-read-generic",
      defaultValue: "can read the capture you run it on",
      comment: "Consent sentence for reading the capture with no declared kinds"
    )
    static func consentDocumentWrite(_ operations: String) -> String {
      format(
        "preferences-plugins.consent-document-write",
        defaultValue: "can change what you have open (%@)",
        comment: "Consent sentence for editing the open document. %@ is a comma-separated list of edit operations.",
        operations
      )
    }
    static let consentDocumentWriteGeneric = string(
      "preferences-plugins.consent-document-write-generic",
      defaultValue: "can change what you have open",
      comment: "Consent sentence for editing the open document with no declared operations"
    )
    static let consentClipboardWrite = string(
      "preferences-plugins.consent-clipboard-write",
      defaultValue: "can put things on your clipboard",
      comment: "Consent sentence for clipboard writes"
    )
    static let consentSecrets = string(
      "preferences-plugins.consent-secrets",
      defaultValue: "can save a password of its own in your Keychain",
      comment: "Consent sentence for secret storage"
    )
    static let consentOCR = string(
      "preferences-plugins.consent-ocr",
      defaultValue: "can read text in images, on your Mac",
      comment: "Consent sentence for on-device OCR"
    )
    static let consentImage = string(
      "preferences-plugins.consent-image",
      defaultValue: "can resize and crop images",
      comment: "Consent sentence for image processing"
    )
    static let consentMedia = string(
      "preferences-plugins.consent-media",
      defaultValue: "can look inside videos",
      comment: "Consent sentence for media inspection"
    )
    static let consentUI = string(
      "preferences-plugins.consent-ui",
      defaultValue: "can ask you questions",
      comment: "Consent sentence for host-rendered UI"
    )
    static let consentStorage = string(
      "preferences-plugins.consent-storage",
      defaultValue: "can save its own settings",
      comment: "Consent sentence for plugin-private storage"
    )
    static let consentNotify = string(
      "preferences-plugins.consent-notify",
      defaultValue: "can send you notifications",
      comment: "Consent sentence for notifications"
    )
    // MARK: - Scope vocabularies
    //
    // Manifest scopes carry API tokens (`addItem`, `annotateSession`). They are
    // small closed sets, so they get read out in words. An unrecognized token
    // falls through to its raw form rather than disappearing.

    static let editAddItem = string(
      "preferences-plugins.edit-add-item",
      defaultValue: "add things",
      comment: "Friendly name for the addItem document edit operation"
    )
    static let editUpdateItem = string(
      "preferences-plugins.edit-update-item",
      defaultValue: "change things",
      comment: "Friendly name for the updateItem document edit operation"
    )
    static let editRemoveItem = string(
      "preferences-plugins.edit-remove-item",
      defaultValue: "delete things",
      comment: "Friendly name for the removeItem document edit operation"
    )
    static let editSetCrop = string(
      "preferences-plugins.edit-set-crop",
      defaultValue: "crop",
      comment: "Friendly name for the setCrop document edit operation"
    )
    static let kindScreenshot = string(
      "preferences-plugins.kind-screenshot",
      defaultValue: "screenshots",
      comment: "Friendly name for the screenshot document kind"
    )
    static let kindVideo = string(
      "preferences-plugins.kind-video",
      defaultValue: "videos",
      comment: "Friendly name for the video document kind"
    )
    static let kindGIF = string(
      "preferences-plugins.kind-gif",
      defaultValue: "GIFs",
      comment: "Friendly name for the GIF document kind"
    )
    static let kindAnnotateSession = string(
      "preferences-plugins.kind-annotate-session",
      defaultValue: "what you're annotating",
      comment: "Friendly name for the annotate session document kind"
    )

    static func consentOther(_ capability: String) -> String {
      format(
        "preferences-plugins.consent-other",
        defaultValue: "asks for “%@”",
        comment: "Consent sentence for an unrecognized capability. %@ is the raw capability id.",
        capability
      )
    }
  }
}
