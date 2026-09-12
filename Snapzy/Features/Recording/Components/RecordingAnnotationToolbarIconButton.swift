//
//  AnnotationToolbarIconButton.swift
//  Snapzy
//
//  Reusable icon button for the recording annotation toolbar
//  Styled to match existing recording toolbar aesthetic
//

import SwiftUI

struct AnnotationToolbarIconButton: View {
  let systemName: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .medium))
        // Selected chrome is accent-tinted glass, so its glyph resolves against the tint instead
        // of the app appearance; hovered chrome is untinted and keeps the label colour.
        .foregroundColor(
          isSelected
            ? LiquidGlassTokens.inkOnAccent
            : .primary.opacity(isHovered ? 1.0 : 0.85)
        )
        .frame(width: 28, height: 28)
        .liquidGlassChrome(
          shape: ToolbarConstants.buttonShape,
          isVisible: isSelected || isHovered,
          isActive: isSelected,
          glassTint: isSelected ? .accentColor : nil
        )
        .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
        .animation(LiquidGlassTokens.hoverSpring, value: isSelected)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering }
    }
  }
}
