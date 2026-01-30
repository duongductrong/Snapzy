//
//  PermissionRow.swift
//  Snapzy
//
//  Reusable permission row component for onboarding
//

import SwiftUI

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
  var isRequired: Bool = true
  let onGrant: () -> Void

  var body: some View {
    HStack(spacing: 16) {
      // Icon
      Image(systemName: icon)
        .font(.system(size: 24))
        .foregroundColor(.blue)
        .frame(width: 44, height: 44)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.blue.opacity(0.1))
        )

      // Title and Description
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))

          if isRequired {
            Text("Required")
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.2))
              .foregroundColor(.orange)
              .cornerRadius(4)
          } else {
            Text("Optional")
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.gray.opacity(0.2))
              .foregroundColor(.secondary)
              .cornerRadius(4)
          }
        }

        Text(description)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Status
      if isGranted {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundColor(.green)
          Text("Granted")
            .font(.caption)
            .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
      } else {
        Button("Grant Access") {
          onGrant()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
        .controlSize(.small)
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.gray.opacity(0.05))
    )
  }
}

#Preview {
  VStack(spacing: 12) {
    PermissionRow(
      icon: "rectangle.dashed.badge.record",
      title: "Screen Recording",
      description: "Required for screenshots",
      isGranted: false,
      isRequired: true,
      onGrant: {}
    )
    PermissionRow(
      icon: "mic.fill",
      title: "Microphone",
      description: "Optional for voice recording",
      isGranted: true,
      isRequired: false,
      onGrant: {}
    )
  }
  .padding()
  .frame(width: 450)
}
