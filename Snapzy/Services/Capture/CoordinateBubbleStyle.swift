//
//  CoordinateBubbleStyle.swift
//  Snapzy
//
//  Shared visual style for the small coordinate/size "bubble" tooltips shown during area
//  selection — used by both `AreaSelectionOverlayView` (plain area screenshot) and
//  `InlineAreaMagnifierHostView` (screenshot-and-annotate's coordinate bubble). Kept in one
//  place so the two entry points can't drift out of sync with each other again: this pairing
//  went from a translucent/no-background label with a hairline shadow (hard to read against
//  some backdrops) to a solid dark pill, per user feedback comparing the two side by side.
//

import AppKit

enum CoordinateBubbleStyle {
  static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
  static let textColor = NSColor.white
  static let backgroundColor = NSColor.black.withAlphaComponent(0.75)
  static let cornerRadius: CGFloat = 4
  static let horizontalInset: CGFloat = 4
  static let verticalInset: CGFloat = 2
}
