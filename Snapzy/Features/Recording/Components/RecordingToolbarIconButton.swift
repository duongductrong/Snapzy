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
      ToolbarIconButtonLabel(systemName: systemName, isHovered: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityLabel(accessibilityLabel)
  }
}

#Preview {
  HStack(spacing: 4) {
    ToolbarIconButton(
      systemName: "xmark",
      action: {},
      accessibilityLabel: L10n.Common.close
    )
    ToolbarIconButton(
      systemName: "gearshape",
      action: {},
      accessibilityLabel: L10n.Common.preferences
    )
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(Radius.rect(Radius.card))
}
