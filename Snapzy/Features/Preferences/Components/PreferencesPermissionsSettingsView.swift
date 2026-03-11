//
//  PermissionsSettingsView.swift
//  Snapzy
//
//  Permissions status tab showing system permission states and settings links
//

import AppKit
import AVFoundation
import SwiftUI

struct PermissionsSettingsView: View {
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
  @ObservedObject private var identityManager = AppIdentityManager.shared
  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var saveFolderGranted = false
  @State private var isChecking = false

  private let fileAccessManager = SandboxFileAccessManager.shared

  // System Settings URLs
  private let screenRecordingURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  private let microphoneURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
  private let accessibilityURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  private let filesAndFoldersURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

  var body: some View {
    Form {
      Section("Permissions") {
        Text("Snapzy requires certain permissions to capture your screen and audio.")
          .font(.caption)
          .foregroundColor(.secondary)

        permissionRow(
          icon: "rectangle.inset.filled.and.person.filled",
          name: "Screen Recording",
          description: screenRecordingDescription,
          statusLabel: screenRecordingStatusLabel,
          statusIcon: screenRecordingStatusIcon,
          statusColor: screenRecordingStatusColor,
          isRequired: true,
          settingsURL: screenRecordingURL
        )

        permissionRow(
          icon: "folder.fill",
          name: "Save Folder",
          description: "Required to save screenshots and recordings",
          statusLabel: saveFolderGranted ? "Granted" : "Not Granted",
          statusIcon: saveFolderGranted ? "checkmark.circle.fill" : "xmark.circle.fill",
          statusColor: saveFolderGranted ? .green : .orange,
          isRequired: true,
          settingsURL: filesAndFoldersURL
        )

        permissionRow(
          icon: "mic.fill",
          name: "Microphone",
          description: "Optional for voice recording",
          statusLabel: microphoneGranted ? "Granted" : "Not Granted",
          statusIcon: microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill",
          statusColor: microphoneGranted ? .green : .orange,
          isRequired: false,
          settingsURL: microphoneURL
        )

        permissionRow(
          icon: "hand.raised.fill",
          name: "Accessibility",
          description: "Optional for global shortcuts",
          statusLabel: accessibilityGranted ? "Granted" : "Not Granted",
          statusIcon: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill",
          statusColor: accessibilityGranted ? .green : .orange,
          isRequired: false,
          settingsURL: accessibilityURL
        )

        if !identityManager.health.isHealthy {
          VStack(alignment: .leading, spacing: 6) {
            Text("Build Identity Needs Attention")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundColor(.orange)

            ForEach(identityManager.health.issues, id: \.self) { issue in
              Text("• \(issue.description)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          .padding(.vertical, 4)
        }

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
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      checkAllPermissions()
    }
  }

  // MARK: - Permission Row Component

  @ViewBuilder
  private func permissionRow(
    icon: String,
    name: String,
    description: String,
    statusLabel: String,
    statusIcon: String,
    statusColor: Color,
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
        Image(systemName: statusIcon)
          .foregroundColor(statusColor)
        Text(statusLabel)
          .font(.caption)
          .foregroundColor(statusColor)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(statusColor.opacity(0.1))
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
    checkSaveFolderPermission()

    Task {
      await checkScreenRecordingPermission()
      await MainActor.run {
        isChecking = false
      }
    }
  }

  private func checkScreenRecordingPermission() async {
    AppIdentityManager.shared.refresh()
    await screenCaptureManager.checkPermission()
  }

  private func checkMicrophonePermission() {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    microphoneGranted = (status == .authorized)
  }

  private func checkAccessibilityPermission() {
    accessibilityGranted = AXIsProcessTrusted()
  }

  private func checkSaveFolderPermission() {
    fileAccessManager.ensureExportLocationInitialized()
    saveFolderGranted = fileAccessManager.hasPersistedExportPermission
  }

  private var screenRecordingDescription: String {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return "Required for screenshots and recordings"
    case .notGranted:
      return "Required for screenshots and recordings"
    case .grantedButUnavailableDueToAppIdentity:
      return "macOS granted the permission, but this build identity is still blocking capture."
    }
  }

  private var screenRecordingStatusLabel: String {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return "Granted"
    case .notGranted:
      return "Not Granted"
    case .grantedButUnavailableDueToAppIdentity:
      return "Unavailable"
    }
  }

  private var screenRecordingStatusIcon: String {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return "checkmark.circle.fill"
    case .notGranted:
      return "xmark.circle.fill"
    case .grantedButUnavailableDueToAppIdentity:
      return "exclamationmark.triangle.fill"
    }
  }

  private var screenRecordingStatusColor: Color {
    switch screenCaptureManager.permissionStatus {
    case .granted:
      return .green
    case .notGranted, .grantedButUnavailableDueToAppIdentity:
      return .orange
    }
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
