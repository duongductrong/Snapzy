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
    VStack(spacing: 0) {
      // Top: Status row
      HStack(spacing: Spacing.sm) {
        // State icon
        licenseIconView
          .frame(width: 28, height: 28)

        // Title + subtitle
        VStack(alignment: .leading, spacing: 2) {
          Text(licenseTitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)

          Text(licenseSubtitle)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }

        Spacer()

        // Masked license key (only when licensed)
        if case .licensed(let license) = licenseManager.state {
          Text(license.displayKey)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.7))
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm + 2)

      // Divider
      Rectangle()
        .fill(licenseStateColor.opacity(0.12))
        .frame(height: 0.5)

      // Bottom: Action buttons
      HStack(spacing: Spacing.sm) {
        Button {
          showLicenseActivation = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "key.fill")
              .font(.system(size: 10))
            Text("License Manager")
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(licenseStateColor)
        }
        .buttonStyle(.plain)

        if case .licensed = licenseManager.state {
          Circle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 3, height: 3)

          Button(role: .destructive) {
            showDeactivateConfirm = true
          } label: {
            HStack(spacing: 4) {
              if isProcessing {
                ProgressView()
                  .controlSize(.small)
                  .scaleEffect(0.6)
              }
              Image(systemName: "xmark.circle")
                .font(.system(size: 10))
              Text("Deactivate Device")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
          .disabled(isProcessing)
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
    }
    .background(
      RoundedRectangle(cornerRadius: Size.radiusLg)
        .fill(licenseStateColor.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: Size.radiusLg)
            .strokeBorder(licenseStateColor.opacity(0.15), lineWidth: 0.5)
        )
    )
    .frame(maxWidth: 340)
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

  @ViewBuilder
  private var licenseIconView: some View {
    switch licenseManager.state {
    case .licensed:
      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 18))
        .foregroundStyle(.green)
    case .invalid:
      Image(systemName: "exclamationmark.shield.fill")
        .font(.system(size: 18))
        .foregroundStyle(.red)
    case .noLicense:
      Image(systemName: "shield.slash")
        .font(.system(size: 18))
        .foregroundStyle(.secondary)
    case .loading:
      ProgressView()
        .controlSize(.small)
    }
  }

  private var licenseStateColor: Color {
    switch licenseManager.state {
    case .licensed: return .green
    case .invalid: return .red
    case .noLicense: return .secondary
    case .loading: return .secondary.opacity(0.5)
    }
  }

  private var licenseTitle: String {
    switch licenseManager.state {
    case .licensed:
      return "Licensed"
    case .invalid:
      return "License Invalid"
    case .noLicense:
      return "No License"
    case .loading:
      return "Checking\u{2026}"
    }
  }

  private var licenseSubtitle: String {
    switch licenseManager.state {
    case .licensed:
      return "Your device is activated"
    case .invalid(let reason):
      return licenseManager.state.statusDescription
    case .noLicense:
      return "Activate to unlock all features"
    case .loading:
      return "Verifying your license"
    }
  }

  private func deactivateLicense() {
    isProcessing = true
    licenseError = nil
    Task {
      do {
        try await licenseManager.deactivateLicense()
        isProcessing = false

        // Close Settings window and open the license activation screen
        NSApp.keyWindow?.close()
        SplashWindowController.shared.showLicenseActivation()
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
