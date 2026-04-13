//
//  CompletionView.swift
//  Snapzy
//
//  Completion screen for onboarding flow — adaptive dark/light theme
//

import SwiftUI

struct CompletionView: View {
  let onComplete: () -> Void

  var body: some View {
    OnboardingStepContainer {

      // Success Icon
      Image(systemName: "checkmark.circle")
        .font(.system(size: 48, weight: .light))
        .foregroundColor(.green.opacity(0.85))

      // Title
      Text(L10n.Onboarding.completionTitle)
        .vsHeading()
        .padding(.top, 20)

      // Subtitle
      Text(L10n.Onboarding.completionDescription)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Quick reference cards
      VStack(spacing: 10) {
        CompletionHintRow(
          icon: "menubar.arrow.up.rectangle",
          title: L10n.Onboarding.menuBar,
          description: L10n.Onboarding.menuBarHint
        )

        CompletionHintRow(
          icon: "keyboard",
          title: L10n.Preferences.shortcutsTab,
          description: L10n.Onboarding.shortcutsHint
        )

        CompletionHintRow(
          icon: "gearshape",
          title: L10n.Common.preferences,
          description: L10n.Onboarding.preferencesHint
        )
      }
      .frame(maxWidth: 380)
      .padding(.top, 20)

      // Actions
      VStack(spacing: 10) {
        HStack(spacing: 12) {
          Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            onComplete()
          } label: {
            Text(L10n.Onboarding.openPreferences)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(VSDesignSystem.Colors.tertiary)
          }
          .buttonStyle(.plain)

          Button(L10n.Onboarding.getStarted) {
            onComplete()
          }
          .buttonStyle(VSDesignSystem.SuccessButtonStyle())
          .keyboardShortcut(.return, modifiers: [])
        }

        Text(L10n.Splash.pressEnter)
          .font(.system(size: 11))
          .foregroundStyle(VSDesignSystem.Colors.quaternary)
      }
      .padding(.top, 32)
    }
  }
}

// MARK: - Completion Hint Row

private struct CompletionHintRow: View {
  let icon: String
  let title: String
  let description: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundColor(VSDesignSystem.Colors.tertiary)
        .frame(width: 24, alignment: .center)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(VSDesignSystem.Colors.primary)

        Text(description)
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.tertiary)
      }

      Spacer()
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
}

#Preview {
  CompletionView(
    onComplete: {}
  )
  .frame(width: 500, height: 520)
  .background(.black.opacity(0.5))
}
