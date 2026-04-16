//
//  ShortcutsView.swift
//  Snapzy
//
//  Shortcuts setup screen for onboarding flow — adaptive dark/light theme
//

import SwiftUI

struct ShortcutsView: View {
  var onBack: (() -> Void)? = nil
  let onDecline: () -> Void
  let onAccept: () -> Void

  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController
  @State private var hasConflict: Bool = true
  @State private var isCheckingConflict: Bool = false
  @State private var pollTimer: Timer?
  @State private var shakeOffset: CGFloat = 0
  @State private var conflictCardHighlight: Bool = false

  var body: some View {
    OnboardingStepContainer(onBack: onBack) {

      // Header icon
      Image(systemName: "keyboard")
        .font(.system(size: 44))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      // Title
      Text(shortcutsTitle)
        .vsHeading()
        .padding(.top, 20)

      // Subtitle
      Text(shortcutsSubtitle)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Shortcut groups
      VStack(spacing: 14) {
        ShortcutGroup(title: captureSectionTitle, shortcuts: [
          ShortcutItem(keys: "⇧⌘3", action: captureFullscreenTitle),
          ShortcutItem(keys: "⇧⌘4", action: captureAreaTitle),
          ShortcutItem(keys: "⇧⌘2", action: captureTextOCRTitle),
        ])

        ShortcutGroup(title: recordingSectionTitle, shortcuts: [
          ShortcutItem(keys: "⇧⌘5", action: recordScreenTitle),
        ])

        ShortcutGroup(title: toolsSectionTitle, shortcuts: [
          ShortcutItem(keys: "⇧⌘A", action: openAnnotateTitle),
          ShortcutItem(keys: "⇧⌘E", action: openVideoEditorTitle),
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

              Text(resolveShortcutOverlapTitle)
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

              Text(openSettingsTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
            }

            // Step-by-step guidance
            VStack(alignment: .leading, spacing: 4) {
              GuideStepRow(step: "1", text: guideStep1Title)
              GuideStepRow(step: "2", text: guideStep2Title)
              GuideStepRow(step: "3", text: guideStep3Title)
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

          Text(noConflictDetectedTitle)
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

        Text(customizeHintTitle)
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.quaternary)
      }
      .padding(.top, 4)

      // Actions
      HStack(spacing: 16) {
        Button(noThanksTitle) {
          stopPolling()
          onDecline()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button(enableShortcutsTitle) {
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

  private var shortcutsTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.title",
      defaultValue: "Set as default screenshot tool?",
      comment: "Onboarding shortcuts step title"
    )
  }

  private var shortcutsSubtitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.subtitle",
      defaultValue: "Assign system shortcuts to Snapzy for quick access.",
      comment: "Onboarding shortcuts step subtitle"
    )
  }

  private var captureSectionTitle: String {
    onboardingLocalization.string(
      "shortcut-overlay.capture-section",
      defaultValue: "Capture",
      comment: "Capture section title in shortcut overlay"
    )
  }

  private var captureFullscreenTitle: String {
    onboardingLocalization.string(
      "action.capture-fullscreen",
      defaultValue: "Capture Fullscreen",
      comment: "Action label for fullscreen screenshot"
    )
  }

  private var captureAreaTitle: String {
    onboardingLocalization.string(
      "action.capture-area",
      defaultValue: "Capture Area",
      comment: "Action label for area screenshot"
    )
  }

  private var captureTextOCRTitle: String {
    onboardingLocalization.string(
      "action.capture-text-ocr",
      defaultValue: "Capture Text (OCR)",
      comment: "Action label for OCR screenshot"
    )
  }

  private var recordingSectionTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.section-recording",
      defaultValue: "Recording",
      comment: "Shortcut group title in onboarding"
    )
  }

  private var recordScreenTitle: String {
    onboardingLocalization.string(
      "menu.record-screen",
      defaultValue: "Record Screen",
      comment: "Menu action title for starting screen recording"
    )
  }

  private var toolsSectionTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.section-tools",
      defaultValue: "Tools",
      comment: "Shortcut group title in onboarding"
    )
  }

  private var openAnnotateTitle: String {
    onboardingLocalization.string(
      "action.open-annotate",
      defaultValue: "Open Annotate",
      comment: "Action label for opening the image annotator"
    )
  }

  private var openVideoEditorTitle: String {
    onboardingLocalization.string(
      "action.open-video-editor",
      defaultValue: "Open Video Editor",
      comment: "Action label for opening the video editor"
    )
  }

  private var resolveShortcutOverlapTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.resolve-overlap",
      defaultValue: "Resolve macOS shortcut overlap",
      comment: "Warning title when system screenshot shortcuts overlap with Snapzy shortcuts"
    )
  }

  private var openSettingsTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.open-settings",
      defaultValue: "Open Settings →",
      comment: "Action hint to open system settings"
    )
  }

  private var guideStep1Title: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.guide-step-1",
      defaultValue: "Open System Settings → Keyboard → Keyboard Shortcuts",
      comment: "Step 1 in onboarding shortcut conflict resolution guide"
    )
  }

  private var guideStep2Title: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.guide-step-2",
      defaultValue: "Select Screenshots from the sidebar",
      comment: "Step 2 in onboarding shortcut conflict resolution guide"
    )
  }

  private var guideStep3Title: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.guide-step-3",
      defaultValue: "Uncheck the macOS screenshot shortcuts that overlap with the Snapzy shortcuts you want to keep on",
      comment: "Step 3 in onboarding shortcut conflict resolution guide"
    )
  }

  private var noConflictDetectedTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.no-conflict",
      defaultValue: "No overlapping macOS screenshot shortcuts detected — ready to go!",
      comment: "Success message when no system shortcut conflict exists"
    )
  }

  private var customizeHintTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.customize-hint",
      defaultValue: "You can customize or turn off shortcuts anytime in Preferences → Shortcuts.",
      comment: "Hint text below shortcut setup card"
    )
  }

  private var noThanksTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.no-thanks",
      defaultValue: "No, thanks",
      comment: "Secondary decline button on shortcut setup screen"
    )
  }

  private var enableShortcutsTitle: String {
    onboardingLocalization.string(
      "onboarding.shortcuts.enable",
      defaultValue: "Yes, enable shortcuts",
      comment: "Primary accept button on shortcut setup screen"
    )
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
