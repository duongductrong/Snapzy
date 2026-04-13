//
//  QuickAccessPosition.swift
//  Snapzy
//
//  Screen corner positions for quick access panel placement
//

import AppKit
import Foundation

/// Screen corner positions for quick access screenshot panel
enum QuickAccessPosition: String, CaseIterable, Codable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight

  /// Calculate origin point for panel placement
  func calculateOrigin(for size: CGSize, on screen: NSScreen, padding: CGFloat = 20) -> CGPoint {
    let frame = screen.visibleFrame

    switch self {
    case .topLeft:
      return CGPoint(x: frame.minX + padding, y: frame.maxY - size.height - padding)
    case .topRight:
      return CGPoint(x: frame.maxX - size.width - padding, y: frame.maxY - size.height - padding)
    case .bottomLeft:
      return CGPoint(x: frame.minX + padding, y: frame.minY + padding)
    case .bottomRight:
      return CGPoint(x: frame.maxX - size.width - padding, y: frame.minY + padding)
    }
  }

  /// Display name for UI
  var displayName: String {
    switch self {
    case .topLeft: return L10n.KeystrokePosition.topLeft
    case .topRight: return L10n.KeystrokePosition.topRight
    case .bottomLeft: return L10n.KeystrokePosition.bottomLeft
    case .bottomRight: return L10n.KeystrokePosition.bottomRight
    }
  }

  /// Check if position is on left side of screen
  var isLeftSide: Bool {
    self == .topLeft || self == .bottomLeft
  }

  /// Create position from side preference
  static func fromSide(_ isLeft: Bool, preferTop: Bool = false) -> QuickAccessPosition {
    if isLeft {
      return preferTop ? .topLeft : .bottomLeft
    } else {
      return preferTop ? .topRight : .bottomRight
    }
  }

  // MARK: - Animation Support

  /// Calculate off-screen origin for slide-in animation
  /// Panel starts off-screen and slides into view from the edge
  func offscreenOrigin(for size: CGSize, on screen: NSScreen, padding: CGFloat = 20) -> CGPoint {
    let frame = screen.visibleFrame
    let offscreenMargin: CGFloat = 50  // Extra margin to ensure fully off-screen

    switch self {
    case .topLeft:
      return CGPoint(
        x: frame.minX - size.width - offscreenMargin,
        y: frame.maxY - size.height - padding
      )
    case .topRight:
      return CGPoint(
        x: frame.maxX + offscreenMargin,
        y: frame.maxY - size.height - padding
      )
    case .bottomLeft:
      return CGPoint(
        x: frame.minX - size.width - offscreenMargin,
        y: frame.minY + padding
      )
    case .bottomRight:
      return CGPoint(
        x: frame.maxX + offscreenMargin,
        y: frame.minY + padding
      )
    }
  }

  /// Swipe dismiss direction based on position (toward nearest edge)
  var dismissDirection: CGFloat {
    isLeftSide ? -1 : 1
  }
}
