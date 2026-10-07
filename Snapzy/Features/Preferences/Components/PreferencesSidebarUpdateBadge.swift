//
//  PreferencesSidebarUpdateBadge.swift
//  Snapzy
//
//  Sidebar bottom badge showing app icon, name, update channel, and quick update action.
//

import AppKit
import Sparkle
import SwiftUI

struct PreferencesSidebarUpdateBadge: View {
  @AppStorage(PreferencesKeys.updateChannel)
  private var updateChannel: String = UpdateChannel.stable.rawValue

  @State private var isHovering = false

  private var isBeta: Bool {
    updateChannel == UpdateChannel.beta.rawValue
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    return "v\(version)"
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .opacity(0.4)

      Button {
        UpdaterManager.shared.checkForUpdates()
      } label: {
        HStack(spacing: 10) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) // radius-lint:allow — clips the app icon bitmap; matches the icon's own corner
            .overlay(
              RoundedRectangle(cornerRadius: 6, style: .continuous) // radius-lint:allow — traces the icon clip
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
              Text(verbatim: "Snapzy")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)

              Spacer(minLength: 4)

              channelBadge
            }

            Text(appVersion)
              .font(.system(size: 10.5))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
          Radius.rect(Radius.card)
            .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.035))
        }
        .overlay {
          Radius.rect(Radius.card)
            .strokeBorder(isHovering ? Color.primary.opacity(0.1) : Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(Radius.rect(Radius.card))
      }
      .buttonStyle(.plain)
      .onHover { hovering in
        isHovering = hovering
      }
      .help(L10n.Menu.checkForUpdates)
      .contextMenu {
        Button(L10n.Menu.checkForUpdates) {
          UpdaterManager.shared.checkForUpdates()
        }

        Divider()

        Button {
          setChannel(.stable)
        } label: {
          HStack {
            Text(L10n.PreferencesAbout.updateChannelStable)
            if !isBeta {
              Image(systemName: "checkmark")
            }
          }
        }

        Button {
          setChannel(.beta)
        } label: {
          HStack {
            Text(L10n.PreferencesAbout.updateChannelBeta)
            if isBeta {
              Image(systemName: "checkmark")
            }
          }
        }

        Divider()

        Button(L10n.Preferences.aboutTab) {
          PreferencesNavigationState.shared.select(.about)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }

  private var channelBadge: some View {
    Text(isBeta ? "BETA" : "STABLE")
      .font(.system(size: 9.5, weight: .bold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1.5)
      .foregroundStyle(isBeta ? Color.orange : Color.secondary)
      .background(
        Capsule()
          .fill(isBeta ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
      )
  }

  private func setChannel(_ channel: UpdateChannel) {
    guard updateChannel != channel.rawValue else { return }
    updateChannel = channel.rawValue
    SnapzyConfigurationSyncCoordinator.shared.scheduleSync(reason: .explicitChange)
    UpdaterManager.shared.checkForUpdates()
  }
}

#Preview {
  PreferencesSidebarUpdateBadge()
    .frame(width: 220)
}
