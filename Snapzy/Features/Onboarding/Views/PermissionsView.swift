//
//  PermissionsView.swift
//  Snapzy
//
//  Permissions grant screen for onboarding flow
//

import AVFoundation
import ScreenCaptureKit
import SwiftUI

struct PermissionsView: View {
  @ObservedObject var screenCaptureManager: ScreenCaptureManager
  let onQuit: () -> Void
  let onNext: () -> Void

  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false

  // System Settings URLs
  private let microphoneURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
  private let accessibilityURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

  private var requiredPermissionsGranted: Bool {
    screenCaptureManager.hasPermission
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Header
      Image(systemName: "lock.shield")
        .font(.system(size: 48))
        .foregroundColor(.blue)

      Text("Grant Permissions")
        .vsHeading()

      Text("Snapzy needs certain permissions to capture your screen and audio.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)

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
            openSystemSettings(accessibilityURL)
          }
        )
      }
      .frame(maxWidth: 420)

      Spacer()

      // Bottom Navigation
      HStack(spacing: 16) {
        Button("Quit") {
          onQuit()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button(requiredPermissionsGranted ? "Next" : "Skip") {
          onNext()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      }

      Spacer()
        .frame(height: 40)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      await screenCaptureManager.checkPermission()
      checkMicrophonePermission()
      checkAccessibilityPermission()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      // Refresh permissions when app becomes active (user returns from System Settings)
      Task {
        await screenCaptureManager.checkPermission()
      }
      checkMicrophonePermission()
      checkAccessibilityPermission()
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

  private func requestMicrophonePermission() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        microphoneGranted = granted
      }
    }
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
}
