//
//  PermissionsView.swift
//  Snapzy
//
//  Permissions grant screen for onboarding flow — dark/frosted theme
//

import AVFoundation
import ApplicationServices
import SwiftUI

struct PermissionsView: View {
  @ObservedObject var screenCaptureManager: ScreenCaptureManager
  @ObservedObject private var identityManager = AppIdentityManager.shared
  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController
  var onBack: (() -> Void)? = nil
  let onNext: () -> Void

  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var exportFolderGranted = false
  private let fileAccessManager = SandboxFileAccessManager.shared

  // System Settings URLs
  private let microphoneURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
  private let accessibilityURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

  private var requiredPermissionsGranted: Bool {
    screenCaptureManager.hasPermission && exportFolderGranted
  }

  var body: some View {
    OnboardingStepContainer(onBack: onBack) {

      // Header
      Image(systemName: "lock.shield")
        .font(.system(size: 48))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      Text(permissionsTitle)
        .vsHeading()
        .padding(.top, 24)

      Text(permissionsSubtitle)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Permission Rows
      VStack(spacing: 12) {
        // Screen Recording - Required
        PermissionRow(
          icon: "rectangle.dashed.badge.record",
          title: screenRecordingTitle,
          description: screenRecordingDescription,
          status: screenRecordingStatus,
          isRequired: true,
          onGrant: {
            Task {
              if case .grantedButUnavailableDueToAppIdentity = screenCaptureManager.permissionStatus {
                await refreshPermissions()
              } else {
                _ = await screenCaptureManager.requestPermission()
              }
            }
          }
        )

        // Save Folder - Required
        PermissionRow(
          icon: "folder.fill",
          title: saveFolderTitle,
          description: requiredForCapturesTitle,
          status: exportFolderGranted ? .granted : .needsAction(buttonTitle: grantAccessTitle),
          isRequired: true,
          onGrant: {
            requestExportFolderPermission()
          }
        )

        // Microphone - Optional
        PermissionRow(
          icon: "mic.fill",
          title: microphoneTitle,
          description: optionalForVoiceRecordingTitle,
          status: microphoneGranted ? .granted : .needsAction(buttonTitle: grantAccessTitle),
          isRequired: false,
          onGrant: {
            requestMicrophonePermission()
          }
        )

        // Accessibility - Optional
        PermissionRow(
          icon: "hand.raised.fill",
          title: accessibilityTitle,
          description: optionalForGlobalShortcutsTitle,
          status: accessibilityGranted ? .granted : .needsAction(buttonTitle: grantAccessTitle),
          isRequired: false,
          onGrant: {
            requestAccessibilityPermission()
          }
        )
      }
      .frame(maxWidth: 420)
      .padding(.top, 24)

      if !identityManager.health.isHealthy {
        VStack(alignment: .leading, spacing: 8) {
          Text(buildIdentityNeedsAttentionTitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.orange)

          ForEach(identityManager.health.issues, id: \.self) { issue in
            Text("• \(localizedIdentityIssue(issue))")
              .font(.caption)
              .foregroundColor(VSDesignSystem.Colors.tertiary)
          }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(14)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color.orange.opacity(0.12))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .padding(.top, 16)
      }

      // Bottom Navigation
      Button(commonNextTitle) {
        onNext()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      .disabled(!requiredPermissionsGranted)
      .keyboardShortcut(.return, modifiers: [])
      .padding(.top, 32)
    }
    .task {
      await refreshPermissions()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task {
        await refreshPermissions()
      }
    }
  }

  // MARK: - Permission Checking

  private func checkMicrophonePermission() {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    microphoneGranted = (status == .authorized)
  }

  private func checkAccessibilityPermission() {
    accessibilityGranted = AXIsProcessTrusted()
  }

  private func checkExportFolderPermission() {
    fileAccessManager.ensureExportLocationInitialized()
    exportFolderGranted = fileAccessManager.hasPersistedExportPermission
  }

  private var screenRecordingDescription: String {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return requiredForCapturesTitle
    case .notGranted:
      return requiredForCapturesTitle
    case .grantedButUnavailableDueToAppIdentity:
      return screenRecordingIdentityBlockedTitle
    }
  }

  private var screenRecordingStatus: PermissionRowStatus {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return .granted
    case .notGranted:
      return .needsAction(buttonTitle: grantAccessTitle)
    case .grantedButUnavailableDueToAppIdentity:
      return .blocked(label: unavailableTitle, buttonTitle: refreshStatusTitle)
    }
  }

  private func refreshPermissions() async {
    fileAccessManager.ensureExportLocationInitialized()
    AppIdentityManager.shared.refresh()
    await screenCaptureManager.checkPermission()
    checkMicrophonePermission()
    checkAccessibilityPermission()
    checkExportFolderPermission()
  }

  private func requestExportFolderPermission() {
    _ = fileAccessManager.chooseExportDirectory(
      message: chooseFolderMessageTitle,
      prompt: grantAccessTitle,
      directoryURL: fileAccessManager.defaultExportDirectory
    )
    checkExportFolderPermission()
  }

  private func requestMicrophonePermission() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        microphoneGranted = granted
      }
    }
  }

  private func requestAccessibilityPermission() {
    if AXIsProcessTrusted() {
      accessibilityGranted = true
      return
    }

    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    // Keep user on the correct settings page if macOS does not navigate there.
    openSystemSettings(accessibilityURL)
    checkAccessibilityPermission()
  }

  private func openSystemSettings(_ urlString: String) {
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }

  private func localizedIdentityIssue(_ issue: AppIdentityIssue) -> String {
    switch issue {
    case .unexpectedBundleIdentifier(let bundleIdentifier):
      return onboardingLocalization.format(
        "app-identity.unexpected-bundle-id",
        defaultValue: "Expected bundle ID %@, found %@.",
        comment: "Identity issue message. First %@ is expected bundle identifier. Second %@ is current bundle identifier.",
        arguments: [AppBundleIdentity.expected, bundleIdentifier ?? "missing"]
      )
    case .invalidBundleSignature:
      return onboardingLocalization.string(
        "app-identity.invalid-signature",
        defaultValue: "This app bundle does not pass macOS code-signature validation.",
        comment: "Identity issue message when bundle signature validation fails"
      )
    case .outsideApplications(let bundleURL):
      return onboardingLocalization.format(
        "app-identity.outside-applications",
        defaultValue: "Install Snapzy in /Applications before granting permissions. Current path: %@",
        comment: "Identity issue message. %@ is the current app bundle path.",
        arguments: [bundleURL.path]
      )
    case .quarantined:
      return onboardingLocalization.string(
        "app-identity.quarantined",
        defaultValue: "This app still has the macOS quarantine flag. Reinstall with the installer script or remove quarantine before granting permissions.",
        comment: "Identity issue message when app is quarantined"
      )
    }
  }

  private var permissionsTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.title",
      defaultValue: "Grant Permissions",
      comment: "Onboarding permissions step title"
    )
  }

  private var permissionsSubtitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.subtitle",
      defaultValue: "Snapzy needs permissions for capture, audio, and save location.",
      comment: "Onboarding permissions step subtitle"
    )
  }

  private var screenRecordingTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.screen-recording",
      defaultValue: "Screen Recording",
      comment: "Screen recording permission label"
    )
  }

  private var saveFolderTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.save-folder",
      defaultValue: "Save Folder",
      comment: "Save folder permission label"
    )
  }

  private var microphoneTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.microphone",
      defaultValue: "Microphone",
      comment: "Microphone permission label"
    )
  }

  private var accessibilityTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.accessibility",
      defaultValue: "Accessibility",
      comment: "Accessibility permission label"
    )
  }

  private var requiredForCapturesTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.required-for-captures",
      defaultValue: "Required for screenshots and recordings",
      comment: "Permission description for required capture-related permissions"
    )
  }

  private var optionalForVoiceRecordingTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.optional-voice-recording",
      defaultValue: "Optional for voice recording",
      comment: "Permission description for microphone access"
    )
  }

  private var optionalForGlobalShortcutsTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.optional-global-shortcuts",
      defaultValue: "Optional for global shortcuts",
      comment: "Permission description for accessibility access"
    )
  }

  private var grantAccessTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.grant-access",
      defaultValue: "Grant Access",
      comment: "Button title to grant permission or folder access"
    )
  }

  private var refreshStatusTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.refresh-status",
      defaultValue: "Refresh Status",
      comment: "Button title to refresh permission or identity status"
    )
  }

  private var unavailableTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.unavailable",
      defaultValue: "Unavailable",
      comment: "Badge shown when permission is unavailable due to app identity state"
    )
  }

  private var buildIdentityNeedsAttentionTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.identity-attention",
      defaultValue: "Build Identity Needs Attention",
      comment: "Warning title when app identity health issues block permission usage"
    )
  }



  private var chooseFolderMessageTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.choose-folder-message",
      defaultValue: "Choose a folder for Snapzy captures (default: Desktop/Snapzy)",
      comment: "Open panel message for selecting export directory during onboarding"
    )
  }

  private var screenRecordingIdentityBlockedTitle: String {
    onboardingLocalization.string(
      "onboarding.permissions.identity-blocked-description",
      defaultValue: "Granted in System Settings, but this build cannot use the permission until the identity issues below are fixed.",
      comment: "Description shown when screen recording permission exists but app identity prevents using it"
    )
  }

  private var commonNextTitle: String {
    onboardingLocalization.string(
      "common.next",
      defaultValue: "Next",
      comment: "Primary next action button title"
    )
  }
}

#Preview {
  PermissionsView(
    screenCaptureManager: ScreenCaptureManager.shared,
    onNext: {}
  )
  .frame(width: 500, height: 500)
  .background(.black.opacity(0.5))
}
