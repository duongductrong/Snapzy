//
//  DiagnosticsOptInView.swift
//  Snapzy
//
//  Onboarding step for crash logging opt-in — adaptive dark/light theme
//

import SwiftUI

struct DiagnosticsOptInView: View {
  var onBack: (() -> Void)? = nil
  let onNext: () -> Void

  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController
  @AppStorage(PreferencesKeys.diagnosticsEnabled) private var diagnosticsEnabled = true

  var body: some View {
    OnboardingStepContainer(onBack: onBack) {

      // Icon
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      // Title
      Text(diagnosticsTitle)
        .vsHeading()
        .padding(.top, 24)

      // Description
      Text(diagnosticsDescription)
      .vsBody()
      .multilineTextAlignment(.center)
      .frame(maxWidth: 340)
      .padding(.top, 4)

      // Toggle card
      VStack(spacing: 12) {
        HStack(spacing: 12) {
          Image(systemName: "ant.fill")
            .font(.system(size: 14))
            .foregroundColor(VSDesignSystem.Colors.tertiary)
            .frame(width: 24, alignment: .center)

          VStack(alignment: .leading, spacing: 2) {
            Text(enableCrashLoggingTitle)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(VSDesignSystem.Colors.primary)

            Text(logsStoredLocallyTitle)
              .font(.system(size: 12))
              .foregroundColor(VSDesignSystem.Colors.tertiary)
          }

          Spacer()

          Toggle("", isOn: $diagnosticsEnabled)
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(VSDesignSystem.Colors.cardFill)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(VSDesignSystem.Colors.cardStroke, lineWidth: 1)
        )
      }
      .frame(maxWidth: 380)
      .padding(.top, 24)

      // Privacy note
      Text(diagnosticsPrivacyNoteTitle)
        .font(.system(size: 11))
        .foregroundColor(VSDesignSystem.Colors.quaternary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 8)

      // Navigation
      Button(commonNextTitle) {
        onNext()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      .keyboardShortcut(.return, modifiers: [])
      .padding(.top, 32)
    }
  }

  private var diagnosticsTitle: String {
    onboardingLocalization.string(
      "onboarding.diagnostics.title",
      defaultValue: "Help improve Snapzy?",
      comment: "Diagnostics onboarding step title"
    )
  }

  private var diagnosticsDescription: String {
    onboardingLocalization.string(
      "onboarding.diagnostics.description",
      defaultValue: "Allow local crash logs so Snapzy can recover better when something goes wrong.",
      comment: "Diagnostics onboarding step description"
    )
  }

  private var enableCrashLoggingTitle: String {
    onboardingLocalization.string(
      "onboarding.diagnostics.enable-crash-logging",
      defaultValue: "Enable crash logging",
      comment: "Toggle label for enabling crash logging during onboarding"
    )
  }

  private var logsStoredLocallyTitle: String {
    onboardingLocalization.string(
      "onboarding.diagnostics.logs-stored-locally",
      defaultValue: "Logs stay on this Mac unless you choose to share them.",
      comment: "Supporting text below crash logging toggle during onboarding"
    )
  }

  private var diagnosticsPrivacyNoteTitle: String {
    onboardingLocalization.string(
      "onboarding.diagnostics.privacy-note",
      defaultValue: "You can change this later in Preferences -> General.",
      comment: "Privacy note shown below diagnostics toggle during onboarding"
    )
  }

  private var commonNextTitle: String {
    onboardingLocalization.string(
      "common.next",
      defaultValue: "Next",
      comment: "Primary next action button title"
    )
  }
}

#Preview {
  DiagnosticsOptInView(
    onNext: {}
  )
  .frame(width: 500, height: 520)
  .background(OnboardingSurfaceBackground())
}
