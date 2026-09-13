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
        state: state,
        primaryActionTitle: primaryActionTitle,
        onCancel: { onCancel?() },
        onConvert: { onSave?() }
      )
    }
    // Keyboard shortcuts
    .background {
      // Cloud upload shortcut (⌘U)
      Button("") {
        NotificationCenter.default.post(name: .videoEditorCloudUpload, object: nil)
      }
      .keyboardShortcut("u", modifiers: [.command])
      .opacity(0)
      .frame(width: 0, height: 0)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .padding(.top, WindowSpacingConfiguration.default.contentTopPadding)
        .padding(.bottom, WindowSpacingConfiguration.default.contentBottomPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var videoEditorContent: some View {
    VStack(spacing: 0) {
      videoWorkspaceRow
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      VideoTimelineView(state: state)
        .windowContentHPadding()
        .padding(.top, WindowSpacingConfiguration.default.contentTopPadding)
        .padding(.bottom, WindowSpacingConfiguration.default.contentBottomPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var videoWorkspaceRow: some View {
    HStack(spacing: 0) {
      if state.isLeftSidebarVisible {
        VideoEditorLeftSidebar(state: state)
          .frame(maxHeight: .infinity, alignment: .top)

        Divider()
      }

      videoPlayerColumn

      if state.isRightSidebarVisible {
        Divider()

        VideoEditorRightSidebar(
          state: state,
          previewImage: currentFrameImage
        )
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: state.isLeftSidebarVisible)
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
