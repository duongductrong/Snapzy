//
//  VSDesignSystem.swift
//  Snapzy
//
//  Design system for onboarding views — adaptive dark/light theme for opaque surface
//

import AppKit
import SwiftUI

struct VSDesignSystem {

  // MARK: - Adaptive Colors

  /// Semantic color tokens that adapt to dark/light mode.
  /// Tuned for an opaque window surface — text and controls stay readable
  /// regardless of the user's desktop wallpaper.
  struct Colors {
    /// Headings, titles, prominent icon tints
    static let primary = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { $0.bestMatch(from: [.darkAqua]) == .darkAqua ? .white : .black }
    ))

    /// Body copy, subtitles
    static let secondary = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.85)
          : NSColor.black.withAlphaComponent(0.7)
      }
    ))

    /// Descriptions, supporting text
    static let tertiary = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.65)
          : NSColor.black.withAlphaComponent(0.5)
      }
    ))

    /// Footnotes, dim labels, "Press Enter" hints
    static let quaternary = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.5)
          : NSColor.black.withAlphaComponent(0.35)
      }
    ))

    /// Card / row background fill
    static let cardFill = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.08)
          : NSColor.black.withAlphaComponent(0.04)
      }
    ))

    /// Card / row border stroke
    static let cardStroke = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.14)
          : NSColor.black.withAlphaComponent(0.1)
      }
    ))

    /// Subtle divider
    static let divider = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.12)
          : NSColor.black.withAlphaComponent(0.1)
      }
    ))

    /// Primary button fill
    static let buttonFill = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.25)
          : NSColor.black.withAlphaComponent(0.1)
      }
    ))

    /// Primary button stroke
    static let buttonStroke = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.35)
          : NSColor.black.withAlphaComponent(0.2)
      }
    ))

    /// Secondary / disabled button fill
    static let secondaryButtonFill = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.12)
          : NSColor.black.withAlphaComponent(0.06)
      }
    ))

    /// Secondary button stroke
    static let secondaryButtonStroke = Color(nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.22)
          : NSColor.black.withAlphaComponent(0.15)
      }
    ))
  }

  // MARK: - Typography

  struct Typography {
    static let heading = Font.system(size: 24, weight: .bold)
    static let body = Font.system(size: 13)
    static let bodyColor = Colors.secondary
  }

  // MARK: - Primary Button Style

  struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Colors.primary)
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
          Capsule()
            .fill(isDisabled ? Colors.secondaryButtonFill : Colors.buttonFill)
        )
        .overlay(Capsule().stroke(Colors.buttonStroke, lineWidth: 1))
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
  }

  // MARK: - Secondary Button Style

  struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(Colors.secondary)
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
          Capsule()
            .fill(Colors.secondaryButtonFill)
        )
        .overlay(Capsule().stroke(Colors.secondaryButtonStroke, lineWidth: 1))
        .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
  }

  // MARK: - Success Button Style

  struct SuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Colors.primary)
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
      .foregroundColor(VSDesignSystem.Colors.primary)
  }

  func vsBody() -> some View {
    self
      .font(VSDesignSystem.Typography.body)
      .foregroundColor(VSDesignSystem.Typography.bodyColor)
  }
}
