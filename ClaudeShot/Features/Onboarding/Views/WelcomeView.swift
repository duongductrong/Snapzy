//
//  WelcomeView.swift
//  ClaudeShot
//
//  Welcome screen for onboarding flow
//

import SwiftUI

struct WelcomeView: View {
  let onContinue: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // App Icon
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 60))
        .foregroundColor(.blue)
        .frame(width: 80, height: 80)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(Color.blue.opacity(0.1))
        )

      // Title
      Text("Welcome to ClaudeShot")
        .vsHeading()

      // Subtitle
      Text("Capture screenshots and record screen videos with powerful annotation tools.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)

      Spacer()

      // Primary CTA
      Button("Let's do it!") {
        onContinue()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())

      Spacer()
        .frame(height: 40)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  WelcomeView(onContinue: {})
    .frame(width: 500, height: 400)
}
