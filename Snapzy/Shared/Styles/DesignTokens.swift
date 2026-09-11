//
//  DesignTokens.swift
//  Snapzy
//
//  Centralized design tokens for consistent UI across the app.
//  Based on 8pt grid system.
//

import SwiftUI

// MARK: - Spacing (8pt Grid)

enum Spacing {
  static let xs: CGFloat = 4    // Tight spacing (icons, compact lists)
  static let sm: CGFloat = 8    // Standard gap
  static let md: CGFloat = 16   // Section padding
  static let lg: CGFloat = 24   // Large gaps
  static let xl: CGFloat = 32   // Major sections
}

// MARK: - Sizing

enum Size {
  // Grid items (backgrounds, wallpapers, gradients)
  static let gridItem: CGFloat = 48
  static let gridItemSmall: CGFloat = 40

  // Color swatches
  static let colorSwatch: CGFloat = 32
  static let colorSwatchSmall: CGFloat = 24

  // Corner radii
  static let radiusXs: CGFloat = 4
  static let radiusSm: CGFloat = 6
  static let radiusMd: CGFloat = 8
  static let radiusLg: CGFloat = 12

  // Strokes
  static let strokeDefault: CGFloat = 1
  static let strokeSelected: CGFloat = 2
}

// MARK: - Typography

enum Typography {
  static let labelSmall: Font = .system(size: 10)
  static let labelMedium: Font = .system(size: 11, weight: .medium)
  static let sectionHeader: Font = .system(size: 11, weight: .semibold)
  static let body: Font = .system(size: 12)
}

// MARK: - Colors (Semantic)

enum SidebarColors {
  // Backgrounds
  static let itemDefault = Color.primary.opacity(0.05)
  static let itemHover = Color.primary.opacity(0.10)
  static let itemSelected = Color.accentColor.opacity(0.15)

  // Borders
  static let borderDefault = Color.secondary.opacity(0.3)
  static let borderHover = Color.secondary.opacity(0.5)
  static let borderSelected = Color.accentColor

  // Text
  static let labelPrimary = Color.primary
  static let labelSecondary = Color.secondary
  static let labelTertiary = Color.secondary.opacity(0.7)

  // Actions
  static let actionButton = Color.primary.opacity(0.08)
  static let actionButtonHover = Color.primary.opacity(0.15)
}

// MARK: - Grid Configuration

enum GridConfig {
  static let backgroundColumns = 6
  static let colorColumns = 8
  static let gap = Spacing.sm
}

// MARK: - Sidebar Item Style Modifier

struct SidebarItemStyle: ViewModifier {
  let isSelected: Bool
  let cornerRadius: CGFloat

  @State private var isHovering = false

  init(isSelected: Bool, cornerRadius: CGFloat = Size.radiusMd) {
    self.isSelected = isSelected
    self.cornerRadius = cornerRadius
  }

  func body(content: Content) -> some View {
    content
      .aspectRatio(1, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(isHovering && !isSelected ? SidebarColors.itemHover.opacity(0.35) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(borderColor, lineWidth: Size.strokeSelected)
      )
      .onHover { isHovering = $0 }
  }

  private var borderColor: Color {
    if isSelected { return SidebarColors.borderSelected }
    if isHovering { return SidebarColors.borderHover }
    return .clear
  }

}

// MARK: - Color Swatch Style Modifier

struct ColorSwatchStyle: ViewModifier {
  let isSelected: Bool

  @State private var isHovering = false

  init(isSelected: Bool) {
    self.isSelected = isSelected
  }

  func body(content: Content) -> some View {
    content
      .aspectRatio(1, contentMode: .fit)
      .clipShape(Circle())
      .overlay(
        Circle()
          .stroke(borderColor, lineWidth: borderWidth)
      )
      .scaleEffect(isHovering && !isSelected ? 1.1 : 1.0)
      .animation(.easeInOut(duration: 0.15), value: isHovering)
      .onHover { isHovering = $0 }
  }

  private var borderColor: Color {
    if isSelected { return SidebarColors.borderSelected }
    if isHovering { return SidebarColors.borderHover }
    return Color.secondary.opacity(0.3)
  }

  private var borderWidth: CGFloat {
    isSelected ? Size.strokeSelected : Size.strokeDefault
  }
}

// MARK: - Action Button Style (for + buttons)

struct ActionButtonStyle: ViewModifier {
  let cornerRadius: CGFloat

  @State private var isHovering = false

  init(cornerRadius: CGFloat = Size.radiusMd) {
    self.cornerRadius = cornerRadius
  }

  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(isHovering ? SidebarColors.actionButtonHover : SidebarColors.actionButton)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
          .foregroundColor(isHovering ? .primary.opacity(0.5) : .primary.opacity(0.3))
      )
      .onHover { isHovering = $0 }
  }
}

// MARK: - View Extensions

extension View {
  func sidebarItemStyle(isSelected: Bool, cornerRadius: CGFloat = Size.radiusMd) -> some View {
    modifier(SidebarItemStyle(isSelected: isSelected, cornerRadius: cornerRadius))
  }

  func colorSwatchStyle(isSelected: Bool) -> some View {
    modifier(ColorSwatchStyle(isSelected: isSelected))
  }

  func actionButtonStyle(cornerRadius: CGFloat = Size.radiusMd) -> some View {
    modifier(ActionButtonStyle(cornerRadius: cornerRadius))
  }
}
