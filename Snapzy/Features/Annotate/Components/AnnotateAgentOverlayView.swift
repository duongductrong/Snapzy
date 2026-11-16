//
//  AnnotateAgentOverlayView.swift
//  Snapzy
//
//  What the canvas shows while the AI prompt works, in the same light as Auto
//  Translate:
//  - reading: a faint veil and the diagonal sweep over the image;
//  - acting: the veil eases off; an agent "cursor" (a small multi-hue light) flies to
//    each target, the target lights up with the rim, and every new or edited
//    annotation flashes briefly as it lands.
//  Reduce Motion: no sweep, the cursor jumps, marks only fade.
//

import SwiftUI

struct AnnotateAgentOverlayView: View {
  @ObservedObject var agent: AnnotateAgentController
  let scale: CGFloat
  let canvasBounds: CGRect

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var phaseStart = Date()

  private var isVisible: Bool {
    agent.isRunning || !agent.marks.isEmpty
  }

  var body: some View {
    Group {
      if isVisible {
        TimelineView(.animation(paused: false)) { timeline in
          Canvas { context, size in
            draw(in: &context, size: size, now: timeline.date)
          }
        }
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
      }
    }
    .allowsHitTesting(false)
    .onChange(of: agent.phase) { _ in phaseStart = Date() }
    .accessibilityHidden(true)
  }

  // MARK: Drawing

  private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
    let fullRect = CGRect(origin: .zero, size: size)
    let isDark = colorScheme == .dark
    let elapsed = now.timeIntervalSince(phaseStart)

    // Veil: strongest while reading, then a whisper while acting, gone afterwards.
    let veilTarget: Double
    switch agent.phase {
    case .reading: veilTarget = isDark ? 0.2 : 0.1
    case .acting: veilTarget = isDark ? 0.08 : 0.04
    case .idle: veilTarget = 0
    }
    let veilIn = reduceMotion ? 1 : min(elapsed / 0.35, 1)
    if veilTarget > 0 {
      context.fill(Path(fullRect), with: .color(.black.opacity(veilTarget * veilIn)))
    }
    if agent.phase == .reading, !reduceMotion {
      AnnotateAIOverlayPainter.drawSweep(in: &context, rect: fullRect, now: now, phaseOffset: 0, strength: 0.16 * veilIn)
    }

    for mark in agent.marks {
      drawMark(mark, in: &context, now: now, isDark: isDark)
    }

    if agent.isRunning, let point = agent.currentCursorPoint(at: reduceMotion ? .distantFuture : now) {
      drawCursor(at: displayPoint(point), in: &context, now: now)
    }
  }

  private func drawMark(_ mark: AnnotateAgentController.Mark, in context: inout GraphicsContext, now: Date, isDark: Bool) {
    let age = now.timeIntervalSince(mark.date)
    let life = AnnotateAgentController.markLifetime
    guard age >= 0, age < life else { return }
    let fade = 1 - easeIn(age / life)
    var rect = displayRect(mark.rect).insetBy(dx: -4, dy: -4)
    guard rect.width > 1, rect.height > 1 else { return }

    switch mark.kind {
    case .target:
      let shape = Path(roundedRect: rect, cornerRadius: min(rect.height * 0.2, 8), style: .continuous)
      AnnotateAIOverlayPainter.drawRim(
        in: &context, shape: shape, rect: rect, now: now, strength: fade * 0.8,
        reduceMotion: reduceMotion, isDark: isDark
      )
    case .added:
      // Lands with a small settle: grows from 96% to 100% while the glow fades.
      if !reduceMotion {
        let settle = 0.96 + 0.04 * easeOut(min(age / 0.28, 1))
        rect = rect.insetBy(dx: rect.width * (1 - settle) / 2, dy: rect.height * (1 - settle) / 2)
      }
      let shape = Path(roundedRect: rect, cornerRadius: min(rect.height * 0.2, 8), style: .continuous)
      var glow = context
      glow.opacity = fade * (isDark ? 0.22 : 0.16)
      glow.fill(shape, with: .linearGradient(
        Gradient(colors: TranslationCardMotion.rimHues),
        startPoint: CGPoint(x: rect.minX, y: rect.minY),
        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
      ))
      AnnotateAIOverlayPainter.drawRim(
        in: &context, shape: shape, rect: rect, now: now, strength: fade,
        reduceMotion: reduceMotion, isDark: isDark, lineWidth: 1.6
      )
    }
  }

  /// A small light with a multi-hue bloom that breathes slowly.
  private func drawCursor(at point: CGPoint, in context: inout GraphicsContext, now: Date) {
    let breathe = reduceMotion ? 1 : 0.85 + 0.15 * sin(now.timeIntervalSinceReferenceDate * 4)
    let bloomRadius: CGFloat = 16 * breathe
    let bloom = CGRect(x: point.x - bloomRadius, y: point.y - bloomRadius, width: bloomRadius * 2, height: bloomRadius * 2)
    var halo = context
    halo.opacity = 0.7
    halo.addFilter(.blur(radius: 7))
    halo.fill(Path(ellipseIn: bloom), with: .conicGradient(
      Gradient(colors: TranslationCardMotion.rimHues),
      center: point,
      angle: .degrees(now.timeIntervalSinceReferenceDate * 90)
    ))

    let dot = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
    context.fill(Path(ellipseIn: dot), with: .color(.white))
    context.stroke(Path(ellipseIn: dot.insetBy(dx: -1, dy: -1)), with: .color(.black.opacity(0.25)), lineWidth: 1)
  }

  // MARK: Geometry

  /// Annotate image rect (bottom-left origin) → overlay view rect (top-left).
  private func displayRect(_ rect: CGRect) -> CGRect {
    CGRect(
      x: (rect.minX - canvasBounds.minX) * scale,
      y: (canvasBounds.maxY - rect.maxY) * scale,
      width: rect.width * scale,
      height: rect.height * scale
    )
  }

  private func displayPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: (point.x - canvasBounds.minX) * scale, y: (canvasBounds.maxY - point.y) * scale)
  }

  private func easeOut(_ value: Double) -> Double { 1 - pow(1 - min(max(value, 0), 1), 3) }
  private func easeIn(_ value: Double) -> Double { pow(min(max(value, 0), 1), 2) }
}

// MARK: - Result pill

/// Result of the last prompt, above the dock: summary, Undo, close. Hidden while running
/// (the dock shows live status instead).
struct AnnotateAgentNoticePill: View {
  @ObservedObject var agent: AnnotateAgentController
  @ObservedObject var state: AnnotateState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if let notice = agent.notice, !agent.isRunning {
        content(notice)
          .font(.system(size: 12))
          .padding(.horizontal, 14)
          .frame(height: 34)
          .liquidGlassSurface(shape: Capsule(style: .continuous), layer: .control)
          .fixedSize()
          .onHover { agent.holdNotice($0) }
      }
    }
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
    .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.32), value: agent.notice)
  }

  @ViewBuilder
  private func content(_ notice: AnnotateAgentController.Notice) -> some View {
    HStack(spacing: 10) {
      switch notice {
      case .finished(let message, _, _):
        AnnotateAgentGlyph(size: 12)
        Text(message)
          .lineLimit(2)
          .frame(maxWidth: 420, alignment: .leading)
        undoButton
      case .stopped(let count, _):
        Image(systemName: "stop.circle.fill")
          .foregroundStyle(.secondary)
        Text(count > 0 ? "\(L10n.AnnotateAI.stopped) · \(L10n.AnnotateAI.changes(count))" : L10n.AnnotateAI.stopped)
        undoButton
      case .failed(let message, let offersSettings):
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(message)
          .lineLimit(2)
          .frame(maxWidth: 420, alignment: .leading)
        if offersSettings {
          pillButton(L10n.AnnotateAI.settings) {
            agent.dismissNotice()
            AnnotateAgentAISettings.open()
          }
        }
      }
      closeButton
    }
  }

  @ViewBuilder
  private var undoButton: some View {
    // Re-evaluated with `state` so it disappears once the user edits on their own.
    if agent.canUndoLastRun {
      pillButton(L10n.Common.undo) { agent.undoLastRun() }
    }
  }

  private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var closeButton: some View {
    Button {
      agent.dismissNotice()
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(L10n.Common.close)
  }
}

/// The AI glyph painted with the rim hues (Apple Intelligence style).
struct AnnotateAgentGlyph: View {
  var size: CGFloat = 14
  var angle: Angle = .degrees(-135)

  static let symbolName: String = {
    NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil
      ? "apple.intelligence"
      : "sparkles"
  }()

  /// Ask's glyph: the Apple Intelligence mark with a pen (Writing Tools), so it reads as
  /// "write a prompt" next to the plain orb.
  static let askSymbolName: String = {
    NSImage(systemSymbolName: "apple.writing.tools", accessibilityDescription: nil) != nil
      ? "apple.writing.tools"
      : (NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: nil) != nil ? "pencil.tip.crop.circle" : symbolName)
  }()

  var body: some View {
    Image(systemName: Self.symbolName)
      .font(.system(size: size, weight: .medium))
      .foregroundStyle(AngularGradient(colors: TranslationCardMotion.rimHues, center: .center, angle: angle))
  }
}
