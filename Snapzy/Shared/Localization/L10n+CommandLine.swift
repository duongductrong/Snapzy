//
//  L10n+CommandLine.swift
//  Snapzy
//
//  Strings for the `snapzy` command line integration: the permission
//  prompt, the capture toast, the Settings section and installer errors.
//

import Foundation

extension L10n {
  nonisolated enum CommandLine {
    static let promptAlwaysAllow = string(
      "command-line.prompt-always-allow",
      defaultValue: "Always Allow",
      comment: "Alert button: always allow this app to use the snapzy command"
    )
    static let promptAllowOnce = string(
      "command-line.prompt-allow-once",
      defaultValue: "Allow Once",
      comment: "Alert button: allow this app to use the snapzy command for this run only"
    )
    static let promptDontAllow = string(
      "command-line.prompt-dont-allow",
      defaultValue: "Don’t Allow",
      comment: "Alert button: deny this app the snapzy command"
    )
    static let unknownApp = string(
      "command-line.unknown-app",
      defaultValue: "An unknown app",
      comment: "Name used when the app behind a snapzy command is unknown"
    )
    static let accessTitle = string(
      "command-line.access-title",
      defaultValue: "Command line access",
      comment: "Settings row title: enable the snapzy command"
    )
    static let accessDescription = string(
      "command-line.access-description",
      defaultValue: "Let apps and AI agents capture with the snapzy command",
      comment: "Settings row description for the snapzy command toggle"
    )
    static let toolTitle = string(
      "command-line.tool-title",
      defaultValue: "snapzy command",
      comment: "Settings row title for installing the snapzy command; keep snapzy verbatim"
    )
    static let toolNotInstalled = string(
      "command-line.tool-not-installed",
      defaultValue: "Not on PATH yet. Apps can still run it from Snapzy.app/Contents/Helpers",
      comment: "snapzy command state when it is not on PATH"
    )
    static let installButton = string(
      "command-line.install-button",
      defaultValue: "Install",
      comment: "Button: install the snapzy command on PATH"
    )
    static let uninstallButton = string(
      "command-line.uninstall-button",
      defaultValue: "Uninstall",
      comment: "Button: remove the snapzy command link from PATH"
    )
    static let copyCommandButton = string(
      "command-line.copy-command-button",
      defaultValue: "Copy Command",
      comment: "Button: copy the Homebrew command that adds the snapzy command"
    )
    static let installFailedTitle = string(
      "command-line.install-failed-title",
      defaultValue: "Couldn’t update the snapzy command",
      comment: "Alert title when installing or removing the snapzy command failed"
    )
    static let allowedAppsTitle = string(
      "command-line.allowed-apps-title",
      defaultValue: "Allowed apps",
      comment: "Settings row title: apps allowed to use the snapzy command"
    )
    static let allowedAppsDescription = string(
      "command-line.allowed-apps-description",
      defaultValue: "Apps that asked to use the snapzy command",
      comment: "Settings row description for the allowed apps list"
    )
    static let allowedAppsEmpty = string(
      "command-line.allowed-apps-empty",
      defaultValue: "No app has asked yet",
      comment: "Shown when no app has asked to use the snapzy command"
    )
    static let statusAllowed = string(
      "command-line.status-allowed",
      defaultValue: "Allowed",
      comment: "Status of an app in the allowed apps list"
    )
    static let statusDenied = string(
      "command-line.status-denied",
      defaultValue: "Denied",
      comment: "Status of an app in the allowed apps list"
    )
    static let removeAppButton = string(
      "command-line.remove-app-button",
      defaultValue: "Remove",
      comment: "Button: forget one app's snapzy command decision"
    )
    static let removeAllButton = string(
      "command-line.remove-all-button",
      defaultValue: "Remove All",
      comment: "Button: forget all snapzy command decisions"
    )
    static let errorHelperMissing = string(
      "command-line.error-helper-missing",
      defaultValue: "This copy of Snapzy doesn’t include the snapzy command.",
      comment: "Error: this Snapzy build has no snapzy command"
    )
    static let errorTemporaryLocation = string(
      "command-line.error-temporary-location",
      defaultValue: "Move Snapzy to the Applications folder first. It is running from a temporary location.",
      comment: "Error: Snapzy runs from a disk image or quarantine location"
    )
    static let errorCancelled = string(
      "command-line.error-cancelled",
      defaultValue: "The change was cancelled.",
      comment: "Error: the administrator password prompt was cancelled"
    )

    static func promptTitle(_ appName: String) -> String {
      format(
        "command-line.prompt-title",
        defaultValue: "“%@” wants to capture your screen with Snapzy",
        comment: "Title of the alert asking whether an app may use the snapzy command; %@ is the app name",
        appName
      )
    }

    static func promptMessage(command: String) -> String {
      format(
        "command-line.prompt-message",
        defaultValue: "It ran “snapzy %@”. If you allow it, this app and anything it runs can capture your displays and windows through Snapzy. You can change this later in Settings → Command Line.",
        comment: "Body of the snapzy command permission alert; %@ is the command, e.g. capture window",
        command
      )
    }

    static func captureToast(_ appName: String) -> String {
      format(
        "command-line.capture-toast",
        defaultValue: "%@ captured the screen with the snapzy command",
        comment: "Toast when another app captured the screen via the snapzy command; %@ is the app name",
        appName
      )
    }

    static func toolInstalled(_ path: String) -> String {
      format(
        "command-line.tool-installed",
        defaultValue: "Installed at %@",
        comment: "snapzy command state; %@ is the link path",
        path
      )
    }

    static func toolPointsElsewhere(_ destination: String) -> String {
      format(
        "command-line.tool-points-elsewhere",
        defaultValue: "Linked to another copy: %@",
        comment: "snapzy command state when the link points to another copy; %@ is the link target",
        destination
      )
    }

    static func toolBlocked(_ path: String) -> String {
      format(
        "command-line.tool-blocked",
        defaultValue: "%@ is a file, not a link",
        comment: "snapzy command state when a regular file occupies the link path; %@ is the path",
        path
      )
    }

    static func errorBlocked(_ path: String) -> String {
      format(
        "command-line.error-blocked",
        defaultValue: "%@ already exists and isn’t a link. Remove it, then try again.",
        comment: "Error: a regular file occupies the link path; %@ is the path",
        path
      )
    }

    static func errorOccupied(path: String, destination: String) -> String {
      format(
        "command-line.error-occupied",
        defaultValue: "%1$@ already links to %2$@. Remove that link, then try again.",
        comment: "Error: another tool's link occupies the path; %1$@ is the path, %2$@ the link target",
        path,
        destination
      )
    }

    static func promptUnverified(path: String) -> String {
      format(
        "command-line.prompt-unverified",
        defaultValue: "Snapzy couldn’t verify who made this app. Only allow it if you trust the app at %@.",
        comment: "Extra line in the snapzy permission alert when the app's signature cannot be verified; %@ is its path",
        path
      )
    }

    static func toolHomebrew(_ path: String) -> String {
      format(
        "command-line.tool-homebrew",
        defaultValue: "Installed by Homebrew at %@",
        comment: "snapzy command state when Homebrew manages the link; %@ is the link path",
        path
      )
    }

    static func toolHomebrewLinkMissing(_ command: String) -> String {
      format(
        "command-line.tool-homebrew-link-missing",
        defaultValue: "Installed with Homebrew. Run %@ in Terminal to put it on PATH",
        comment: "snapzy command state when the Homebrew cask has not linked it yet; %@ is the brew command",
        command
      )
    }

    static func errorHomebrewLinkMissing(_ command: String) -> String {
      format(
        "command-line.error-homebrew-link-missing",
        defaultValue: "Snapzy was installed with Homebrew, which adds the snapzy command. Run %@ in Terminal.",
        comment: "Error: Homebrew should link the snapzy command, not Snapzy; %@ is the brew command",
        command
      )
    }
  }
}
