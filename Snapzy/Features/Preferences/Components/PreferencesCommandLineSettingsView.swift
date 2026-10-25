//
//  PreferencesCommandLineSettingsView.swift
//  Snapzy
//
//  Command Line settings tab: turn the `snapzy` command on or off, put it on
//  PATH, and review the apps that asked to use it.
//

import AppKit
import SwiftUI

struct CommandLineSettingsView: View {
  @AppStorage(PreferencesKeys.cliEnabled) private var cliEnabled = true
  @ObservedObject private var store = CLIAuthorizationStore.shared
  @State private var toolState = CLIToolInstaller.currentState()
  @State private var isUpdatingTool = false

  var body: some View {
    Form {
      Section {
        SettingRow(
          icon: "terminal",
          title: L10n.CommandLine.accessTitle,
          description: L10n.CommandLine.accessDescription
        ) {
          Toggle("", isOn: $cliEnabled)
            .labelsHidden()
        }

        SettingRow(
          icon: "chevron.left.forwardslash.chevron.right",
          title: L10n.CommandLine.toolTitle,
          description: toolStateDescription
        ) {
          if case .managedByHomebrew = toolState {
            EmptyView()
          } else if toolState == .homebrewLinkMissing {
            Button(L10n.CommandLine.copyCommandButton) { copyHomebrewCommand() }
          } else if toolState == .installed {
            Button(L10n.CommandLine.uninstallButton) { updateTool(install: false) }
              .disabled(isUpdatingTool)
          } else {
            Button(L10n.CommandLine.installButton) { updateTool(install: true) }
              .disabled(isUpdatingTool || toolState == .blockedByFile)
          }
        }
      }

      Section {
        if store.callers.isEmpty {
          Text(L10n.CommandLine.allowedAppsEmpty)
            .font(.callout)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }

        ForEach(store.callers) { caller in
          CommandLineAllowedAppRow(caller: caller) {
            store.revoke(key: caller.key)
          }
        }
      } header: {
        CommandLineSectionHeader(
          title: L10n.CommandLine.allowedAppsTitle,
          description: L10n.CommandLine.allowedAppsDescription
        ) {
          if !store.callers.isEmpty {
            Button(L10n.CommandLine.removeAllButton) { store.revokeAll() }
              .buttonStyle(.borderless)
              .font(.caption)
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { toolState = CLIToolInstaller.currentState() }
  }

  private var toolStateDescription: String {
    switch toolState {
    case .installed:
      L10n.CommandLine.toolInstalled(CLIToolInstaller.linkPath)
    case .notInstalled:
      L10n.CommandLine.toolNotInstalled
    case .pointsElsewhere(let destination):
      L10n.CommandLine.toolPointsElsewhere(destination)
    case .blockedByFile:
      L10n.CommandLine.toolBlocked(CLIToolInstaller.linkPath)
    case .managedByHomebrew(let path):
      L10n.CommandLine.toolHomebrew(path)
    case .homebrewLinkMissing:
      L10n.CommandLine.toolHomebrewLinkMissing(CLIToolInstaller.homebrewUpgradeCommand)
    }
  }

  private func copyHomebrewCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(CLIToolInstaller.homebrewUpgradeCommand, forType: .string)
  }

  private func updateTool(install: Bool) {
    isUpdatingTool = true
    Task {
      do {
        if install {
          try await CLIToolInstaller.install()
        } else {
          try await CLIToolInstaller.uninstall()
        }
      } catch CLIToolInstaller.InstallError.cancelled {
        // The user dismissed the password prompt; nothing to report.
      } catch {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.CommandLine.installFailedTitle
        alert.informativeText = error.localizedDescription
        alert.runModal()
      }
      toolState = CLIToolInstaller.currentState()
      isUpdatingTool = false
    }
  }
}

/// Title over a one-line description, like the other list sections in Settings.
private struct CommandLineSectionHeader<Accessory: View>: View {
  let title: String
  let description: String
  @ViewBuilder let accessory: () -> Accessory

  var body: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .foregroundColor(.primary)
        Text(description)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()
      accessory()
    }
    .padding(.bottom, 4)
  }
}

private struct CommandLineAllowedAppRow: View {
  let caller: CLIApprovedCaller
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: caller.path))
        .resizable()
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: caller.displayName)
          .fontWeight(.medium)
        Text(verbatim: subtitle)
          .font(.caption)
          .foregroundColor(caller.decision == .allow ? .secondary : .red)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      Button(L10n.CommandLine.removeAppButton, action: onRemove)
    }
    .padding(.vertical, 4)
    .help(caller.path)
  }

  private var subtitle: String {
    let status = caller.decision == .allow ? L10n.CommandLine.statusAllowed : L10n.CommandLine.statusDenied
    return [status, caller.bundleID].compactMap { $0 }.joined(separator: " · ")
  }
}
