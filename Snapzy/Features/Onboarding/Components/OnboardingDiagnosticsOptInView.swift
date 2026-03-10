//
//  DiagnosticsOptInView.swift
//  Snapzy
//
//  Onboarding step for crash logging opt-in — adaptive dark/light theme
//

import SwiftUI

struct DiagnosticsOptInView: View {
  let onNext: () -> Void

  @AppStorage(PreferencesKeys.diagnosticsEnabled) private var diagnosticsEnabled = true

  var body: some View {
    OnboardingStepContainer {

      // Icon
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      // Title
      Text("Help Us Improve")
        .vsHeading()
        .padding(.top, 24)

      // Description
      Text(
        "Snapzy can collect anonymous diagnostic logs when something goes wrong. These logs help us find and fix bugs faster."
      )
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
            Text("Enable Crash Logging")
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(VSDesignSystem.Colors.primary)

            Text("Logs are stored locally on your device")
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
      Text("No personal data is collected. Nothing is sent without your action.")
        .font(.system(size: 11))
        .foregroundColor(VSDesignSystem.Colors.quaternary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 8)

      // Navigation
      Button("Next") {
        onNext()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      .keyboardShortcut(.return, modifiers: [])
      .padding(.top, 32)
    }
  }
}

#Preview {
  DiagnosticsOptInView(
    onNext: {}
  )
  .frame(width: 500, height: 520)
  .background(.black.opacity(0.5))
}
