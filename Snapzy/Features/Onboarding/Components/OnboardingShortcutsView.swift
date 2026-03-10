//
//  ShortcutsView.swift
//  Snapzy
//
//  Shortcuts setup screen for onboarding flow — adaptive dark/light theme
//

import SwiftUI

struct ShortcutsView: View {
  let onDecline: () -> Void
  let onAccept: () -> Void

  var body: some View {
    OnboardingStepContainer {

      // Header icon
      Image(systemName: "keyboard")
        .font(.system(size: 44))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      // Title
      Text("Set as default screenshot tool?")
        .vsHeading()
        .padding(.top, 20)

      // Subtitle
      Text("Assign system shortcuts to Snapzy for quick access.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Shortcut groups
      VStack(spacing: 14) {
        ShortcutGroup(title: "Capture", shortcuts: [
          ShortcutItem(keys: "⇧⌘3", action: "Capture Fullscreen"),
          ShortcutItem(keys: "⇧⌘4", action: "Capture Area"),
          ShortcutItem(keys: "⇧⌘2", action: "Capture Text (OCR)"),
        ])

        ShortcutGroup(title: "Recording", shortcuts: [
          ShortcutItem(keys: "⇧⌘5", action: "Record Screen"),
        ])

        ShortcutGroup(title: "Tools", shortcuts: [
          ShortcutItem(keys: "⇧⌘A", action: "Open Annotate"),
          ShortcutItem(keys: "⇧⌘E", action: "Open Video Editor"),
        ])
      }
      .frame(maxWidth: 380)
      .padding(.top, 20)

      // Settings hint
      HStack(spacing: 8) {
        Image(systemName: "gearshape")
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.quaternary)

        Text("You can customize shortcuts anytime in Preferences → Shortcuts.")
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.quaternary)
      }
      .padding(.top, 4)

      // Actions
      HStack(spacing: 16) {
        Button("No, thanks") {
          onDecline()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button("Yes, enable shortcuts") {
          onAccept()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(.top, 32)
    }
  }
}

// MARK: - Shortcut Item Model

private struct ShortcutItem {
  let keys: String
  let action: String
}

// MARK: - Shortcut Group Component

private struct ShortcutGroup: View {
  let title: String
  let shortcuts: [ShortcutItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Category label
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(VSDesignSystem.Colors.quaternary)
        .tracking(1.2)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)

      // Shortcut rows
      VStack(spacing: 0) {
        ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
          ShortcutRow(keys: item.keys, action: item.action)

          if index < shortcuts.count - 1 {
            Divider()
              .background(VSDesignSystem.Colors.divider)
              .padding(.horizontal, 14)
          }
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(VSDesignSystem.Colors.cardFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(VSDesignSystem.Colors.cardStroke, lineWidth: 1)
      )
    }
  }
}

// MARK: - Shortcut Row Component

private struct ShortcutRow: View {
  let keys: String
  let action: String

  var body: some View {
    HStack(spacing: 12) {
      // Fixed-width key badge
      Text(keys)
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundColor(VSDesignSystem.Colors.primary)
        .frame(width: 56, alignment: .center)
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(VSDesignSystem.Colors.secondaryButtonFill)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(VSDesignSystem.Colors.cardStroke, lineWidth: 1)
        )

      // Action label
      Text(action)
        .font(.system(size: 13))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }
}

#Preview {
  ShortcutsView(onDecline: {}, onAccept: {})
    .frame(width: 500, height: 520)
    .background(.black.opacity(0.5))
}
