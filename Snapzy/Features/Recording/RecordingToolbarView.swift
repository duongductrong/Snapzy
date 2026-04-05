//
//  RecordingToolbarView.swift
//  Snapzy
//
//  Pre-record toolbar with options menu and record/cancel buttons
//  Styled to match Apple's native macOS recording toolbar aesthetic
//
//  Layout: [✕] | [📷] | [□ □] | [🎙] | [Options▾] [Record]
//

import SwiftUI

struct RecordingToolbarView: View {
  @ObservedObject var state: RecordingToolbarState
  let onRecord: () -> Void
  let onCapture: () -> Void
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: ToolbarConstants.itemSpacing) {
      // Close button
      ToolbarIconButton(
        systemName: "xmark",
        action: onCancel,
        accessibilityLabel: "Cancel recording"
      )

      RecordingToolbarDivider()

      // Capture screenshot button
      ToolbarIconButton(
        systemName: "camera",
        action: onCapture,
        accessibilityLabel: "Capture screenshot"
      )

      RecordingToolbarDivider()

      // Capture mode toggle (fullscreen / area)
      ToolbarCaptureAreaToggle(state: state)

      RecordingToolbarDivider()

      // Mic toggle button
      ToolbarMicToggleButton(state: state)

      RecordingToolbarDivider()

      // Options menu (text button with chevron)
      ToolbarOptionsMenu(state: state)

      // Record button group: [Record <badge>] [▼]
      HStack(spacing: 1) {
        RecordButtonWithBadge(state: state, onRecord: onRecord)

        ToolbarOutputModeDropdown(state: state)
      }
      .fixedSize()
    }
    .padding(.horizontal, ToolbarConstants.horizontalPadding)
    .padding(.vertical, ToolbarConstants.verticalPadding)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Recording toolbar")
  }
}

#Preview {
  RecordingToolbarView(
    state: RecordingToolbarState(),
    onRecord: {},
    onCapture: {},
    onCancel: {}
  )
  .padding()
}
