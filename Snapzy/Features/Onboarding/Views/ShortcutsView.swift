//
//  ShortcutsView.swift
//  Snapzy
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

      // App Icon
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 80, height: 80)

      // Title
      Text("Set as default screenshot tool?")
        .vsHeading()

      // Subtitle
      Text("Assign system shortcuts to Snapzy for quick access:")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)

      // Shortcut badges
      VStack(spacing: 8) {
        ShortcutBadge(keys: "⇧⌘3", action: "Capture Fullscreen")
        ShortcutBadge(keys: "⇧⌘4", action: "Capture Area")
        ShortcutBadge(keys: "⇧⌘5", action: "Record Screen")
      }
      .padding(.top, 4)

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

// MARK: - Shortcut Badge Component

private struct ShortcutBadge: View {
  let keys: String
  let action: String

  var body: some View {
    HStack(spacing: 12) {
      Text(keys)
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.15))
        )

      Text(action)
        .font(.system(size: 13))
        .foregroundColor(.secondary)
    }
  }
}

#Preview {
  ShortcutsView(onDecline: {}, onAccept: {})
    .frame(width: 500, height: 400)
}
