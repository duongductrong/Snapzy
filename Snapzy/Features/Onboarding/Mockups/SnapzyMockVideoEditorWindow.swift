//
//  SnapzyMockVideoEditorWindow.swift
//  Snapzy
//
//  Faithful replica of Snapzy's VideoEditorMainView for Step 2 onboarding.
//  Features traffic-light window chrome, top toolbar with video specs, video player viewport,
//  playback controls with interactive Play/Pause, filmstrip timeline with trim handles,
//  and bottom action bar with Replay Flow and Export.
//

import SwiftUI

struct SnapzyMockVideoEditorWindow: View {
  var onReplay: (() -> Void)? = nil
  var onExport: (() -> Void)? = nil

  @State private var isPlaying: Bool = true
  @State private var playProgress: CGFloat = 0.45 // 0.0 to 1.0 (0s to 3s)
  @State private var playbackTimer: Timer? = nil
  @State private var isExportHovered: Bool = false
  @State private var isReplayHovered: Bool = false

  private var formattedCurrentTime: String {
    let secs = Double(playProgress * 3.0)
    return String(format: "00:%04.1f", secs)
  }

  var body: some View {
    VStack(spacing: 0) {
      // 1. Top Window Chrome & Toolbar
      windowToolbar

      Divider()
        .opacity(0.35)

      // 2. Main Player Viewport
      playerSection
        .frame(maxHeight: .infinity)

      Divider()
        .opacity(0.35)

      // 3. Filmstrip Timeline with Trim Handles
      timelineSection
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

      Divider()
        .opacity(0.35)

      // 4. Bottom Action Bar
      bottomBar
    }
    .frame(width: 480, height: 320)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
    )
    .shadow(color: Color.black.opacity(0.40), radius: 26, y: 12)
    .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
    .onAppear {
      startPlaybackTimer()
    }
    .onDisappear {
      stopPlaybackTimer()
    }
  }

  // MARK: - 1. Window Toolbar

  private var windowToolbar: some View {
    HStack(spacing: 8) {
      // Traffic lights
      HStack(spacing: 5) {
        Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 9, height: 9)
        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 9, height: 9)
        Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 9, height: 9)
      }
      .padding(.leading, 12)

      // Undo / Redo
      HStack(spacing: 3) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Color.primary.opacity(0.6))
        Image(systemName: "arrow.uturn.forward")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Color.primary.opacity(0.3))
      }
      .padding(.leading, 4)

      Spacer()

      // Title & Specs
      VStack(spacing: 1.5) {
        Text("Screen Recording 2026-09-09.mp4")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(1)

        Text("440 × 260 • 3.0s • 60 fps • 1.2 MB")
          .font(.system(size: 8.5, weight: .regular, design: .monospaced))
          .foregroundStyle(Color.primary.opacity(0.55))
      }

      Spacer()

      // Toolbar Actions
      HStack(spacing: 6) {
        Image(systemName: "folder")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.primary.opacity(0.75))

        Image(systemName: "info.circle")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.primary.opacity(0.75))
      }
      .padding(.trailing, 12)
    }
    .frame(height: 38)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
  }

  // MARK: - 2. Video Player Viewport

  private var playerSection: some View {
    ZStack {
      Color(red: 0.10, green: 0.10, blue: 0.11)

      // Mini Finder frame preview
      VStack(spacing: 0) {
        HStack(spacing: 3) {
          Circle().fill(Color.red.opacity(0.8)).frame(width: 4, height: 4)
          Circle().fill(Color.yellow.opacity(0.8)).frame(width: 4, height: 4)
          Circle().fill(Color.green.opacity(0.8)).frame(width: 4, height: 4)
          Spacer()
          Text("Finder — Documents")
            .font(.system(size: 6.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.6))
          Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color(white: 0.22))

        // Document rows
        VStack(spacing: 3) {
          ForEach(0..<4) { i in
            HStack(spacing: 6) {
              Image(systemName: i == 0 ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 7))
                .foregroundStyle(i == 0 ? Color.blue : Color.gray)
              Text(["Snapzy Captures", "Roadmap.xlsx", "config.toml", "Demo.mp4"][i])
                .font(.system(size: 7.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.85))
              Spacer()
              Text(["Folder", "12 KB", "4 KB", "3.2 MB"][i])
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.40))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 1.5)
          }
        }
        .padding(.vertical, 4)
        .background(Color(white: 0.14))

        Spacer(minLength: 0)
      }
      .frame(width: 320, height: 110)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .shadow(color: Color.black.opacity(0.5), radius: 8, y: 3)

      // Playback Controls Overlay at bottom of player
      VStack {
        Spacer()

        HStack(spacing: 12) {
          // Transport buttons
          HStack(spacing: 8) {
            Button {
              playProgress = max(0.0, playProgress - 0.1)
            } label: {
              Image(systemName: "backward.frame")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Button {
              togglePlayback()
            } label: {
              Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.20)))
            }
            .buttonStyle(.plain)

            Button {
              playProgress = min(1.0, playProgress + 0.1)
            } label: {
              Image(systemName: "forward.frame")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
          }

          // Timecode
          Text("\(formattedCurrentTime) / 00:03.0")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))

          Spacer()

          // Resolution badge
          Text("1080p 60fps")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(0.65))
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
      }
    }
  }

  // MARK: - 3. Filmstrip Timeline

  private var timelineSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Timeline Track")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Color.primary.opacity(0.65))

        Spacer()

        Text("Trim: 0.0s – 3.0s")
          .font(.system(size: 8.5, weight: .medium, design: .monospaced))
          .foregroundStyle(Color.primary.opacity(0.55))
      }

      // Filmstrip bar with yellow trim brackets and red playhead
      GeometryReader { geo in
        let totalWidth = geo.size.width
        let playheadX = totalWidth * playProgress

        ZStack(alignment: .leading) {
          // Filmstrip thumbnails container
          HStack(spacing: 2) {
            ForEach(0..<7) { i in
              ZStack {
                Color.black.opacity(0.25)

                HStack(spacing: 2) {
                  RoundedRectangle(cornerRadius: 1).fill(Color.blue.opacity(0.8)).frame(width: 6, height: 14)
                  VStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.3)).frame(height: 2)
                    RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.3)).frame(height: 2)
                  }
                }
                .padding(3)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .clipShape(RoundedRectangle(cornerRadius: 2))
            }
          }
          .padding(2)
          .background(Color(nsColor: .controlBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 4))

          // Yellow trim border and handles (matching Snapzy's VideoEditorVideoTrimHandlesView)
          RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color(red: 0.98, green: 0.74, blue: 0.16), lineWidth: 2)

          // Left handle
          HStack {
            RoundedRectangle(cornerRadius: 2)
              .fill(Color(red: 0.98, green: 0.74, blue: 0.16))
              .frame(width: 8, height: geo.size.height)
              .overlay(
                Image(systemName: "chevron.compact.left")
                  .font(.system(size: 8, weight: .bold))
                  .foregroundStyle(Color.black.opacity(0.8))
              )

            Spacer()

            // Right handle
            RoundedRectangle(cornerRadius: 2)
              .fill(Color(red: 0.98, green: 0.74, blue: 0.16))
              .frame(width: 8, height: geo.size.height)
              .overlay(
                Image(systemName: "chevron.compact.right")
                  .font(.system(size: 8, weight: .bold))
                  .foregroundStyle(Color.black.opacity(0.8))
              )
          }

          // Red Playhead Line
          Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: geo.size.height + 4)
            .overlay(
              Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .offset(y: -(geo.size.height / 2 + 2))
            )
            .offset(x: max(8, min(totalWidth - 8, playheadX)))
        }
      }
      .frame(height: 32)
    }
  }

  // MARK: - 4. Bottom Action Bar

  private var bottomBar: some View {
    HStack {
      // Replay Demo button
      Button {
        onReplay?()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 9.5, weight: .medium))
          Text("Replay Demo")
            .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isReplayHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05))
        )
      }
      .buttonStyle(.plain)
      .onHover { h in isReplayHovered = h }

      Spacer()

      // Primary Export button
      Button {
        onExport?()
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 10.5, weight: .medium))
          Text("Export MP4 (⌘S)")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isExportHovered ? Color(red: 0.12, green: 0.45, blue: 0.95) : Color(red: 0.08, green: 0.40, blue: 0.90))
        )
        .shadow(color: Color.blue.opacity(0.3), radius: 4, y: 1.5)
      }
      .buttonStyle(.plain)
      .onHover { h in isExportHovered = h }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
  }

  // MARK: - Playback Helpers

  private func togglePlayback() {
    isPlaying.toggle()
    if isPlaying {
      startPlaybackTimer()
    } else {
      stopPlaybackTimer()
    }
  }

  private func startPlaybackTimer() {
    stopPlaybackTimer()
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
      if isPlaying {
        playProgress += 0.018
        if playProgress > 1.0 {
          playProgress = 0.0
        }
      }
    }
  }

  private func stopPlaybackTimer() {
    playbackTimer?.invalidate()
    playbackTimer = nil
  }
}
