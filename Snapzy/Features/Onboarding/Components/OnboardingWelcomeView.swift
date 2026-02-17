//
//  WelcomeView.swift
//  Snapzy
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
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 128, height: 128)

      // Title
      Text("Snapzy")
        .vsHeading()

      // Subtitle
      Text("A powerful screenshot & screen recording app for macOS")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)

      // Feature highlights
      VStack(alignment: .leading, spacing: 12) {
        FeatureRow(icon: "crop", text: "Capture area or fullscreen screenshots")
        FeatureRow(icon: "video", text: "Record screen with audio")
        FeatureRow(icon: "pencil.and.outline", text: "Annotate and edit captures")
      }
      .padding(.top, 8)

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

// MARK: - Feature Row Component

private struct FeatureRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundColor(.blue)
        .frame(width: 24)

      Text(text)
        .font(.system(size: 13))
        .foregroundColor(.secondary)
    }
  }
}

#Preview {
  WelcomeView(onContinue: {})
    .frame(width: 500, height: 400)
}
