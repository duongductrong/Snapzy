//
//  SnapzyMockAreaCaptureView.swift
//  Snapzy
//
//  Step 1 interactive mockup: The complete, authentic Snapzy workflow
//  Capture (Area Selection) -> Quick Access (Floating Card) -> Annotate Window.
//

import SwiftUI

struct SnapzyMockAreaCaptureView: View {
  @ObservedObject var state: SnapzyOnboardingState
  @State private var feedbackToast: String? = nil
  @State private var selectionProgress: CGFloat = 0.0
  @State private var autoCaptureTimer: Task<Void, Never>? = nil

  private let targetSelectionWidth: CGFloat = 410
  private let targetSelectionHeight: CGFloat = 160

  var body: some View {
    ZStack(alignment: .top) {
      // 1. macOS Desktop Wallpaper Canvas
      SnapzyMockWallpaper(app: .notes).equatable()

      // 2. Desktop Window / Canvas Layer
      desktopContent

      // 3. macOS Menu Bar & Camera Notch
      SnapzyMockMenuBar(app: .notes).equatable()

      // 4. Full-Screen Dimmed Overlay during Area Capture (Covering 100% of demo screen including Menu Bar!)
      if state.step1Stage == .selectingArea {
        Color.black.opacity(0.36)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .transition(.opacity)
      }

      // 5. Overlaid Interactive Elements by Stage
      interactiveStageOverlay

      // 6. Toast Feedback Notification
      if let toast = feedbackToast {
        toastNotification(toast)
      }

      // 7. Camera Shutter Screen Flash
      Color.white
        .opacity(state.screenFlashOpacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: state.step1Stage) { newStage in
      handleStageTransition(to: newStage)
    }
    .onAppear {
      if state.step1Stage == .selectingArea {
        startAutoSelectionAnimation()
      }
    }
    .onDisappear {
      autoCaptureTimer?.cancel()
      autoCaptureTimer = nil
    }
  }

  private func handleStageTransition(to newStage: Step1WorkflowStage) {
    autoCaptureTimer?.cancel()
    autoCaptureTimer = nil

    if newStage == .selectingArea {
      startAutoSelectionAnimation()
    } else {
      selectionProgress = 0.0
    }
  }

  private func startAutoSelectionAnimation() {
    selectionProgress = 0.0
    withAnimation(.easeInOut(duration: 0.78)) {
      selectionProgress = 1.0
    }

    autoCaptureTimer = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_050_000_000) // 1.05s total
      guard !Task.isCancelled, state.step1Stage == .selectingArea else { return }
      state.completeCaptureToQuickAccess()
    }
  }

  // MARK: - Desktop Content

  @ViewBuilder
  private var desktopContent: some View {
    if state.step1Stage == .annotateWindowOpen {
      // Full Annotate Window centered on the desktop
      VStack(spacing: 0) {
        Spacer(minLength: 16)

        SnapzyMockAnnotateWindow {
          state.resetStep1Flow()
        }
        .frame(maxWidth: 520, maxHeight: 340)
        .padding(.horizontal, 16)

        Spacer(minLength: 16)
      }
      .padding(.top, 28)
      .transition(.asymmetric(
        insertion: .scale(scale: 0.94).combined(with: .opacity),
        removal: .scale(scale: 0.94).combined(with: .opacity)
      ))
    } else {
      // Apple Notes Window in background for capture & quick access stages
      VStack(spacing: 0) {
        Spacer(minLength: 16)

        SnapzyMockNotesWindow().equatable()
          .frame(maxWidth: 470)
          .padding(.horizontal, 24)

        Spacer(minLength: 16)
      }
      .padding(.top, 28)
      .transition(.opacity)
    }
  }

  // MARK: - Interactive Stage Overlay

  @ViewBuilder
  private var interactiveStageOverlay: some View {
    switch state.step1Stage {
    case .readyToCapture:
      // Prompt button to begin capture
      VStack {
        Spacer()

        Button {
          state.simulateAreaCapture()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "viewfinder")
              .font(.system(size: 13, weight: .bold))

            Text("Press ⇧⌘4 or Click to Capture")
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

    case .selectingArea:
      // Authentic ⇧⌘4 Area Selection (animated auto-draw from corner)
      activeAreaSelectionView
        .transition(.opacity)

    case .quickAccessFloating:
      // Floating Quick Access Card in bottom-left corner
      VStack {
        Spacer()

        HStack {
          SnapzyMockQuickAccessCard(
            isPinned: state.isCardPinned,
            onCopy: {
              showToast("Copied to Clipboard (⌘C)")
            },
            onSave: {
              showToast("Saved to Desktop (⌘S)")
            },
            onAnnotate: {
              state.openAnnotateFromQuickAccess()
            },
            onTogglePin: {
              state.isCardPinned.toggle()
              showToast(state.isCardPinned ? "Pinned on Screen (⌘P)" : "Unpinned")
            },
            onDismiss: {
              state.resetStep1Flow()
            }
          )
          .padding(.leading, 24)
          .padding(.bottom, 22)

          Spacer()
        }
      }
      .transition(.asymmetric(
        insertion: .scale(scale: 0.88, anchor: .bottomLeading).combined(with: .opacity).combined(with: .offset(x: -16, y: 16)),
        removal: .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity)
      ))

    case .annotateWindowOpen:
      EmptyView()
    }
  }

  // MARK: - Authentic ⇧⌘4 Area Selection View

  private var activeAreaSelectionView: some View {
    let currentWidth = max(28, targetSelectionWidth * selectionProgress)
    let currentHeight = max(24, targetSelectionHeight * selectionProgress)

    return VStack(spacing: 0) {
      Spacer(minLength: 16)

      ZStack(alignment: .topLeading) {
        // Selection Box anchored over the Notes content
        ZStack(alignment: .bottomTrailing) {
          // 1. Un-dimmed crisp cutout preview of the note
          selectionNoteCutout(width: currentWidth, height: currentHeight)

          // 2. Dashed border (marching-ants style)
          RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .strokeBorder(
              LinearGradient(
                colors: [Color.white, Color(red: 0.40, green: 0.75, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
            .shadow(color: Color.black.opacity(0.25), radius: 2)

          // 3. Eight Resize Handles
          selectionHandles(width: currentWidth, height: currentHeight)

          // 4. Dimension Badge
          HStack(spacing: 2) {
            Text("\(Int(420 * max(0.1, selectionProgress))) × \(Int(160 * max(0.1, selectionProgress)))")
              .font(.system(size: 8.5, weight: .bold, design: .monospaced))
              .lineLimit(1)
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
          .padding(5)

          // 5. Precision Crosshair Cursor tracking the growing corner
          if selectionProgress < 0.98 {
            crosshairCursor
              .offset(x: 10, y: 10)
          }
        }
        .frame(width: currentWidth, height: currentHeight)
        .contentShape(Rectangle())
        .onTapGesture {
          // Clicking anywhere triggers immediate capture
          autoCaptureTimer?.cancel()
          state.completeCaptureToQuickAccess()
        }
      }
      .frame(maxWidth: 470, alignment: .topLeading)
      .padding(.leading, 30)
      .padding(.top, 36)

      Spacer(minLength: 16)
    }
    .padding(.top, 28)
  }

  // MARK: - Selection Cutout & Handles

  private func selectionNoteCutout(width: CGFloat, height: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      Color.white

      VStack(alignment: .leading, spacing: 8) {
        Text("18 August 2026 at 19:08")
          .font(.system(size: 9, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.40))
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 2)

        Text("The beam swept across the dark water one final time. Marcus had kept the lighthouse for forty-three years, and tomorrow, automation would take over.")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
          .lineSpacing(3)

        Text("At the top, he sat in the keeper’s chair—the one he’d occupied during countless storms and ordinary mornings. The brass was worn smooth from his hands.")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
          .lineSpacing(3)
      }
      .padding(.horizontal, 14)
      .padding(.top, 6)
      .frame(width: targetSelectionWidth, alignment: .topLeading)
    }
    .frame(width: width, height: height, alignment: .topLeading)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
  }

  private func selectionHandles(width: CGFloat, height: CGFloat) -> some View {
    ZStack {
      handle.position(x: 0, y: 0)
      handle.position(x: width / 2, y: 0)
      handle.position(x: width, y: 0)
      handle.position(x: 0, y: height / 2)
      handle.position(x: width, y: height / 2)
      handle.position(x: 0, y: height)
      handle.position(x: width / 2, y: height)
      handle.position(x: width, y: height)
    }
  }

  private var handle: some View {
    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
      .fill(Color.white)
      .frame(width: 5.5, height: 5.5)
      .overlay(
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .strokeBorder(Color.black.opacity(0.50), lineWidth: 0.5)
      )
      .shadow(color: Color.black.opacity(0.25), radius: 1, y: 0.5)
  }

  private var crosshairCursor: some View {
    ZStack {
      Circle()
        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.2)
        .frame(width: 16, height: 16)
        .background(Circle().fill(Color.black.opacity(0.25)))

      Image(systemName: "plus")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
    }
    .shadow(color: Color.black.opacity(0.40), radius: 2, y: 1)
  }

  // MARK: - Toast Notification

  private func toastNotification(_ message: String) -> some View {
    VStack {
      Spacer()
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.green)
        Text(message)
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

  private func showToast(_ text: String) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      feedbackToast = text
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        if self.feedbackToast == text {
          self.feedbackToast = nil
        }
      }
    }
  }
}
