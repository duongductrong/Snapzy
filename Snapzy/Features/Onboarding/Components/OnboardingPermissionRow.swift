//
//  PermissionRow.swift
//  Snapzy
//
//  Reusable permission row component for onboarding — adaptive dark/light theme
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
        .foregroundColor(VSDesignSystem.Colors.primary)
        .frame(width: 44, height: 44)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(VSDesignSystem.Colors.secondaryButtonFill)
        )

      // Title and Description
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(VSDesignSystem.Colors.primary)

          if isRequired {
            Text("Required")
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.3))
              .foregroundColor(.orange)
              .cornerRadius(4)
          } else {
            Text("Optional")
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(VSDesignSystem.Colors.secondaryButtonFill)
              .foregroundColor(VSDesignSystem.Colors.tertiary)
              .cornerRadius(4)
          }
        }

        Text(description)
          .font(.system(size: 12))
          .foregroundColor(VSDesignSystem.Colors.tertiary)
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
        .background(Color.green.opacity(0.15))
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
        .fill(VSDesignSystem.Colors.cardFill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(VSDesignSystem.Colors.cardStroke, lineWidth: 1)
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
  .background(.black.opacity(0.5))
}
