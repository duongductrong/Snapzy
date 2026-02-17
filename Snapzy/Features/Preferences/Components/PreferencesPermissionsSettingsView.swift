//
//  PermissionsSettingsView.swift
//  Snapzy
//
//  Permissions status tab showing system permission states and settings links
//

import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

struct PermissionsSettingsView: View {
  @State private var screenRecordingGranted = false
  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var isChecking = false

  // System Settings URLs
  private let screenRecordingURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  private let microphoneURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
  private let accessibilityURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

  var body: some View {
    Form {
      Section("Permissions") {
        Text("Snapzy requires certain permissions to capture your screen and audio.")
          .font(.caption)
          .foregroundColor(.secondary)

        permissionRow(
          icon: "rectangle.inset.filled.and.person.filled",
          name: "Screen Recording",
          description: "Required for screenshots and recordings",
          isGranted: screenRecordingGranted,
          isRequired: true,
          settingsURL: screenRecordingURL
        )

        permissionRow(
          icon: "mic.fill",
          name: "Microphone",
          description: "Optional for voice recording",
          isGranted: microphoneGranted,
          isRequired: false,
          settingsURL: microphoneURL
        )

        permissionRow(
          icon: "hand.raised.fill",
          name: "Accessibility",
          description: "Optional for global shortcuts",
          isGranted: accessibilityGranted,
          isRequired: false,
          settingsURL: accessibilityURL
        )

        HStack {
          Spacer()
          Button {
            checkAllPermissions()
          } label: {
            HStack(spacing: 4) {
              if isChecking {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: "arrow.clockwise")
              }
              Text("Refresh Status")
            }
          }
          .disabled(isChecking)
        }
        .padding(.top, 4)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      checkAllPermissions()
    }
  }

  // MARK: - Permission Row Component

  @ViewBuilder
  private func permissionRow(
    icon: String,
    name: String,
    description: String,
    isGranted: Bool,
    isRequired: Bool,
    settingsURL: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(name)
            .fontWeight(.medium)
          if isRequired {
            Text("Required")
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.2))
              .foregroundColor(.orange)
              .cornerRadius(4)
          }
        }
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      HStack(spacing: 4) {
        Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
          .foregroundColor(isGranted ? .green : .orange)
        Text(isGranted ? "Granted" : "Not Granted")
          .font(.caption)
          .foregroundColor(isGranted ? .green : .orange)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(isGranted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
      .cornerRadius(6)

      Button("Open Settings") {
        openSystemSettings(settingsURL)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Permission Checking

  private func checkAllPermissions() {
    isChecking = true

    checkMicrophonePermission()
    checkAccessibilityPermission()

    Task {
      await checkScreenRecordingPermission()
      await MainActor.run {
        isChecking = false
      }
    }
  }

  private func checkScreenRecordingPermission() async {
    do {
      _ = try await SCShareableContent.current
      await MainActor.run {
        screenRecordingGranted = true
      }
    } catch {
      await MainActor.run {
        screenRecordingGranted = false
      }
    }
  }

  private func checkMicrophonePermission() {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    microphoneGranted = (status == .authorized)
  }

  private func checkAccessibilityPermission() {
    accessibilityGranted = AXIsProcessTrusted()
  }

  // MARK: - System Settings Navigation

  private func openSystemSettings(_ urlString: String) {
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }
}

#Preview {
  PermissionsSettingsView()
    .frame(width: 600, height: 400)
}
