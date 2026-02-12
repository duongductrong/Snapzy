//
//  AboutSettingsView.swift
//  Snapzy
//
//  Modern card-based About tab with app branding, features, and links
//

import SwiftUI
import Sparkle

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

  // MARK: - Hero Section

  private var heroSection: some View {
    VStack(spacing: Spacing.md) {
      // App Icon with subtle glow
      ZStack {
        // Circle()
        //   .fill(
        //     RadialGradient(
        //       colors: [Color.accentColor.opacity(0.3), Color.clear],
        //       center: .center,
        //       startRadius: 40,
        //       endRadius: 80
        //     )
        //   )
        //   .frame(width: 160, height: 160)

        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 96, height: 96)
          .clipShape(RoundedRectangle(cornerRadius: 22))
          .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
      }

      // App Name & Tagline
      VStack(spacing: Spacing.xs) {
        Text("Snapzy")
          .font(.system(size: 28, weight: .bold, design: .rounded))

        Text("Screenshot & Recording for macOS")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      // Version Badge
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

      // Update Button
      Button(action: { updater.checkForUpdates() }) {
        HStack(spacing: Spacing.sm) {
          Image(systemName: "arrow.triangle.2.circlepath")
          Text("Check for Updates")
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.md)
  }

  // MARK: - Feature Highlights

  private var featureHighlightsSection: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      sectionHeader("Highlights")

      LazyVGrid(columns: [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
      ], spacing: Spacing.md) {
        AboutFeatureCard(
          icon: "camera.viewfinder",
          iconColor: .blue,
          title: "Screen Capture",
          description: "Capture windows, regions, or full screen with precision"
        )
        AboutFeatureCard(
          icon: "video.fill",
          iconColor: .red,
          title: "Screen Recording",
          description: "Record your screen with audio and system sound"
        )
        AboutFeatureCard(
          icon: "pencil.and.outline",
          iconColor: .orange,
          title: "Annotations",
          description: "Add arrows, shapes, text, and blur to screenshots"
        )
        AboutFeatureCard(
          icon: "sparkles",
          iconColor: .purple,
          title: "Quick Access",
          description: "Instant access to recent captures from menu bar"
        )
      }
    }
  }

  // MARK: - Links Section

  private var linksSection: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      sectionHeader("Resources")

      HStack(spacing: Spacing.md) {
        AboutLinkCard(
          icon: "globe",
          title: "Website",
          subtitle: "github.com/duongductrong",
          url: "https://github.com/duongductrong/Snapzy"
        )
        AboutLinkCard(
          icon: "star.fill",
          title: "Rate on GitHub",
          subtitle: "Leave a star",
          url: "https://github.com/duongductrong/Snapzy"
        )
        AboutLinkCard(
          icon: "ant.fill",
          title: "Report Issue",
          subtitle: "Bug reports & feedback",
          url: "https://github.com/duongductrong/Snapzy/issues"
        )
      }
    }
  }

  // MARK: - Credits Section

  private var creditsSection: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      sectionHeader("Acknowledgments")

      VStack(spacing: Spacing.sm) {
        AboutCreditRow(name: "SwiftUI", role: "UI Framework", icon: "swift")
        AboutCreditRow(name: "ScreenCaptureKit", role: "Screen Recording", icon: "rectangle.dashed.badge.record")
        AboutCreditRow(name: "Sparkle", role: "Auto Updates", icon: "arrow.triangle.2.circlepath")
      }
      .padding(Spacing.md)
      .background(Color.primary.opacity(0.03))
      .clipShape(RoundedRectangle(cornerRadius: Size.radiusLg))

      Text("© 2024-2025 Duong Duc Trong. All rights reserved.")
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Spacing.sm)
    }
  }

  // MARK: - Helpers

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.secondary)
  }
}

#Preview {
  AboutSettingsView()
    .frame(width: 700, height: 550)
}
