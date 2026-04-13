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

  @State private var hasConflict: Bool = true
  @State private var isCheckingConflict: Bool = false
  @State private var pollTimer: Timer?
  @State private var shakeOffset: CGFloat = 0
  @State private var conflictCardHighlight: Bool = false

  var body: some View {
    OnboardingStepContainer {

      // Header icon
      Image(systemName: "keyboard")
        .font(.system(size: 44))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      // Title
      Text(L10n.Onboarding.shortcutsTitle)
        .vsHeading()
        .padding(.top, 20)

      // Subtitle
      Text(L10n.Onboarding.shortcutsSubtitle)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Shortcut groups
      VStack(spacing: 14) {
        ShortcutGroup(title: L10n.ShortcutOverlay.captureSection, shortcuts: [
          ShortcutItem(keys: "⇧⌘3", action: L10n.Actions.captureFullscreen),
          ShortcutItem(keys: "⇧⌘4", action: L10n.Actions.captureArea),
          ShortcutItem(keys: "⇧⌘2", action: L10n.Actions.captureTextOCR),
        ])

        ShortcutGroup(title: L10n.Onboarding.recordingSection, shortcuts: [
          ShortcutItem(keys: "⇧⌘5", action: L10n.Menu.recordScreen),
        ])

        ShortcutGroup(title: L10n.Onboarding.toolsSection, shortcuts: [
          ShortcutItem(keys: "⇧⌘A", action: L10n.Actions.openAnnotate),
          ShortcutItem(keys: "⇧⌘E", action: L10n.Actions.openVideoEditor),
        ])
      }
      .frame(maxWidth: 380)
      .padding(.top, 20)

      // Conflict status card
      if hasConflict {
        // Warning card — conflict detected
        Button {
          SystemScreenshotShortcutManager.shared.openSystemScreenshotSettings()
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)

              Text(L10n.Onboarding.resolveShortcutOverlap)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(VSDesignSystem.Colors.primary)

              Spacer()

              // Refresh button
              Button {
                refreshConflictStatus()
              } label: {
                Image(systemName: isCheckingConflict ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                  .font(.system(size: 11))
                  .foregroundColor(VSDesignSystem.Colors.quaternary)
                  .rotationEffect(.degrees(isCheckingConflict ? 360 : 0))
                  .animation(
                    isCheckingConflict
                      ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                      : .default,
                    value: isCheckingConflict
                  )
              }
              .buttonStyle(.plain)

              Text(L10n.Onboarding.openSettings)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
            }

            // Step-by-step guidance
            VStack(alignment: .leading, spacing: 4) {
              GuideStepRow(step: "1", text: L10n.Onboarding.guideStep1)
              GuideStepRow(step: "2", text: L10n.Onboarding.guideStep2)
              GuideStepRow(step: "3", text: L10n.Onboarding.guideStep3)
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(Color.orange.opacity(conflictCardHighlight ? 0.18 : 0.08))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.orange.opacity(conflictCardHighlight ? 0.6 : 0.25), lineWidth: conflictCardHighlight ? 1.5 : 1)
          )
          .scaleEffect(conflictCardHighlight ? 1.02 : 1.0)
          .animation(.easeInOut(duration: 0.25), value: conflictCardHighlight)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 380)
        .padding(.top, 12)
      } else {
        // Success card — no conflict
        HStack(spacing: 10) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundColor(.green)

          Text(L10n.Onboarding.noConflictDetected)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(VSDesignSystem.Colors.primary)

          Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.green.opacity(0.08))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: 380)
        .padding(.top, 12)
      }

      Spacer().frame(height: 8)

      // Settings hint
      HStack(spacing: 8) {
        Image(systemName: "gearshape")
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.quaternary)

        Text(L10n.Onboarding.customizeHint)
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.quaternary)
      }
      .padding(.top, 4)

      // Actions
      HStack(spacing: 16) {
        Button(L10n.Onboarding.noThanks) {
          stopPolling()
          onDecline()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button(L10n.Onboarding.enableShortcuts) {
          if hasConflict {
            triggerConflictHint()
          } else {
            stopPolling()
            onAccept()
          }
        }
        .buttonStyle(
          hasConflict
            ? VSDesignSystem.PrimaryButtonStyle(isDisabled: true)
            : VSDesignSystem.PrimaryButtonStyle()
        )
        .offset(x: shakeOffset)
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(.top, 20)
      .padding(.bottom, 48)
    }
    .onAppear {
      refreshConflictStatus()
      startPolling()
    }
    .onDisappear {
      stopPolling()
    }
  }

  // MARK: - Conflict Status

  private func refreshConflictStatus() {
    isCheckingConflict = true
    // Small delay so the animation is visible
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      hasConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
      isCheckingConflict = false
    }
  }

  /// Poll every 2 seconds to detect when user disables system shortcuts in System Settings
  private func startPolling() {
    stopPolling()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
      Task { @MainActor in
        let newConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
        if newConflict != hasConflict {
          withAnimation(.easeInOut(duration: 0.3)) {
            hasConflict = newConflict
          }
        }
      }
    }
  }

  private func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
  }

  /// Shake the button and pulse the conflict card to hint resolution is needed
  private func triggerConflictHint() {
    // Pulse the conflict card highlight
    withAnimation {
      conflictCardHighlight = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      withAnimation {
        conflictCardHighlight = false
      }
    }

    // Shake the button horizontally
    let shakeDuration: TimeInterval = 0.06
    let offsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
    for (index, offset) in offsets.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + shakeDuration * Double(index)) {
        withAnimation(.linear(duration: shakeDuration)) {
          shakeOffset = offset
        }
      }
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

// MARK: - Guide Step Row

private struct GuideStepRow: View {
  let step: String
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      Text(step)
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(.orange)
        .frame(width: 16, height: 16)
        .background(
          Circle()
            .fill(Color.orange.opacity(0.15))
        )

      Text(text)
        .font(.system(size: 11))
        .foregroundColor(VSDesignSystem.Colors.tertiary)
    }
  }
}

#Preview {
  ShortcutsView(onDecline: {}, onAccept: {})
    .frame(width: 500, height: 600)
    .background(.black.opacity(0.5))
}
