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

  var body: some View {
    ZStack(alignment: .top) {
      // 1. macOS Desktop Wallpaper Canvas
      SnapzyMockWallpaper(app: .finder).equatable()

      // 2. macOS Finder Window in Background
      VStack(spacing: 0) {
        Spacer(minLength: 16)

        SnapzyMockFinderWindow().equatable()
          .frame(maxWidth: 480, maxHeight: 280)
          .padding(.horizontal, 20)

        Spacer(minLength: 16)
      }
      .padding(.top, 28) // Room for Menu Bar

      // 3. macOS Menu Bar & Camera Notch
      SnapzyMockMenuBar(app: .finder).equatable()

      // 4. Centered Floating Snapzy Shortcut HUD & Simulator
      VStack(spacing: 12) {
        Spacer()

        // Floating Shortcut HUD Capsule
        shortcutHUDCapsule

        // Portable Config & Diagnostics Card
        bottomConfigCard

        Spacer(minLength: 20)
      }
      .padding(.horizontal, 24)
      .padding(.top, 28)

      // 5. Camera Shutter Flash Effect
      Color.white
        .opacity(screenFlashOpacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Shortcut HUD Capsule

  private var shortcutHUDCapsule: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        shortcutButton(mode: "Area", keys: ["⇧", "⌘", "4"], icon: "viewfinder")
        divider
        shortcutButton(mode: "Full", keys: ["⇧", "⌘", "3"], icon: "macwindow")
        divider
        shortcutButton(mode: "Record", keys: ["⇧", "⌘", "5"], icon: "record.circle")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background {
        SnapzyGlassSurface(
          shape: Capsule(style: .continuous),
          substrate: SnapzySurfaceGlass.baseDarkness,
          tint: 0.12
        )
      }
      .clipShape(Capsule(style: .continuous))
      .shadow(color: Color.black.opacity(0.35), radius: 18, y: 8)
      .shadow(color: Color.black.opacity(0.12), radius: 4, y: 1)

      // Active status / conflict resolution indicator
      HStack(spacing: 6) {
        if state.hasConflict {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9.5))
            .foregroundStyle(Color.orange)

          Text("System conflict detected with macOS screenshot shortcut.")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))

          Button {
            SystemScreenshotShortcutManager.shared.openSystemScreenshotSettings()
            state.hasConflict = false
          } label: {
            Text("Resolve")
              .font(.system(size: 9.5, weight: .bold))
              .foregroundStyle(Color.orange)
              .underline()
          }
          .buttonStyle(.plain)
        } else {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 9.5))
            .foregroundStyle(Color.green)

          Text(triggeredMode != nil ? "Captured \(triggeredMode!)!" : "All global shortcuts active & ready")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(Color.black.opacity(0.40))
      )
    }
  }

  private func shortcutButton(mode: String, keys: [String], icon: String) -> some View {
    Button {
      triggerCaptureSimulation(mode: mode)
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.accentColor)

        Text(mode)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.white)

        HStack(spacing: 2) {
          ForEach(keys, id: \.self) { key in
            Text(key)
              .font(.system(size: 9.5, weight: .bold, design: .monospaced))
              .foregroundStyle(Color.white.opacity(0.90))
              .padding(.horizontal, 4)
              .padding(.vertical, 1.5)
              .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                  .fill(Color.white.opacity(0.12))
                  .overlay(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                      .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                  )
              )
          }
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.white.opacity(0.04))
      )
    }
    .buttonStyle(.plain)
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.16))
      .frame(width: 0.75, height: 16)
  }

  // MARK: - Bottom Config & Diagnostics Card

  private var bottomConfigCard: some View {
    HStack(spacing: 12) {
      // Config.toml item
      HStack(spacing: 8) {
        Image(systemName: "doc.text.fill")
          .font(.system(size: 12))
          .foregroundStyle(Color.blue)

        VStack(alignment: .leading, spacing: 1) {
          Text("~/.config/snapzy/config.toml")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.90))
          Text("Portable plaintext settings")
            .font(.system(size: 8.5))
            .foregroundStyle(Color.white.opacity(0.55))
        }

        Button {
          state.isConfigGranted = true
        } label: {
          Text(state.isConfigGranted ? "Linked" : "Grant")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(state.isConfigGranted ? Color.green.opacity(0.8) : Color.blue)
            )
        }
        .buttonStyle(.plain)
      }

      Rectangle()
        .fill(Color.white.opacity(0.12))
        .frame(width: 0.75, height: 22)

      // Diagnostics Toggle
      HStack(spacing: 6) {
        Toggle("", isOn: $state.diagnosticsOptIn)
          .labelsHidden()
          .toggleStyle(.switch)
          .scaleEffect(0.65)

        VStack(alignment: .leading, spacing: 1) {
          Text("Anonymous Diagnostics")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))
          Text("Crash reports only, zero capture content")
            .font(.system(size: 8))
            .foregroundStyle(Color.white.opacity(0.50))
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background {
      SnapzyGlassSurface(
        shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
        substrate: SnapzySurfaceGlass.baseDarkness,
        tint: 0.08
      )
    }
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .shadow(color: Color.black.opacity(0.24), radius: 10, y: 5)
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
