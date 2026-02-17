//
//  SkipConfirmationView.swift
//  Snapzy
//
//  Confirmation screen when user taps Skip — dark/frosted theme
//

import SwiftUI

struct SkipConfirmationView: View {
  let onGoBack: () -> Void
  let onConfirmSkip: () -> Void

  var body: some View {
    OnboardingStepContainer {

      // Icon
      Image(systemName: "forward.fill")
        .font(.system(size: 44))
        .foregroundColor(.white.opacity(0.7))

      // Title
      Text("Skip remaining setup?")
        .vsHeading()
        .padding(.top, 24)

      // Description
      Text("All remaining settings will use their defaults. You can always change them later in Preferences.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // What will be skipped
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          Image(systemName: "keyboard")
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.5))
            .frame(width: 20)
          Text("Keyboard shortcuts — system defaults")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.6))
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.white.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(Color.white.opacity(0.12), lineWidth: 1)
      )
      .padding(.top, 24)

      // Actions
      HStack(spacing: 16) {
        Button("Go Back") {
          onGoBack()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button("Skip Setup") {
          onConfirmSkip()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(.top, 32)
    }
  }
}

#Preview {
  SkipConfirmationView(onGoBack: {}, onConfirmSkip: {})
    .frame(width: 500, height: 450)
    .background(.black.opacity(0.5))
}
