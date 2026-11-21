//
//  SnapzyMockShortcutsView.swift
//  Snapzy
//
//  Step 3 interactive mockup: Authentic macOS Finder desktop with
//  Snapzy Floating Shortcut HUD, screen flash simulator, and portable config card.
//

import SwiftUI

struct SnapzyMockShortcutsView: View {
  @ObservedObject var state: SnapzyOnboardingState
  @State private var screenFlashOpacity: Double = 0
  @State private var triggeredMode: String? = nil
  @State private var hoveredMode: String? = nil

  private static let columnWidth: CGFloat = 512

  var body: some View {
    ZStack(alignment: .top) {
      // 1. macOS Desktop Wallpaper Canvas
      SnapzyMockWallpaper(app: .settings).equatable()

      // 2. Two aligned architectural blocks: System Settings window + unified Snapzy utility panel
      VStack(spacing: 14) {
        Spacer(minLength: 8)

        SnapzyMockSystemSettingsWindow(
          hasFullscreenConflict: $state.hasFullscreenConflict,
          hasAreaConflict: $state.hasAreaConflict,
          hasRecordingConflict: $state.hasRecordingConflict,
          onConflictChanged: { fullscreen, area, recording in
            state.updateShortcutConflicts(fullscreenConflict: fullscreen, areaConflict: area, recordingConflict: recording)
          },
          onResolveAll: {
            state.resolveShortcutConflicts()
          },
          onOpenRealSettings: {
            SystemScreenshotShortcutManager.shared.openSystemScreenshotSettings()
          }
        )

        // Single unified Snapzy Companion Panel (aligned to the exact 512pt window width)
        unifiedCompanionPanel

        Spacer(minLength: 10)
      }
      .padding(.horizontal, 16)
      .padding(.top, SnapzyMockMenuBar.barHeight + 6)

      // 3. macOS Menu Bar & Camera Notch
      SnapzyMockMenuBar(app: .settings).equatable()

      // 4. Camera Shutter Flash Effect
      Color.white
        .opacity(screenFlashOpacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Unified Companion Panel (Shortcuts + Status + Config + Diagnostics)

  private var unifiedCompanionPanel: some View {
    VStack(spacing: 0) {
      // Row 1: Interactive Snapzy shortcuts + inline conflict status / Resolve All
      HStack(spacing: 6) {
        shortcutButton(mode: L10n.Onboarding.mockModeArea, keys: "⇧⌘4", icon: "viewfinder")
        shortcutButton(mode: L10n.Onboarding.mockModeFull, keys: "⇧⌘3", icon: "macwindow")
        shortcutButton(mode: L10n.Onboarding.mockModeRecord, keys: "⇧⌘5", icon: "record.circle")

        Spacer(minLength: 6)

        statusAccessory
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)

      Rectangle()
        .fill(Color.white.opacity(0.09))
        .frame(height: 0.5)

      // Row 2: Portable config.toml + Anonymous Diagnostics cleanly paired side-by-side
      HStack(spacing: 12) {
        // Portable Config
        HStack(spacing: 8) {
          Image(systemName: "doc.text")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.70))
            .frame(width: 14)

          VStack(alignment: .leading, spacing: 1) {
            Text("~/.config/snapzy/config.toml")
              .font(.system(size: 9.5, weight: .medium, design: .monospaced))
              .foregroundStyle(Color.white.opacity(0.92))
              .lineLimit(1)

            Text(L10n.Onboarding.mockPortableConfig)
              .font(.system(size: 8.5))
              .foregroundStyle(Color.white.opacity(0.52))
              .lineLimit(1)
          }

          Spacer(minLength: 4)

          Button {
            withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
              state.isConfigGranted = true
            }
          } label: {
            Text(state.isConfigGranted ? L10n.Onboarding.mockLinked : L10n.Onboarding.mockGrant)
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(state.isConfigGranted ? Color.white : Color(red: 0.06, green: 0.09, blue: 0.16))
              .padding(.horizontal, 9)
              .padding(.vertical, 3.5)
              .background(
                Capsule(style: .continuous)
                  .fill(state.isConfigGranted ? Color.green.opacity(0.82) : Color.white)
              )
          }
          .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)

        Rectangle()
          .fill(Color.white.opacity(0.10))
          .frame(width: 0.5, height: 24)

        // Diagnostics Toggle
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 1) {
            Text(L10n.Onboarding.mockAnonymousDiagnostics)
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(Color.white.opacity(0.90))
              .lineLimit(1)

            Text(L10n.Onboarding.mockDiagnosticsDetail)
              .font(.system(size: 8.5))
              .foregroundStyle(Color.white.opacity(0.52))
              .lineLimit(1)
          }

          Spacer(minLength: 4)

          Toggle("", isOn: $state.diagnosticsOptIn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
    }
    .frame(width: Self.columnWidth)
    .background {
      SnapzyGlassSurface(
        shape: Radius.rect(Radius.card),
        substrate: 0.44,
        tint: 0.06
      )
    }
    .clipShape(Radius.rect(Radius.card))
    .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
    .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
  }

  private func shortcutButton(mode: String, keys: String, icon: String) -> some View {
    let isHovered = hoveredMode == mode
    return Button {
      triggerCaptureSimulation(mode: mode)
    } label: {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.78))

        Text(mode)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.92))

        Text(keys)
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .foregroundStyle(Color.white.opacity(0.66))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4.5)
      .background(
        Radius.rect(Radius.controlXS)
          .fill(Color.white.opacity(isHovered ? 0.14 : 0.07))
          .overlay(
            Radius.rect(Radius.controlXS)
              .strokeBorder(Color.white.opacity(isHovered ? 0.22 : 0.10), lineWidth: 0.5)
          )
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        hoveredMode = hovering ? mode : nil
      }
    }
  }

  @ViewBuilder
  private var statusAccessory: some View {
    if state.hasConflict {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          state.resolveShortcutConflicts()
        }
      } label: {
        HStack(spacing: 5) {
          Circle()
            .fill(Color.orange)
            .frame(width: 5.5, height: 5.5)

          Text(L10n.Onboarding.mockResolveAll)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
          Capsule(style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay(
              Capsule(style: .continuous)
                .strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.5)
            )
        )
      }
      .buttonStyle(.plain)
    } else {
      HStack(spacing: 5) {
        Circle()
          .fill(Color.green)
          .frame(width: 5.5, height: 5.5)

        Text(triggeredMode != nil ? L10n.Onboarding.mockCapturedMode(triggeredMode!) : L10n.Onboarding.mockShortcutsReady)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.84))
          .lineLimit(1)
      }
      .padding(.horizontal, 6)
    }
  }

  // MARK: - Simulation Trigger

  private func triggerCaptureSimulation(mode: String) {
    withAnimation(.easeOut(duration: 0.12)) {
      screenFlashOpacity = 0.55
      triggeredMode = mode
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      withAnimation(.easeOut(duration: 0.35)) {
        screenFlashOpacity = 0
      }
    }

    state.completeChallenge(.checkShortcuts)
  }
}
