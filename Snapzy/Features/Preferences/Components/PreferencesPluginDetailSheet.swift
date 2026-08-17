import AppKit
import SnapzyPluginAPI
import SwiftUI

/// Everything about one plugin, on purpose rather than by accident.
///
/// The list stays short because this sheet exists: permissions in plain
/// language, what the plugin adds, and the two decisions worth making — ask me
/// again, or remove it. Bundle ids and folder paths appear last and only when
/// they mean something.
struct PluginDetailSheet: View {
  let snapshot: PluginSnapshot
  let onClose: () -> Void

  @ObservedObject private var host = PluginHostController.shared
  @State private var notice: String?

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if !snapshot.problem.isEmpty {
            calloutSection(
              title: L10n.PreferencesPlugins.problemTitle,
              systemImage: "exclamationmark.triangle.fill",
              tint: .orange,
              lines: [snapshot.problem]
            )
          }

          if !snapshot.warnings.isEmpty {
            calloutSection(
              title: L10n.PreferencesPlugins.warningsTitle,
              systemImage: "info.circle.fill",
              tint: .secondary,
              lines: snapshot.warnings
            )
          }

          permissions

          commands

          if let path = snapshot.locationPath {
            section(L10n.PreferencesPlugins.locationTitle) {
              Text(path)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          resetPermissions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
      }

      Divider()

      footer
    }
    .frame(width: 480, height: 560)
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "puzzlepiece.extension.fill")
        .font(.system(size: 30))
        .foregroundColor(.accentColor)
        .frame(width: 38)

      VStack(alignment: .leading, spacing: 5) {
        Text(snapshot.displayName)
          .font(.title3.weight(.semibold))

        Text(L10n.PreferencesPlugins.version(snapshot.version))
          .font(.caption)
          .foregroundColor(.secondary)

        HStack(spacing: 6) {
          PluginStatusBadge(status: snapshot.status)
          PluginTierBadge(tier: snapshot.tier)
        }
        .padding(.top, 1)

        Text(L10n.PreferencesPlugins.sandboxNote)
          .font(.caption2)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(20)
  }

  // MARK: - Sections

  private var permissions: some View {
    section(L10n.PreferencesPlugins.permissionsTitle) {
      let items = PluginCapabilityPresentation.items(for: snapshot.declaredCapabilities)
      if items.isEmpty {
        Text(L10n.PreferencesPlugins.permissionsNone)
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(items) { item in
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: item.systemImage)
                .font(.body)
                .foregroundColor(item.isSensitive ? .orange : .secondary)
                .frame(width: 20)

              VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                  .font(.callout.weight(.medium))
                Text(item.detail)
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      }
    }
  }

  private var commands: some View {
    section(L10n.PreferencesPlugins.commandsTitle) {
      if snapshot.contributions.isEmpty {
        Text(L10n.PreferencesPlugins.commandsNone)
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(snapshot.contributions) { item in
            HStack(spacing: 10) {
              Image(systemName: item.systemImage)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 20)
              Text(item.title)
                .font(.callout)
              Spacer(minLength: 0)
            }
          }

          Text(L10n.PreferencesPlugins.commandsWhere)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
      }
    }
  }

  private var resetPermissions: some View {
    section(L10n.PreferencesPlugins.resetPermissions) {
      HStack(alignment: .top, spacing: 12) {
        Text(notice ?? L10n.PreferencesPlugins.resetPermissionsDescription)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        Button(L10n.PreferencesPlugins.resetPermissions) {
          Task {
            await host.revokeConsent(for: snapshot.id)
            notice = L10n.PreferencesPlugins.resetPermissionsDone
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Button(L10n.PreferencesPlugins.remove) {
        remove()
      }
      .buttonStyle(.bordered)
      .controlSize(.regular)
      .tint(.red)

      Spacer()

      Button(L10n.PreferencesPlugins.done, action: onClose)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  // MARK: - Building blocks

  @ViewBuilder
  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      content()
    }
  }

  @ViewBuilder
  private func calloutSection(
    title: String,
    systemImage: String,
    tint: Color,
    lines: [String]
  ) -> some View {
    section(title) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(lines, id: \.self) { line in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
              .font(.caption)
              .foregroundColor(tint)
            Text(line)
              .font(.caption)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  /// Removal deletes settings, storage, and Keychain items, so it asks first
  /// and says what it takes with it.
  private func remove() {
    let alert = NSAlert()
    alert.messageText = L10n.PreferencesPlugins.removeAlertTitle(snapshot.displayName)
    alert.informativeText = L10n.PreferencesPlugins.removeAlertMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.PreferencesPlugins.removeConfirm)
    alert.addButton(withTitle: L10n.Common.cancel)

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    Task {
      await host.removePlugin(snapshot.id)
      onClose()
    }
  }
}
