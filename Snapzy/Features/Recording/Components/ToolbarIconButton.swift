//
//  ToolbarIconButton.swift
//  Snapzy
//
//  Reusable icon button for the recording toolbar with hover state
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
        .foregroundColor(.primary)
        .frame(
          width: ToolbarConstants.iconButtonSize,
          height: ToolbarConstants.iconButtonSize
        )
        .background(
          RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
            .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
        )
        .animation(ToolbarConstants.hoverAnimation, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Double-tap to activate")
  }
}

#Preview {
  HStack(spacing: 16) {
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
  .padding()
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
