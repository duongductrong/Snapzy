//
//  TranslationCardMotion.swift
//  Snapzy
//
//  Motion for the Snip to Translate window ("read → resolve"):
//  - While translating, the source text sits dimmed in the text well and a soft band of light
//    sweeps across it, as if being read; the well's rim carries a faint, slowly turning
//    multi-hue light. No spinner.
//  - When the translation arrives, the same well changes content: the source blurs away and the
//    translation resolves line by line (blur → sharp, rising a few points, staggered). macOS 15+
//    uses a `TextRenderer`; earlier systems resolve the block as a whole. Only content animates:
//    the layout changes at once and the window's animated height change does the growing, so
//    nothing is drawn outside the well mid-transition.
//  - Reduce Motion: no sweep, no rim, no per-line motion; plain cross-fades.
//

import SwiftUI

enum TranslationCardMotion {
  /// Content swap inside the well and the window's height change share this length.
  static let revealDuration: Double = 0.42
  /// Per-line delay of the line-by-line reveal.
  static let lineStagger: Double = 0.07
  /// One line's own resolve time.
  static let lineDuration: Double = 0.38
  /// One pass of the reading sweep, followed by a short rest.
  static let sweepDuration: Double = 1.7
  static let sweepRest: Double = 0.5
  /// One turn of the rim light.
  static let rimTurnDuration: Double = 5.0

  /// Rim light hues (cool → warm → cool, so the turn has no seam).
  static let rimHues: [Color] = [
    Color(red: 0.36, green: 0.72, blue: 1.00),
    Color(red: 0.62, green: 0.48, blue: 1.00),
    Color(red: 1.00, green: 0.45, blue: 0.70),
    Color(red: 1.00, green: 0.66, blue: 0.36),
    Color(red: 0.36, green: 0.72, blue: 1.00),
  ]

  static let reveal: Animation = .timingCurve(0.2, 0.9, 0.25, 1, duration: revealDuration)

  /// Notes, the footer and other parts that arrive with the result follow the text by a beat.
  static func lateEntrance(reduceMotion: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity.animation(.easeOut(duration: 0.2)) }
    return .asymmetric(
      insertion: .opacity
        .combined(with: .offset(y: 6))
        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.4).delay(0.16)),
      removal: .opacity.animation(.easeOut(duration: 0.12))
    )
  }

  /// The dimmed source leaving the well.
  static func sourceExit(reduceMotion: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity.animation(.easeOut(duration: 0.15)) }
    return .asymmetric(
      insertion: .opacity.animation(.easeOut(duration: 0.2)),
      removal: .modifier(
        active: BlurFadeModifier(radius: 8, opacity: 0, offsetY: -4),
        identity: BlurFadeModifier(radius: 0, opacity: 1, offsetY: 0)
      )
      .animation(.easeIn(duration: 0.18))
    )
  }
}

struct BlurFadeModifier: ViewModifier {
  let radius: CGFloat
  let opacity: Double
  let offsetY: CGFloat

  func body(content: Content) -> some View {
    content
      .blur(radius: radius)
      .opacity(opacity)
      .offset(y: offsetY)
  }
}

// MARK: - Reading state

/// The source text, dimmed, with a band of light sweeping across it while it is translated.
struct TranslationReadingText: View {
  let text: String
  let font: Font
  let lineSpacing: CGFloat
  /// Lines shown before the text fades out at the bottom.
  var lineLimit = 6

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let base = Text(text)
      .font(font)
      .lineSpacing(lineSpacing)
      .lineLimit(lineLimit)
      .frame(maxWidth: .infinity, alignment: .leading)
      .multilineTextAlignment(.leading)

    base
      .foregroundStyle(LiquidGlassTokens.inkMuted.opacity(0.55))
      .overlay {
        if !reduceMotion {
          TimelineView(.animation) { context in
            base
              .foregroundStyle(LiquidGlassTokens.inkPrimary)
              .mask { sweepMask(at: context.date) }
          }
        }
      }
      // Long source text trails off instead of ending on a hard edge.
      .mask(
        LinearGradient(
          stops: [.init(color: .black, location: 0.78), .init(color: .black.opacity(0.25), location: 1)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.Translate.translating)
  }

  /// A soft diagonal band moving leading → trailing; eased so it glides in and out.
  private func sweepMask(at date: Date) -> some View {
    let cycle = TranslationCardMotion.sweepDuration + TranslationCardMotion.sweepRest
    let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
    let raw = min(t / TranslationCardMotion.sweepDuration, 1)
    let eased = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
    let width = 0.38
    let center = -width + eased * (1 + 2 * width)
    let visible = raw < 1
    return LinearGradient(
      stops: [
        .init(color: .clear, location: max(0, min(1, center - width))),
        .init(color: .white.opacity(visible ? 0.9 : 0), location: max(0, min(1, center))),
        .init(color: .clear, location: max(0, min(1, center + width))),
      ],
      startPoint: UnitPoint(x: 0, y: 0.2),
      endPoint: UnitPoint(x: 1, y: 0.8)
    )
  }
}

/// Faint multi-hue light running around the well's rim while translating.
struct TranslationReadingRim<S: InsettableShape>: View {
  let shape: S

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private var hues: [Color] { TranslationCardMotion.rimHues }


  var body: some View {
    if reduceMotion {
      shape.strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
    } else {
      TimelineView(.animation) { context in
        let turn = context.date.timeIntervalSinceReferenceDate
          .truncatingRemainder(dividingBy: TranslationCardMotion.rimTurnDuration)
          / TranslationCardMotion.rimTurnDuration
        let gradient = AngularGradient(colors: hues, center: .center, angle: .degrees(turn * 360))
        ZStack {
          // Soft glow under a crisp hairline.
          shape.strokeBorder(gradient, lineWidth: 3)
            .blur(radius: 5)
            .opacity(colorScheme == .dark ? 0.45 : 0.35)
          shape.strokeBorder(gradient, lineWidth: 1)
            .opacity(colorScheme == .dark ? 0.7 : 0.6)
        }
      }
      .allowsHitTesting(false)
    }
  }
}

// MARK: - Line-by-line resolve (macOS 15+)

/// Draws each line of the translation from blurred, faded and slightly lowered to sharp, one
/// line after another. `elapsed` is animated from 0 to `totalDuration` by the transition.
@available(macOS 15.0, *)
struct TranslationLineRevealRenderer: TextRenderer, Animatable {
  var elapsed: TimeInterval
  var totalDuration: TimeInterval

  var animatableData: Double {
    get { elapsed }
    set { elapsed = newValue }
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for (index, line) in layout.enumerated() {
      let start = Double(index) * TranslationCardMotion.lineStagger
      let raw = max(0, min(1, (elapsed - start) / TranslationCardMotion.lineDuration))
      // Ease-out cubic: quick to arrive, gentle to settle.
      let progress = 1 - pow(1 - raw, 3)
      var lineContext = context
      lineContext.opacity = progress
      if progress < 1 {
        lineContext.addFilter(.blur(radius: (1 - progress) * 7))
        lineContext.translateBy(x: 0, y: (1 - progress) * 6)
      }
      lineContext.draw(line, options: .disablesSubpixelQuantization)
    }
  }
}

/// The translation, resolving line by line when it appears (macOS 15+, unless Reduce Motion);
/// a block resolve otherwise. It runs its own animation on appear, so the card's layout can
/// change without animation (the window's height change does the growing).
struct TranslationResolvingText: View {
  let text: String
  let font: Font
  let lineSpacing: CGFloat
  let layoutDirection: LayoutDirection

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var elapsed: Double = 0
  @State private var isSettled = false

  private var totalDuration: Double {
    TranslationCardMotion.lineDuration
      + Double(max(0, TranslationCardView.estimatedLineCount(text) - 1)) * TranslationCardMotion.lineStagger
  }

  var body: some View {
    styled
      .modifier(LineRevealModifier(elapsed: elapsed, totalDuration: totalDuration, isActive: !isSettled && !reduceMotion))
      .modifier(BlockRevealModifier(isActive: !isSettled && !reduceMotion && !Self.supportsLineReveal))
      .opacity(reduceMotion && !isSettled ? 0 : 1)
      .onAppear(perform: reveal)
  }

  private var styled: some View {
    Text(text)
      .font(font)
      .lineSpacing(lineSpacing)
      .foregroundStyle(LiquidGlassTokens.inkPrimary)
      // Selectable text is drawn by AppKit and skips `TextRenderer`, so selection turns on once
      // the reveal has settled (both paths draw the same glyphs; the switch is invisible).
      .modifier(SelectableWhen(isEnabled: isSettled))
      .frame(maxWidth: .infinity, alignment: .leading)
      .multilineTextAlignment(.leading)
      .environment(\.layoutDirection, layoutDirection)
  }

  private static var supportsLineReveal: Bool {
    if #available(macOS 15.0, *) { return true }
    return false
  }

  private func reveal() {
    if reduceMotion {
      withAnimation(.easeOut(duration: 0.2)) { isSettled = true }
      return
    }
    if Self.supportsLineReveal {
      withAnimation(.linear(duration: totalDuration)) { elapsed = totalDuration }
      // Drop the custom renderer once every line has settled.
      DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.05) { isSettled = true }
    } else {
      withAnimation(TranslationCardMotion.reveal) { isSettled = true }
    }
  }
}

private struct SelectableWhen: ViewModifier {
  let isEnabled: Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content.textSelection(.enabled)
    } else {
      content.textSelection(.disabled)
    }
  }
}

private struct LineRevealModifier: ViewModifier {
  let elapsed: Double
  let totalDuration: Double
  let isActive: Bool

  func body(content: Content) -> some View {
    if #available(macOS 15.0, *), isActive {
      content.textRenderer(TranslationLineRevealRenderer(elapsed: elapsed, totalDuration: totalDuration))
    } else {
      content
    }
  }
}

/// macOS 13–14: the whole block resolves (blur → sharp, rising) instead of line by line.
private struct BlockRevealModifier: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .blur(radius: isActive ? 7 : 0)
      .opacity(isActive ? 0 : 1)
      .offset(y: isActive ? 6 : 0)
  }
}
