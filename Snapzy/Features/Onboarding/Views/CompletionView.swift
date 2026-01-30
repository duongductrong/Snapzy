//
//  CompletionView.swift
//  Snapzy
//
//  Completion screen for onboarding flow - "Ready to go!"
//

import SwiftUI

struct CompletionView: View {
  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Success Icon
      ZStack {
        Circle()
          .fill(Color.green.opacity(0.15))
          .frame(width: 100, height: 100)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 64))
          .foregroundColor(.green)
      }

      // Title
      Text("Ready to go!")
        .vsHeading()

      // Subtitle
      Text("You can access Snapzy through the menu bar icon or by using the keyboard shortcuts you configured.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)

      // Menu bar hint
      HStack(spacing: 8) {
        Image(systemName: "menubar.arrow.up.rectangle")
          .font(.system(size: 16))
          .foregroundColor(.blue)

        Text("Look for the camera icon in your menu bar")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.blue.opacity(0.08))
      )

      Spacer()

      // Actions
      VStack(spacing: 12) {
        SettingsLink {
          Text("Open Preferences")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
              RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
          onComplete()
        })

        Button("Get Started") {
          onComplete()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())
      }

      Spacer()
        .frame(height: 40)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  CompletionView(
    onComplete: {}
  )
  .frame(width: 500, height: 450)
}
