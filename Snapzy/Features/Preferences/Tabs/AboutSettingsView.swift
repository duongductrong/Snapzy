//
//  AboutSettingsView.swift
//  Snapzy
//
//  Modern card-based About tab with app branding, features, and links
//

import SwiftUI
import Sparkle

struct AboutSettingsView: View {
  @ObservedObject private var licenseManager = LicenseManager.shared

  @State private var showLicenseActivation = false
  @State private var showDeactivateConfirm = false
  @State private var showDeactivateError = false
  @State private var licenseError: String?
  @State private var isProcessing = false

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

      // License Management
      licenseSection

      // Contact Links
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

  // MARK: - License Management

  private var licenseSection: some View {
    VStack(spacing: Spacing.sm) {
      // License status badge
      HStack(spacing: Spacing.sm) {
        Circle()
          .fill(licenseStatusColor)
          .frame(width: 7, height: 7)

        Text(licenseStatusText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(Color.primary.opacity(0.05))
      .clipShape(Capsule())

      // Action buttons
      HStack(spacing: Spacing.sm) {
        // License Manager — re-open the activation flow
        Button {
          showLicenseActivation = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "key.fill")
              .font(.system(size: 11))
            Text("License Manager")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)

        // Deactivate Device — only when licensed
        if case .licensed = licenseManager.state {
          Button(role: .destructive) {
            showDeactivateConfirm = true
          } label: {
            HStack(spacing: 4) {
              if isProcessing {
                ProgressView()
                  .controlSize(.small)
                  .scaleEffect(0.7)
              }
              Image(systemName: "xmark.circle")
                .font(.system(size: 11))
              Text("Deactivate Device")
            }
            .font(.system(size: 12))
          }
          .controlSize(.small)
          .disabled(isProcessing)
        }

        // DEBUG ONLY: Clear all license data
        #if DEBUG
        Button(role: .destructive) {
          Task {
            try? await licenseManager.clearLicense()
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "trash")
              .font(.system(size: 11))
            Text("Clear Cache")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)

        Button {
          licenseManager.printDebugInfo()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "info.circle")
              .font(.system(size: 11))
            Text("Debug Info")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)
        #endif
      }
    }
    .alert("Deactivate Device", isPresented: $showDeactivateConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Deactivate", role: .destructive) {
        deactivateLicense()
      }
    } message: {
      Text("This will unlink your device from the license key. You can re-activate later with the same or a different key.")
    }
    .alert("Deactivation Error", isPresented: $showDeactivateError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(licenseError ?? "An unknown error occurred.")
    }
    .sheet(isPresented: $showLicenseActivation) {
      LicenseActivationView(onContinue: {
        showLicenseActivation = false
      })
      .frame(width: 500, height: 500)
    }
  }

  // MARK: - License Helpers

  private var licenseStatusColor: Color {
    switch licenseManager.state {
    case .licensed: return .green
    case .trial: return .orange
    case .trialExpired, .invalid: return .red
    case .noLicense: return .secondary
    case .loading: return .secondary.opacity(0.5)
    }
  }

  private var licenseStatusText: String {
    switch licenseManager.state {
    case .licensed(let license):
      return "Licensed \u{2014} \(license.displayKey)"
    case .trial(let days):
      return "Trial \u{2014} \(days) days left"
    case .trialExpired:
      return "Trial Expired"
    case .invalid:
      return "License Invalid"
    case .noLicense:
      return "No License"
    case .loading:
      return "Checking\u{2026}"
    }
  }

  private func deactivateLicense() {
    isProcessing = true
    licenseError = nil
    Task {
      do {
        try await licenseManager.deactivateLicense()
        isProcessing = false
      } catch {
        isProcessing = false
        licenseError = error.localizedDescription
        showDeactivateError = true
      }
    }
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
