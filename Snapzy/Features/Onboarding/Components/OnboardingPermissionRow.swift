//
//  PermissionRow.swift
//  Snapzy
//
//  Reusable permission row component for onboarding — adaptive dark/light theme
//

import SwiftUI

enum PermissionRowStatus {
  case granted
  case needsAction(buttonTitle: String)
  case blocked(label: String, buttonTitle: String)
}

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let status: PermissionRowStatus
  var isRequired: Bool = true
  let onGrant: () -> Void

  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

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
            Text(requiredLabel)
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.3))
              .foregroundColor(.orange)
              .cornerRadius(4)
          } else {
            Text(optionalLabel)
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

      VStack(alignment: .trailing, spacing: 8) {
        if let badge = badge {
          HStack(spacing: 4) {
            Image(systemName: badge.icon)
              .font(.system(size: 16))
              .foregroundColor(badge.color)
            Text(badge.label)
              .font(.caption)
              .foregroundColor(badge.color)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(badge.color.opacity(0.15))
          .cornerRadius(6)
        }

        if let buttonTitle = actionTitle {
          Button(buttonTitle) {
            onGrant()
          }
          .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
          .controlSize(.small)
        }
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

  private var badge: (label: String, color: Color, icon: String)? {
    switch status {
    case .granted:
      return (grantedLabel, .green, "checkmark.circle.fill")
    case .needsAction:
      return nil
    case .blocked(let label, _):
      return (label, .orange, "exclamationmark.triangle.fill")
    }
  }

  private var actionTitle: String? {
    switch status {
    case .granted:
      return nil
    case .needsAction(let buttonTitle), .blocked(_, let buttonTitle):
      return buttonTitle
    }
  }

  private var requiredLabel: String {
    onboardingLocalization.string(
      "permission-row.required",
      defaultValue: "Required",
      comment: "Badge label shown on required permission rows"
    )
  }

  private var optionalLabel: String {
    onboardingLocalization.string(
      "permission-row.optional",
      defaultValue: "Optional",
      comment: "Badge label shown on optional permission rows"
    )
  }

  private var grantedLabel: String {
    onboardingLocalization.string(
      "permission-row.granted",
      defaultValue: "Granted",
      comment: "Badge label shown when a permission has been granted"
    )
  }
}

#Preview {
  VStack(spacing: 12) {
    PermissionRow(
      icon: "rectangle.dashed.badge.record",
      title: "Screen Recording",
      description: "Required for screenshots",
      status: .needsAction(buttonTitle: "Grant Access"),
      isRequired: true,
      onGrant: {}
    )
    PermissionRow(
      icon: "mic.fill",
      title: "Microphone",
      description: "Optional for voice recording",
      status: .granted,
      isRequired: false,
      onGrant: {}
    )
  }
  .padding()
  .frame(width: 450)
  .background(OnboardingSurfaceBackground())
}
