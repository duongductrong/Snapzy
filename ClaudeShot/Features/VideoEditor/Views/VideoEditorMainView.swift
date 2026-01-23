//
//  VideoEditorMainView.swift
//  ClaudeShot
//
//  Main container view for video editor
//

import AVFoundation
import SwiftUI

/// Main view for video editor containing player, timeline, controls, and info
struct VideoEditorMainView: View {
  @ObservedObject var state: VideoEditorState
  var onSave: (() -> Void)?
  var onSaveAs: (() -> Void)?
  var onCancel: (() -> Void)?

  // Computed property for current frame preview
  private var currentFrameImage: NSImage? {
    guard !state.frameThumbnails.isEmpty else { return nil }
    let duration = CMTimeGetSeconds(state.duration)
    guard duration > 0 else { return nil }
    let progress = CMTimeGetSeconds(state.currentTime) / duration
    let index = Int(progress * Double(state.frameThumbnails.count - 1))
    let clampedIndex = max(0, min(index, state.frameThumbnails.count - 1))
    return state.frameThumbnails[clampedIndex]
  }

  var body: some View {
    HStack(spacing: 0) {
      // Main editor content
      VStack(spacing: 0) {
        // Add safe area spacer for traffic lights
        Color.clear
          .frame(height: 28) // Standard macOS title bar height

        // Video player with zoom preview
        ZoomableVideoPlayerSection(state: state)
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

      // Zoom settings sidebar (appears when zoom selected)
      if state.selectedZoomId != nil {
        Divider()

        ZoomSettingsPopover(
          state: state,
          previewImage: currentFrameImage
        )
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
      }
    }
    .background(Color(NSColor.windowBackgroundColor))
    .ignoresSafeArea(.all, edges: .top) // Extend background behind title bar
    .overlay {
      // Export progress overlay
      if state.isExporting {
        ExportProgressOverlay(state: state)
      }
    }
    .task {
      await state.loadMetadata()
      await state.extractFrames()
    }
  }
}
