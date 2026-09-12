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
/// Radius is only half the system. The shape a control takes says what *class* of control it is,
/// and the app uses exactly three. Picking a shape is a semantic decision; picking its radius is
/// then automatic.
///
/// **1. `Capsule` — the pill family.** Every button that carries a label, because a label reads
/// as a pill and the pill is the app's soft, friendly action shape:
/// - terminal actions (`Done`, `Save As`, `Apply`, `Cancel` in an action row) and ordinary
///   labelled actions — `Restore`, `Continue`, `Open All Links`, `Check for Updates`, the
///   language picker, the legacy VS button styles;
/// - selects and menus that show text (the zoom picker, the pinned window's zoom menu);
/// - selection tracks (the segmented control and its sliding indicator);
/// - search fields;
/// - filter and tag pills;
/// - non-interactive status badges.
///
/// The last three are strong platform conventions, and making a badge fully round is what keeps
/// it from being mistaken for the button beside it.
///
/// **2. `Circle` — round chrome.** Reserved for:
/// - chrome floating over *user content* — Quick Access cards, the pinned-screenshot window,
///   History cards. This is the same population as `LiquidGlassChromeEmphasis.overlay`, and for
///   the same reason: a control with no toolbar around it has to read as an object in its own
///   right, and a disc does that where a squircle reads as a fragment of a missing bar;
/// - media transport (play / pause / skip);
/// - content that is inherently round (colour swatches, radio dots, step beads).
///
/// **3. `RoundedRectangle(cornerRadius: Radius.control(forHeight:), style: .continuous)` — the
/// squircle ramp.** Controls with no text to justify a pill, and the default when in doubt:
/// icon-only buttons and icon toggles, text fields that are not search (the pill belongs to
/// buttons), and stacked icon-over-text tiles that would become lozenges as capsules.
///
/// The dividing line between families 2 and 3 is *what the control sits on*, not how big it is.
/// A 28pt icon button in the Annotate toolbar is a squircle; a 28pt icon button on the pinned
/// window, floating over a screenshot, is a circle. Both are deliberate.
///
/// A square icon button inside a toolbar is deliberately *not* promoted to a capsule: it has no
/// label, and at 28×28 a capsule is a circle, which would move it into family 2 and claim it
/// floats over content. `controlM` closes most of the gap to the neighbouring `Done` pill while
/// keeping the button legibly rectangular.
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
