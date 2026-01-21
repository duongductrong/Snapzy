//
//  VideoEditorMainView.swift
//  ClaudeShot
//
//  Main container view for video editor
//

import SwiftUI

/// Main view for video editor containing player, timeline, controls, and info
struct VideoEditorMainView: View {
  @ObservedObject var state: VideoEditorState
  var onSave: (() -> Void)?
  var onSaveAs: (() -> Void)?
  var onCancel: (() -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      // Video player
      VideoPlayerSection(player: state.player)
        .frame(minHeight: 200)

      // Timeline with frame previews and trim handles
      VideoTimelineView(state: state)
        .padding(.horizontal, 16)
        .padding(.top, 12)

      // Playback controls
      VideoControlsView(state: state)
        .padding(.horizontal, 16)
        .padding(.top, 8)

      // Info panel
      VideoInfoPanel(state: state)
        .padding(.horizontal, 16)
        .padding(.top, 12)

      Spacer(minLength: 0)

      // Divider
      Divider()

      // Footer actions
      VideoEditorActionsView(
        state: state,
        onSave: { onSave?() },
        onSaveAs: { onSaveAs?() },
        onCancel: { onCancel?() }
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(NSColor.windowBackgroundColor))
    .task {
      await state.loadMetadata()
      await state.extractFrames()
    }
  }
}
