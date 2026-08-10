//
//  CoordinateBubbleStyle.swift
//  Snapzy
//
//  Shared visual style for the small coordinate "bubble" tooltips shown during area
//  selection — used by both `AreaSelectionOverlayView` (plain area screenshot) and
//  `InlineAreaMagnifierHostView` (screenshot-and-annotate's coordinate bubble). Kept in one
//  place so the two entry points can't drift out of sync with each other. Matches Snapzy's
//  existing, near-native presentation (transparent background, dark text, a hairline white
//  shadow for legibility) per maintainer feedback on #466 to stay close to the built-in macOS
//  screenshot tool's look, rather than the solid dark pill this used to be.
//

import AppKit

enum CoordinateBubbleStyle {
  static let font = NSFont.systemFont(ofSize: 10, weight: .medium)
  static let textColor = NSColor(white: 0.05, alpha: 1.0)
  static let backgroundColor = NSColor.clear
  static let cornerRadius: CGFloat = 4
  static let horizontalInset: CGFloat = 4
  static let verticalInset: CGFloat = 2
  static let shadowColor = NSColor.white
  static let shadowOffset = CGSize(width: 0.5, height: -0.5)
  static let shadowRadius: CGFloat = 0.1
  static let shadowOpacity: Float = 1.0
}
