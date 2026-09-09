//
//  SnapzyOnboardingPermissionsView.swift
//  Snapzy
//
//  Step 4 full-width permissions grid with promises, assurances, live TCC checks, and privacy band.
//

import ApplicationServices
import AVFoundation
import SwiftUI

struct SnapzyOnboardingPermissionsView: View {
  @ObservedObject var state: SnapzyOnboardingState

  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
  @ObservedObject private var identityManager = AppIdentityManager.shared
  private let fileAccessManager = SandboxFileAccessManager.shared

  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var exportFolderGranted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      headline

      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: SnapzySpace.xxl, alignment: .top),
          count: 3
        ),
        spacing: SnapzySpace.xxl
      ) {
        // 1. Screen Recording
        PermissionCard(
          title: "Screen Recording",
          isRequired: true,
          promise: "Captures your displays, windows, and selections with pixel precision",
          assurances: [
            "Captures only when you invoke a shortcut or action.",
            "No background streaming or hidden recording.",
            "OCR text extraction runs completely on-device.",
          ],
          isGranted: screenCaptureManager.hasPermission,
          actionTitle: "Allow Screen Recording…",
          onAction: {
            Task {
              _ = await screenCaptureManager.requestPermission()
              await refreshPermissions()
            }
          }
        )

        // 2. Save Location
        PermissionCard(
          title: "Save Folder",
          isRequired: true,
          promise: "Stores your captures in your chosen folder without permission prompts",
          assurances: [
            "Snapzy only touches its assigned folder (default: Desktop/Snapzy).",
            "Saves with customizable naming tokens and subfolders.",
            "Files remain completely local on your Mac.",
          ],
          isGranted: exportFolderGranted,
          actionTitle: "Choose Folder…",
          onAction: {
            requestExportFolder()
          }
        )

        // 3. Accessibility & Global Shortcuts
        PermissionCard(
          title: "Accessibility",
          isRequired: false,
          promise: "Listens for ⇧⌘4 and your custom global hotkeys from any application",
          assurances: [
            "Only checks keys against configured capture shortcuts.",
            "Never reads passwords or logs your keystrokes.",
            "Can be toggled off anytime in System Settings.",
          ],
          isGranted: accessibilityGranted,
          actionTitle: "Enable Shortcuts…",
          onAction: {
            requestAccessibility()
          }
        )
      }

      privacyBand

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      Task { await refreshPermissions() }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await refreshPermissions() }
    }
  }

  // MARK: - Headline

  private var headline: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xl) {
      Text(state.currentStep.title)
        .font(.system(size: SnapzyOnboardingType.display - 4, weight: .bold))
        .tracking(-0.5)
        .foregroundStyle(SnapzyGlassInk.primary)

      VStack(alignment: .leading, spacing: SnapzySpace.md) {
        Text(state.currentStep.subtitle)
          .font(.system(size: SnapzyOnboardingType.lede))
          .foregroundStyle(SnapzyGlassInk.body)

        Text("Take them all or take some — you can adjust permissions in System Settings anytime.")
          .font(.system(size: SnapzyOnboardingType.lede))
          .foregroundStyle(SnapzyGlassInk.muted)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Privacy Band

  private var privacyBand: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xl) {
      SnapzyOnboardingOverline("No matter what you choose")

      HStack(alignment: .top, spacing: SnapzySpace.xxl + SnapzySpace.xs) {
        PrivacyPromise(
          symbol: "hand.tap",
          title: "You trigger every capture",
          detail: "Snapzy stays completely idle until you press a shortcut. There is zero background scanning of your display."
        )

        PrivacyPromise(
          symbol: "lock.shield",
          title: "100% On-Device & Private",
          detail: "Vision OCR, image annotations, and audio capture are processed entirely locally on your Mac's hardware."
        )

        PrivacyPromise(
          symbol: "arrow.uturn.backward",
          title: "Undo anytime in Settings",
          detail: "Withdraw grants in System Settings whenever you like, and Snapzy gracefully continues with remaining tools."
        )
      }
    }
    .padding(SnapzySpace.xxl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: SnapzyRadius.card + 2, style: .continuous)
        .fill(Color.white.opacity(0.035))
        .overlay(
          RoundedRectangle(cornerRadius: SnapzyRadius.card + 2, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    )
  }

  // MARK: - Actions

  private func refreshPermissions() async {
    fileAccessManager.ensureExportLocationInitialized()
    AppIdentityManager.shared.refresh()
    await screenCaptureManager.checkPermission()
    accessibilityGranted = AXIsProcessTrusted()
    exportFolderGranted = fileAccessManager.hasPersistedExportPermission
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    state.setChallenge(.grantScreenRecording, completed: screenCaptureManager.hasPermission)
    state.setChallenge(.grantSaveFolder, completed: exportFolderGranted)
    state.setChallenge(.grantAccessibility, completed: accessibilityGranted)
  }

  private func requestExportFolder() {
    _ = fileAccessManager.chooseExportDirectory(
      message: "Choose a folder for Snapzy captures (default: Desktop/Snapzy)",
      prompt: "Grant Access",
      directoryURL: fileAccessManager.defaultExportDirectory
    )
    Task { await refreshPermissions() }
  }

  private func requestAccessibility() {
    if AXIsProcessTrusted() {
      accessibilityGranted = true
      return
    }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    Task { await refreshPermissions() }
  }
}

// MARK: - Permission Card

private struct PermissionCard: View {
  var title: String
  var isRequired: Bool
  var promise: String
  var assurances: [String]
  var isGranted: Bool
  var actionTitle: String
  var onAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xl) {
      HStack(spacing: SnapzySpace.md) {
        SnapzyOnboardingOverline(title)
        badge
        Spacer(minLength: 0)
      }

      Text(promise)
        .font(.system(size: SnapzyOnboardingType.lede - 1.5, weight: .semibold))
        .foregroundStyle(SnapzyGlassInk.primary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: SnapzySpace.lg) {
        ForEach(assurances, id: \.self) { item in
          HStack(alignment: .top, spacing: SnapzySpace.md) {
            Image(systemName: "checkmark.circle")
              .font(.system(size: 11))
              .foregroundStyle(SnapzyGlassInk.faint)

            Text(item)
              .font(.system(size: SnapzyOnboardingType.caption))
              .foregroundStyle(SnapzyGlassInk.body)
              .lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      Spacer(minLength: SnapzySpace.lg)

      // Status button row
      if isGranted {
        HStack(spacing: SnapzySpace.md) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(Color.green)

          Text("Granted")
            .font(.system(size: SnapzyOnboardingType.body, weight: .medium))
            .foregroundStyle(SnapzyGlassInk.body)
        }
      } else {
        Button(action: onAction) {
          Text(actionTitle)
            .font(.system(size: SnapzyOnboardingType.body, weight: .semibold))
            .foregroundStyle(SnapzyGlassInk.primary)
            .padding(.horizontal, SnapzySpace.xl)
            .frame(height: 32)
            .background(
              RoundedRectangle(cornerRadius: SnapzyRadius.control, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .overlay(
                  RoundedRectangle(cornerRadius: SnapzyRadius.control, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                )
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(SnapzySpace.xxl)
    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: SnapzyRadius.card + 2, style: .continuous)
        .fill(Color.white.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: SnapzyRadius.card + 2, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    )
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: isGranted)
  }

  private var badge: some View {
    Text(isRequired ? "REQUIRED" : "OPTIONAL")
      .font(.system(size: 9, weight: .bold))
      .tracking(0.8)
      .foregroundStyle(SnapzyGlassInk.body)
      .padding(.horizontal, SnapzySpace.md)
      .padding(.vertical, 3)
      .background(
        Capsule().fill(Color.white.opacity(isRequired ? 0.12 : 0.07))
      )
  }
}

private struct PrivacyPromise: View {
  var symbol: String
  var title: String
  var detail: String

  var body: some View {
    HStack(alignment: .top, spacing: SnapzySpace.xl) {
      Image(systemName: symbol)
        .font(.system(size: 13))
        .foregroundStyle(SnapzyGlassInk.body)
        .frame(width: 26, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.10))
        )

      VStack(alignment: .leading, spacing: SnapzySpace.sm) {
        Text(title)
          .font(.system(size: SnapzyOnboardingType.body, weight: .semibold))
          .foregroundStyle(SnapzyGlassInk.primary)

        Text(detail)
          .font(.system(size: SnapzyOnboardingType.caption))
          .foregroundStyle(SnapzyGlassInk.muted)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
