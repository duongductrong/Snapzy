//
//  SnapzyOnboardingPermissionsView.swift
//  Snapzy
//
//  Step 4 full-width permissions screen: a scannable list of grants beside a quiet
//  reassurance rail.
//

import ApplicationServices
import AVFoundation
import SwiftUI

struct SnapzyOnboardingPermissionsView: View {
  @ObservedObject var state: SnapzyOnboardingState

  /// Height of the per-row grant button. The frame and the shape both derive from it.
  static let grantButtonHeight: CGFloat = 28
  /// Grant button shape. A labelled action, so it is a pill; the pill derives its own radius
  /// from the button's height, so the frame and the shape cannot drift.
  static var grantButtonShape: Capsule {
    Capsule(style: .continuous)
  }

  /// Width of the open editorial privacy column beside the permissions list.
  private static let privacyRailWidth: CGFloat = 304

  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
  @ObservedObject private var identityManager = AppIdentityManager.shared
  private let fileAccessManager = SandboxFileAccessManager.shared

  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var exportFolderGranted = false
  @State private var probeTimer: Timer? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.huge) {
      headline

      HStack(alignment: .top, spacing: SnapzySpace.giant) {
        permissionList
          .frame(maxWidth: .infinity, alignment: .top)

        privacyRail
          .frame(width: SnapzyOnboardingPermissionsView.privacyRailWidth, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    VStack(alignment: .leading, spacing: SnapzySpace.md) {
      SnapzyOnboardingOverline(
        L10n.Onboarding.stepIndicator(state.currentStep.stepNumber, SnapzyOnboardingStep.allCases.count)
      )

      Text(state.currentStep.title)
        .font(.system(size: SnapzyOnboardingType.title, weight: .bold))
        .tracking(SnapzyOnboardingType.displayTracking + 0.2)
        .foregroundStyle(SnapzyGlassInk.primary)

      Text(state.currentStep.subtitle)
        .font(.system(size: SnapzyOnboardingType.lede))
        .foregroundStyle(SnapzyGlassInk.body)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Permissions

  private var permissionList: some View {
    VStack(spacing: 0) {
      PermissionsGrantRow(
        symbol: "display",
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

      rowRule

      PermissionsGrantRow(
        symbol: "folder",
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

      rowRule

      PermissionsGrantRow(
        symbol: "keyboard",
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
    .background(listShape.fill(SnapzyGlassInk.fillQuiet))
    .overlay(listShape.strokeBorder(SnapzyGlassInk.hairline, lineWidth: SnapzySurfaceGlass.specularLineWidth))
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: screenCaptureManager.hasPermission)
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: exportFolderGranted)
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: accessibilityGranted)
  }

  private var listShape: RoundedRectangle {
    Radius.rect(SnapzyRadius.card)
  }

  private var rowRule: some View {
    Rectangle()
      .fill(SnapzyGlassInk.hairline)
      .frame(height: SnapzySurfaceGlass.specularLineWidth)
      .padding(.horizontal, SnapzySpace.xxxl)
  }

  // MARK: - Open Editorial Privacy Column (No Empty Box Stretching to Bottom)

  private var privacyRail: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xxxl) {
      SnapzyOnboardingOverline(L10n.Onboarding.permissionsPrivacyOverline, rule: true)

      VStack(alignment: .leading, spacing: SnapzySpace.xxxl) {
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

      Rectangle()
        .fill(SnapzyGlassInk.hairline)
        .frame(height: SnapzySurfaceGlass.specularLineWidth)

      Text(L10n.Onboarding.permissionsAdjustAnytime)
        .font(.system(size: SnapzyOnboardingType.caption))
        .foregroundStyle(SnapzyGlassInk.faint)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, SnapzySpace.sm)
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  // MARK: - Actions

  private func refreshPermissions() async {
    fileAccessManager.ensureExportLocationInitialized()
    AppIdentityManager.shared.refresh(force: true)
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
      message: L10n.Onboarding.chooseFolderMessage,
      prompt: L10n.Onboarding.grantAccess,
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
    probeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
      Task { @MainActor in
        if screenCaptureManager.hasPermission {
          stopProbeTimer()
          return
        }
        await refreshPermissions()
      }
    }
  }

  private func stopProbeTimer() {
    probeTimer?.invalidate()
    probeTimer = nil
  }
}

// MARK: - Permission Row

private struct PermissionsGrantRow: View {
  var symbol: String
  var title: String
  var isRequired: Bool
  var promise: String
  var assurances: [String]
  var isGranted: Bool
  var actionTitle: String
  var onAction: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: SnapzySpace.xl) {
      tile

      VStack(alignment: .leading, spacing: SnapzySpace.xs) {
        // Single-line header: capability title + subtle inline necessity label + trailing status/CTA
        HStack(alignment: .center, spacing: SnapzySpace.sm) {
          Text(title)
            .font(.system(size: SnapzyOnboardingType.challenge, weight: .semibold))
            .foregroundStyle(SnapzyGlassInk.primary)

          Text("·")
            .font(.system(size: SnapzyOnboardingType.caption, weight: .medium))
            .foregroundStyle(SnapzyGlassInk.faint)
            .accessibilityHidden(true)

          Text(isRequired ? L10n.Onboarding.permissionsBadgeRequired : L10n.Onboarding.permissionsBadgeOptional)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(isRequired ? SnapzyGlassInk.muted : SnapzyGlassInk.faint)
            .accessibilityLabel(isRequired ? L10n.Onboarding.requiredForCaptures : L10n.Onboarding.optionalForGlobalShortcuts)

          Spacer(minLength: SnapzySpace.lg)

          trailing
        }
        .frame(minHeight: SnapzyOnboardingPermissionsView.grantButtonHeight)

        Text(promise)
          .font(.system(size: SnapzyOnboardingType.body - 0.5))
          .foregroundStyle(SnapzyGlassInk.body)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)

        // Quiet editorial assurance list anchored with a subtle vertical rule — preserves 100% of
        // the privacy details while staying crisp, scannable, and free of SaaS card clutter.
        VStack(alignment: .leading, spacing: 2.5) {
          ForEach(assurances, id: \.self) { item in
            Text(item)
              .font(.system(size: 11.5))
              .foregroundStyle(SnapzyGlassInk.muted.opacity(0.85))
              .lineSpacing(2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.leading, SnapzySpace.md)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(SnapzyGlassInk.hairline)
            .frame(width: 1)
            .padding(.vertical, 2)
        }
        .padding(.top, SnapzySpace.xs)
      }
    }
    .padding(.horizontal, SnapzySpace.xxxl)
    .padding(.vertical, SnapzySpace.xxl)
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  /// Trailing grant state: quiet green status dot + label (never duplicating a green checkmark box
  /// on the left), or a crisp action pill when still needed.
  @ViewBuilder
  private var trailing: some View {
    if isGranted {
      HStack(spacing: 6) {
        Circle()
          .fill(Color(red: 0.22, green: 0.80, blue: 0.42))
          .frame(width: 6.5, height: 6.5)

        Text(L10n.Onboarding.permissionsStatusGranted)
          .font(.system(size: SnapzyOnboardingType.caption, weight: .medium))
          .foregroundStyle(SnapzyGlassInk.body)
      }
      .fixedSize()
    } else {
      Button(action: onAction) {
        Text(actionTitle)
          .font(.system(size: SnapzyOnboardingType.caption, weight: .semibold))
          .foregroundStyle(isRequired ? Color(red: 0.04, green: 0.08, blue: 0.22) : SnapzyGlassInk.primary)
          .padding(.horizontal, SnapzySpace.xl)
          .frame(height: SnapzyOnboardingPermissionsView.grantButtonHeight)
          .background(
            SnapzyOnboardingPermissionsView.grantButtonShape
              .fill(isRequired ? Color.white : SnapzyGlassInk.fillRaised)
          )
          .overlay(
            SnapzyOnboardingPermissionsView.grantButtonShape
              .strokeBorder(
                isRequired ? Color.black.opacity(0.06) : SnapzyGlassInk.hairlineStrong,
                lineWidth: SnapzySurfaceGlass.specularLineWidth
              )
          )
          .contentShape(SnapzyOnboardingPermissionsView.grantButtonShape)
      }
      .buttonStyle(SnapzyGrantButtonStyle(isProminent: isRequired))
      .fixedSize()
    }
  }

  /// Keeps each permission's real macOS capability glyph (`display`, `folder`, `keyboard`) intact
  /// instead of turning all three rows into identical green check boxes.
  private var tile: some View {
    ZStack {
      Radius.rect(Radius.tile)
        .fill(SnapzyGlassInk.fillRaised)

      Image(systemName: symbol)
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(isGranted ? SnapzyGlassInk.primary : SnapzyGlassInk.body)
    }
    .frame(width: 32, height: 32)
    .overlay(
      Radius.rect(Radius.tile)
        .strokeBorder(SnapzyGlassInk.hairline, lineWidth: SnapzySurfaceGlass.specularLineWidth)
    )
    .accessibilityHidden(true)
  }
}

private struct SnapzyGrantButtonStyle: ButtonStyle {
  var isProminent: Bool = false
  @State private var isHovered = false

  private var shape: Capsule {
    SnapzyOnboardingPermissionsView.grantButtonShape
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay(
        shape.fill(
          (isProminent ? Color(red: 0.06, green: 0.20, blue: 0.90).opacity(0.10) : SnapzyGlassInk.fillHover)
            .opacity(configuration.isPressed ? 0.8 : (isHovered ? 1 : 0))
        )
      )
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .onHover { hovering in
        withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
      }
      .animation(SnapzyMotionPreferences.shared.spec(.anticipation).animation, value: configuration.isPressed)
  }
}

private struct PrivacyPromise: View {
  var symbol: String
  var title: String
  var detail: String

  var body: some View {
    HStack(alignment: .top, spacing: SnapzySpace.lg) {
      Image(systemName: symbol)
        .font(.system(size: 12))
        .foregroundStyle(SnapzyGlassInk.body)
        .frame(width: 22)
        .padding(.top, 2)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: SnapzySpace.xxs) {
        Text(title)
          .font(.system(size: SnapzyOnboardingType.body, weight: .semibold))
          .foregroundStyle(SnapzyGlassInk.primary)

        Text(detail)
          .font(.system(size: SnapzyOnboardingType.caption))
          .foregroundStyle(SnapzyGlassInk.muted)
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
