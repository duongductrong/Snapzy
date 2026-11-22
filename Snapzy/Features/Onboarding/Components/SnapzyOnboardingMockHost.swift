//
//  SnapzyOnboardingMockHost.swift
//  Snapzy
//
//  Right-column stage: a physical MacBook display hosting persistent hardware chrome (camera notch
//  & macOS menu bar) over a 120fps GPU-accelerated macOS Spaces 3D depth-parallax deck.
//

import SwiftUI

struct SnapzyOnboardingMockHost: View {
  @ObservedObject var state: SnapzyOnboardingState
  @Environment(\.accessibilityReduceMotion) private var envReduceMotion

  @State private var activeSpaceIndex: CGFloat
  /// The Space the deck last came to rest on (`-1` while the stage itself is still arriving).
  /// Until a glide lands, the departing Space stays live so it keeps moving naturally while it
  /// slides out; after that only the current Space is live.
  @State private var settledSpaceIndex: Int
  /// Every Space the current glide sweeps across, so a Space passing through the middle of a
  /// two-step jump keeps moving as it did before it was paused off-stage.
  @State private var glideRange: ClosedRange<Int>?
  @State private var settleTask: Task<Void, Never>?

  init(state: SnapzyOnboardingState) {
    self.state = state
    _activeSpaceIndex = State(initialValue: CGFloat(Self.spaceIndex(for: state.currentStep)))
    _settledSpaceIndex = State(initialValue: -1)
  }

  private var reduceMotion: Bool {
    SnapzyMotionPreferences.shared.reduceMotion || envReduceMotion
  }

  private var currentSpaceInt: Int {
    Self.spaceIndex(for: state.currentStep)
  }

  private var currentMockApp: SnapzyMockApp {
    switch state.currentStep {
    case .meetSnapzy: .notes
    case .quickAccess: .finder
    case .shortcuts: .settings
    case .permissions: .settings
    }
  }

  private static func spaceIndex(for step: SnapzyOnboardingStep) -> Int {
    switch step {
    case .meetSnapzy: 0
    case .quickAccess: 1
    case .shortcuts: 2
    case .permissions: 2
    }
  }

  private static let gutterColor = Color(red: 0.045, green: 0.050, blue: 0.065)

  private var viewportShape: SnapzyUnevenRoundedRectangle {
    SnapzyUnevenRoundedRectangle(
      cornerRadii: SnapzyCornerRadii(
        topLeading: 18,
        bottomLeading: 0,
        bottomTrailing: SnapzyOnboardingMetrics.windowRadius,
        topTrailing: 0
      )
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let stageWidth = max(1, proxy.size.width)

      ZStack(alignment: .top) {
        // Deep obsidian Spaces gutter visible cleanly between desktop cards mid-swipe
        Self.gutterColor

        // Persistent 3-Space macOS Desktop Deck: zero view-tree teardown on step switches,
        // pure GPU 120fps horizontal swipe with Mission Control depth recession & perspective tilt.
        spaceSlot(index: 0, stageWidth: stageWidth) {
          SnapzyMockAreaCaptureView(state: state, showMenuBar: false)
        }

        spaceSlot(index: 1, stageWidth: stageWidth) {
          SnapzyMockQuickAccessView(state: state, showMenuBar: false)
        }

        spaceSlot(index: 2, stageWidth: stageWidth) {
          SnapzyMockShortcutsView(state: state, showMenuBar: false)
        }

        // Cropped real-scale macOS menu bar & shifted hardware notch stay anchored while
        // Desktop Spaces glide smoothly beneath them.
        SnapzyMockMenuBar(app: currentMockApp)
          .allowsHitTesting(false)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipShape(viewportShape)
    .overlay(
      viewportShape.strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(0.24),
            Color.white.opacity(0.09),
            Color.white.opacity(0.02),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: 0.75
      )
    )
    // The stage casts its shadow from a static plate of the same shape. The stage is opaque
    // inside `viewportShape`, so the result is identical, but the blur no longer has to be
    // recomputed from the gliding Spaces on every frame.
    .background(
      viewportShape
        .fill(Self.gutterColor)
        .shadow(color: Color.black.opacity(0.38), radius: 28, x: -6, y: 8)
        .shadow(color: Color.black.opacity(0.16), radius: 6, x: -2, y: 2)
    )
    .onAppear {
      activeSpaceIndex = CGFloat(currentSpaceInt)
      // The stage arrives with the page transition (or the welcome reveal); it counts as at rest
      // once that entrance has played.
      settle(on: currentSpaceInt, after: Self.entranceSettleDelay)
    }
    .onDisappear {
      settleTask?.cancel()
      // Leaving for the wide Permissions page: there is no stage left to be in flight.
      state.isStageInFlight = false
    }
    .onChange(of: state.currentStep) { newStep in
      guard newStep != .permissions else {
        settleTask?.cancel()
        return
      }
      let target = CGFloat(Self.spaceIndex(for: newStep))
      let origin = Int(activeSpaceIndex.rounded())
      glideRange = min(origin, Int(target))...max(origin, Int(target))
      let jump = abs(target - activeSpaceIndex)
      let duration: Double
      if reduceMotion {
        duration = 0.22
        withAnimation(.easeInOut(duration: duration)) {
          activeSpaceIndex = target
        }
      } else {
        // Smooth MacBook Spaces trackpad glide with pillowy deceleration tail; slightly longer
        // sweep when jumping 2 Spaces so Space 2 visibly flows past through center.
        duration = jump > 1.5 ? 0.80 : 0.64
        withAnimation(.timingCurve(0.20, 0.0, 0.10, 1.0, duration: duration)) {
          activeSpaceIndex = target
        }
      }
      settle(on: Int(target), after: duration)
    }
  }

  /// Longest entrance the stage can arrive with: the welcome reveal (0.86s after a 0.06s delay)
  /// outlasts the page transition's spring.
  private static let entranceSettleDelay: Double = 0.95

  private func settle(on index: Int, after delay: Double) {
    settleTask?.cancel()
    settleTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      settledSpaceIndex = index
      glideRange = nil
      state.isStageInFlight = false
    }
  }

  private func spaceSlot<Content: View>(
    index: Int,
    stageWidth: CGFloat,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .environment(
        \.snapzyMockSceneIsLive,
        index == currentSpaceInt || index == settledSpaceIndex || glideRange?.contains(index) == true
      )
      .environment(
        \.snapzyMockSceneIsSettled,
        !state.isStageInFlight && index == currentSpaceInt && index == settledSpaceIndex
      )
      .allowsHitTesting(currentSpaceInt == index)
      .accessibilityHidden(currentSpaceInt != index)
      .modifier(
        MacOSSpacesParallaxModifier(
          spaceIndex: CGFloat(index),
          activeIndex: activeSpaceIndex,
          stageWidth: stageWidth,
          reduceMotion: reduceMotion
        )
      )
  }
}

// MARK: - macOS Spaces 3D Depth-Parallax Transform (Pure GPU 120fps)

/// Animates each desktop Space across the MacBook display with authentic macOS Spaces spatial
/// separation, gentle Mission-Control depth recession (`scale 1.0 → 0.935`), crisp rounded card
/// edges catching specular light in the dark gutter, and a delicate 4.8° optical perspective tilt.
/// Zero animated blurs or shadow-radius rebuilds keep ProMotion locked at 120fps.
private struct MacOSSpacesParallaxModifier: ViewModifier, Animatable {
  let spaceIndex: CGFloat
  var activeIndex: CGFloat
  let stageWidth: CGFloat
  let reduceMotion: Bool

  var animatableData: CGFloat {
    get { activeIndex }
    set { activeIndex = newValue }
  }

  func body(content: Content) -> some View {
    let delta = spaceIndex - activeIndex
    let distance = abs(delta)
    let isOffscreen = !reduceMotion && distance >= 1.18
    let t: CGFloat = reduceMotion ? 0 : min(1.0, distance)
    let isMoving = !reduceMotion && !isOffscreen && distance > 0.0005

    // 28pt dark-glass macOS Spaces gutter between desktop cards
    let gutter: CGFloat = 28
    let offsetX: CGFloat = reduceMotion ? 0 : delta * (stageWidth + gutter)

    // Smooth Mission Control depth recession + gentle optical perspective yaw
    let scale: CGFloat = 1.0 - 0.065 * t
    let clampedDelta = max(-1.0, min(1.0, delta))
    let tiltDegrees: Double = reduceMotion ? 0 : Double(-clampedDelta) * 4.8

    // Continuous rounded corners emerge only while gliding in 3D space, then lock flush at rest
    let cornerRadius: CGFloat = 14.0 * t
    let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) // radius-lint:allow — continuous 0 → 14pt Spaces card recession during glide

    let dimOpacity = Double(t) * 0.24
    let rimOpacity = Double(t) * 0.22
    let cardOpacity: Double = reduceMotion
      ? max(0.0, 1.0 - Double(distance))
      : (isOffscreen ? 0.0 : 1.0)

    // Single unified structural branch guarantees zero SwiftUI view-identity churn mid-flight
    content
      .overlay {
        if dimOpacity > 0.004 && !isOffscreen {
          Color.black.opacity(dimOpacity)
            .allowsHitTesting(false)
        }
      }
      .clipShape(cardShape)
      .overlay {
        if isMoving {
          // A solid stroke under a fixed gradient mask, faded with layer opacity: the same
          // white `rimOpacity → rimOpacity × 0.30` rim as a gradient stroke, but the changing
          // path renders as a plain shape layer instead of re-rasterizing a full-card gradient
          // on the CPU every frame.
          cardShape.strokeBorder(Color.white, lineWidth: 0.75)
            .mask(
              LinearGradient(
                colors: [Color.white, Color.white.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .opacity(rimOpacity)
            .allowsHitTesting(false)
        }
      }
      .scaleEffect(scale)
      .rotation3DEffect(
        .degrees(tiltDegrees),
        axis: (x: 0, y: 1, z: 0),
        perspective: 0.42
      )
      .offset(x: offsetX)
      .opacity(cardOpacity)
  }
}
