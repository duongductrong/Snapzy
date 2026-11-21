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

  private var desktopContent: some View {
    VStack(spacing: 0) {
      Spacer(minLength: SnapzySpace.xl)

      SnapzyMockFinderWindow().equatable()
        .frame(maxWidth: regionWidth, maxHeight: regionHeight)
        .padding(.horizontal, SnapzyMockScene.windowInset)

      Spacer(minLength: SnapzySpace.xl)
    }
    .padding(.top, SnapzyMockScene.windowTopInset) // Space for Menu Bar
  }

  // MARK: - Dimmed Overlay with Framed Cutout

  private var dimmedOverlay: some View {
    ZStack {
      Color.black.opacity(0.38)

      // Un-dimmed region cutout showing the framed Finder window
      VStack(spacing: 0) {
        Spacer(minLength: SnapzySpace.xl)

        ZStack {
          // Sharp cutout
          SnapzyMockFinderWindow().equatable()
            .frame(maxWidth: regionWidth, maxHeight: regionHeight)
            .padding(.horizontal, SnapzyMockScene.windowInset)

          // Selection border & handles
          if state.step2Stage == .prerecordArea {
            prerecordBorder
          } else if state.step2Stage == .recordingActive {
            activeRecordingBorder
          }
        }

        Spacer(minLength: SnapzySpace.xl)
      }
      .padding(.top, SnapzyMockScene.windowTopInset)
    }
  }

  // MARK: - Selection Borders

  private var prerecordBorder: some View {
    ZStack(alignment: .topLeading) {
      // Dashed border
      Radius.rect(Radius.controlL)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white, SnapzyMockPalette.selectionAccent],
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
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .lineLimit(1)

        Text("px")
          .font(.system(size: 8.5))
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, SnapzySpace.sm)
      .padding(.vertical, SnapzySpace.xxs)
      .background(Color.black.opacity(0.78))
      .clipShape(Radius.rect(Radius.ornament))
      .overlay(
        Radius.rect(Radius.ornament)
          .strokeBorder(Color.white.opacity(0.22), lineWidth: SnapzySurfaceGlass.specularLineWidth)
      )
      .padding(SnapzySpace.sm)
    }
    .frame(width: regionWidth, height: regionHeight)
  }

  private var activeRecordingBorder: some View {
    Radius.rect(Radius.controlL)
      .strokeBorder(Color.red.opacity(0.88), lineWidth: 1.75)
      .shadow(color: Color.red.opacity(0.22), radius: 3)
      .frame(width: regionWidth, height: regionHeight)
  }

  private var resizeHandles: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let points: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: w / 2, y: 0),
        CGPoint(x: w, y: 0),
        CGPoint(x: 0, y: h / 2),
        CGPoint(x: w, y: h / 2),
        CGPoint(x: 0, y: h),
        CGPoint(x: w / 2, y: h),
        CGPoint(x: w, y: h),
      ]

      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        handleCircle
          .position(point)
      }
    }
  }

  private var handleCircle: some View {
    Circle()
      .fill(Color.white)
      .frame(width: 6.5, height: 6.5)
      .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: SnapzySurfaceGlass.specularLineWidth))
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

        SnapzyMockSceneButton(
          title: L10n.Onboarding.mockPressToRecord,
          symbol: "record.circle"
        ) {
          state.simulateStartPrerecord()
        }
        .transition(SnapzyMockScene.hudTransition)

        Spacer()
      }
      .padding(.top, SnapzyMockScene.windowTopInset)

    case .prerecordArea:
      // Pre-record Toolbar floating below the framed selection area
      VStack(spacing: 0) {
        Spacer(minLength: SnapzySpace.xl)

        // Empty space matching Finder window height
        Color.clear
          .frame(width: regionWidth, height: regionHeight)

        // Floating Pre-record Toolbar
        SnapzyMockPrerecordToolbar(
          onRecord: {
            state.simulateStartRecording()
          },
          onCapture: {
            triggerFeedback(L10n.Onboarding.mockCapturedMode(L10n.CaptureKind.screenshot))
          },
          onCancel: {
            state.resetStep2Flow()
          }
        )
        .padding(.top, -10)

        Spacer(minLength: SnapzySpace.md)
      }
      .padding(.top, SnapzyMockScene.windowTopInset)
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

        HStack(alignment: .bottom, spacing: SnapzySpace.md) {
          VStack(alignment: .leading, spacing: SnapzySpace.xs) {
            // Curved hint arrow pointing down to the card
            SnapzyCurvedHintArrow(
              text: L10n.Onboarding.mockOpenEditorHint,
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
                triggerFeedback(L10n.Onboarding.mockToastCopied)
              },
              onSave: {
                triggerFeedback(L10n.Onboarding.mockToastSaved)
              },
              onAnnotate: {
                state.openVideoEditorFromQuickAccess()
              },
              onTogglePin: {
                withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
                  state.isCardPinned.toggle()
                }
                triggerFeedback(state.isCardPinned
                  ? L10n.Onboarding.mockToastPinned
                  : L10n.Onboarding.mockToastUnpinned)
              },
              onDismiss: {
                state.resetStep2Flow()
              }
            )
          }
          .padding(.leading, SnapzyMockScene.windowInset)
          .padding(.bottom, SnapzySpace.xl)

          Spacer()
        }
      }
      .transition(SnapzyMockScene.cardTransition)

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
            triggerFeedback(L10n.Onboarding.mockToastExported)
            state.completeChallenge(.openVideoEditor)
          }
        )
      }
      .transition(SnapzyMockScene.windowTransition)
    }
  }

  // MARK: - Toast Overlay

  private func toastOverlay(_ feedback: String) -> some View {
    VStack {
      Spacer()
      HStack(spacing: SnapzySpace.sm) {
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
      .shadow(color: SnapzyGlassShadow.controlColor, radius: SnapzyGlassShadow.controlRadius,
              y: SnapzyGlassShadow.controlY)
      .padding(.bottom, SnapzySpace.xl)
      .transition(SnapzyMockScene.hudTransition)
    }
  }

  private func triggerFeedback(_ message: String) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      feedbackMessage = message
      state.simulateQuickAccessAction(message)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        if feedbackMessage == message {
          feedbackMessage = nil
        }
      }
    }
  }
}
