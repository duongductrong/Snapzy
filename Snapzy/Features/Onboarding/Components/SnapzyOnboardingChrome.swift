//
//  SnapzyOnboardingChrome.swift
//  Snapzy
//
//  Header brand mark, language selector, close button, and footer escape affordance.
//

import AppKit
import SwiftUI

// MARK: - Section Label

/// A quiet label above a block of content.
///
/// This used to force `text.uppercased()` with 1.3pt tracking. Two problems: the string is
/// localized into ten other scripts where capitalization does not exist, and the tracked-caps
/// treatment is a magazine convention that onboarding applies to everything, which makes it
/// decoration rather than hierarchy. Sentence case at the token tracking keeps the label a label.
struct SnapzyOnboardingOverline: View {
  var text: String
  var tint: Color = SnapzyGlassInk.muted
  /// Draw a short hairline before the text, for labels that sit inside a card.
  var rule: Bool = false

  init(_ text: String, tint: Color = SnapzyGlassInk.muted, rule: Bool = false) {
    self.text = text
    self.tint = tint
    self.rule = rule
  }

  var body: some View {
    HStack(spacing: SnapzySpace.md) {
      if rule {
        Rectangle()
          .fill(tint.opacity(0.55))
          .frame(width: 12, height: 0.5)
      }

      Text(text)
        .font(.system(size: SnapzyOnboardingType.sectionLabel, weight: .semibold))
        .tracking(SnapzyOnboardingType.sectionTracking)
        .foregroundStyle(tint)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
  }
}

// MARK: - Close Button

struct SnapzyOnboardingCloseButton: View {
  var action: () -> Void

  @State private var isHovered = false

  /// The header is a toolbar, so its icon button takes the squircle ramp like every other
  /// 28pt icon button in the app — the circle family is reserved for chrome over user content.
  private var shape: RoundedRectangle {
    Radius.controlRect(forHeight: 28)
  }

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isHovered ? SnapzyGlassInk.primary : SnapzyGlassInk.muted)
        .frame(width: 28, height: 28)
        .background(
          shape
            .fill(isHovered ? SnapzyGlassInk.fillHover : SnapzyGlassInk.fillRaised)
            .overlay(
              shape.strokeBorder(
                isHovered ? SnapzyGlassInk.hairlineStrong : SnapzyGlassInk.hairline,
                lineWidth: SnapzySurfaceGlass.specularLineWidth
              )
            )
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovered = hovering
      }
    }
    .accessibilityLabel(L10n.Onboarding.chromeCloseAccessibility)
  }
}

// MARK: - Language Picker Pill

struct SnapzyOnboardingLanguagePicker: View {
  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

  @State private var isHovered = false

  var body: some View {
    Menu {
      Button {
        onboardingLocalization.selectLanguage("")
      } label: {
        HStack {
          Text(L10n.Onboarding.chromeLanguageAutoSystem)
          if onboardingLocalization.selectedLanguageIdentifier.isEmpty {
            Image(systemName: "checkmark")
          }
        }
      }

      Divider()

      ForEach(onboardingLocalization.availableOptions) { option in
        Button {
          onboardingLocalization.selectLanguage(option.identifier)
        } label: {
          HStack {
            Text(option.displayName)
            if onboardingLocalization.selectedLanguageIdentifier == option.identifier {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      HStack(spacing: SnapzySpace.sm) {
        Image(systemName: "globe")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(SnapzyGlassInk.muted)

        Text(currentLanguageLabel)
          .font(.system(size: SnapzyOnboardingType.caption, weight: .medium))
          .foregroundStyle(SnapzyGlassInk.body)

        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(SnapzyGlassInk.muted)
      }
      .padding(.horizontal, SnapzySpace.lg)
      .frame(height: 28)
      .background(
        Capsule(style: .continuous)
          .fill(isHovered ? SnapzyGlassInk.fillHover : SnapzyGlassInk.fillRaised)
          .overlay(
            Capsule(style: .continuous)
              .strokeBorder(
                isHovered ? SnapzyGlassInk.hairlineStrong : SnapzyGlassInk.hairline,
                lineWidth: SnapzySurfaceGlass.specularLineWidth
              )
          )
      )
      .contentShape(Capsule(style: .continuous))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovered = hovering
      }
    }
    .accessibilityLabel(L10n.Onboarding.chromeLanguageLabel)
  }

  private var currentLanguageLabel: String {
    if onboardingLocalization.selectedLanguageIdentifier.isEmpty {
      return onboardingLocalization.systemResolvedOption?.displayName ?? L10n.Onboarding.chromeLanguageAuto
    }
    return onboardingLocalization.availableOptions
      .first(where: { $0.identifier == onboardingLocalization.selectedLanguageIdentifier })?.displayName ?? L10n
      .Onboarding.chromeLanguageLabel
  }
}

// MARK: - Escape Hint

struct SnapzyOnboardingEscapeHint: View {
  var text: String

  var body: some View {
    HStack(spacing: SnapzySpace.md) {
      SnapzyKeycapChip(label: "esc")
      Text(text)
        .font(.system(size: SnapzyOnboardingType.caption))
        .foregroundStyle(SnapzyGlassInk.muted)
    }
  }
}
