//
//  VideoControlsView.swift
//  ClaudeShot
//
//  Playback controls with play/pause button, time display, and zoom controls
//

import AVFoundation
import SwiftUI

/// Playback controls view with play/pause, zoom controls, and time display
struct VideoControlsView: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    HStack(spacing: 16) {
      // Play/Pause button
      Button(action: { state.togglePlayback() }) {
        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 16))
          .foregroundColor(.primary)
          .frame(width: 32, height: 32)
          .background(Color.white.opacity(0.1))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.space, modifiers: [])

      // Mute button
      Button(action: { state.toggleMute() }) {
        Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
          .font(.system(size: 16))
          .foregroundColor(state.isMuted ? .red : .primary)
          .frame(width: 32, height: 32)
          .background(Color.white.opacity(0.1))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut("m", modifiers: [])
      .help(state.isMuted ? "Unmute (M)" : "Mute (M)")

      Divider()
        .frame(height: 24)

      // Zoom controls
      zoomControls

      // Time display
      HStack(spacing: 4) {
        Text(state.formattedCurrentTime)
          .font(.system(size: 13, design: .monospaced))
          .foregroundColor(.primary)

        Text("/")
          .font(.system(size: 13))
          .foregroundColor(.secondary)

        Text(state.formattedDuration)
          .font(.system(size: 13, design: .monospaced))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Zoom count indicator
      if !state.zoomSegments.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "plus.magnifyingglass")
            .font(.system(size: 11))
            .foregroundColor(ZoomColors.primary)

          Text("\(state.zoomSegments.count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(ZoomColors.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ZoomColors.primary.opacity(0.15))
        .cornerRadius(4)
      }

      // Trimmed duration indicator
      if state.hasUnsavedChanges {
        HStack(spacing: 4) {
          Image(systemName: "scissors")
            .font(.system(size: 12))
            .foregroundColor(.yellow)

          Text(state.formattedTrimmedDuration)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.yellow)
        }
      }
    }
    .padding(.vertical, 8)
  }

  // MARK: - Zoom Controls

  private var zoomControls: some View {
    HStack(spacing: 8) {
      // Add zoom button
      Button(action: addZoomAtPlayhead) {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 14))
          .foregroundColor(.primary)
          .frame(width: 28, height: 28)
          .background(ZoomColors.primary.opacity(0.2))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .keyboardShortcut("z", modifiers: [])
      .help("Add Zoom at Playhead (Z)")

      // Delete selected zoom button
      if state.selectedZoomId != nil {
        Button(action: deleteSelectedZoom) {
          Image(systemName: "trash")
            .font(.system(size: 12))
            .foregroundColor(.red)
            .frame(width: 28, height: 28)
            .background(Color.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.delete, modifiers: [])
        .help("Delete Selected Zoom (⌫)")
      }

      // Toggle zoom track visibility
      Button(action: { state.toggleZoomTrackVisibility() }) {
        Image(systemName: state.isZoomTrackVisible ? "eye.fill" : "eye.slash")
          .font(.system(size: 12))
          .foregroundColor(state.isZoomTrackVisible ? .primary : .secondary)
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .help(state.isZoomTrackVisible ? "Hide Zoom Track" : "Show Zoom Track")
    }
  }

  // MARK: - Actions

  private func addZoomAtPlayhead() {
    let currentTime = CMTimeGetSeconds(state.currentTime)
    state.addZoom(at: currentTime)
  }

  private func deleteSelectedZoom() {
    if let id = state.selectedZoomId {
      state.removeZoom(id: id)
    }
  }
}
