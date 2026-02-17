//
//  VSDesignSystem.swift
//  Snapzy
//
//  Design system for onboarding views — dark/frosted theme for splash overlay
//

import SwiftUI

struct VSDesignSystem {

  // MARK: - Typography

  struct Typography {
    static let heading = Font.system(size: 24, weight: .bold)
    static let body = Font.system(size: 13)
    static let bodyColor = Color.white.opacity(0.7)
  }

  // MARK: - Primary Button Style

  struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
          Capsule()
            .fill(isDisabled ? Color.white.opacity(0.1) : Color.white.opacity(0.2))
        )
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
  }

  // MARK: - Secondary Button Style

  struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.white.opacity(0.8))
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
          Capsule()
            .fill(Color.white.opacity(0.1))
        )
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
        .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
  }

  // MARK: - Success Button Style

  struct SuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
          Capsule()
            .fill(Color.green.opacity(0.3))
        )
        .overlay(Capsule().stroke(.green.opacity(0.5), lineWidth: 1))
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
  }
}

// MARK: - Convenience Extensions

extension View {
  func vsHeading() -> some View {
    self
      .font(VSDesignSystem.Typography.heading)
      .foregroundColor(.white)
  }

  func vsBody() -> some View {
    self
      .font(VSDesignSystem.Typography.body)
      .foregroundColor(VSDesignSystem.Typography.bodyColor)
  }
}
