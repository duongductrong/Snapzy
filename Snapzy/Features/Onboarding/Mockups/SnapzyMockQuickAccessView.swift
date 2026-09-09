//
//  SnapzyMockQuickAccessView.swift
//  Snapzy
//
//  Step 2 interactive mockup: Complete Screen Recording & Video Editor workflow simulation.
//  5-stage lifecycle:
//  1. Ready to Record (Desktop with Finder window, ⇧⌘5 prompt)
//  2. Prerecord Area (Dimmed overlay, framed region, Apple-style toolbar & curved hint arrow to Record)
//  3. Active Recording (Pulsing HUD status bar, 3s countdown, waveform, Stop button)
//  4. Video Quick Access (Video card in bottom-left, duration badge, curved hint arrow to card)
//  5. Video Editor Window (Toolbar specs, video viewport, playback scrubber, filmstrip timeline, replay/export)
//

import SwiftUI

struct SnapzyMockQuickAccessView: View {
  @ObservedObject var state: SnapzyOnboardingState
  @State private var feedbackMessage: String? = nil

  // Framed area sizing
  private let regionWidth: CGFloat = 460
  private let regionHeight: CGFloat = 240

  var body: some View {
    ZStack(alignment: .top) {
      // 1. macOS Desktop Wallpaper Canvas
      SnapzyMockWallpaper(app: .finder).equatable()

      // 2. Finder Window in Background
      desktopContent

      // 3. macOS Menu Bar & Camera Notch
      SnapzyMockMenuBar(app: .finder).equatable()

      // 4. Dimmed Fullscreen Overlay (covers 100% of demo screen in prerecord and recording stages)
      if state.step2Stage == .prerecordArea || state.step2Stage == .recordingActive {
        dimmedOverlay
          .ignoresSafeArea()
          .transition(.opacity)
      }

      // 5. Interactive Stage Overlay
      stageOverlay

      // 6. Toast Feedback Notification
      if let feedback = feedbackMessage {
        toastOverlay(feedback)
      }

      // 7. Camera Shutter Screen Flash
      Color.white
        .opacity(state.screenFlashOpacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Desktop Content

  @ViewBuilder
  private var desktopContent: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 16)

      SnapzyMockFinderWindow().equatable()
        .frame(maxWidth: regionWidth, maxHeight: regionHeight)
        .padding(.horizontal, 24)

      Spacer(minLength: 16)
    }
    .padding(.top, 28) // Space for Menu Bar
  }

  // MARK: - Dimmed Overlay with Framed Cutout

  private var dimmedOverlay: some View {
    ZStack {
      Color.black.opacity(0.38)

      // Un-dimmed region cutout showing the framed Finder window
      VStack(spacing: 0) {
        Spacer(minLength: 16)

        ZStack {
          // Sharp cutout
          SnapzyMockFinderWindow().equatable()
            .frame(maxWidth: regionWidth, maxHeight: regionHeight)
            .padding(.horizontal, 24)

          // Selection border & handles
          if state.step2Stage == .prerecordArea {
            prerecordBorder
          } else if state.step2Stage == .recordingActive {
            activeRecordingBorder
          }
        }

        Spacer(minLength: 16)
      }
      .padding(.top, 28)
    }
  }

  // MARK: - Selection Borders

  private var prerecordBorder: some View {
    ZStack(alignment: .topLeading) {
      // Dashed border
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white, Color(red: 0.40, green: 0.75, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
        )

      // 8 Resize Handles
      resizeHandles

      // Dimension Badge at top-left
      HStack(spacing: 2) {
        Text("460 × 240")
          .font(.system(size: 8.5, weight: .bold, design: .monospaced))
        Text("px")
          .font(.system(size: 7.5, weight: .medium))
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, 6)
      .padding(.vertical, 2.5)
      .background(Color.black.opacity(0.80))
      .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
          .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
      )
      .padding(6)
    }
    .frame(width: regionWidth, height: regionHeight)
  }

  private var activeRecordingBorder: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .strokeBorder(Color.red.opacity(0.88), lineWidth: 2)
      .shadow(color: Color.red.opacity(0.40), radius: 6)
      .frame(width: regionWidth, height: regionHeight)
  }

  private var resizeHandles: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height

      ForEach([
        CGPoint(x: 0, y: 0),
        CGPoint(x: w / 2, y: 0),
        CGPoint(x: w, y: 0),
        CGPoint(x: 0, y: h / 2),
        CGPoint(x: w, y: h / 2),
        CGPoint(x: 0, y: h),
        CGPoint(x: w / 2, y: h),
        CGPoint(x: w, y: h),
      ], id: \.x) { point in
        handleCircle
          .position(point)
      }
    }
  }

  private var handleCircle: some View {
    Circle()
      .fill(Color.white)
      .frame(width: 6.5, height: 6.5)
      .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5))
      .shadow(color: Color.black.opacity(0.25), radius: 1)
  }

  // MARK: - Stage Overlays

  @ViewBuilder
  private var stageOverlay: some View {
    switch state.step2Stage {
    case .readyToRecord:
      // Prompt button to trigger ⇧⌘5 simulation
      VStack {
        Spacer()

        Button {
          state.simulateStartPrerecord()
        } label: {
          HStack(spacing: 7) {
            Image(systemName: "record.circle")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Color.red)

            Text("Simulate ⇧⌘5 Area Selection")
              .font(.system(size: 11.5, weight: .semibold))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
          .foregroundStyle(Color.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background {
            SnapzyGlassSurface(
              shape: Capsule(style: .continuous),
              substrate: SnapzySurfaceGlass.baseDarkness,
              tint: 0.12
            )
          }
          .clipShape(Capsule(style: .continuous))
          .shadow(color: Color.black.opacity(0.32), radius: 12, y: 6)
        }
        .buttonStyle(.plain)

        Spacer()
      }
      .padding(.top, 28)
      .transition(.scale(scale: 0.92).combined(with: .opacity))

    case .prerecordArea:
      // Pre-record Toolbar floating below the framed selection area
      VStack(spacing: 0) {
        Spacer(minLength: 16)

        // Empty space matching Finder window height
        Color.clear
          .frame(width: regionWidth, height: regionHeight)

        // Floating Pre-record Toolbar
        SnapzyMockPrerecordToolbar(
          onRecord: {
            state.simulateStartRecording()
          },
          onCapture: {
            triggerFeedback("Snapshot taken")
          },
          onCancel: {
            state.resetStep2Flow()
          }
        )
        .padding(.top, -10)

        Spacer(minLength: 8)
      }
      .padding(.top, 28)
      .transition(.opacity.combined(with: .move(edge: .bottom)))

    case .recordingActive:
      // Floating Recording Status Bar at top of screen
      VStack {
        SnapzyMockRecordingStatusBar(
          elapsedSeconds: state.recordingSeconds,
          onStop: {
            state.simulateFinishRecording()
          }
        )
        .padding(.top, 38)

        Spacer()
      }
      .transition(.move(edge: .top).combined(with: .opacity))

    case .videoQuickAccess:
      // Video Quick Access Card in bottom-left corner with curved hint arrow
      VStack {
        Spacer()

        HStack(alignment: .bottom, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            // Curved hint arrow pointing down to the card
            SnapzyCurvedHintArrow(
              text: "Click card to open Video Editor",
              orientation: .curveDownToTarget,
              arrowAlignment: .leading,
              color: .white
            )
            .padding(.leading, 12)

            // Video Quick Access Card
            SnapzyMockQuickAccessCard(
              isPinned: state.isCardPinned,
              isVideo: true,
              durationText: "00:03",
              onCopy: {
                triggerFeedback("Copied Video (⌘C)")
              },
              onSave: {
                triggerFeedback("Saved to Desktop (⌘S)")
              },
              onAnnotate: {
                state.openVideoEditorFromQuickAccess()
              },
              onTogglePin: {
                withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
                  state.isCardPinned.toggle()
                }
                triggerFeedback(state.isCardPinned ? "Pinned on Screen (⌘P)" : "Unpinned")
              },
              onDismiss: {
                state.resetStep2Flow()
              }
            )
          }
          .padding(.leading, 24)
          .padding(.bottom, 20)

          Spacer()
        }
      }
      .transition(.asymmetric(
        insertion: .scale(scale: 0.88, anchor: .bottomLeading).combined(with: .opacity),
        removal: .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity)
      ))

    case .videoEditorOpen:
      // Full Video Editor Window centered on screen
      ZStack {
        Color.black.opacity(0.38)
          .ignoresSafeArea()

        SnapzyMockVideoEditorWindow(
          onReplay: {
            state.resetStep2Flow()
          },
          onExport: {
            triggerFeedback("Exported MP4 (⌘S)")
            state.completeChallenge(.openVideoEditor)
          }
        )
      }
      .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
  }

  // MARK: - Toast Overlay

  private func toastOverlay(_ feedback: String) -> some View {
    VStack {
      Spacer()
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.green)
        Text(feedback)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color.white)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background {
        SnapzyGlassSurface(
          shape: Capsule(style: .continuous),
          substrate: SnapzySurfaceGlass.baseDarkness,
          tint: 0.10
        )
      }
      .clipShape(Capsule(style: .continuous))
      .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
      .padding(.bottom, 16)
      .transition(.scale(scale: 0.92).combined(with: .opacity))
    }
  }

  private func triggerFeedback(_ message: String) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      feedbackMessage = message
      state.simulateQuickAccessAction(message)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        if self.feedbackMessage == message {
          self.feedbackMessage = nil
        }
      }
    }
  }
}
