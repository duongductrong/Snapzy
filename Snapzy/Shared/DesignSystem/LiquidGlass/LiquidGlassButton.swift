//
//  LiquidGlassButton.swift
//  Snapzy
//
//  Liquid Glass button styles and action buttons with tactile spring feedback and keycaps.
//

import SwiftUI

enum LiquidGlassActionEmphasis: Equatable, Sendable {
  case primary
  case secondary
  case destructive
  case contextPill
}

// MARK: - Button Style

struct LiquidGlassButtonStyle: ButtonStyle {
  var emphasis: LiquidGlassActionEmphasis = .secondary
  var capsule: Bool = false
  var isActive: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    // Hover state lives in a nested View rather than on the style itself: a ButtonStyle is a
    // value re-created on every evaluation, so @State here is not reliably scoped per button.
    LiquidGlassButtonSurface(
      configuration: configuration,
      emphasis: emphasis,
      capsule: capsule,
      isActive: isActive
    )
  }
}

// MARK: - Action Button

struct LiquidGlassActionButton: View {
  var title: String
  var icon: String? = nil
  var trailingKey: String? = nil
  var emphasis: LiquidGlassActionEmphasis = .secondary
  var capsule: Bool = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let icon {
          Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
        }
        Text(title)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        if let trailingKey {
          Text(trailingKey)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(LiquidGlassTokens.veilFill.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
        }
      }
    }
    .buttonStyle(LiquidGlassButtonStyle(emphasis: emphasis, capsule: capsule))
  }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
  static func liquidGlass(
    emphasis: LiquidGlassActionEmphasis = .secondary,
    capsule: Bool = false,
    isActive: Bool = false
  ) -> LiquidGlassButtonStyle {
    LiquidGlassButtonStyle(emphasis: emphasis, capsule: capsule, isActive: isActive)
  }
}
