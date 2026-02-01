//
//  ToolbarCaptureAreaToggle.swift
//  Snapzy
//
//  Toggle button for switching between area selection and fullscreen capture
//

import SwiftUI

enum RecordingCaptureMode: String {
  case area
  case fullscreen
}

struct ToolbarCaptureAreaToggle: View {
  @Binding var captureMode: RecordingCaptureMode
  @State private var isHovered = false

  private var isFullscreen: Bool {
    captureMode == .fullscreen
  }

  private var systemName: String {
    isFullscreen ? "rectangle.inset.filled" : "rectangle.dashed"
  }

  private var accessibilityLabel: String {
    isFullscreen ? "Switch to area selection" : "Switch to fullscreen capture"
  }

  private var tooltipText: String {
    isFullscreen ? "Fullscreen" : "Area selection"
  }

  var body: some View {
    Button {
      captureMode = isFullscreen ? .area : .fullscreen
    } label: {
      Image(systemName: systemName)
        .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
        .foregroundColor(foregroundColor)
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
    .help(tooltipText)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Double-tap to toggle")
  }

  private var foregroundColor: Color {
    isFullscreen ? .primary : .secondary
  }
}

#Preview {
  HStack(spacing: 16) {
    ToolbarCaptureAreaToggle(captureMode: .constant(.area))
    ToolbarCaptureAreaToggle(captureMode: .constant(.fullscreen))
  }
  .padding()
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
