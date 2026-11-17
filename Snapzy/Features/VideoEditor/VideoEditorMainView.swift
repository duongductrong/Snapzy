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
  /// The AI prompt: while it runs, authoring is locked (play and the transport stay live).
  @ObservedObject private var agent: VideoEditorAgentController
  var primaryActionTitle: String = "Convert"
  var onSave: (() -> Void)?
  var onCancel: (() -> Void)?

  init(
    state: VideoEditorState,
    primaryActionTitle: String = "Convert",
    onSave: (() -> Void)? = nil,
    onCancel: (() -> Void)? = nil
  ) {
    self.state = state
    _agent = ObservedObject(wrappedValue: state.agent)
    self.primaryActionTitle = primaryActionTitle
    self.onSave = onSave
    self.onCancel = onCancel
  }

  private var isAuthoringLocked: Bool { agent.isRunning }

  /// Computed property for current frame preview
  private var currentFrameImage: NSImage? {
    guard !state.frameThumbnails.isEmpty else { return nil }
    let duration = CMTimeGetSeconds(state.duration)
    guard duration > 0 else { return nil }
    let progress = CMTimeGetSeconds(state.currentTime) / duration
    // Thumbnails are sampled at the center of each timeline cell
    // (VideoEditorState.generateFrameThumbnails), so the slot containing the
    // playhead is Int(progress * count) — the same frame shown in the strip.
    let index = Int(progress * Double(state.frameThumbnails.count))
    let clampedIndex = max(0, min(index, state.frameThumbnails.count - 1))
    return state.frameThumbnails[clampedIndex]
  }

  var body: some View {
    VStack(spacing: 0) {
      VideoEditorToolbarView(state: state)
        .disabled(isAuthoringLocked)

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
      .disabled(isAuthoringLocked)
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
      .disabled(isAuthoringLocked)

      if !state.isGIF {
        // AI prompt (⌘K): open, refocus, or close when the field has the caret.
        Button("") {
          agent.handleShortcut(isFieldEditing: PromptTextField.isEditing(in: NSApp.keyWindow))
        }
        .keyboardShortcut("k", modifiers: [.command])
        .opacity(0)
        .frame(width: 0, height: 0)
        .disabled(!agent.isAvailable)

        editingShortcuts
          .disabled(isAuthoringLocked)
          .disabled(!agent.allowsPlainKeyShortcuts)
      }
    }
    .disabled(state.isExporting)
    .overlay {
      // Export progress overlay
      if state.isExporting {
        ExportProgressOverlay(state: state)
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.isExporting)
    .ignoresSafeArea(.all, edges: .top)
    .task {
      await state.loadMetadata()
      await state.extractFrames()
    }
  }

  /// Plain-key editing shortcuts (Z, S, Delete, I, O, ⌘=, ⌘-, ⌘0).
  @ViewBuilder
  private var editingShortcuts: some View {
    // Add zoom at playhead (Z key)
    Button("") {
      let currentTime = CMTimeGetSeconds(state.currentTime)
      state.addZoom(at: currentTime)
    }
    .keyboardShortcut("z", modifiers: [])
    .opacity(0)
    .frame(width: 0, height: 0)

    // Split at playhead (S key)
    Button("") {
      state.splitAtPlayhead()
    }
    .keyboardShortcut("s", modifiers: [])
    .opacity(0)
    .frame(width: 0, height: 0)
    .disabled(!state.canSplitAtPlayhead)

    // Delete selected zoom / speed / clip (Delete key) — priority:
    // zoom selection → speed selection → clip.
    Button("") {
      if let id = state.selectedZoomId {
        state.removeZoom(id: id)
      } else if let id = state.selectedSpeedId {
        state.removeSpeed(id: id)
      } else {
        state.deleteSelectedClip()
      }
    }
    .keyboardShortcut(.delete, modifiers: [])
    .opacity(0)
    .frame(width: 0, height: 0)
    .disabled(
      state.selectedZoomId == nil &&
        state.selectedSpeedId == nil &&
        !state.canDeleteSelectedClip
    )

    // Set trim start at playhead (I key)
    Button("") {
      state.setTrimStart(state.currentTime)
    }
    .keyboardShortcut("i", modifiers: [])
    .opacity(0)
    .frame(width: 0, height: 0)

    // Set trim end at playhead (O key)
    Button("") {
      state.setTrimEnd(state.currentTime)
    }
    .keyboardShortcut("o", modifiers: [])
    .opacity(0)
    .frame(width: 0, height: 0)

    // Timeline zoom in (⌘= / ⌘+)
    Button("") {
      state.timelineViewport.zoomIn(anchorTime: CMTimeGetSeconds(state.currentTime))
    }
    .keyboardShortcut("=", modifiers: [.command])
    .opacity(0)
    .frame(width: 0, height: 0)

    // Timeline zoom out (⌘-)
    Button("") {
      state.timelineViewport.zoomOut(anchorTime: CMTimeGetSeconds(state.currentTime))
    }
    .keyboardShortcut("-", modifiers: [.command])
    .opacity(0)
    .frame(width: 0, height: 0)

    // Timeline fit (⌘0)
    Button("") {
      state.timelineViewport.fit()
    }
    .keyboardShortcut("0", modifiers: [.command])
    .opacity(0)
    .frame(width: 0, height: 0)
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

      // Keep this GeometryReader responsive to parent/window width changes;
      // equatable-wrapping the container can freeze its initial viewport size.
      VideoTimelineView(state: state)
        .disabled(isAuthoringLocked)
        .windowContentHPadding()
        .padding(.top, WindowSpacingConfiguration.default.contentTopPadding)
        .padding(.bottom, WindowSpacingConfiguration.default.contentBottomPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var videoWorkspaceRow: some View {
    HStack(spacing: 0) {
      Group {
        VideoEditorLeftRail(state: state)

        Divider()

        if state.isLeftSidebarVisible {
          VideoEditorLeftSidebar(state: state, previewImage: currentFrameImage)
            .frame(maxHeight: .infinity, alignment: .top)

          Divider()
        }
      }
      .disabled(isAuthoringLocked)

      videoPlayerColumn
    }
    .animation(.easeInOut(duration: 0.2), value: state.isLeftSidebarVisible)
    .animation(.easeInOut(duration: 0.2), value: state.leftSidebarPanel)
  }

  private var videoPlayerColumn: some View {
    VStack(spacing: 0) {
      ZoomableVideoPlayerSection(state: state)
        .frame(minHeight: 200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          // Outside the player's zoom transform, like the Annotate dock over its canvas.
          GeometryReader { proxy in
            VideoEditorAIDockView(state: state, maxWidth: proxy.size.width - 32)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
              .padding(.bottom, 14)
          }
        }

      VideoControlsView(state: state)
        .padding(.horizontal, WindowSpacingConfiguration.default.contentHPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
