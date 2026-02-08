//
//  RecordingToolbarView.swift
//  Snapzy
//
//  Pre-record toolbar with options menu and record/cancel buttons
//  Styled to match Apple's native macOS recording toolbar aesthetic
//
//  Layout: [✕] | [□ □] | [🎙] | [Options▾] [Record]
//

import SwiftUI

struct RecordingToolbarView: View {
  @ObservedObject var state: RecordingToolbarState
  let onRecord: () -> Void
  let onCancel: () -> Void

  @State private var isRecordHovered = false

  var body: some View {
    HStack(spacing: ToolbarConstants.itemSpacing) {
      // Close button
      ToolbarIconButton(
        systemName: "xmark",
        action: onCancel,
        accessibilityLabel: "Cancel recording"
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

      // Record button (native text style)
      Button(action: onRecord) {
        Text("Record")
      }
      .buttonStyle(RecordButtonStyle())
      .onHover { isRecordHovered = $0 }
      .fixedSize()
      .accessibilityLabel("Start recording")
      .accessibilityHint("Begins screen recording with current settings")
    }
    .padding(.horizontal, ToolbarConstants.horizontalPadding)
    .padding(.vertical, ToolbarConstants.verticalPadding)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: ToolbarConstants.toolbarCornerRadius))
    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Recording toolbar")
  }
}

#Preview {
  RecordingToolbarView(
    state: RecordingToolbarState(),
    onRecord: {},
    onCancel: {}
  )
  .padding()
}
