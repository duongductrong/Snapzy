//
//  VSDesignSystem.swift
//  ZapShot
//
//  Design system for onboarding views
//

import SwiftUI

struct VSDesignSystem {

  // MARK: - Typography

  struct Typography {
    static let heading = Font.system(size: 24, weight: .bold)
    static let body = Font.system(size: 13)
    static let bodyColor = Color.secondary
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
          RoundedRectangle(cornerRadius: 10)
            .fill(isDisabled ? Color.blue.opacity(0.5) : Color.blue)
        )
        .opacity(configuration.isPressed ? 0.8 : 1.0)
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
  }

  // MARK: - Secondary Button Style

  struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.primary)
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.2))
        )
        .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
  }
}

// MARK: - Convenience Extensions

extension View {
  func vsHeading() -> some View {
    self.font(VSDesignSystem.Typography.heading)
  }

  func vsBody() -> some View {
    self
      .font(VSDesignSystem.Typography.body)
      .foregroundColor(VSDesignSystem.Typography.bodyColor)
  }
}
