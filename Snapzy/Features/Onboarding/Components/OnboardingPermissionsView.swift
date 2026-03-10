//
//  PermissionsView.swift
//  Snapzy
//
//  Permissions grant screen for onboarding flow — dark/frosted theme
//

import AVFoundation
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

struct PermissionsView: View {
  @ObservedObject var screenCaptureManager: ScreenCaptureManager
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

      Text("Grant Permissions")
        .vsHeading()
        .padding(.top, 24)

      Text("Snapzy needs permissions for capture, audio, and save location.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(.top, 4)

      // Permission Rows
      VStack(spacing: 12) {
        // Screen Recording - Required
        PermissionRow(
          icon: "rectangle.dashed.badge.record",
          title: "Screen Recording",
          description: "Required for screenshots and recordings",
          isGranted: screenCaptureManager.hasPermission,
          isRequired: true,
          onGrant: {
            Task {
              await screenCaptureManager.requestPermission()
            }
          }
        )

        // Save Folder - Required
        PermissionRow(
          icon: "folder.fill",
          title: "Save Folder",
          description: "Required to save screenshots and recordings",
          isGranted: exportFolderGranted,
          isRequired: true,
          onGrant: {
            requestExportFolderPermission()
          }
        )

        // Microphone - Optional
        PermissionRow(
          icon: "mic.fill",
          title: "Microphone",
          description: "Optional for voice recording",
          isGranted: microphoneGranted,
          isRequired: false,
          onGrant: {
            requestMicrophonePermission()
          }
        )

        // Accessibility - Optional
        PermissionRow(
          icon: "hand.raised.fill",
          title: "Accessibility",
          description: "Optional for global shortcuts",
          isGranted: accessibilityGranted,
          isRequired: false,
          onGrant: {
            requestAccessibilityPermission()
          }
        )
      }
      .frame(maxWidth: 420)
      .padding(.top, 24)

      // Bottom Navigation
      HStack(spacing: 16) {
        Button("Quit") {
          onQuit()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button("Next") {
          onNext()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
        .disabled(!requiredPermissionsGranted)
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(.top, 32)
    }
    .task {
      fileAccessManager.ensureExportLocationInitialized()
      await screenCaptureManager.checkPermission()
      checkMicrophonePermission()
      checkAccessibilityPermission()
      checkExportFolderPermission()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      // Refresh permissions when app becomes active (user returns from System Settings)
      Task {
        await screenCaptureManager.checkPermission()
      }
      checkMicrophonePermission()
      checkAccessibilityPermission()
      checkExportFolderPermission()
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

  private func requestExportFolderPermission() {
    _ = fileAccessManager.chooseExportDirectory(
      message: "Choose a folder for Snapzy captures (default: Desktop/Snapzy)",
      prompt: "Grant Access",
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
