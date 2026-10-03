//
//  ToolbarSystemAudioToggleButton.swift
//  Snapzy
//
//  System audio quick toggle for the recording toolbar
//  Styled to match Apple's native macOS recording toolbar
//

import SwiftUI

struct ToolbarSystemAudioToggleButton: View {
  @ObservedObject var state: RecordingToolbarState
  @State private var isHovered = false

  private let speakerIconSize = ToolbarConstants.iconSize - 1

  private var systemName: String {
    state.captureAudio ? "speaker.wave.2.fill" : "speaker.slash.fill"
  }

  private var statusText: String {
    state.captureAudio ? L10n.Common.on : L10n.Common.off
  }

  private var helpText: String {
    "\(L10n.RecordingToolbar.systemAudio): \(statusText)"
  }

  var body: some View {
    Button {
      state.captureAudio.toggle()
    } label: {
      ToolbarIconButtonLabel(
        systemName: systemName,
        iconSize: speakerIconSize,
        isHovered: isHovered
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(helpText)
    .accessibilityLabel(L10n.RecordingToolbar.systemAudio)
    .accessibilityValue(statusText)
  }
}

#Preview {
  HStack(spacing: 4) {
    ToolbarSystemAudioToggleButton(state: RecordingToolbarState())
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(Radius.rect(Radius.card))
}
