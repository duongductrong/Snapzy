//
//  AnnotateAutoTranslateOverlayView.swift
//  Snapzy
//
//  Auto Translate in Annotate uses the same "read → resolve" motion as the Snip to
//  Translate card (⌥⇧2), laid over the image itself:
//  - reading: a faint veil and a soft band of light sweeping across the image;
//  - blocks found: each text block lights up in reading order with a multi-hue rim;
//  - translating: the source dims under its cover while light sweeps inside each block;
//  - resolving: covers settle and each translation resolves from blurred to sharp,
//    block after block, then the real annotations take over at the same frames.
//  Everything is drawn in one `Canvas` per frame. Reduce Motion: plain fades.
//

import SwiftUI
import Translation

// MARK: - Canvas overlay

struct AnnotateAutoTranslateOverlayView: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let canvasBounds: CGRect
  /// Corner radius the canvas clips the image with (display points).
  var cornerRadius: CGFloat = 0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var phaseStart = Date()
  @State private var resolveStart = Date()

  private static let entranceStagger: Double = 0.035
  private static let entranceDuration: Double = 0.32
  private static let rimLimit = 60

  var body: some View {
    TimelineView(.animation(paused: reduceMotion && state.autoTranslatePhase != .resolving)) { timeline in
      Canvas { context, size in
        draw(in: &context, size: size, now: timeline.date)
      }
    }
    .allowsHitTesting(false)
    .onAppear { phaseStart = Date() }
    .onChange(of: state.autoTranslatePhase) { phase in
      if phase == .resolving {
        resolveStart = Date()
      } else {
        phaseStart = Date()
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(state.autoTranslatePhase == .reading ? L10n.AnnotateTranslate.reading : L10n.Translate.translating)
  }

  // MARK: Drawing

  private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
    let phase = state.autoTranslatePhase
    let elapsed = now.timeIntervalSince(phaseStart)
    let fullRect = CGRect(origin: .zero, size: size)
    let isDark = colorScheme == .dark
    // Paint only inside the image's own outline (rounded corners included).
    let imageShape = AnnotateAIOverlayPainter.imageShape(size: size, cornerRadius: cornerRadius)
    context.clip(to: imageShape)

    // Veil: whole image while reading, eased back once blocks are known.
    let veilTarget: Double = phase == .reading ? (isDark ? 0.22 : 0.12) : (isDark ? 0.12 : 0.06)
    let veilIn = reduceMotion ? 1 : min(elapsed / 0.35, 1)
    let veilFade = phase == .resolving ? max(0, 1 - now.timeIntervalSince(resolveStart) / 0.5) : veilIn
    let veilOpacity = veilTarget * veilFade

    // Translate Area: the area stays clear and reads; outside it sits a little darker.
    if let region = state.autoTranslateRegion {
      let area = displayRect(region).intersection(fullRect)
      var outside = Path(fullRect)
      outside.addRect(area)
      context.fill(outside, with: .color(.black.opacity((isDark ? 0.3 : 0.18) * veilFade)), style: FillStyle(eoFill: true))
      context.fill(Path(area), with: .color(.black.opacity(veilOpacity * 0.6)))
      if phase == .reading, !reduceMotion {
        drawSweep(in: &context, rect: area, now: now, phaseOffset: 0, strength: 0.22)
      }
      let areaShape = Path(roundedRect: area, cornerRadius: 4, style: .continuous)
      drawRim(in: &context, shape: areaShape, rect: area, now: now, strength: phase == .reading ? veilIn : 0.5 * veilFade)
    } else {
      context.fill(Path(fullRect), with: .color(.black.opacity(veilOpacity)))
      if phase == .reading, !reduceMotion {
        drawSweep(in: &context, rect: fullRect, now: now, phaseOffset: 0, strength: 0.16)
      }
      // Whole image is being read: light its edge; fades out with the veil on resolve.
      AnnotateAIOverlayPainter.drawEdgeGlow(
        in: &context, shape: imageShape, rect: fullRect, now: now,
        strength: (phase == .reading ? 1 : 0.6) * veilFade,
        reduceMotion: reduceMotion, isDark: isDark
      )
    }

    let blocks = state.autoTranslateBlocks
    guard !blocks.isEmpty else { return }
    let resolveElapsed = now.timeIntervalSince(resolveStart)

    for block in blocks {
      let rect = displayRect(block.bounds)
      guard rect.width > 0.5, rect.height > 0.5 else { continue }
      let radius = min(rect.height * 0.18, 6)
      let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)

      let entrance = reduceMotion ? 1 : easeOut(clamp((elapsed - Double(block.index) * Self.entranceStagger) / Self.entranceDuration))
      var reveal: Double = 0
      if phase == .resolving, block.translatedText != nil {
        let delay = Double(min(block.index, 24)) * AnnotateState.autoTranslateResolveStagger
        reveal = reduceMotion
          ? clamp(resolveElapsed / 0.2)
          : easeOut(clamp((resolveElapsed - delay) / AnnotateState.autoTranslateResolveDuration))
      }

      // Cover: dims the source while translating, settles fully as the result lands.
      // Settle at the opacity the committed annotation draws with, so nothing jumps.
      let settled: Double
      switch block.cover {
      case .solid: settled = 1
      case .frosted: settled = 0.72
      case .none: settled = 0
      }
      let coverOpacity = (phase == .resolving ? 0.5 + (settled - 0.5) * reveal : 0.5) * entrance
      context.fill(shape, with: .color(block.coverColor.opacity(coverOpacity)))

      if phase != .resolving || reveal < 1 {
        let rimStrength = entrance * (1 - reveal)
        if !reduceMotion, phase != .reading {
          drawSweep(in: &context, rect: rect, clip: shape, now: now, phaseOffset: Double(block.index) * 0.37, strength: 0.28 * rimStrength)
        }
        if block.index < Self.rimLimit {
          drawRim(in: &context, shape: shape, rect: rect, now: now, strength: rimStrength)
        } else {
          context.stroke(shape, with: .color(.accentColor.opacity(0.4 * rimStrength)), lineWidth: 1)
        }
      }

      if let text = block.translatedText, reveal > 0 {
        drawText(text, block: block, in: &context, rect: rect, reveal: reveal)
      }
    }
  }

  private func drawText(
    _ text: String,
    block: AnnotateAutoTranslateOverlayBlock,
    in context: inout GraphicsContext,
    rect: CGRect,
    reveal: Double
  ) {
    let fontSize = max(block.fontSize * scale, 1)
    let padding = AnnotateTranslationTextLayout.padding(for: block.bounds) * scale
    let resolved = context.resolve(
      Text(text)
        .font(.system(size: fontSize, weight: block.isBold ? .bold : .regular))
        .foregroundColor(block.textColor)
    )
    let available = CGSize(width: max(rect.width - padding * 2, 1), height: rect.height)
    let measured = resolved.measure(in: available)
    let x: CGFloat
    switch block.alignment {
    case .leading: x = rect.minX + padding
    case .center: x = rect.midX - measured.width / 2
    case .trailing: x = rect.maxX - padding - measured.width
    }
    let y = rect.midY - min(measured.height, rect.height) / 2 + (reduceMotion ? 0 : (1 - reveal) * 3)
    var layer = context
    layer.clip(to: Path(rect))
    layer.opacity = reveal
    if !reduceMotion, reveal < 1 {
      layer.addFilter(.blur(radius: (1 - reveal) * 6))
    }
    layer.draw(resolved, in: CGRect(x: x, y: y, width: available.width, height: min(measured.height, rect.height)))
  }

  private func drawRim(in context: inout GraphicsContext, shape: Path, rect: CGRect, now: Date, strength: Double) {
    AnnotateAIOverlayPainter.drawRim(
      in: &context, shape: shape, rect: rect, now: now, strength: strength,
      reduceMotion: reduceMotion, isDark: colorScheme == .dark
    )
  }

  private func drawSweep(
    in context: inout GraphicsContext,
    rect: CGRect,
    clip: Path? = nil,
    now: Date,
    phaseOffset: Double,
    strength: Double
  ) {
    AnnotateAIOverlayPainter.drawSweep(
      in: &context, rect: rect, clip: clip, now: now, phaseOffset: phaseOffset, strength: strength
    )
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

  private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  private func easeOut(_ value: Double) -> Double {
    1 - pow(1 - value, 3)
  }
}

// MARK: - Translate Area marquee

/// Shown while Translate Area waits for (or follows) a drag: a light veil with the
/// dragged area cut out, the card's rim light around it and its size.
struct AnnotateTranslateAreaSelectionView: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let canvasBounds: CGRect

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    GeometryReader { proxy in
      let full = CGRect(origin: .zero, size: proxy.size)
      let area = state.translateAreaDraft.map(displayRect)?.intersection(full)
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          var veil = Path(full)
          if let area, !area.isNull { veil.addRect(area) }
          context.fill(
            veil,
            with: .color(.black.opacity(colorScheme == .dark ? 0.32 : 0.2)),
            style: FillStyle(eoFill: true)
          )
        }

        if let area, !area.isNull, area.width > 1, area.height > 1 {
          TranslationReadingRim(shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: area.width, height: area.height)
            .offset(x: area.minX, y: area.minY)

          if let draft = state.translateAreaDraft {
            Text("\(Int(draft.width.rounded())) × \(Int(draft.height.rounded()))")
              .font(.system(size: 10, weight: .semibold).monospacedDigit())
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Capsule().fill(Color.black.opacity(0.55)))
              .fixedSize()
              .offset(x: area.minX, y: max(area.minY - 22, 2))
          }
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func displayRect(_ rect: CGRect) -> CGRect {
    CGRect(
      x: (rect.minX - canvasBounds.minX) * scale,
      y: (canvasBounds.maxY - rect.maxY) * scale,
      width: rect.width * scale,
      height: rect.height * scale
    )
  }
}

// MARK: - Status / result pill

struct AnnotateAutoTranslatePill: View {
  @ObservedObject var state: AnnotateState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      // A running translation shows its status inside the AI dock.
      if state.isTranslateAreaSelecting {
        pill { areaSelectionContent }
      } else if let notice = state.autoTranslateNotice {
        pill { noticeContent(notice) }
          .onHover { state.holdAutoTranslateNotice($0) }
      }
    }
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
    .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.32), value: state.isTranslateAreaSelecting)
    .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.32), value: state.autoTranslateNotice)
  }

  private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 10) {
      content()
    }
    .font(.system(size: 12))
    .padding(.horizontal, 14)
    .frame(height: 34)
    .liquidGlassSurface(shape: Capsule(style: .continuous), layer: .control)
    .fixedSize()
  }

  @ViewBuilder
  private var areaSelectionContent: some View {
    Image(systemName: "text.viewfinder")
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.secondary)
    Text(L10n.AnnotateTranslate.areaHint(state.autoTranslateTarget.displayName))
      .foregroundStyle(.primary)
    Text(L10n.AnnotateTranslate.cancelHint)
      .foregroundStyle(.tertiary)
    pillButton(L10n.AnnotateTranslate.wholeImage) { state.autoTranslate() }
    pillButton(L10n.Common.cancel) { state.endTranslateAreaSelection() }
  }

  @ViewBuilder
  private func noticeContent(_ notice: AnnotateAutoTranslateNotice) -> some View {
    switch notice {
    case .success(let count, let language):
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text(L10n.AnnotateTranslate.success(count, language))
      if !state.includesTranslationsInExport {
        Text(L10n.AnnotateTranslate.notInExport)
          .font(.system(size: 10, weight: .medium))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.orange.opacity(0.18)))
          .foregroundStyle(.orange)
      }
      ShowOriginalButton(state: state)
      pillButton(L10n.Common.undo) {
        state.dismissAutoTranslateNotice()
        state.undo()
      }
      closeButton
    case .failure(let message, let action):
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .lineLimit(2)
        .frame(maxWidth: 420, alignment: .leading)
      if let action {
        pillButton(title(for: action)) { state.performAutoTranslateNoticeAction(action) }
      }
      closeButton
    }
  }

  private func title(for action: AnnotateAutoTranslateFailureAction) -> String {
    switch action {
    case .openSettings: L10n.Translate.openSettings
    case .translateWithEndpoint(let name, _): L10n.Translate.useEndpoint(name)
    }
  }

  private var closeButton: some View {
    Button {
      state.dismissAutoTranslateNotice()
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
}

/// Press and hold to see the text under the translations (same as holding ⌥).
private struct ShowOriginalButton: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    Text(L10n.AnnotateTranslate.showOriginal)
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 8)
      .frame(height: 22)
      .background(
        Capsule(style: .continuous)
          .fill(Color.primary.opacity(state.isPeekingOriginalTranslations ? 0.18 : 0.08))
      )
      .contentShape(Capsule())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in state.setPeekingOriginalTranslations(true) }
          .onEnded { _ in state.setPeekingOriginalTranslations(false) }
      )
      .help(L10n.AnnotateTranslate.peekHint)
  }
}

// MARK: - Apple Translation host

/// Hidden host for Apple Translation: `.translationTask` is the only way to get a
/// `TranslationSession` before macOS 26. No-op on older systems.
struct AnnotateAppleTranslationHost: ViewModifier {
  @ObservedObject var state: AnnotateState

  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content.background(AnnotateAppleTranslationTaskView(state: state))
    } else {
      content
    }
  }
}

@available(macOS 15.0, *)
private struct AnnotateAppleTranslationTaskView: View {
  @ObservedObject var state: AnnotateState
  @State private var configuration: TranslationSession.Configuration?
  @State private var pending: AnnotateAppleTranslationRequest?

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .translationTask(configuration) { @MainActor session in
        guard let request = pending else { return }
        pending = nil
        do {
          let output = try await AppleBlockTranslator.run(request.texts, session: session)
          state.completeAppleTranslation(token: request.token, result: .success(output))
        } catch {
          state.completeAppleTranslation(token: request.token, result: .failure(error))
        }
      }
      .onAppear { sync(state.appleTranslationRequest) }
      .onChange(of: state.appleTranslationRequest) { sync($0) }
  }

  /// A new request means "translate now": build the configuration, or invalidate
  /// the existing one so the task runs again.
  private func sync(_ request: AnnotateAppleTranslationRequest?) {
    guard let request, request != pending else { return }
    pending = request
    let next = TranslationSession.Configuration(
      source: request.sourceLanguageIdentifier.map { Locale.Language(identifier: $0) },
      target: Locale.Language(identifier: request.targetLanguageIdentifier)
    )
    if configuration?.source == next.source, configuration?.target == next.target {
      configuration?.invalidate()
    } else {
      configuration = next
    }
  }
}
