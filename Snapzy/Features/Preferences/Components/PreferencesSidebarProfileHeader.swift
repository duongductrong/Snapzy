//
//  PreferencesSidebarProfileHeader.swift
//  Snapzy
//
//  Sidebar header styled like the System Settings account row: app icon, name, version and
//  update channel. Click opens About; the context menu checks for updates and switches channel.
//

import AppKit
import SwiftUI

struct PreferencesSidebarProfileHeader: View {
  let isSelected: Bool
  let action: () -> Void

  @AppStorage(PreferencesKeys.updateChannel)
  private var updateChannel: String = UpdateChannel.stable.rawValue

  @State private var isHovering = false

  private static let iconSize: CGFloat = 40
  private static let height: CGFloat = 54

  private var isBeta: Bool {
    updateChannel == UpdateChannel.beta.rawValue
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    return "v\(version)"
  }

  private var channelName: String {
    isBeta ? L10n.PreferencesAbout.updateChannelBeta : L10n.PreferencesAbout.updateChannelStable
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        PreferencesAppIconImage(size: Self.iconSize)
          .shadow(color: Color.black.opacity(0.15), radius: 3, y: 1)

        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: "Snapzy")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)

          HStack(spacing: 5) {
            Circle()
              .fill(isBeta ? Color.orange : Color.green)
              .frame(width: 6, height: 6)

            Text(verbatim: "\(appVersion) · \(channelName)")
              .font(.system(size: 11.5))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .frame(height: Self.height)
      .background {
        Radius.rect(Radius.card)
          .fill(Color.primary.opacity(isSelected ? 0.08 : (isHovering ? 0.045 : 0)))
      }
      .contentShape(Radius.rect(Radius.card))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(L10n.Preferences.aboutTab)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    }
  }

  private func setChannel(_ channel: UpdateChannel) {
    guard updateChannel != channel.rawValue else { return }
    updateChannel = channel.rawValue
    SnapzyConfigurationSyncCoordinator.shared.scheduleSync(reason: .explicitChange)
    UpdaterManager.shared.checkForUpdates()
  }
}

#Preview {
  PreferencesSidebarProfileHeader(isSelected: false) {}
    .frame(width: 220)
    .padding()
}
