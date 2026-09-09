//
//  SnapzyGlassTokens.swift
//  Snapzy
//
//  Design tokens for liquid glass surfaces, dark theme typography, and layout metrics.
//

import AppKit
import SwiftUI

enum SnapzySpace {
  static let xxs: CGFloat = 2
  static let xs: CGFloat = 4
  static let sm: CGFloat = 6
  static let md: CGFloat = 8
  static let lg: CGFloat = 10
  static let xl: CGFloat = 12
  static let xxl: CGFloat = 16
  static let xxxl: CGFloat = 20
  static let huge: CGFloat = 24
}

enum SnapzyGlassInk {
  /// Headings, titles, and primary keycaps
  static let primary = Color.white
  /// Body prose and descriptions
  static let body = Color.white.opacity(0.72)
  /// Secondary text, inactive markers, overlines
  static let muted = Color.white.opacity(0.46)
  /// Background structure, faint connectors, borders
  static let faint = Color.white.opacity(0.30)
}

enum SnapzyRadius {
  static let control: CGFloat = 10
  static let card: CGFloat = 12
  static let surface: CGFloat = 26
  static let window: CGFloat = 28
  static func round(_ size: CGFloat) -> CGFloat { size / 2 }
}

enum SnapzySurfaceGlass {
  static let baseDarkness: CGFloat = 0.28
  static let specularLineWidth: CGFloat = 0.5
  static let specularTopColor: Color = .white.opacity(0.16)
  static let specularBottomColor: Color = .white.opacity(0.04)

  static let controlSubstrateResting: CGFloat = 0.20
  static let controlSubstrateHover: CGFloat = 0.28
  static let controlSubstratePressed: CGFloat = 0.36

  static let controlStrokeResting: CGFloat = 0.08
  static let controlStrokeHover: CGFloat = 0.22

  static let fallbackSubstrateScale: CGFloat = 0.4
  static let fallbackControlSheenTop: Double = 0.10
  static let fallbackControlSheenBottom: Double = 0.02
}

enum SnapzyOnboardingMetrics {
  static let windowRadius: CGFloat = 28
  static let screenFill: CGFloat = 0.92
  static let screenMargin: CGFloat = 16
  static let minSize = CGSize(width: 1060, height: 720)
  static let maxSize = CGSize(width: 1280, height: 826)
  static let gutter: CGFloat = 34
  static let railWidth: CGFloat = 404
  static let columnGap: CGFloat = 40
  static let headerHeight: CGFloat = 40
  static let footerHeight: CGFloat = 44
  static let mockRadius: CGFloat = 12
}

enum SnapzyOnboardingType {
  static let overline: CGFloat = 9.5
  static let display: CGFloat = 32.5
  static let lede: CGFloat = 14.0
  static let sectionLabel: CGFloat = 9.0
  static let challenge: CGFloat = 13.0
  static let body: CGFloat = 11.5
  static let caption: CGFloat = 11.0
  static let keycap: CGFloat = 9.0
}
