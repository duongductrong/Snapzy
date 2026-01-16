//
//  PermissionsView.swift
//  ZapShot
//
//  Permissions grant screen for onboarding flow
//

import SwiftUI

struct PermissionsView: View {
  @ObservedObject var screenCaptureManager: ScreenCaptureManager
  let onQuit: () -> Void
  let onNext: () -> Void

  private var allPermissionsGranted: Bool {
    screenCaptureManager.hasPermission
  }

  var body: some View {
    VStack(spacing: 24) {
      // Header
      VStack(spacing: 12) {
        Image(systemName: "lock.shield")
          .font(.system(size: 48))
          .foregroundColor(.blue)

        Text("Grant Permissions")
          .vsHeading()

        Text("ZapShot needs access to screen recording to capture your screen.")
          .vsBody()
          .multilineTextAlignment(.center)
          .frame(maxWidth: 320)
      }

      Spacer()
        .frame(height: 20)

      // Permission Rows
      VStack(spacing: 12) {
        PermissionRow(
          icon: "rectangle.dashed.badge.record",
          title: "Screen Recording",
          description: "Required to capture screenshots",
          isGranted: screenCaptureManager.hasPermission,
          onGrant: {
            Task {
              await screenCaptureManager.requestPermission()
            }
          }
        )
      }
      .frame(maxWidth: 400)

      Spacer()

      // Bottom Navigation
      HStack {
        Button("Quit") {
          onQuit()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Spacer()

        Button("Next") {
          onNext()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle(isDisabled: !allPermissionsGranted))
        .disabled(!allPermissionsGranted)
      }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      await screenCaptureManager.checkPermission()
    }
  }
}

#Preview {
  PermissionsView(
    screenCaptureManager: ScreenCaptureManager.shared,
    onQuit: {},
    onNext: {}
  )
  .frame(width: 500, height: 450)
}
