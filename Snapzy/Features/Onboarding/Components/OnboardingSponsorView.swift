//
//  OnboardingSponsorView.swift
//  Snapzy
//
//  Sponsor prompt shown during onboarding and once for existing users.
//

import AppKit
import SwiftUI

struct SponsorView: View {
  let onContinue: () -> Void

  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

  var body: some View {
    OnboardingStepContainer {
      Image(systemName: "heart.circle")
        .font(.system(size: 48, weight: .light))
        .foregroundColor(.pink.opacity(0.85))

      Text(sponsorTitle)
        .vsHeading()
        .padding(.top, 24)

      Text(sponsorDescription)
      .vsBody()
      .multilineTextAlignment(.center)
      .frame(maxWidth: 360)
      .padding(.top, 4)

      VStack(spacing: 12) {
        ForEach(localizedSponsorLinks) { link in
          Button {
            NSWorkspace.shared.open(link.url)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: link.systemImage)
                .font(.system(size: 15))
                .foregroundColor(VSDesignSystem.Colors.secondary)
                .frame(width: 24, alignment: .center)

              VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                  .font(.system(size: 13, weight: .medium))
                  .foregroundColor(VSDesignSystem.Colors.primary)

                Text(link.subtitle)
                  .font(.system(size: 12))
                  .foregroundColor(VSDesignSystem.Colors.tertiary)
              }

              Spacer()

              Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(VSDesignSystem.Colors.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
              RoundedRectangle(cornerRadius: 10)
                .fill(VSDesignSystem.Colors.cardFill)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 10)
                .stroke(VSDesignSystem.Colors.cardStroke, lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: 400)
      .padding(.top, 24)

      Text(sponsorOptionalNote)
        .font(.system(size: 11))
        .foregroundColor(VSDesignSystem.Colors.quaternary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(.top, 10)

      Button(commonContinueTitle) {
        onContinue()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      .keyboardShortcut(.return, modifiers: [])
      .padding(.top, 32)
    }
  }

  private var localizedSponsorLinks: [SponsorLink] {
    [
      SponsorLink(
        id: "github-sponsors",
        title: "GitHub Sponsors",
        subtitle: recurringSupportTitle,
        systemImage: "heart.fill",
        color: .pink,
        url: URL(string: "https://github.com/sponsors/duongductrong")!
      ),
      SponsorLink(
        id: "ko-fi",
        title: "Ko-fi",
        subtitle: oneTimeTipTitle,
        systemImage: "cup.and.saucer.fill",
        color: .orange,
        url: URL(string: "https://ko-fi.com/duongductrong")!
      ),
      SponsorLink(
        id: "paypal",
        title: "PayPal",
        subtitle: directSupportTitle,
        systemImage: "creditcard.fill",
        color: .blue,
        url: URL(string: "https://www.paypal.com/paypalme/duongductrong")!
      ),
    ]
  }

  private var sponsorTitle: String {
    onboardingLocalization.string(
      "onboarding.sponsor.title",
      defaultValue: "Support Snapzy",
      comment: "Onboarding sponsor step title"
    )
  }

  private var sponsorDescription: String {
    onboardingLocalization.string(
      "onboarding.sponsor.description",
      defaultValue: "If Snapzy saves you time, supporting the project helps keep it independent and improving.",
      comment: "Onboarding sponsor step description"
    )
  }

  private var sponsorOptionalNote: String {
    onboardingLocalization.string(
      "onboarding.sponsor.optional-note",
      defaultValue: "Completely optional. Snapzy stays fully usable either way.",
      comment: "Note shown below sponsor links during onboarding"
    )
  }

  private var recurringSupportTitle: String {
    onboardingLocalization.string(
      "sponsor.recurring-support",
      defaultValue: "Recurring support",
      comment: "Subtitle for GitHub Sponsors option"
    )
  }

  private var oneTimeTipTitle: String {
    onboardingLocalization.string(
      "sponsor.one-time-tip",
      defaultValue: "One-time tip",
      comment: "Subtitle for Ko-fi option"
    )
  }

  private var directSupportTitle: String {
    onboardingLocalization.string(
      "sponsor.direct-support",
      defaultValue: "Direct support",
      comment: "Subtitle for PayPal option"
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

#Preview {
  SponsorView(onContinue: {})
    .frame(width: 500, height: 520)
    .background(OnboardingSurfaceBackground())
}
