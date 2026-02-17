//
//  VideoControlsView.swift
//  Snapzy
//
//  Playback controls with play/pause button and time display
//

import AVFoundation
import SwiftUI

/// Playback controls view with play/pause and time display
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

      Divider()
        .frame(height: 24)

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
}
