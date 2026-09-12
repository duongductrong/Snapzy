//
//  RadiusTokens.swift
//  Snapzy
//
//  Corner-radius scale. Roundness is a function of control height, not of a t-shirt size.
//

import SwiftUI

// MARK: - Radius

/// The app's corner-radius vocabulary.
///
/// Split in two tiers, because they answer different questions:
///
/// - **Controls** — how round should a 28pt icon button be? Proportional: a fixed radius applied
///   across sizes makes small controls look like circles and large ones like boxes. Every control
///   token sits near `0.36 × height`, so a 24pt chip and a 32pt button read as the same family.
///   Ask `control(forHeight:)` rather than picking a token by eye.
/// - **Containers** — how round should a card be? Not proportional; a 400pt-tall inspector does
///   not want a 144pt radius. These are semantic, fixed values.
///
/// ### Shape families
///
/// Radius is only half the system. The shape a control takes says what kind of control it is:
///
/// - `Capsule` — terminal text actions (`Done`, `Save As`, `Apply`) and selection tracks
///   (the segmented control and its sliding indicator). The pill *is* the "this commits" signal.
/// - `RoundedRectangle(cornerRadius: Radius.control(forHeight:), style: .continuous)` — every
///   other interactive control: icon buttons, toggle chips, selects, ratio buttons, fields.
/// - `Circle` — only where the content is inherently round (colour swatches, radio dots).
///
/// A square icon button is deliberately *not* promoted to a capsule: at 28×28 a capsule is a
/// circle, which reads as a different control class (destructive/media transport) and loses the
/// glyph's optical alignment. `controlM` closes most of the gap to the neighbouring `Done` pill
/// while keeping the button legibly rectangular.
///
/// Always pass `style: .continuous`. At an identical radius, circular corners read squarer —
/// the curvature starts abruptly instead of easing in — so mixing the two styles reintroduces
/// exactly the inconsistency this scale exists to remove. `rect(_:)` pins it for you.
enum Radius {

  // MARK: Controls (proportional — ~0.36 × height)

  /// h ≤ 19 — keycaps, inline badges, mini toggles.
  static let controlXS: CGFloat = 6
  /// h 20–25 — property-bar chips, segment buttons, small selects.
  static let controlS: CGFloat = 8
  /// h 26–30 — toolbar and bottom-bar icon buttons, selects, text fields.
  static let controlM: CGFloat = 10
  /// h 31–36 — recording toolbar buttons, prominent actions.
  static let controlL: CGFloat = 12
  /// h ≥ 37 — oversized touch targets and action tiles.
  static let controlXL: CGFloat = 14

  /// The control ramp, ascending. `control(forHeight:)` snaps to the nearest entry.
  static let controlRamp: [CGFloat] = [controlXS, controlS, controlM, controlL, controlXL]

  /// Ratio the ramp is tuned against. Below ~0.30 a control reads square; above ~0.42 it starts
  /// reading as a pill, at which point use `Capsule` deliberately instead of a large radius.
  static let controlRoundness: CGFloat = 0.36

  // MARK: Containers (semantic — fixed)

  /// Badges, keycap plates, hairline frames, tiny colour-sample outlines.
  static let ornament: CGFloat = 4
  /// Grid thumbnails, preset tiles, inline previews.
  static let tile: CGFloat = 8
  /// Cards, list rows, floating bars.
  static let card: CGFloat = 14
  /// Popovers, inspectors, sheets.
  static let panel: CGFloat = 20
  /// Window backdrops.
  static let window: CGFloat = 26

  // MARK: Lookup

  /// Radius for an interactive control of the given height.
  ///
  /// Snaps `height × controlRoundness` to the nearest ramp entry, so call sites state the fact
  /// they already know — the control's height — instead of hand-picking a token and drifting.
  /// Ties resolve downward: at the boundary the tighter corner is the safer default, because a
  /// glyph that is slightly under-rounded still reads as a button while an over-rounded one
  /// starts colliding with the capsule family.
  static func control(forHeight height: CGFloat) -> CGFloat {
    let target = height * controlRoundness
    guard let first = controlRamp.first else { return controlM }
    return controlRamp.dropFirst().reduce(first) { best, candidate in
      abs(candidate - target) < abs(best - target) ? candidate : best
    }
  }

  /// `RoundedRectangle` with `.continuous` corners pinned.
  static func rect(_ radius: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
  }

  /// `RoundedRectangle` sized for an interactive control of the given height.
  static func controlRect(forHeight height: CGFloat) -> RoundedRectangle {
    rect(control(forHeight: height))
  }
}

// MARK: - Shared Control Metrics

/// Heights the shared chrome is built at.
///
/// These live next to `Radius` so a control's height and its roundness cannot drift apart —
/// changing a height here moves the radius with it.
enum ControlMetrics {
  /// Toolbar and bottom-bar icon buttons (`ToolbarButton`, `BottomBarButton`).
  static let toolbarButton: CGFloat = 28
  /// Compact property-bar chips and segments.
  static let propertyChip: CGFloat = 24
  /// Bottom-bar pills: zoom select, mode toggle, drag handle.
  static let bottomBarControl: CGFloat = 28
}
