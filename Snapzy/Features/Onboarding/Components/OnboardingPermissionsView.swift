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
  let onQuit: () -> Void
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
    OnboardingStepContainer {

      // Header
      Image(systemName: "lock.shield")
        .font(.system(size: 48))
        .foregroundColor(VSDesignSystem.Colors.secondary)

      Text(L10n.Onboarding.permissionsTitle)
        .vsHeading()
        .padding(.top, 24)

      Text(L10n.Onboarding.permissionsSubtitle)
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Permission Rows
      VStack(spacing: 12) {
        // Screen Recording - Required
        PermissionRow(
          icon: "rectangle.dashed.badge.record",
          title: L10n.Onboarding.screenRecording,
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
          title: L10n.Onboarding.saveFolder,
          description: L10n.Onboarding.requiredForCaptures,
          status: exportFolderGranted ? .granted : .needsAction(buttonTitle: L10n.Onboarding.grantAccess),
          isRequired: true,
          onGrant: {
            requestExportFolderPermission()
          }
        )

        // Microphone - Optional
        PermissionRow(
          icon: "mic.fill",
          title: L10n.Onboarding.microphone,
          description: L10n.Onboarding.optionalForVoiceRecording,
          status: microphoneGranted ? .granted : .needsAction(buttonTitle: L10n.Onboarding.grantAccess),
          isRequired: false,
          onGrant: {
            requestMicrophonePermission()
          }
        )

        // Accessibility - Optional
        PermissionRow(
          icon: "hand.raised.fill",
          title: L10n.Onboarding.accessibility,
          description: L10n.Onboarding.optionalForGlobalShortcuts,
          status: accessibilityGranted ? .granted : .needsAction(buttonTitle: L10n.Onboarding.grantAccess),
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
          Text(L10n.Onboarding.buildIdentityNeedsAttention)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.orange)

          ForEach(identityManager.health.issues, id: \.self) { issue in
            Text("• \(issue.description)")
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
      HStack(spacing: 16) {
        Button(L10n.Onboarding.quit) {
          onQuit()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button(L10n.Common.next) {
          onNext()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
        .disabled(!requiredPermissionsGranted)
        .keyboardShortcut(.return, modifiers: [])
      }
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
      return L10n.Onboarding.requiredForCaptures
    case .notGranted:
      return L10n.Onboarding.requiredForCaptures
    case .grantedButUnavailableDueToAppIdentity:
      return L10n.Onboarding.screenRecordingIdentityBlocked
    }
  }

  private var screenRecordingStatus: PermissionRowStatus {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return .granted
    case .notGranted:
      return .needsAction(buttonTitle: L10n.Onboarding.grantAccess)
    case .grantedButUnavailableDueToAppIdentity:
      return .blocked(label: L10n.Onboarding.unavailable, buttonTitle: L10n.Onboarding.refreshStatus)
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
      message: L10n.Onboarding.chooseFolderMessage,
      prompt: L10n.Onboarding.grantAccess,
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
}

#Preview {
  PermissionsView(
    screenCaptureManager: ScreenCaptureManager.shared,
    onQuit: {},
    onNext: {}
  )
  .frame(width: 500, height: 500)
  .background(.black.opacity(0.5))
}
