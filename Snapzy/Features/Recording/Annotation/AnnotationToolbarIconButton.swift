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
        .foregroundColor(isSelected ? .accentColor : .primary.opacity(isHovered ? 1.0 : 0.85))
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .animation(ToolbarConstants.hoverAnimation, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }

  private var backgroundColor: Color {
    if isSelected {
      return Color.accentColor.opacity(0.2)
    } else if isHovered {
      return Color.primary.opacity(0.1)
    }
    return .clear
  }
}
