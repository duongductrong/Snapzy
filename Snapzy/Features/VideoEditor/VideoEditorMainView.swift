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
  /// Not observed: the editor follows `aiChrome` only, so typing in the prompt never
  /// re-renders the player, timeline or toolbar.
  private let agent: VideoEditorAgentController
  @State private var aiChrome = VideoEditorAgentController.Chrome()
  @AppStorage(PreferencesKeys.videoEditorAILayout)
  private var aiLayout = VideoEditorAILayout.defaultValue
  /// The editor narrows for the sidebar in one step (no per-frame relayout of the player and
  /// timeline); the panel itself slides in on top as a cheap transform animation.
  @State private var reservesAIPanelSpace = false
  @State private var showsAIPanel = false
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
    agent = state.agent
    self.primaryActionTitle = primaryActionTitle
    self.onSave = onSave
    self.onCancel = onCancel
  }

  private var isAuthoringLocked: Bool { aiChrome.isRunning }
  private var isAIPanelVisible: Bool {
    aiLayout == .sidebar && aiChrome.isPromptPresented && (agent.isAvailable || aiChrome.isRunning)
  }

  private static var aiPanelSlotWidth: CGFloat {
    VideoEditorAIPanelView.width + 2 * VideoEditorAIPanelView.inset
  }

  private var aiPanelAnimation: Animation { .spring(response: 0.32, dampingFraction: 0.9) }

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
    // The AI panel sits beside the whole editor, toolbar included: it runs the full window
    // height and the editor narrows to make room. Its header sits on the toolbar line.
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        // Locks its own authoring controls during a run; the AI toggle stays live.
        VideoEditorToolbarView(
          state: state,
          isAuthoringLocked: isAuthoringLocked,
          aiChrome: aiChrome,
          aiLayout: aiLayout
        )

        Divider()

        VStack(spacing: 0) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if reservesAIPanelSpace {
        Color.clear
          .frame(width: Self.aiPanelSlotWidth)
          .transition(.identity)
      }
    }
    .overlay(alignment: .trailing) {
      if showsAIPanel {
        VideoEditorAIPanelView(state: state)
          .padding(VideoEditorAIPanelView.inset)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .onReceive(agent.chromePublisher) { aiChrome = $0 }
    .onAppear {
      aiChrome = agent.chrome
      syncAIPanel(animated: false)
    }
    .onChange(of: isAIPanelVisible) { _ in syncAIPanel(animated: true) }
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

      // The AI prompt shortcut (configurable, default ⌘K) is matched by VideoEditorWindow.
      if !state.isGIF {
        editingShortcuts
          .disabled(isAuthoringLocked)
          .disabled(!aiChrome.allowsPlainKeyShortcuts)
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

  /// Reserves the sidebar's space without animation (one layout pass for the editor), then
  /// slides the panel over it. On close the editor takes the space back under the leaving panel.
  private func syncAIPanel(animated: Bool) {
    let visible = isAIPanelVisible
    var instant = Transaction()
    instant.disablesAnimations = true
    instant.animation = nil
    withTransaction(instant) { reservesAIPanelSpace = visible }
    if animated {
      withAnimation(aiPanelAnimation) { showsAIPanel = visible }
    } else {
      withTransaction(instant) { showsAIPanel = visible }
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
          if aiLayout == .dock {
            // Outside the player's zoom transform, like the Annotate dock over its canvas.
            GeometryReader { proxy in
              VideoEditorAIDockView(state: state, maxWidth: proxy.size.width - 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 14)
            }
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
