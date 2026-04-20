//
//  VideoEditorMainView.swift
//  Snapzy
//
//  Main container view for video editor
//

import AVFoundation
import SwiftUI

/// Main view for video editor containing player, timeline, controls, and info
struct VideoEditorMainView: View {
  @ObservedObject var state: VideoEditorState
  var primaryActionTitle: String = "Convert"
  var onSave: (() -> Void)?
  var onCancel: (() -> Void)?

  private let videoDetailsSidebarWidth: CGFloat = 280
  private let workspaceSpacing: CGFloat = 14

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
      VideoEditorToolbarView(state: state)

      Divider()

      if state.isGIF {
        gifContent
      } else {
        videoEditorContent
      }

      // Bottom bar with Cancel/Save
      VideoEditorBottomBar(
        primaryActionTitle: primaryActionTitle,
        onCancel: { onCancel?() },
        onConvert: { onSave?() }
      )
    }
    // Keyboard shortcuts for zoom operations (video only)
    .background {
      if !state.isGIF {
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
    }
    .overlay {
      // Export progress overlay
      if state.isExporting {
        ExportProgressOverlay(state: state)
      }
    }
    .ignoresSafeArea(.all, edges: .top)
    .task {
      await state.loadMetadata()
      await state.extractFrames()
    }
  }

  private var gifContent: some View {
    VStack(spacing: 0) {
      AnimatedGIFView(url: state.sourceURL)
        .frame(minHeight: 200)

      VideoEditorGIFSettingsPanel(state: state)
        .windowContentHPadding()
        .padding(.top, 8)
        .padding(.bottom, WindowSpacingConfiguration.default.contentBottomPadding)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var videoEditorContent: some View {
    VStack(spacing: 0) {
      videoWorkspaceRow
        .windowContentHPadding()
        .padding(.top, WindowSpacingConfiguration.default.contentTopPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      VideoTimelineView(state: state)
        .windowContentHPadding()
        .padding(.top, WindowSpacingConfiguration.default.contentTopPadding)

      VideoExportSettingsPanel(state: state)
        .windowContentHPadding()
        .padding(.top, 8)
        .padding(.bottom, WindowSpacingConfiguration.default.contentBottomPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var videoWorkspaceRow: some View {
    HStack(alignment: .top, spacing: workspaceSpacing) {
      if state.isVideoInfoSidebarVisible {
        VideoDetailsSidebarView(state: state)
          .frame(width: videoDetailsSidebarWidth)
          .frame(maxHeight: .infinity, alignment: .top)
          .videoEditorSidebarPanel()
      }

      videoPlayerColumn

      if state.isRightSidebarVisible {
        VideoEditorRightSidebar(
          state: state,
          previewImage: currentFrameImage
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .videoEditorSidebarPanel()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: state.isVideoInfoSidebarVisible)
    .animation(.easeInOut(duration: 0.2), value: state.isRightSidebarVisible)
  }

  private var videoPlayerColumn: some View {
    VStack(spacing: 0) {
      ZoomableVideoPlayerSection(state: state)
        .frame(minHeight: 200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      VideoControlsView(state: state)
        .padding(.horizontal, WindowSpacingConfiguration.default.contentHPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
