//
//  PermissionRow.swift
//  ZapShot
//
//  Reusable permission row component for onboarding
//

import SwiftUI

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
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
        Text(title)
          .font(.system(size: 14, weight: .semibold))

        Text(description)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Status
      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 24))
          .foregroundColor(.green)
      } else {
        Button("Grant Access") {
          onGrant()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
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
      description: "Required to capture screenshots",
      isGranted: false,
      onGrant: {}
    )
    PermissionRow(
      icon: "rectangle.dashed.badge.record",
      title: "Screen Recording",
      description: "Required to capture screenshots",
      isGranted: true,
      onGrant: {}
    )
  }
  .padding()
  .frame(width: 450)
}
