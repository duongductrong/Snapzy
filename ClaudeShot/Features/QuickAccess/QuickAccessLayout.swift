//
//  QuickAccessLayout.swift
//  ClaudeShot
//
//  Centralized layout constants for QuickAccess panel
//

import Foundation

/// Centralized layout constants for QuickAccess panel
/// Single source of truth for dimensions used by Manager and StackView
enum QuickAccessLayout {
  /// Width of panel content area (matches card container width)
  static let cardWidth: CGFloat = 180

  /// Height of each card slot in the panel
  static let cardHeight: CGFloat = 112

  /// Vertical spacing between cards
  static let cardSpacing: CGFloat = 8

  /// Padding around the card stack (12pt for shadow clearance: radius 8 + y-offset 4)
  static let containerPadding: CGFloat = 12
}
