//
//  SnapzyMockAreaCaptureView.swift
//  Snapzy
//
//  Step 1 mockup: the Snapzy workflow as a miniature — area selection → Quick Access card →
//  Annotate window.
//

import SwiftUI

struct SnapzyMockAreaCaptureView: View {
  @ObservedObject var state: SnapzyOnboardingState
  var showMenuBar: Bool = true

  @State private var feedbackToast: String?
  @State private var selectionProgress: CGFloat = 0
  @State private var autoCaptureTimer: Task<Void, Never>?

  /// The region the simulated ⇧⌘4 drags out, in the note window's own coordinates — aligned
  /// directly over the right prose pane (clearing the 148pt sidebar and 38pt unified toolbar).
  private static let selectionOrigin = CGPoint(x: 158, y: 48)
  private static let selectionSize = CGSize(width: 344, height: 184)

  var body: some View {
    ZStack(alignment: .top) {
      SnapzyMockWallpaper(app: .notes).equatable()

      windowLayer
        .padding(.top, SnapzyMockScene.windowTopInset)
        .padding(.horizontal, SnapzyMockScene.windowInset)

      if showMenuBar {
        SnapzyMockMenuBar(app: .notes).equatable()
      }

      if state.step1Stage == .selectingArea {
        Color.black.opacity(0.34)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .transition(.opacity)
      }

      hud
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

  // MARK: - Stage

  @ViewBuilder
  private var windowLayer: some View {
    if state.step1Stage == .annotateWindowOpen {
      SnapzyMockAnnotateWindow {
        state.resetStep1Flow()
      }
      .frame(maxWidth: 540, maxHeight: 348)
      .transition(SnapzyMockScene.windowTransition)
    } else {
      SnapzyMockNotesWindow()
        .equatable()
        .frame(maxWidth: 520)
        .overlay(alignment: .topLeading) {
          if state.step1Stage == .selectingArea {
            selection
          }
        }
        .transition(.opacity)
    }
  }

  private var selection: some View {
    let size = CGSize(
      width: max(24, SnapzyMockAreaCaptureView.selectionSize.width * selectionProgress),
      height: max(20, SnapzyMockAreaCaptureView.selectionSize.height * selectionProgress)
    )

    return ZStack(alignment: .bottomTrailing) {
      // The captured region, drawn bright again inside the dimmed desktop.
      SnapzyMockSelectionCutout(size: SnapzyMockAreaCaptureView.selectionSize)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()

      Rectangle()
        .fill(.clear)
        .overlay(
          Radius.rect(Radius.ornament)
            .strokeBorder(
              Color.white.opacity(0.95),
              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
        )

      dimensionBadge
        .padding(6)

      if selectionProgress < 0.98 {
        crosshair
          .offset(x: size.width + 9, y: size.height + 9)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .contentShape(Rectangle())
    .onTapGesture {
      autoCaptureTimer?.cancel()
      state.completeCaptureToQuickAccess()
    }
    .offset(
      x: SnapzyMockAreaCaptureView.selectionOrigin.x,
      y: SnapzyMockAreaCaptureView.selectionOrigin.y
    )
    .transition(.opacity)
  }

  private var dimensionBadge: some View {
    HStack(spacing: 2) {
      Text("\(Int(Self.selectionSize.width * max(0.1, selectionProgress))) × \(Int(Self.selectionSize.height * max(0.1, selectionProgress)))")
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .lineLimit(1)

      Text("px")
        .font(.system(size: 8.5))
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(Color.black.opacity(0.78))
    .clipShape(Radius.rect(Radius.ornament))
    .overlay(
      Radius.rect(Radius.ornament)
        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
    )
  }

  private var crosshair: some View {
    ZStack {
      Circle()
        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2)
        .frame(width: 17, height: 17)
        .background(Circle().fill(Color.black.opacity(0.22)))

      Image(systemName: "plus")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
    }
    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
  }

  // MARK: - HUD

  private var hud: some View {
    VStack {
      Spacer()

      switch state.step1Stage {
      case .readyToCapture:
        SnapzyMockSceneButton(
          title: L10n.Onboarding.mockPressToCapture,
          symbol: "viewfinder"
        ) {
          state.simulateAreaCapture()
        }
        .transition(SnapzyMockScene.hudTransition)

      case .quickAccessFloating:
        quickAccessDock
          .transition(SnapzyMockScene.cardTransition)

      case .annotateWindowOpen:
        EmptyView()

      case .selectingArea:
        EmptyView()
      }

      if let toast = feedbackToast {
        toastChip(toast)
          .transition(SnapzyMockScene.hudTransition)
      }
    }
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity)
  }

  private var quickAccessDock: some View {
    HStack(alignment: .bottom, spacing: 12) {
      SnapzyMockQuickAccessCard(
        isPinned: state.isCardPinned,
        onCopy: { showToast(L10n.Onboarding.mockToastCopied) },
        onSave: { showToast(L10n.Onboarding.mockToastSaved) },
        onAnnotate: { state.openAnnotateFromQuickAccess() },
        onTogglePin: {
          state.isCardPinned.toggle()
          showToast(state.isCardPinned
            ? L10n.Onboarding.mockToastPinned
            : L10n.Onboarding.mockToastUnpinned)
        },
        onDismiss: { state.resetStep1Flow() }
      )
      .frame(maxWidth: 300)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, SnapzyMockScene.windowInset)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func toastChip(_ message: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.40))

      Text(message)
        .font(.system(size: 12, weight: .medium))
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
    .padding(.top, 10)
  }

  // MARK: - Stage machine

  private func handleStageTransition(to newStage: Step1WorkflowStage) {
    autoCaptureTimer?.cancel()
    autoCaptureTimer = nil

    if newStage == .selectingArea {
      startAutoSelectionAnimation()
    } else {
      selectionProgress = 0
    }
  }

  private func startAutoSelectionAnimation() {
    selectionProgress = 0
    withAnimation(.easeInOut(duration: 0.78)) {
      selectionProgress = 1
    }

    autoCaptureTimer = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_050_000_000)
      guard !Task.isCancelled, state.step1Stage == .selectingArea else { return }
      state.completeCaptureToQuickAccess()
    }
  }

  private func showToast(_ text: String) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      feedbackToast = text
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        if feedbackToast == text {
          feedbackToast = nil
        }
      }
    }
  }
}

// MARK: - Selection Cutout

/// The note's own prose, redrawn so the selected rectangle can sit above the dim layer.
struct SnapzyMockSelectionCutout: View {
  var size: CGSize

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.white

      VStack(alignment: .leading, spacing: 10) {
        Text("18 August 2026 at 19:08")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(SnapzyMockPalette.inkTertiary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.bottom, 1)

        Text("Keeper’s last night")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(SnapzyMockPalette.ink)

        Text(
          "The beam swept across the dark water one final time. Marcus had kept the lighthouse for "
            + "forty-three years, and tomorrow, automation would take over."
        )
        .font(.system(size: 11.5))
        .foregroundStyle(SnapzyMockPalette.ink.opacity(0.92))
        .lineSpacing(3.5)

        Text(
          "At the top, he sat in the keeper’s chair—the one he’d occupied during countless storms "
            + "and ordinary mornings. The brass was worn smooth from his hands."
        )
        .font(.system(size: 11.5))
        .foregroundStyle(SnapzyMockPalette.ink.opacity(0.92))
        .lineSpacing(3.5)
      }
      .padding(.horizontal, 10)
      .padding(.top, 4)
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }
}
