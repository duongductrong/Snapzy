//
//  LiquidGlassControlChrome.swift
//  Snapzy
//
//  Glass chrome for compact property-bar controls — one treatment, one hover rule, one hit target.
//

import SwiftUI

// MARK: - Emphasis

/// How hard the chrome has to work to stay legible.
///
/// The substrate is what Liquid Glass samples to decide whether it resolves light or dark, so a
/// control that floats over an arbitrary screenshot or video frame needs more of it than one
/// sitting on a window backdrop we already control.
///
/// Note that `substrate` and `tint` only reach the macOS 13–15 composite. On macOS 26 the glass
/// resolves its own contrast from the real backdrop, so the job here is to stay *out of its way* —
/// do not park an opaque fill behind an overlay control to force contrast, or the glass samples
/// that fill instead of the content and renders flat.
enum LiquidGlassChromeEmphasis {
  /// Chrome on a toolbar, bottom bar, or window backdrop.
  case standard
  /// Chrome floating over user content — screenshot thumbnails, video frames, the desktop.
  case overlay

  var restingSubstrate: CGFloat {
    switch self {
    case .standard: 0.14
    case .overlay: 0.34
    }
  }

  var activeSubstrate: CGFloat {
    switch self {
    case .standard: 0.24
    case .overlay: 0.44
    }
  }

  var restingTint: CGFloat {
    switch self {
    case .standard: 0.05
    case .overlay: 0.08
    }
  }

  var activeTint: CGFloat {
    switch self {
    case .standard: 0.10
    case .overlay: 0.14
    }
  }

  /// Native glass tint.
  ///
  /// `.glassEffect` resolves light or dark from the content it samples, and it samples the
  /// *window*, not anything we draw behind the surface — a fill placed back there is simply not
  /// part of the composite it reads. That rules out the two things chrome normally reaches for:
  /// `substrate`/`tint` are macOS 13–15 composite knobs the native path ignores, and a backing
  /// veil is invisible there. The tint is the one channel `.glassEffect` honours, so overlay
  /// chrome states are expressed through it.
  ///
  /// `.overlay` chrome floats over an arbitrary capture, which may be a white document or a black
  /// terminal, so it pins the material dark rather than letting it resolve light and strand
  /// `inkOverlay`. Hover deepens the same tint: that reads as pressing into the glass, and unlike
  /// brightening it can only ever help the glyph's contrast.
  func glassTint(isActive: Bool) -> Color? {
    switch self {
    case .standard:
      nil
    case .overlay:
      .black.opacity(isActive ? Self.overlayTintActive : Self.overlayTintResting)
    }
  }

  /// Tuned against white, mid-grey and black backdrops: below ~0.30 white ink washes out over a
  /// bright screenshot, above ~0.55 the surface stops reading as glass and turns into a grey slab.
  static let overlayTintResting: Double = 0.38
  static let overlayTintActive: Double = 0.52
}

// MARK: - Modifiers

extension View {
  /// Replaces the fill-plus-stroke chrome used by compact property-bar controls with a Liquid
  /// Glass surface.
  ///
  /// Apply this to a control's *label content*, inside the `Button`. It owns its own hover state,
  /// so call sites stay declarative, and it declares an explicit hit target — a glass surface
  /// contributes no hit-testable content, so without one only the glyph responds to clicks.
  /// The default radius is the property-chip step (`Radius.controlS`). For a control at any other
  /// height, pass `Radius.control(forHeight:)` rather than a literal — roundness is proportional
  /// to height in this design system, so a fixed default silently under-rounds taller controls.
  func liquidGlassControl(
    isActive: Bool,
    cornerRadius: CGFloat = Radius.control(forHeight: ControlMetrics.propertyChip)
  ) -> some View {
    liquidGlassControl(isActive: isActive, in: Radius.rect(cornerRadius))
  }

  /// Shape-generic variant, for circular and capsule controls.
  ///
  /// Set `showsRestingSurface` when the control is the *only* affordance in its position — a
  /// button floating over a screenshot has nothing else to signal that it is clickable, so its
  /// surface has to stay lit rather than materialise on hover. Pair it with an emphasis whose
  /// `glassTint(isActive:)` moves; persistent chrome has no appear/disappear tell, and
  /// `substrate`/`tint` cannot stand in for one because `.glassEffect` ignores them.
  func liquidGlassControl<S: InsettableShape>(
    isActive: Bool,
    in shape: S,
    emphasis: LiquidGlassChromeEmphasis = .standard,
    showsRestingSurface: Bool = false
  ) -> some View {
    modifier(LiquidGlassControlChrome(
      isActive: isActive,
      shape: shape,
      emphasis: emphasis,
      showsRestingSurface: showsRestingSurface
    ))
  }

  /// Glass background for chrome buttons whose hover and active state is owned by the caller.
  ///
  /// `liquidGlassControl` tracks its own hover, which is what a self-contained property-bar
  /// control wants. Toolbar and card buttons instead derive visibility from state the parent
  /// already holds (a `ToolbarButton`'s hover, a card's selection), so they drive the surface
  /// directly through `isVisible`.
  ///
  /// Pass `isVisible: false` rather than omitting the modifier — that maps to `Glass.identity`
  /// on macOS 26+, keeping the effect in the hierarchy so nothing is inserted or removed. A
  /// conditional insert brings an implicit `.opacity` transition, which severs backdrop sampling
  /// and blows the glass out into an opaque slab.
  func liquidGlassChrome<S: InsettableShape>(
    shape: S,
    isVisible: Bool,
    isActive: Bool = false,
    emphasis: LiquidGlassChromeEmphasis = .standard,
    glassTint: Color? = nil
  ) -> some View {
    liquidGlassSurface(
      shape: shape,
      isVisible: isVisible,
      substrate: isActive ? emphasis.activeSubstrate : emphasis.restingSubstrate,
      tint: isActive ? emphasis.activeTint : emphasis.restingTint,
      highlight: .none,
      // Native glass draws its own edge; the composite path wants the rim whenever visible.
      withRimLighting: isVisible,
      isInteractive: true,
      // A caller-supplied tint is a statement about state (selected, destructive) and outranks
      // the emphasis default, which is only there to keep the material legible.
      glassTint: glassTint ?? emphasis.glassTint(isActive: isActive)
    )
    // Rule 1: glass contributes no hit-testable content, so the click target is declared here.
    .contentShape(shape)
  }
}

private struct LiquidGlassControlChrome<S: InsettableShape>: ViewModifier {
  let isActive: Bool
  let shape: S
  let emphasis: LiquidGlassChromeEmphasis
  let showsRestingSurface: Bool

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  func body(content: Content) -> some View {
    content
      .liquidGlassChrome(
        shape: shape,
        isVisible: showsGlass,
        isActive: isLit,
        emphasis: emphasis,
        glassTint: isActive ? .accentColor : nil
      )
      .onHover { hovering in
        // Disabling a hovered control never delivers an exit event, so clear it explicitly.
        withAnimation(LiquidGlassTokens.hoverSpring) {
          isHovering = isEnabled && hovering
        }
      }
      .animation(LiquidGlassTokens.hoverSpring, value: isActive)
  }

  /// Resting controls render no glass unless they asked for it. That keeps the cost of a dense
  /// property bar proportional to the one or two surfaces actually lit, not to its button count.
  private var showsGlass: Bool {
    isEnabled && (showsRestingSurface || isActive || isHovering)
  }

  /// A persistent surface still has to brighten under the pointer, so hover feeds the active
  /// substrate rather than the surface's existence.
  private var isLit: Bool {
    isActive || (showsRestingSurface && isHovering)
  }
}
