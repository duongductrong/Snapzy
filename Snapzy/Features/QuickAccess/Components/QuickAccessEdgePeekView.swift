//
//  QuickAccessEdgePeekView.swift
//  Snapzy
//
//  A collapsed Quick Access card peeking out of the screen edge (#591). It is
//  the same card surface as the stack, slid mostly past the edge. Hover slides
//  more of it into view; click restores the card to the stack.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class QuickAccessEdgePeekModel: ObservableObject {
  enum Phase: Equatable {
    /// Fully past the edge (before entering, after leaving).
    case hidden
    /// Resting sliver against the edge.
    case resting
  }

  @Published var item: QuickAccessItem
  @Published var isLeftSide: Bool
  @Published var scale: CGFloat
  @Published var phase: Phase = .hidden
  @Published var isHovered = false
  /// 0...1 progress of a live two-finger move up that will restore the card.
  @Published var restoreSwipeProgress: CGFloat = 0

  init(item: QuickAccessItem, isLeftSide: Bool, scale: CGFloat) {
    self.item = item
    self.isLeftSide = isLeftSide
    self.scale = scale
  }

  var visibleWidth: CGFloat {
    switch phase {
    case .hidden:
      return QuickAccessEdgePeekLayout.hiddenVisibleWidth
    case .resting:
      return isHovered
        ? QuickAccessEdgePeekLayout.hoverVisibleWidth
        : QuickAccessEdgePeekLayout.restingVisibleWidth
    }
  }

  // Explicit and nonisolated: the synthesized main-actor deinit hops through the
  // back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}
}

struct QuickAccessEdgePeekView: View {
  @ObservedObject var model: QuickAccessEdgePeekModel
  let onHover: (Bool) -> Void
  let onRestore: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// One spring drives enter, hover and exit, so interrupted motions blend.
  static let motion = Animation.spring(response: 0.32, dampingFraction: 0.86)
  /// Extra scale at the end of a restore move's travel.
  static let restoreGrowth: CGFloat = 0.08

  var body: some View {
    let cardSize = QuickAccessEdgePeekLayout.cardSize(scale: model.scale)
    let inset = QuickAccessEdgePeekLayout.shadowInset
    let windowWidth = QuickAccessEdgePeekLayout.hoverVisibleWidth + inset

    ZStack(alignment: .topLeading) {
      QuickAccessCardThumbnail(image: model.item.thumbnail, size: cardSize)
        .frame(width: cardSize.width, height: cardSize.height)
        .quickAccessCardSurface()
        // Moving two fingers up grows the card out of the edge with the fingers.
        .scaleEffect(
          reduceMotion ? 1 : 1 + Self.restoreGrowth * model.restoreSwipeProgress,
          anchor: model.isLeftSide ? .leading : .trailing
        )
        .overlay(alignment: model.isLeftSide ? .trailing : .leading) {
          restoreHint
        }
        .onHover(perform: handleHover)
        .onTapGesture(perform: onRestore)
        .help(L10n.QuickAccess.restoreCollapsedCard)
        .accessibilityElement()
        .accessibilityLabel(L10n.QuickAccess.restoreCollapsedCard)
        .accessibilityAddTraits(.isButton)
        .offset(
          x: reduceMotion ? restingOffset(cardSize: cardSize, windowWidth: windowWidth) : offset(
            cardSize: cardSize,
            windowWidth: windowWidth
          ),
          y: inset
        )
        .opacity(reduceMotion && model.phase == .hidden ? 0 : 1)
        .animation(reduceMotion ? QuickAccessAnimations.reducedFade : Self.motion, value: model.visibleWidth)
    }
    .frame(width: windowWidth, height: cardSize.height + inset * 2, alignment: .topLeading)
  }

  /// Chevron pointing back into the screen, shown inside the revealed sliver.
  private var restoreHint: some View {
    Image(systemName: model.isLeftSide ? "chevron.right" : "chevron.left")
      .font(.system(size: 11, weight: .bold))
      .foregroundColor(.white)
      .frame(width: QuickAccessEdgePeekLayout.hoverVisibleWidth, height: 28)
      .shadow(color: .black.opacity(0.45), radius: 2)
      .opacity(model.isHovered ? 1 : 0)
      .animation(QuickAccessAnimations.hoverOverlay, value: model.isHovered)
      .allowsHitTesting(false)
  }

  private func handleHover(_ hovering: Bool) {
    guard model.isHovered != hovering else { return }
    model.isHovered = hovering
    onHover(hovering)
  }

  private func offset(cardSize: CGSize, windowWidth: CGFloat) -> CGFloat {
    QuickAccessEdgePeekLayout.cardOffsetX(
      visibleWidth: model.visibleWidth,
      windowWidth: windowWidth,
      cardWidth: cardSize.width,
      isLeftSide: model.isLeftSide
    )
  }

  private func restingOffset(cardSize: CGSize, windowWidth: CGFloat) -> CGFloat {
    QuickAccessEdgePeekLayout.cardOffsetX(
      visibleWidth: model.isHovered
        ? QuickAccessEdgePeekLayout.hoverVisibleWidth
        : QuickAccessEdgePeekLayout.restingVisibleWidth,
      windowWidth: windowWidth,
      cardWidth: cardSize.width,
      isLeftSide: model.isLeftSide
    )
  }
}

/// Clicks on a non-activating panel must work while another app is active.
final class QuickAccessEdgePeekHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
