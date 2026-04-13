//
//  ToolbarCaptureAreaToggle.swift
//  Snapzy
//
//  Toggle button for switching between area selection and fullscreen capture
//  Styled to match Apple's native macOS recording toolbar
//

import SwiftUI

enum RecordingCaptureMode: String {
  case area
  case fullscreen
}

struct ToolbarCaptureAreaToggle: View {
  @ObservedObject var state: RecordingToolbarState
  @State private var isAreaHovered = false
  @State private var isFullscreenHovered = false

  private var isFullscreen: Bool {
    state.captureMode == .fullscreen
  }

  var body: some View {
    HStack(spacing: ToolbarConstants.groupSpacing) {
      // Fullscreen capture button
      Button {
        state.captureMode = .fullscreen
        state.onCaptureModeChanged?(.fullscreen)
      } label: {
        Image(systemName: "rectangle.inset.filled")
          .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
          .foregroundColor(.primary.opacity(isFullscreen ? 1.0 : 0.5))
          .frame(
            width: ToolbarConstants.iconButtonSize,
            height: ToolbarConstants.iconButtonSize
          )
          .background(
            RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
              .fill(Color.primary.opacity(isFullscreenHovered ? 0.1 : 0))
          )
          .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
          .animation(ToolbarConstants.hoverAnimation, value: isFullscreenHovered)
      }
      .buttonStyle(.plain)
      .onHover { isFullscreenHovered = $0 }
      .help(L10n.RecordingToolbar.fullscreenCapture)
      .accessibilityLabel(L10n.RecordingToolbar.fullscreenCapture)
      .accessibilityAddTraits(isFullscreen ? .isSelected : [])

      // Area selection button
      Button {
        state.captureMode = .area
        state.onCaptureModeChanged?(.area)
      } label: {
        Image(systemName: "rectangle.dashed")
          .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
          .foregroundColor(.primary.opacity(!isFullscreen ? 1.0 : 0.5))
          .frame(
            width: ToolbarConstants.iconButtonSize,
            height: ToolbarConstants.iconButtonSize
          )
          .background(
            RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
              .fill(Color.primary.opacity(isAreaHovered ? 0.1 : 0))
          )
          .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
          .animation(ToolbarConstants.hoverAnimation, value: isAreaHovered)
      }
      .buttonStyle(.plain)
      .onHover { isAreaHovered = $0 }
      .help(L10n.RecordingToolbar.areaSelection)
      .accessibilityLabel(L10n.RecordingToolbar.areaSelectionCapture)
      .accessibilityAddTraits(!isFullscreen ? .isSelected : [])
    }
  }
}

#Preview {
  HStack(spacing: 4) {
    ToolbarCaptureAreaToggle(state: RecordingToolbarState())
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
