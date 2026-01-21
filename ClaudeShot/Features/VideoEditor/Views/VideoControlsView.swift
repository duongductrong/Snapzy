//
//  VideoControlsView.swift
//  ClaudeShot
//
//  Playback controls with play/pause button and time display
//

import SwiftUI

/// Playback controls view with play/pause and time display
struct VideoControlsView: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    HStack(spacing: 16) {
      // Play/Pause button
      Button(action: { state.togglePlayback() }) {
        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 20))
          .foregroundColor(.primary)
          .frame(width: 40, height: 40)
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
