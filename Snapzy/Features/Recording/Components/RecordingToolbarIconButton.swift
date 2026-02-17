//
//  ToolbarIconButton.swift
//  Snapzy
//
//  Reusable icon button for the recording toolbar with hover state
//  Styled to match Apple's native macOS recording toolbar
//

import SwiftUI

struct ToolbarIconButton: View {
  let systemName: String
  let action: () -> Void
  let accessibilityLabel: String

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
        .foregroundColor(.primary.opacity(isHovered ? 1.0 : 0.85))
        .frame(
          width: ToolbarConstants.iconButtonSize,
          height: ToolbarConstants.iconButtonSize
        )
        .background(
          RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
            .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
        .animation(ToolbarConstants.hoverAnimation, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Double-tap to activate")
  }
}

#Preview {
  HStack(spacing: 4) {
    ToolbarIconButton(
      systemName: "xmark",
      action: {},
      accessibilityLabel: "Close"
    )
    ToolbarIconButton(
      systemName: "gearshape",
      action: {},
      accessibilityLabel: "Settings"
    )
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
