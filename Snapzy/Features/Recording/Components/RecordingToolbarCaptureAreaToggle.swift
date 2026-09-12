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
  case application
}

struct ToolbarCaptureAreaToggle: View {
  @ObservedObject var state: RecordingToolbarState
  @State private var isAreaHovered = false
  @State private var isFullscreenHovered = false
  @State private var isApplicationHovered = false

  private func isSelected(_ mode: RecordingCaptureMode) -> Bool {
    state.captureMode == mode
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
          .foregroundColor(.primary.opacity(isSelected(.fullscreen) ? 1.0 : 0.5))
          .frame(
            width: ToolbarConstants.iconButtonSize,
            height: ToolbarConstants.iconButtonSize
          )
          .liquidGlassChrome(shape: ToolbarConstants.buttonShape, isVisible: isFullscreenHovered)
          .animation(LiquidGlassTokens.hoverSpring, value: isFullscreenHovered)
      }
      .buttonStyle(.plain)
      .onHover { isFullscreenHovered = $0 }
      .help(L10n.RecordingToolbar.fullscreenCapture)
      .accessibilityLabel(L10n.RecordingToolbar.fullscreenCapture)
      .accessibilityAddTraits(isSelected(.fullscreen) ? .isSelected : [])

      // Area selection button
      Button {
        state.captureMode = .area
        state.onCaptureModeChanged?(.area)
      } label: {
        Image(systemName: "rectangle.dashed")
          .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
          .foregroundColor(.primary.opacity(isSelected(.area) ? 1.0 : 0.5))
          .frame(
            width: ToolbarConstants.iconButtonSize,
            height: ToolbarConstants.iconButtonSize
          )
          .liquidGlassChrome(shape: ToolbarConstants.buttonShape, isVisible: isAreaHovered)
          .animation(LiquidGlassTokens.hoverSpring, value: isAreaHovered)
      }
      .buttonStyle(.plain)
      .onHover { isAreaHovered = $0 }
      .help(L10n.RecordingToolbar.areaSelection)
      .accessibilityLabel(L10n.RecordingToolbar.areaSelectionCapture)
      .accessibilityAddTraits(isSelected(.area) ? .isSelected : [])

      // Application window button
      Button {
        state.captureMode = .application
        state.onCaptureModeChanged?(.application)
      } label: {
        Image(systemName: "square.on.square")
          .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
          .foregroundColor(.primary.opacity(isSelected(.application) ? 1.0 : 0.5))
          .frame(
            width: ToolbarConstants.iconButtonSize,
            height: ToolbarConstants.iconButtonSize
          )
          .liquidGlassChrome(shape: ToolbarConstants.buttonShape, isVisible: isApplicationHovered)
          .animation(LiquidGlassTokens.hoverSpring, value: isApplicationHovered)
      }
      .buttonStyle(.plain)
      .onHover { isApplicationHovered = $0 }
      .help(L10n.PreferencesShortcuts.applicationRecordingTitle)
      .accessibilityLabel(L10n.PreferencesShortcuts.applicationRecordingTitle)
      .accessibilityAddTraits(isSelected(.application) ? .isSelected : [])
    }
  }
}

#Preview {
  HStack(spacing: 4) {
    ToolbarCaptureAreaToggle(state: RecordingToolbarState())
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(Radius.rect(Radius.card))
}
