//
//  PreferencesHistoryPreview.swift
//  Snapzy
//
//  Live preview for the History tab: the top of a Mac display with the capture history in the
//  chosen style. Picking the other style sends the current surface away the way it really hides
//  and plays the incoming surface's own reveal.
//

import SwiftUI

struct HistorySettingsPreview: View {
  let style: HistoryDisplayStyle

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The surface actually on screen. It trails `style` by the length of the morph.
  @State private var shownStyle: HistoryDisplayStyle
  @State private var isRevealed = true
  /// Bumped per morph so a rapid second pick cancels the first one's entrance.
  @State private var morphToken = 0

  /// A window into the top of a 1440pt display: wide enough for the shelf's right cable anchor
  /// and the panel's control row, and both surfaces bottom out at the same line.
  private static let canvas = CGSize(width: 1000, height: 380)
  private static let menuBarHeight: CGFloat = 24
  private static let shelfTravel: CGFloat = 360
  private static let exitDuration: Double = 0.14

  init(style: HistoryDisplayStyle) {
    self.style = style
    _shownStyle = State(initialValue: style)
  }

  var body: some View {
    DisplayCornerFrame {
      GeometryReader { proxy in
        scene
          .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
          // Cover, not fit, so sub-pixel rounding never leaves a sliver of bezel.
          .scaleEffect(
            max(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height),
            anchor: .topLeading
          )
      }
      .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
    }
    .onChange(of: style) { newValue in
      morph(to: newValue)
    }
    .accessibilityHidden(true)
  }

  // MARK: - Scene

  private var scene: some View {
    ZStack(alignment: .topLeading) {
      PaintedSkyBackdrop()

      surface

      menuBar
    }
    .environment(\.colorScheme, .dark)
  }

  private var surface: some View {
    Group {
      if isRevealed {
        Group {
          switch shownStyle {
          case .hanging:
            HistoryHangingMiniature(captures: HistoryMiniatureCapture.samples, scale: 1)
              .padding(.top, Self.menuBarHeight)
          case .traditional:
            HistoryTraditionalPanelMiniature(captures: HistoryMiniatureCapture.samples, scale: 1)
              .padding(.top, Self.menuBarHeight + 4)
          }
        }
        .transition(transition(for: shownStyle))
      }
    }
    .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .top)
    // The real shelf is clipped by its own window, so it travels out from under the menu bar.
    .clipped()
  }

  /// Each style keeps its own entrance: the shelf drops as one piece, the panel springs off the bar.
  private func transition(for style: HistoryDisplayStyle) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }

    switch style {
    case .hanging:
      return .offset(y: -Self.shelfTravel)
    case .traditional:
      return .offset(y: -10)
        .combined(with: .scale(scale: 0.94, anchor: .top))
        .combined(with: .opacity)
    }
  }

  private var menuBar: some View {
    HStack(spacing: 0) {
      Image(systemName: "apple.logo")
        .font(.system(size: 13, weight: .regular))
        .frame(width: 26)

      Capsule().fill(Color.white.opacity(0.7)).frame(width: 34, height: 2)
      Capsule().fill(Color.white.opacity(0.4)).frame(width: 22, height: 2)

      Spacer(minLength: 0)

      Image(systemName: "camera.viewfinder")
        .font(.system(size: 13, weight: .medium))
        .frame(width: 30)

      Image(systemName: "wifi")
        .font(.system(size: 12, weight: .regular))
        .frame(width: 30)

      TimelineView(.everyMinute) { context in
        Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
          .font(.system(size: 12.5, weight: .medium))
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize()
      }
      .padding(.leading, 6)
      .padding(.trailing, 14)
    }
    .foregroundStyle(.white)
    .frame(height: Self.menuBarHeight)
    .background(Color.black.opacity(0.18))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.black.opacity(0.25))
        .frame(height: 0.5)
    }
  }

  // MARK: - Morph

  /// Sends the current surface away with its own exit, then reveals the other one. Cancelling a
  /// half-finished morph is safe: the newest token is the only one allowed to touch the state.
  private func morph(to next: HistoryDisplayStyle) {
    guard next != shownStyle else { return }

    // Reduce Motion drops the travel entirely — the preview just shows the other style.
    if reduceMotion {
      morphToken += 1
      shownStyle = next
      return
    }

    morphToken += 1
    let token = morphToken
    withAnimation(SnapzyMotionPreferences.shared.spec(.contentOut).animation) {
      isRevealed = false
    }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(Self.exitDuration))
      guard !Task.isCancelled, token == morphToken else { return }

      shownStyle = next
      withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
        isRevealed = true
      }
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    HistorySettingsPreview(style: .hanging)
    HistorySettingsPreview(style: .traditional)
  }
  .padding()
  .frame(width: 620)
}
