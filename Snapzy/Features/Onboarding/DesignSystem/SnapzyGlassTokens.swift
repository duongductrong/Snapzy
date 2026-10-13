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

/// Onboarding's radii, aliased onto the app-wide scale in `Snapzy/Shared/Styles/RadiusTokens.swift`.
///
/// This used to be an independent fork, and it bought nothing: `control` was already
/// `Radius.controlM`, and `card` was declared at 12 but never used raw — every call site wrote
/// `card + 1` or `card + 2`, and `card + 2` is 14, which is `Radius.card`. The fork's only real
/// effect was to stop onboarding and the rest of the app from moving together. `surface`,
/// `round(_:)` and `SnapzyOnboardingMetrics.mockRadius` had no call sites at all and are gone.
///
/// Onboarding still has a deliberate visual language of its own — dark-locked glass, its own
/// substrate ramp in `SnapzySurfaceGlass`. Geometry is not part of that; a corner is a corner.
enum SnapzyRadius {
  static let control = Radius.controlM
  static let card = Radius.card
  static let window = Radius.window
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
  /// Was 28 against the app's 26. The onboarding window genuinely is larger than any other
  /// Snapzy surface, but a 2pt delta reads as a fork rather than a decision, so it now shares
  /// `Radius.window` with every other window backdrop.
  static let windowRadius = SnapzyRadius.window
  static let screenFill: CGFloat = 0.92
  static let screenMargin: CGFloat = 16
  static let minSize = CGSize(width: 1060, height: 720)
  static let maxSize = CGSize(width: 1280, height: 826)
  static let gutter: CGFloat = 34
  static let railWidth: CGFloat = 404
  static let columnGap: CGFloat = 40
  static let headerHeight: CGFloat = 40
  static let footerHeight: CGFloat = 44
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
