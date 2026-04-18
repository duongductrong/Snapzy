//
//  CompletionView.swift
//  Snapzy
//
//  Completion screen for onboarding flow — adaptive dark/light theme
//

import SwiftUI

struct CompletionView: View {
  var onBack: (() -> Void)? = nil
  let onComplete: () -> Void

  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

  var body: some View {
    OnboardingStepContainer(onBack: onBack) {

      // Success Icon
      Image(systemName: "checkmark.circle")
        .font(.system(size: 48, weight: .light))
        .foregroundColor(.green.opacity(0.85))

      // Title
      Text(completionTitle)
        .vsHeading()
        .padding(.top, 20)

      // Subtitle
      Text(completionDescription)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Quick reference cards
      VStack(spacing: 10) {
        CompletionHintRow(
          icon: "menubar.arrow.up.rectangle",
          title: completionMenuBarTitle,
          description: completionMenuBarHint
        )

        CompletionHintRow(
          icon: "keyboard",
          title: preferencesShortcutsTabTitle,
          description: completionShortcutsHint
        )

        CompletionHintRow(
          icon: "gearshape",
          title: commonPreferencesTitle,
          description: completionPreferencesHint
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
            Text(openPreferencesTitle)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(VSDesignSystem.Colors.tertiary)
          }
          .buttonStyle(.plain)

          Button(getStartedTitle) {
            onComplete()
          }
          .buttonStyle(VSDesignSystem.SuccessButtonStyle())
          .keyboardShortcut(.return, modifiers: [])
        }

        Text(splashPressEnterTitle)
          .font(.system(size: 11))
          .foregroundStyle(VSDesignSystem.Colors.quaternary)
      }
      .padding(.top, 32)
    }
  }

  private var completionTitle: String {
    onboardingLocalization.string(
      "onboarding.completion.title",
      defaultValue: "You're all set!",
      comment: "Onboarding completion title"
    )
  }

  private var completionDescription: String {
    onboardingLocalization.string(
      "onboarding.completion.description",
      defaultValue: "Snapzy is ready. Access it from the menu bar or use your keyboard shortcuts.",
      comment: "Onboarding completion description"
    )
  }

  private var completionMenuBarTitle: String {
    onboardingLocalization.string(
      "onboarding.completion.menu-bar",
      defaultValue: "Menu Bar",
      comment: "Completion card title"
    )
  }

  private var completionMenuBarHint: String {
    onboardingLocalization.string(
      "onboarding.completion.menu-bar-hint",
      defaultValue: "Look for the camera icon in your menu bar",
      comment: "Completion card description"
    )
  }

  private var preferencesShortcutsTabTitle: String {
    onboardingLocalization.string(
      "preferences.tab.shortcuts",
      defaultValue: "Shortcuts",
      comment: "Preferences tab title"
    )
  }

  private var completionShortcutsHint: String {
    onboardingLocalization.string(
      "onboarding.completion.shortcuts-hint",
      defaultValue: "Use ⇧⌘3, ⇧⌘4, ⇧⌘5 to capture anytime",
      comment: "Completion card description"
    )
  }

  private var commonPreferencesTitle: String {
    onboardingLocalization.string(
      "common.preferences",
      defaultValue: "Preferences",
      comment: "Generic preferences title"
    )
  }

  private var completionPreferencesHint: String {
    onboardingLocalization.string(
      "onboarding.completion.preferences-hint",
      defaultValue: "Customize shortcuts, output format, and more",
      comment: "Completion card description"
    )
  }

  private var openPreferencesTitle: String {
    onboardingLocalization.string(
      "onboarding.completion.open-preferences",
      defaultValue: "Open Preferences",
      comment: "Secondary action on onboarding completion screen"
    )
  }

  private var getStartedTitle: String {
    onboardingLocalization.string(
      "onboarding.completion.get-started",
      defaultValue: "Get Started",
      comment: "Primary action on onboarding completion screen"
    )
  }

  private var splashPressEnterTitle: String {
    onboardingLocalization.string(
      "splash.press-enter",
      defaultValue: "Press Enter ↵",
      comment: "Hint text under buttons on splash and completion screens"
    )
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
  .environmentObject(OnboardingLocalizationController())
  .frame(width: 500, height: 520)
  .background(OnboardingSurfaceBackground())
}
