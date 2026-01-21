//
//  ShortcutsView.swift
//  ClaudeShot
//
//  Shortcuts setup screen for onboarding flow
//

import SwiftUI

struct ShortcutsView: View {
  let onDecline: () -> Void
  let onAccept: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Icon
      Image(systemName: "command")
        .font(.system(size: 50))
        .foregroundColor(.blue)
        .frame(width: 80, height: 80)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(Color.blue.opacity(0.1))
        )

      // Title
      Text("Set as default screenshot tool?")
        .vsHeading()

      // Subtitle
      Text("Assign ⇧⌘3, ⇧⌘4 for screenshots and ⇧⌘5 for screen recording to ClaudeShot?")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)

      Spacer()

      // Actions
      HStack(spacing: 16) {
        Button("No, thanks") {
          onDecline()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button("Yes!") {
          onAccept()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      }

      Spacer()
        .frame(height: 40)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  ShortcutsView(onDecline: {}, onAccept: {})
    .frame(width: 500, height: 400)
}
