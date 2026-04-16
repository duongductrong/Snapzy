//
//  OnboardingLanguageSelectionView.swift
//  Snapzy
//
//  Onboarding step that lets users preview and choose the onboarding language.
//

import SwiftUI

struct OnboardingLanguageSelectionView: View {
  var onBack: (() -> Void)? = nil
  let onContinue: () -> Void

  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

  var body: some View {
    OnboardingStepContainer(onBack: onBack) {
      Image(systemName: "globe")
        .font(.system(size: 40))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      Text(languageTitle)
        .vsHeading()
        .padding(.top, 20)

      Text(languageSubtitle)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(.top, 4)

      languageScrollList
        .padding(.top, 20)

      Text(languagePreferencesHint)
        .font(.system(size: 11))
        .foregroundColor(VSDesignSystem.Colors.quaternary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(.top, 8)

      Button(continueActionTitle) {
        onContinue()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      .keyboardShortcut(.return, modifiers: [])
      .padding(.top, 24)
    }
  }

  private var languageScrollList: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(spacing: 8) {
        LanguageOptionRow(
          title: languageAutoTitle,
          subtitle: languageAutoDescription,
          isSelected: onboardingLocalization.selectedLanguageIdentifier.isEmpty,
          action: { onboardingLocalization.selectLanguage("") }
        )

        ForEach(onboardingLocalization.availableOptions) { option in
          LanguageOptionRow(
            title: option.displayName,
            subtitle: nil,
            isSelected: onboardingLocalization.selectedLanguageIdentifier == option.identifier,
            action: { onboardingLocalization.selectLanguage(option.identifier) }
          )
        }
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 2)
    }
    .frame(maxWidth: 400, maxHeight: 300)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .mask(
      VStack(spacing: 0) {
        LinearGradient(
          colors: [.clear, .black],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 8)

        Color.black

        LinearGradient(
          colors: [.black, .clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 8)
      }
    )
  }

  private var systemResolvedLanguageName: String {
    onboardingLocalization.systemResolvedOption?.displayName ?? "English"
  }

  private var continueActionTitle: String {
    onboardingLocalization.requiresRelaunchOnCompletion
      ? languageApplyLaterTitle
      : commonContinueTitle
  }

  private var languageTitle: String {
    onboardingLocalization.string(
      "onboarding.language.title",
      defaultValue: "Choose your language",
      comment: "Onboarding language step title"
    )
  }

  private var languageSubtitle: String {
    onboardingLocalization.string(
      "onboarding.language.subtitle",
      defaultValue: "Snapzy can follow your Mac or preview a specific app language during setup.",
      comment: "Onboarding language step subtitle"
    )
  }

  private var languageAutoTitle: String {
    onboardingLocalization.string(
      "onboarding.language.auto-title",
      defaultValue: "Auto",
      comment: "Auto language option title shown during onboarding"
    )
  }

  private var languageAutoDescription: String {
    onboardingLocalization.format(
      "onboarding.language.auto-description",
      defaultValue: "Follow macOS. Currently %@.",
      comment: "Description for the onboarding auto language option. %@ is the resolved language display name.",
      arguments: [systemResolvedLanguageName]
    )
  }

  private var languageApplyLaterTitle: String {
    onboardingLocalization.string(
      "onboarding.language.apply-later",
      defaultValue: "Continue and Apply on Finish",
      comment: "Primary button title when onboarding language changes will be applied after completing onboarding"
    )
  }

  private var languagePreferencesHint: String {
    onboardingLocalization.string(
      "onboarding.language.preferences-hint",
      defaultValue: "You can change this anytime in Preferences -> General.",
      comment: "Hint shown below the onboarding language picker"
    )
  }

  private var commonContinueTitle: String {
    onboardingLocalization.string(
      "common.continue",
      defaultValue: "Continue",
      comment: "Generic continue button title"
    )
  }
}

private struct LanguageOptionRow: View {
  let title: String
  let subtitle: String?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(isSelected ? VSDesignSystem.Colors.primary : VSDesignSystem.Colors.quaternary)
          .frame(width: 24, alignment: .center)

        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(VSDesignSystem.Colors.primary)

          if let subtitle {
            Text(subtitle)
              .font(.system(size: 12))
              .foregroundColor(VSDesignSystem.Colors.tertiary)
              .multilineTextAlignment(.leading)
          }
        }

        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isSelected ? VSDesignSystem.Colors.buttonFill : VSDesignSystem.Colors.cardFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(
            isSelected ? VSDesignSystem.Colors.buttonStroke : VSDesignSystem.Colors.cardStroke,
            lineWidth: 1
          )
      )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  OnboardingLanguageSelectionView(onContinue: {})
    .environmentObject(OnboardingLocalizationController())
    .frame(width: 500, height: 560)
    .background(.black.opacity(0.5))
}
