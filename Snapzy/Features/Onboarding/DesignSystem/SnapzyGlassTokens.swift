//
//  SnapzyGlassTokens.swift
//  Snapzy
//
//  Design tokens for the onboarding surface: ink, type, spacing, radii, glass and layout metrics.
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
  static let giant: CGFloat = 32
  static let hero: CGFloat = 44
}

/// The onboarding ink ramp.
///
/// Onboarding is dark-locked, so ink is white at four steps plus three surface fills. The fills
/// exist because the same `Color.white.opacity(0.07)`-style literal was written out at eleven call
/// sites with seven different values, which is how a card stops matching the card next to it.
enum SnapzyGlassInk {
  /// Headings, titles, and primary keycaps
  static let primary = Color.white
  /// Body prose and descriptions
  static let body = Color.white.opacity(0.80)
  /// Secondary text, inactive markers, labels
  static let muted = Color.white.opacity(0.58)
  /// Background structure, faint connectors, disabled text
  static let faint = Color.white.opacity(0.36)

  /// 0.5pt edges on glass. `strong` is for the edge the user is meant to find with the pointer.
  static let hairline = Color.white.opacity(0.10)
  static let hairlineStrong = Color.white.opacity(0.18)

  /// Card fills, quiet → raised → hovered.
  static let fillQuiet = Color.white.opacity(0.045)
  static let fillRaised = Color.white.opacity(0.075)
  static let fillHover = Color.white.opacity(0.105)
}

/// Onboarding's radii, aliased onto the app-wide scale in `Snapzy/Shared/Styles/RadiusTokens.swift`.
///
/// This used to be an independent fork, and it bought nothing: `control` was already
/// `Radius.controlM`, and `card` was declared at 12 but never used raw — every call site wrote
/// `card + 1` or `card + 2`, and `card + 2` is 14, which is `Radius.card`. The fork's only real
/// effect was to stop onboarding and the rest of the app from moving together.
///
/// Onboarding still has a deliberate visual language of its own — dark-locked glass, its own
/// substrate ramp in `SnapzySurfaceGlass`. Geometry is not part of that; a corner is a corner.
enum SnapzyRadius {
  static let control = Radius.controlM
  static let card = Radius.card
  static let panel = Radius.panel
  static let window = Radius.window
}

enum SnapzySurfaceGlass {
  static let baseDarkness: CGFloat = 0.28
  static let specularLineWidth: CGFloat = 0.5
  static let specularTopColor: Color = .white.opacity(0.16)
  static let specularBottomColor: Color = .white.opacity(0.04)

  /// The mock stage's edge. It is the largest lit object on screen, so its specular sweep keeps a
  /// three-stop ramp instead of the two-stop version controls use; the extra stop is what stops a
  /// 700pt panel from reading as one hard outline.
  static let stageEdgeColors: [Color] = [
    .white.opacity(0.24),
    .white.opacity(0.09),
    .white.opacity(0.02),
  ]
  static let stageEdgeWidth: CGFloat = 0.75

  static let controlSubstrateResting: CGFloat = 0.20
  static let controlSubstrateHover: CGFloat = 0.28
  static let controlSubstratePressed: CGFloat = 0.36

  static let controlStrokeResting: CGFloat = 0.08
  static let controlStrokeHover: CGFloat = 0.22

  static let fallbackSubstrateScale: CGFloat = 0.4
  static let fallbackControlSheenTop: Double = 0.10
  static let fallbackControlSheenBottom: Double = 0.02
}

/// The two shadow stacks the surface uses: whatever sits on the backdrop, and whatever floats
/// above content. Radius and offset travel together, so they are declared as one set.
enum SnapzyGlassShadow {
  static let stageColor = Color.black.opacity(0.40)
  static let stageRadius: CGFloat = 34
  static let stageY: CGFloat = 16
  static let stageAmbientColor = Color.black.opacity(0.18)
  static let stageAmbientRadius: CGFloat = 7

  static let controlColor = Color.black.opacity(0.22)
  static let controlRadius: CGFloat = 14
  static let controlY: CGFloat = 6
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
  static let gutter: CGFloat = 36
  static let railWidth: CGFloat = 420
  static let columnGap: CGFloat = 32
  static let headerHeight: CGFloat = 44
  static let footerHeight: CGFloat = 44
  /// The mock stage is the largest container on screen, so it takes the panel radius rather than
  /// the card radius used by everything inside it.
  static let stageRadius = SnapzyRadius.panel
}

/// Type ramp for a ~1280pt window.
///
/// The previous ramp was written for a much smaller canvas: 11.5pt body and 9pt labels at this
/// width read as a screenshot of a screenshot, and the checklist — the thing the user has to act
/// on — was the smallest text on the page. Body now sits at the macOS default, and the display
/// size came down so the headline stops shouting over it.
enum SnapzyOnboardingType {
  static let display: CGFloat = 31
  static let displayTracking: CGFloat = -0.7
  /// Completion and permissions headlines — a step below the per-step display.
  static let title: CGFloat = 26
  static let lede: CGFloat = 14.5
  static let sectionLabel: CGFloat = 10.5
  static let sectionTracking: CGFloat = 0.7
  static let challenge: CGFloat = 13.5
  static let body: CGFloat = 13
  static let caption: CGFloat = 12
  static let keycap: CGFloat = 10
}

/// Caches `NSApp.applicationIconImage` once on the main actor so 120Hz `Animatable` flight
/// modifiers and onboarding headers never re-query AppKit's bundle icon cache per frame.
@MainActor
enum SnapzyOnboardingIconCache {
  static let appIcon: NSImage = NSApp.applicationIconImage
}
