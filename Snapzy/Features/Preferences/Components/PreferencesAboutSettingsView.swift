//
//  AboutSettingsView.swift
//  Snapzy
//
//  About tab with app info and sponsor CTA.
//

import AppKit
import Sparkle
import SwiftUI

struct AboutSettingsView: View {
  private var updater: SPUUpdater {
    UpdaterManager.shared.updater
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(version) (\(build))"
  }

  var body: some View {
    VStack {
      Spacer()
      heroSection
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var heroSection: some View {
    VStack(spacing: Spacing.md) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

      VStack(spacing: Spacing.xs) {
        Text("Snapzy")
          .font(.system(size: 28, weight: .bold, design: .rounded))

        Text("Screenshot & Recording for macOS")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack(spacing: Spacing.sm) {
        Text("Version \(appVersion)")
          .font(.caption)
          .foregroundColor(.secondary)

        if let lastCheck = updater.lastUpdateCheckDate {
          Text("•")
            .foregroundColor(.secondary.opacity(0.5))
          Text("Checked \(lastCheck, style: .relative) ago")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(Color.primary.opacity(0.05))
      .clipShape(Capsule())

      HStack(spacing: Spacing.sm) {
        Button(action: { updater.checkForUpdates() }) {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text("Check for Updates")
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)

        Button(action: { CrashReportService.presentAlert() }) {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
            Text("Submit Crash Report")
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
      }

      sponsorSection

      HStack(spacing: Spacing.md) {
        Link(destination: URL(string: "https://snapzy.app")!) {
          Image(systemName: "globe")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Website")

        Link(destination: URL(string: "https://github.com/duongductrong")!) {
          Image(systemName: "person.crop.circle")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("GitHub")

        Link(destination: URL(string: "https://github.com/duongductrong/Snapzy/issues")!) {
          Image(systemName: "ant.fill")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Report a Bug")
      }
      .padding(.top, Spacing.xs)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.md)
  }

  private var sponsorSection: some View {
    VStack(alignment: .center, spacing: Spacing.sm) {
      VStack(spacing: 6) {
        Text("Support Snapzy")
          .font(.system(size: 14, weight: .semibold))

        Text("Snapzy is open-source. Sponsor ongoing development if it helps your workflow.")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      HStack(spacing: Spacing.sm) {
        ForEach(SponsorLinks.all) { link in
          Button {
            NSWorkspace.shared.open(link.url)
          } label: {
            VStack(spacing: 4) {
              Image(systemName: link.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(link.color)
              Text(link.title)
                .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Size.radiusLg))
            .overlay(
              RoundedRectangle(cornerRadius: Size.radiusLg)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(Spacing.md)
    .frame(maxWidth: 420)
    .background(Color.primary.opacity(0.03))
    .clipShape(RoundedRectangle(cornerRadius: Size.radiusLg))
    .overlay(
      RoundedRectangle(cornerRadius: Size.radiusLg)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }
}

#Preview {
  AboutSettingsView()
    .frame(width: 700, height: 550)
}
