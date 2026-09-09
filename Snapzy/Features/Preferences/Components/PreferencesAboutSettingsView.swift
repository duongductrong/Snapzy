//
//  AboutSettingsView.swift
//  Snapzy
//
//  Redesigned About tab following clean, card-based Hand Mirror aesthetic.
//

import AppKit
import Sparkle
import SwiftUI

struct AboutSettingsView: View {
  @AppStorage(PreferencesKeys.updateChannel) private var updateChannel: String = UpdateChannel.stable.rawValue

  private var updater: SPUUpdater {
    UpdaterManager.shared.updater
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "Snapzy \(version) (\(build))"
  }

  private var contributors: [String] {
    [
      "Omar Shahine,",
      "Victor Xirau,",
      "Yuri Chukhlib,",
      "Yuan Zhang,",
      "tukuyomi032,",
      "Aurora,",
      "Jiawen Geng,",
      "William Cachamwri,",
      L10n.PreferencesAbout.allContributors
    ]
  }

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 20) {
          // Hero Icon & Title
          heroSection

          // Card 1: Attribution & Special thanks
          attributionCard

          // Card 2: App version, Updates & Support
          versionAndSupportCard

          Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 28)
      }
    }
  }

  // MARK: - Hero Section

  private var heroSection: some View {
    VStack(spacing: 10) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)

      VStack(spacing: 3) {
        Text(verbatim: "Snapzy")
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundStyle(Color.primary)

        Text(L10n.PreferencesAbout.appSubtitle)
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .frame(maxWidth: 420)
      }
    }
    .padding(.bottom, 4)
  }

  // MARK: - Card 1: Attribution & Special Thanks

  private var attributionCard: some View {
    VStack(spacing: 0) {
      // Made by
      HStack(alignment: .center) {
        Text(L10n.PreferencesAbout.madeBy)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(Color.primary)

        Spacer()

        Link(destination: URL(string: "https://github.com/duongductrong")!) {
          Text("Trong Duong")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      divider

      // Special thanks
      HStack(alignment: .top) {
        Text(L10n.PreferencesAbout.specialThanks)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(Color.primary)

        Spacer(minLength: 20)

        Link(destination: URL(string: "https://github.com/duongductrong/Snapzy/graphs/contributors")!) {
          VStack(alignment: .trailing, spacing: 3) {
            ForEach(contributors, id: \.self) { name in
              Text(name)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.trailing)
            }
          }
        }
        .buttonStyle(.plain)
        .help(L10n.PreferencesAbout.viewAllContributors)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .cardContainer(maxWidth: 480)
  }

  // MARK: - Card 2: Version & Support

  private var versionAndSupportCard: some View {
    VStack(spacing: 0) {
      // App version + Check for Updates action
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.PreferencesAbout.appVersion)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.primary)

          HStack(spacing: 6) {
            Text(appVersion)
              .font(.system(size: 11, weight: .regular))
              .foregroundStyle(Color.secondary)

            if let lastCheck = updater.lastUpdateCheckDate {
              Text("•")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.5))

              HStack(spacing: 3) {
                Text(L10n.PreferencesAbout.checkedLabel)
                Text(lastCheck, style: .relative)
              }
              .font(.system(size: 11, weight: .regular))
              .foregroundStyle(Color.secondary)
            }
          }
        }

        Spacer()

        Button(action: {
          updater.checkForUpdates()
        }) {
          Text(L10n.PreferencesAbout.checkForUpdates)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(updater.lastUpdateCheckDate.map { "\(L10n.PreferencesAbout.checkedLabel): \($0.formatted(date: .abbreviated, time: .shortened))" } ?? L10n.PreferencesAbout.checkForUpdates)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      divider

      // Update Channel
      HStack(alignment: .center) {
        Text(L10n.PreferencesAbout.updateChannelTitle)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(Color.primary)

        Spacer()

        Picker("", selection: $updateChannel) {
          Text(L10n.PreferencesAbout.updateChannelStable).tag(UpdateChannel.stable.rawValue)
          Text(L10n.PreferencesAbout.updateChannelBeta).tag(UpdateChannel.beta.rawValue)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .controlSize(.regular)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      if updateChannel == UpdateChannel.beta.rawValue {
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.orange)
          Text(L10n.PreferencesAbout.updateChannelBetaWarning)
            .font(.caption)
            .foregroundColor(.orange)
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
      }

      divider

      // Support & Links
      HStack(alignment: .top) {
        Text(L10n.PreferencesAbout.support)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(Color.primary)

        Spacer(minLength: 20)

        VStack(alignment: .trailing, spacing: 8) {
          supportLink(title: L10n.PreferencesAbout.website, url: "https://snapzy.app")
          supportLink(title: L10n.PreferencesAbout.github, url: "https://github.com/duongductrong/Snapzy")
          supportLink(title: L10n.PreferencesAbout.reportBug, url: "https://github.com/duongductrong/Snapzy/issues")
          supportLink(title: L10n.PreferencesAbout.discordCommunity, url: "https://discord.gg/xkWDAuJkZu")
          supportLink(title: "\(L10n.PreferencesAbout.supportTitle) ❤️", url: "https://github.com/sponsors/duongductrong", isHighlighted: true)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .cardContainer(maxWidth: 480)
    .onChange(of: updateChannel) { _ in
      SnapzyConfigurationSyncCoordinator.shared.scheduleSync(reason: .explicitChange)
      UpdaterManager.shared.checkForUpdates()
    }
  }

  // MARK: - Helpers

  private var divider: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.08))
      .frame(height: 0.5)
      .padding(.horizontal, 12)
  }

  private func supportLink(title: String, url: String, isHighlighted: Bool = false) -> some View {
    Link(destination: URL(string: url)!) {
      HStack(spacing: 4) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(isHighlighted ? Color.red.opacity(0.9) : Color.accentColor)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(isHighlighted ? Color.red.opacity(0.8) : Color.accentColor.opacity(0.8))
      }
    }
    .buttonStyle(.plain)
  }
}

private extension View {
  func cardContainer(maxWidth: CGFloat) -> some View {
    self
      .background {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.primary.opacity(0.04))
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .frame(maxWidth: maxWidth)
  }
}

#Preview {
  AboutSettingsView()
    .frame(width: 700, height: 600)
}
