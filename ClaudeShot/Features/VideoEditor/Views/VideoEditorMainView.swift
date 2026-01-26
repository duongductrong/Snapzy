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
    VStack(spacing: 0) {
      // NEW: Full-width toolbar at top
      VideoEditorToolbarView(
        state: state,
        onSave: { onSave?() }
      )

      Divider()

      // Content area with optional sidebars
      HStack(spacing: 0) {
        // Video details sidebar (left side)
        if state.isVideoInfoSidebarVisible {
          VideoDetailsSidebarView(state: state)
            .frame(width: 280)
            .frame(maxHeight: .infinity, alignment: .top)

          Divider()
        }

        // Main editor content
        VStack(spacing: 0) {
          // Video player with zoom preview
          ZoomableVideoPlayerSection(state: state)
            .frame(minHeight: 200)

          // MOVED UP: Playback controls now under video
          VideoControlsView(state: state)
            .windowContentHPadding()
            .padding(.top, 8)

          // Timeline with frame previews and trim handles
          VideoTimelineView(state: state)
            .windowContentHPadding()
            .padding(.top, WindowSpacingConfiguration.default.contentTopPadding)
            .padding(.bottom, WindowSpacingConfiguration.default.contentBottomPadding)

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Right sidebar with tabs (Zoom + Background)
        Divider()

        VideoEditorRightSidebar(
          state: state,
          previewImage: currentFrameImage
        )
      }
      .animation(.easeInOut(duration: 0.2), value: state.isVideoInfoSidebarVisible)
    }
    // Keyboard shortcuts for zoom operations
    .background {
      // Add zoom at playhead (Z key)
      Button("") {
        let currentTime = CMTimeGetSeconds(state.currentTime)
        state.addZoom(at: currentTime)
      }
      .keyboardShortcut("z", modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)

      // Delete selected zoom (Delete key)
      Button("") {
        if let id = state.selectedZoomId {
          state.removeZoom(id: id)
        }
      }
      .keyboardShortcut(.delete, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)
      .disabled(state.selectedZoomId == nil)
    }
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
