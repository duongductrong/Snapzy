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

  var body: some View {
    OnboardingStepContainer {
      Image(systemName: "heart.circle")
        .font(.system(size: 48, weight: .light))
        .foregroundColor(.pink.opacity(0.85))

      Text("Sponsor the Author")
        .vsHeading()
        .padding(.top, 24)

      Text(
        "Snapzy is now open-source. If it saves you time, consider supporting ongoing development."
      )
      .vsBody()
      .multilineTextAlignment(.center)
      .frame(maxWidth: 360)
      .padding(.top, 4)

      VStack(spacing: 12) {
        ForEach(SponsorLinks.all) { link in
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

      Text("Support is optional. Snapzy remains fully usable without sponsoring.")
        .font(.system(size: 11))
        .foregroundColor(VSDesignSystem.Colors.quaternary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(.top, 10)

      Button("Continue") {
        onContinue()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      .keyboardShortcut(.return, modifiers: [])
      .padding(.top, 32)
    }
  }
}

#Preview {
  SponsorView(onContinue: {})
    .frame(width: 500, height: 520)
    .background(.black.opacity(0.5))
}
