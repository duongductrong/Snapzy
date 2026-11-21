//
//  QuickAccessEdgePeekLayout.swift
//  Snapzy
//
//  Geometry for collapsed Quick Access cards that peek out of the screen
//  edge (#591). Pure so it is unit tested without windows.
//
//  Each collapsed card lives in a fixed-size window flush with the screen
//  edge. The window never resizes: rest, hover and enter/exit only move the
//  full-size card inside it (a GPU transform), so motion stays smooth.
//

import CoreGraphics

enum QuickAccessEdgePeekLayout {
  /// How much of the card shows while resting against the edge.
  static let restingVisibleWidth: CGFloat = 16
  /// How much of the card shows while the pointer is over it (preview only).
  static let hoverVisibleWidth: CGFloat = 44
  /// Room around the card for its drop shadow (matches the stack's padding).
  static let shadowInset: CGFloat = QuickAccessLayout.containerPadding
  /// Distance from the panel's top/bottom screen edge, matching the panel padding.
  static let edgePadding: CGFloat = 20
  /// Vertical gap between cards, matching the card stack.
  static let spacing: CGFloat = QuickAccessLayout.cardSpacing
  /// Share of each card that must stay uncovered when the column has to overlap.
  static let minimumVisibleShare: CGFloat = 0.25

  static func cardSize(scale: CGFloat) -> CGSize {
    let scale = max(0.1, scale)
    return CGSize(
      width: QuickAccessLayout.scaledCardWidth(scale),
      height: QuickAccessLayout.scaledCardHeight(scale)
    )
  }

  /// Vertical step between cards. Normal spacing when the column fits on
  /// screen; otherwise cards overlap like a deck so the column still fits.
  static func cardSpacing(count: Int, cardHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
    guard count > 1 else { return spacing }

    let usable = availableHeight - edgePadding * 2
    let needed = CGFloat(count) * cardHeight + CGFloat(count - 1) * spacing
    guard needed > usable else { return spacing }

    let fitted = (usable - CGFloat(count) * cardHeight) / CGFloat(count - 1)
    return max(fitted, -cardHeight * (1 - minimumVisibleShare))
  }

  /// Resting strip of each collapsed card on screen (the visible sliver), in
  /// stack order: index 0 is the top of the column, like the card stack.
  static func stripFrames(
    count: Int,
    position: QuickAccessPosition,
    visibleFrame: CGRect,
    scale: CGFloat
  ) -> [CGRect] {
    guard count > 0 else { return [] }

    let height = cardSize(scale: scale).height
    let step = cardSpacing(count: count, cardHeight: height, availableHeight: visibleFrame.height)
    let columnHeight = CGFloat(count) * height + CGFloat(count - 1) * step
    let columnTop: CGFloat
    switch position {
    case .topLeft, .topRight:
      columnTop = visibleFrame.maxY - edgePadding
    case .bottomLeft, .bottomRight:
      columnTop = visibleFrame.minY + edgePadding + columnHeight
    }

    let x = position.isLeftSide ? visibleFrame.minX : visibleFrame.maxX - restingVisibleWidth
    return (0..<count).map { index in
      let y = columnTop - CGFloat(index + 1) * height - CGFloat(index) * step
      return CGRect(x: x, y: y, width: restingVisibleWidth, height: height)
    }
  }

  /// Fixed window holding one card: flush with the screen edge, wide enough
  /// for the hover preview, padded for the shadow on the three inner sides.
  static func windowFrame(forStrip strip: CGRect, position: QuickAccessPosition) -> CGRect {
    let width = hoverVisibleWidth + shadowInset
    let x = position.isLeftSide ? strip.minX : strip.maxX - width
    return CGRect(
      x: x,
      y: strip.minY - shadowInset,
      width: width,
      height: strip.height + shadowInset * 2
    )
  }

  /// Leading x of the card inside its window so `visibleWidth` of it shows
  /// past the screen edge. Negative visible widths park it fully off screen.
  static func cardOffsetX(
    visibleWidth: CGFloat,
    windowWidth: CGFloat,
    cardWidth: CGFloat,
    isLeftSide: Bool
  ) -> CGFloat {
    isLeftSide ? visibleWidth - cardWidth : windowWidth - visibleWidth
  }

  /// Visible width used to hide the card, shadow included, while entering or leaving.
  static let hiddenVisibleWidth: CGFloat = -shadowInset
}
