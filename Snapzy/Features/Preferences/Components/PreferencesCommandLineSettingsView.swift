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
      } header: {
        PreferencesPageHero(tab: .commandLine, subtitle: L10n.CommandLine.heroSubtitle)
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
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        CommandLineToolBadge(
          state: toolState,
          stateDescription: toolStateDescription,
          isUpdating: isUpdatingTool,
          onInstall: { updateTool(install: true) },
          onUninstall: { updateTool(install: false) },
          onCopyCommand: copyHomebrewCommand
        )
      }
      ToolbarItem(placement: .primaryAction) {
        Toggle(L10n.CommandLine.accessTitle, isOn: accessBinding)
          .toggleStyle(.switch)
          .controlSize(.small)
          .labelsHidden()
          // Inset so the switch sits inside the toolbar's capsule like the back/forward pair.
          .padding(.horizontal, 8)
          .disabled(isUpdatingTool)
          .help("\(L10n.CommandLine.accessTitle): \(L10n.CommandLine.accessDescription)")
      }
    }
    .onAppear { toolState = CLIToolInstaller.currentState() }
  }

  private var isToolInstalled: Bool {
    switch toolState {
    case .installed, .managedByHomebrew: true
    default: false
    }
  }

  /// Access reads as off until the command is installed; switching it on installs it.
  private var accessBinding: Binding<Bool> {
    Binding(
      get: { isToolInstalled && cliEnabled },
      set: { isOn in
        cliEnabled = isOn
        if isOn, !isToolInstalled {
          updateTool(install: true)
        }
      }
    )
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

/// Toolbar badge for the `snapzy` command on PATH. The icon's colour says whether it's
/// installed; clicking it explains what installing does and offers Install or Uninstall.
private struct CommandLineToolBadge: View {
  let state: CLIToolInstaller.State
  let stateDescription: String
  let isUpdating: Bool
  let onInstall: () -> Void
  let onUninstall: () -> Void
  let onCopyCommand: () -> Void

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(Color.secondary)
        .frame(width: 24, height: 24)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    // Equal inset on every side so the circle sits centred in the toolbar capsule.
    .padding(6)
    .help("\(L10n.CommandLine.toolTitle): \(stateDescription)")
    .accessibilityLabel(L10n.CommandLine.toolTitle)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      popoverContent
        .padding(16)
        .frame(width: 320)
    }
  }

  private var isInstalled: Bool {
    switch state {
    case .installed, .managedByHomebrew: true
    default: false
    }
  }

  private var needsAttention: Bool {
    switch state {
    case .pointsElsewhere, .blockedByFile, .homebrewLinkMissing: true
    default: false
    }
  }

  private var symbol: String {
    if needsAttention { return "exclamationmark.triangle.fill" }
    return isInstalled ? "terminal.fill" : "terminal"
  }

  private var tint: Color {
    if needsAttention { return .orange }
    return isInstalled ? .green : .secondary
  }

  @ViewBuilder
  private var popoverContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 18))
          .foregroundColor(tint)

        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.CommandLine.toolTitle)
            .font(.system(size: 13, weight: .semibold))
          Text(stateDescription)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }

      Text(L10n.CommandLine.installExplanation)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Spacer(minLength: 0)
        action
      }
      .controlSize(.regular)
    }
  }

  @ViewBuilder
  private var action: some View {
    switch state {
    case .managedByHomebrew:
      EmptyView()
    case .homebrewLinkMissing:
      Button(L10n.CommandLine.copyCommandButton, action: onCopyCommand)
    case .installed:
      Button(L10n.CommandLine.uninstallButton, action: onUninstall)
        .disabled(isUpdating)
    default:
      Button(L10n.CommandLine.installButton, action: onInstall)
        .keyboardShortcut(.defaultAction)
        .disabled(isUpdating || state == .blockedByFile)
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
    .help(caller.path)
  }

  private var subtitle: String {
    let status = caller.decision == .allow ? L10n.CommandLine.statusAllowed : L10n.CommandLine.statusDenied
    return [status, caller.bundleID].compactMap { $0 }.joined(separator: " · ")
  }
}
