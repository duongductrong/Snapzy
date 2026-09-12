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

  /// Height of the per-row grant button. The frame and the shape both derive from it.
  static let grantButtonHeight: CGFloat = 32
  /// Grant button shape. A labelled action, so it is a pill; the pill derives its own radius
  /// from the button's height, so the frame and the shape cannot drift.
  static var grantButtonShape: Capsule {
    Capsule(style: .continuous)
  }

  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
  @ObservedObject private var identityManager = AppIdentityManager.shared
  private let fileAccessManager = SandboxFileAccessManager.shared

  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var exportFolderGranted = false
  @State private var probeTimer: Timer? = nil

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
          title: L10n.Onboarding.screenRecording,
          isRequired: true,
          promise: L10n.Onboarding.permissionsScreenRecordingPromise,
          assurances: [
            L10n.Onboarding.permissionsScreenRecordingAssurance1,
            L10n.Onboarding.permissionsScreenRecordingAssurance2,
            L10n.Onboarding.permissionsScreenRecordingAssurance3,
          ],
          isGranted: screenCaptureManager.hasPermission,
          actionTitle: L10n.Onboarding.permissionsScreenRecordingAction,
          onAction: {
            Task {
              _ = await screenCaptureManager.requestPermission()
              await refreshPermissions()
            }
          }
        )

        // 2. Save Location
        PermissionCard(
          title: L10n.Onboarding.saveFolder,
          isRequired: true,
          promise: L10n.Onboarding.permissionsSaveFolderPromise,
          assurances: [
            L10n.Onboarding.permissionsSaveFolderAssurance1,
            L10n.Onboarding.permissionsSaveFolderAssurance2,
            L10n.Onboarding.permissionsSaveFolderAssurance3,
          ],
          isGranted: exportFolderGranted,
          actionTitle: L10n.Onboarding.permissionsSaveFolderAction,
          onAction: {
            requestExportFolder()
          }
        )

        // 3. Accessibility & Global Shortcuts
        PermissionCard(
          title: L10n.Onboarding.accessibility,
          isRequired: false,
          promise: L10n.Onboarding.permissionsAccessibilityPromise,
          assurances: [
            L10n.Onboarding.permissionsAccessibilityAssurance1,
            L10n.Onboarding.permissionsAccessibilityAssurance2,
            L10n.Onboarding.permissionsAccessibilityAssurance3,
          ],
          isGranted: accessibilityGranted,
          actionTitle: L10n.Onboarding.permissionsAccessibilityAction,
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
      startProbeTimer()
      Task { await refreshPermissions() }
    }
    .onDisappear {
      stopProbeTimer()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await refreshPermissions() }
    }
    .onChange(of: screenCaptureManager.hasPermission) { hasPermission in
      if hasPermission {
        stopProbeTimer()
      }
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

        Text(L10n.Onboarding.permissionsAdjustAnytime)
          .font(.system(size: SnapzyOnboardingType.lede))
          .foregroundStyle(SnapzyGlassInk.muted)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Privacy Band

  private var privacyBand: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xl) {
      SnapzyOnboardingOverline(L10n.Onboarding.permissionsPrivacyOverline)

      HStack(alignment: .top, spacing: SnapzySpace.xxl + SnapzySpace.xs) {
        PrivacyPromise(
          symbol: "hand.tap",
          title: L10n.Onboarding.permissionsPrivacyTriggerTitle,
          detail: L10n.Onboarding.permissionsPrivacyTriggerDetail
        )

        PrivacyPromise(
          symbol: "lock.shield",
          title: L10n.Onboarding.permissionsPrivacyLocalTitle,
          detail: L10n.Onboarding.permissionsPrivacyLocalDetail
        )

        PrivacyPromise(
          symbol: "arrow.uturn.backward",
          title: L10n.Onboarding.permissionsPrivacySettingsTitle,
          detail: L10n.Onboarding.permissionsPrivacySettingsDetail
        )
      }
    }
    .padding(SnapzySpace.xxl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Radius.rect(SnapzyRadius.card)
        .fill(Color.white.opacity(0.035))
        .overlay(
          Radius.rect(SnapzyRadius.card)
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

  // MARK: - Probe Timer

  private func startProbeTimer() {
    stopProbeTimer()
    guard !screenCaptureManager.hasPermission else { return }
    probeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak screenCaptureManager] timer in
      guard let screenCaptureManager else {
        timer.invalidate()
        return
      }
      if screenCaptureManager.hasPermission {
        timer.invalidate()
        return
      }
      Task { @MainActor in
        await refreshPermissions()
      }
    }
  }

  private func stopProbeTimer() {
    probeTimer?.invalidate()
    probeTimer = nil
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

          Text(L10n.Onboarding.permissionsStatusGranted)
            .font(.system(size: SnapzyOnboardingType.body, weight: .medium))
            .foregroundStyle(SnapzyGlassInk.body)
        }
      } else {
        let shape = SnapzyOnboardingPermissionsView.grantButtonShape

        Button(action: onAction) {
          Text(actionTitle)
            .font(.system(size: SnapzyOnboardingType.body, weight: .semibold))
            .foregroundStyle(SnapzyGlassInk.primary)
            .padding(.horizontal, SnapzySpace.xl)
            .frame(height: SnapzyOnboardingPermissionsView.grantButtonHeight)
            .background(
              shape
                .fill(Color.white.opacity(0.14))
                .overlay(
                  shape
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
      Radius.rect(SnapzyRadius.card)
        .fill(Color.white.opacity(0.05))
        .overlay(
          Radius.rect(SnapzyRadius.card)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    )
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: isGranted)
  }

  private var badge: some View {
    Text(isRequired ? L10n.Onboarding.permissionsBadgeRequired : L10n.Onboarding.permissionsBadgeOptional)
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
          Radius.rect(Radius.tile)
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
