//
//  AnnotateAIDockView.swift
//  Snapzy
//
//  Floating AI dock at the bottom center of the Annotate canvas. At rest it is a
//  single glass orb with the multi-hue AI glyph (the same hues as the translation
//  reading rim). Clicking it grows the glass horizontally into a small toolbar:
//
//    [ orb ] | [ ✦ Ask ] | [ Translate ] [ Area ] [ 🌐 Language ⌄ ] [ ⋯ ]
//
//  "Ask" opens the AI prompt in the same glass: the tools leave, Ask turns into a back
//  button and the field slides in. While the agent works the field becomes a live
//  status line and the dock carries the reading rim.
//
//    [ orb ] [ ‹ ] [ Describe what to annotate…        ] [ ◉ Mock ⌄ ] [ ↑ ]
//
//  Translate / Area runs the same way: the tools give way to a live status line and a
//  stop button in the same glass, then the dock returns to where it was.
//
//    [ orb ] [ 文A ] [ Reading text…   esc ] [ ■ ]
//

import AppKit
import SwiftUI

struct AnnotateAIDockView: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var agent: AnnotateAgentController
  /// Widest the dock may grow (the canvas width minus margins).
  let maxWidth: CGFloat

  @ObservedObject private var shortcuts = AnnotateShortcutManager.shared
  @State private var promptGlow: Double = 0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let height: CGFloat = 40
  static let inset: CGFloat = 4
  static let itemHeight: CGFloat = height - inset * 2

  init(state: AnnotateState, maxWidth: CGFloat = .infinity) {
    self.state = state
    _agent = ObservedObject(wrappedValue: state.agent)
    self.maxWidth = maxWidth
  }

  private var expandAnimation: Animation {
    reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.86)
  }

  /// Annotate mode only, same rule as the Auto Translate actions; stays up while a run finishes.
  private var isAvailable: Bool {
    state.canAutoTranslate || state.isAutoTranslateRunning || agent.isRunning
  }

  private var isWorking: Bool {
    state.isAutoTranslateRunning || agent.isRunning
  }

  private var isPrompt: Bool { agent.isPromptPresented }

  private var isExpanded: Bool {
    get { agent.isDockExpanded }
    nonmutating set { agent.isDockExpanded = newValue }
  }

  private var isTranslating: Bool { state.isAutoTranslateRunning }

  /// Rounded rect with the capsule's radius: a capsule at one line, a soft card when the
  /// prompt wraps onto more lines.
  private var dockShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
  }

  var body: some View {
    Group {
      if isAvailable {
        dock
          .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
      }
    }
    .animation(.easeOut(duration: 0.18), value: isAvailable)
  }

  private var dock: some View {
    HStack(alignment: .bottom, spacing: 0) {
      AnnotateAIDockOrb(
        isExpanded: isExpanded || isPrompt || isTranslating,
        isWorking: isWorking
      ) {
        withAnimation(expandAnimation) {
          // While a translation runs the glass belongs to its status; stop ends it.
          guard !isTranslating else { return }
          if isPrompt {
            agent.dismissPrompt()
            isExpanded = false
          } else {
            isExpanded.toggle()
          }
        }
      }

      if isTranslating {
        // Translate / Area morph into the run's status line in the same glass, like Ask.
        AnnotateAIDockTranslateStatusRow(state: state, maxWidth: maxWidth)
          .transition(promptTransition)
      } else if isPrompt {
        AnnotateAIDockPromptRow(
          state: state,
          agent: agent,
          maxWidth: maxWidth
        ) {
          withAnimation(expandAnimation) { agent.dismissPrompt() }
        }
        .transition(promptTransition)
      } else if isExpanded {
        Group {
          AnnotateAIDockHairline()
          if AnnotateAgentProviderResolver.isFeatureAvailable {
            AnnotateAIDockAskItem(
              help: help(L10n.AnnotateAI.askHelp, .aiPrompt)
            ) {
              withAnimation(expandAnimation) { agent.presentPrompt() }
            }
            .disabled(!agent.isAvailable)
            AnnotateAIDockHairline()
          }
          AnnotateAIDockTranslateSection(state: state, shortcuts: shortcuts)
        }
        .transition(sectionTransition)
      }
    }
    .padding(Self.inset)
    .frame(minHeight: Self.height)
    .clipShape(dockShape)
    .liquidGlassSurface(
      shape: dockShape,
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.04,
      highlight: .none,
      withRimLighting: true
    )
    .overlay {
      if isWorking {
        TranslationReadingRim(shape: dockShape)
          .transition(.opacity)
      }
    }
    .overlay {
      // Ask's colors flow into the field's border as it opens, then settle.
      dockShape
        .strokeBorder(
          AngularGradient(colors: TranslationCardMotion.rimHues, center: .center),
          lineWidth: 1.5
        )
        .opacity(promptGlow)
        .allowsHitTesting(false)
    }
    .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    .fixedSize()
    .animation(.easeInOut(duration: 0.25), value: isWorking)
    .animation(expandAnimation, value: isPrompt)
    .animation(expandAnimation, value: isTranslating)
    .onChange(of: isAvailable) { available in
      if !available {
        isExpanded = false
        agent.dismissPrompt()
      }
    }
    .onChange(of: isPrompt) { presented in
      // ⌘K opens the prompt straight from the orb; back lands on the tools.
      if presented {
        isExpanded = true
        flashPromptGlow()
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.AnnotateTranslate.aiTools)
  }

  private func flashPromptGlow() {
    guard !reduceMotion else { return }
    promptGlow = 0.9
    withAnimation(.easeOut(duration: 0.7).delay(0.15)) { promptGlow = 0 }
  }

  private func help(_ title: String, _ kind: AnnotateActionShortcutKind) -> String {
    guard shortcuts.isActionShortcutEnabled(for: kind),
          let config = shortcuts.shortcut(for: kind) else { return title }
    return "\(title) (\(config.displayString))"
  }

  /// Items fade and settle in from the orb while the glass grows; they leave faster than they come.
  private var sectionTransition: AnyTransition {
    if reduceMotion { return .opacity }
    return .asymmetric(
      insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .leading))
        .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.05)),
      removal: .modifier(
        active: AnnotateAIDockBlurFade(radius: 4, opacity: 0, scale: 0.92),
        identity: AnnotateAIDockBlurFade(radius: 0, opacity: 1, scale: 1)
      )
      .animation(.easeOut(duration: 0.14))
    )
  }

  /// The field slides in from where Ask was; it leaves quickly with a little blur.
  private var promptTransition: AnyTransition {
    if reduceMotion { return .opacity }
    return .asymmetric(
      insertion: .opacity.combined(with: .offset(x: -8))
        .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.05)),
      removal: .modifier(
        active: AnnotateAIDockBlurFade(radius: 4, opacity: 0, scale: 0.96),
        identity: AnnotateAIDockBlurFade(radius: 0, opacity: 1, scale: 1)
      )
      .animation(.easeOut(duration: 0.14))
    )
  }
}

struct AnnotateAIDockBlurFade: ViewModifier {
  let radius: CGFloat
  let opacity: Double
  let scale: CGFloat

  func body(content: Content) -> some View {
    content
      .blur(radius: radius)
      .opacity(opacity)
      .scaleEffect(scale, anchor: .leading)
  }
}

// MARK: - Orb

/// The AI glyph in a circle. Static multi-hue at rest; the hues turn slowly and glow while working.
struct AnnotateAIDockOrb: View {
  let isExpanded: Bool
  let isWorking: Bool
  /// Tooltip and VoiceOver name at rest.
  var label: String = L10n.AnnotateTranslate.aiTools
  /// Tooltip while collapsed; falls back to `label` (e.g. to append the shortcut).
  var help: String? = nil
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      TimelineView(.animation(minimumInterval: nil, paused: !isWorking || reduceMotion)) { context in
        let angle = gradientAngle(at: context.date)
        let gradient = AngularGradient(
          colors: TranslationCardMotion.rimHues,
          center: .center,
          angle: angle
        )
        ZStack {
          Circle()
            .fill(Color.primary.opacity(isExpanded ? 0.09 : (isHovered ? 0.06 : 0)))

          // Soft bloom of the same hues, strongest while working.
          Circle()
            .fill(gradient)
            .frame(width: 18, height: 18)
            .blur(radius: 9)
            .opacity(glowOpacity)

          Image(systemName: AnnotateAgentGlyph.symbolName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(gradient)
            .scaleEffect(isHovered ? 1.06 : 1)
        }
      }
      .frame(width: AnnotateAIDockView.itemHeight, height: AnnotateAIDockView.itemHeight)
      .contentShape(Circle())
    }
    .buttonStyle(AnnotateAIDockPressStyle())
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering }
    }
    .help(isExpanded ? L10n.Common.close : (help ?? label))
    .accessibilityLabel(label)
    .accessibilityAddTraits(isExpanded ? .isSelected : [])
  }

  private var glowOpacity: Double {
    if isWorking { return colorScheme == .dark ? 0.55 : 0.4 }
    return isHovered ? 0.22 : 0.1
  }

  private func gradientAngle(at date: Date) -> Angle {
    // Resting angle puts blue/violet at the top-left, warm tones bottom-right.
    let rest = Angle.degrees(-135)
    guard isWorking, !reduceMotion else { return rest }
    let duration = TranslationCardMotion.rimTurnDuration * 0.6
    let turn = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
    return rest + .degrees(turn * 360)
  }
}

// MARK: - Ask

/// The AI prompt's entry: the only dock item painted with the AI hues. Glyph and label carry
/// the gradient; a tinted pill with a gradient hairline sits behind. On hover the hues turn and
/// bloom. The first time it appears it shimmers once as a hint.
private struct AnnotateAIDockAskItem: View {
  let help: String
  let action: () -> Void

  @AppStorage("annotateAgent.didUseAsk") private var didUseAsk = false
  /// The hint plays once per launch until Ask has been used, not every time the dock opens.
  private static var didShimmerThisLaunch = false
  @State private var isHovered = false
  @State private var shimmerStart: Date?
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  private static let shimmerDuration: TimeInterval = 0.9

  var body: some View {
    Button {
      didUseAsk = true
      action()
    } label: {
      TimelineView(.animation(paused: !isAnimating)) { timeline in
        let angle = gradientAngle(at: timeline.date)
        let gradient = AngularGradient(colors: TranslationCardMotion.rimHues, center: .center, angle: angle)
        let label = HStack(spacing: 6) {
          Image(systemName: AnnotateAgentGlyph.askSymbolName)
            .font(.system(size: 13, weight: .medium))
          Text(L10n.AnnotateAI.ask)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
        }
        label
          .foregroundStyle(gradient)
          .overlay { shimmer(at: timeline.date).mask(label) }
          .padding(.horizontal, 11)
          .frame(minWidth: AnnotateAIDockView.itemHeight)
          .frame(height: AnnotateAIDockView.itemHeight)
          .background {
            // Nothing at rest: the AI colors alone set Ask apart. Hover = the same neutral
            // fill as the other items plus a faint bloom of the hues.
            ZStack {
              Capsule(style: .continuous)
                .fill(gradient)
                .blur(radius: 10)
                .opacity(isHovered ? 0.18 : 0)
              Capsule(style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
              if contrast == .increased {
                Capsule(style: .continuous)
                  .strokeBorder(gradient, lineWidth: 1)
                  .opacity(0.8)
              }
            }
          }
      }
      .contentShape(Capsule(style: .continuous))
      .opacity(isEnabled ? 1 : 0.45)
    }
    .buttonStyle(AnnotateAIDockPressStyle(pressedScale: 0.96))
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering && isEnabled }
    }
    .onAppear {
      guard !didUseAsk, !reduceMotion, !Self.didShimmerThisLaunch else { return }
      Self.didShimmerThisLaunch = true
      let start = Date().addingTimeInterval(0.35)
      shimmerStart = start
      // Clearing it pauses the timeline once the hint has played.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Self.shimmerDuration + 0.05) {
        if shimmerStart == start { shimmerStart = nil }
      }
    }
    .help(help)
    .accessibilityLabel(L10n.AnnotateAI.askHelp)
  }

  private var isAnimating: Bool {
    !reduceMotion && (isHovered || shimmerStart != nil)
  }

  private func gradientAngle(at date: Date) -> Angle {
    let rest = Angle.degrees(-135)
    guard isHovered, !reduceMotion else { return rest }
    return rest + .degrees(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360)
  }

  /// One soft band of light across the pill, once.
  @ViewBuilder
  private func shimmer(at date: Date) -> some View {
    if let shimmerStart {
      let t = date.timeIntervalSince(shimmerStart) / Self.shimmerDuration
      if t > 0, t < 1 {
        GeometryReader { proxy in
          let band = proxy.size.width * 0.5
          LinearGradient(
            colors: [.clear, .white.opacity(0.45), .clear],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: band)
          .offset(x: -band + (proxy.size.width + band) * (1 - pow(1 - t, 2)))
          .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
      }
    }
  }
}

// MARK: - Prompt

private struct AnnotateAIDockPromptRow: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject var agent: AnnotateAgentController
  let maxWidth: CGFloat
  let onBack: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The field hugs its text (placeholder, draft or status) between these widths;
  /// past the maximum the single-line field scrolls with the caret.
  private static let minimumFieldWidth: CGFloat = 140
  private static let maximumFieldWidth: CGFloat = 300
  /// Width changes snap to this step so typing doesn't resize the glass on every key.
  private static let fieldWidthStep: CGFloat = 16
  /// Orb, back, provider, send and paddings.
  private static let chromeWidth: CGFloat = 170
  private static let fieldFont = AnnotateAIDockPromptField.font

  private var placeholderText: String {
    agent.hasConversation ? L10n.AnnotateAI.followUpPlaceholder : L10n.AnnotateAI.placeholder
  }

  private var fieldWidth: CGFloat {
    let available = maxWidth - Self.chromeWidth - (selectionCount > 0 ? 110 : 0)
    var content = Self.textWidth(placeholderText)
    if agent.isRunning {
      content = max(content, Self.textWidth(agent.status))
    } else {
      content = max(content, Self.textWidth(agent.draft))
    }
    // Room for the caret, then snap up to the next step.
    let stepped = ((content + 8) / Self.fieldWidthStep).rounded(.up) * Self.fieldWidthStep
    let upper = max(min(Self.maximumFieldWidth, available), Self.minimumFieldWidth)
    return min(max(stepped, Self.minimumFieldWidth), upper)
  }

  private static func textWidth(_ text: String) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    return ceil((text as NSString).size(withAttributes: [.font: fieldFont]).width)
  }

  private var selectionCount: Int {
    agent.isRunning ? 0 : state.selectedAnnotationIds.count
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      backButton

      if selectionCount > 0 {
        selectionChip
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
      }

      ZStack(alignment: .leading) {
        // The field stays mounted through a run (hidden under the status line) so its
        // caret comes straight back when the run ends.
        field
          .opacity(agent.isRunning ? 0 : 1)
          .allowsHitTesting(!agent.isRunning)
          .accessibilityHidden(agent.isRunning)
        if agent.isRunning {
          AnnotateAIDockStatusLine(text: agent.status)
            .transition(.opacity)
        }
      }
      .frame(width: fieldWidth, height: AnnotateAIDockView.itemHeight, alignment: .leading)
      .padding(.horizontal, 6)
      .animation(.easeInOut(duration: 0.2), value: agent.isRunning)
      .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: fieldWidth)

      providerChip
      sendButton
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectionCount > 0)
  }

  private var field: some View {
    // AppKit-backed so the caret lands reliably even while the dock is still animating in;
    // see AnnotateAIDockPromptField for why @FocusState wasn't enough.
    AnnotateAIDockPromptField(
      text: $agent.draft,
      placeholder: placeholderText,
      focusRequest: agent.promptFocusRequest,
      isActive: !agent.isRunning,
      onSubmit: { agent.submit() },
      onEscape: {
        if agent.draft.isEmpty {
          onBack()
        } else {
          agent.handleEscape()
        }
      }
    )
    .frame(height: AnnotateAIDockView.itemHeight)
    .accessibilityLabel(L10n.AnnotateAI.askHelp)
  }

  private var backButton: some View {
    Button(action: onBack) {
      Image(systemName: "chevron.left")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: AnnotateAIDockView.itemHeight)
    }
    .buttonStyle(AnnotateAIDockItemStyle())
    .disabled(agent.isRunning)
    .help(L10n.AnnotateAI.back)
    .accessibilityLabel(L10n.AnnotateAI.back)
  }

  private var selectionChip: some View {
    HStack(spacing: 4) {
      Text(L10n.AnnotateAI.selected(selectionCount))
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
      Button {
        state.setSelectedAnnotationIds([])
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
          .frame(width: 14, height: 14)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L10n.AnnotateAI.clearSelection)
    }
    .foregroundStyle(Color.accentColor)
    .padding(.horizontal, 8)
    .frame(height: 22)
    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.16)))
    .padding(.bottom, (AnnotateAIDockView.itemHeight - 22) / 2)
    .fixedSize()
  }

  private var providerChip: some View {
    let provider = agent.provider
    return AnnotateAIDockMenuButton(help: provider?.displayName ?? L10n.AnnotateAI.notConfigured, makeMenu: providerMenu) { _ in
      HStack(spacing: 5) {
        // Icon only: the name lives in the tooltip and the menu, keeping the dock compact.
        AnnotateAgentProviderIcon(
          symbolName: provider?.symbolName ?? "exclamationmark.circle",
          logoImageName: provider?.logoImageName
        )
        .accessibilityLabel(provider?.displayName ?? L10n.AnnotateAI.notConfigured)
        if agent.hasConversation {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
        }
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .opacity(0.6)
      }
      .padding(.horizontal, 8)
    }
    .disabled(agent.isRunning)
  }

  private func providerMenu() -> NSMenu {
    AnnotateAIDockProviderMenu.make(
      provider: agent.provider,
      selection: agent.providerSelection,
      isRunning: agent.isRunning,
      hasConversation: agent.hasConversation,
      onSelect: { [weak agent] in agent?.selectProvider($0) },
      onNewConversation: { [weak agent] in agent?.startNewConversation() }
    )
  }

  @ViewBuilder
  private var sendButton: some View {
    if agent.isRunning {
      AnnotateAIDockRoundButton(symbol: "stop.fill", isProminent: false, help: L10n.AnnotateAI.stop) {
        agent.stop()
      }
    } else {
      AnnotateAIDockRoundButton(symbol: "arrow.up", isProminent: true, help: L10n.AnnotateAI.send) {
        agent.submit()
      }
      .disabled(!agent.canSend)
    }
  }
}

// MARK: - Translate status

/// Auto Translate / Translate Area in progress, shown in place of the tools:
///
///    [ orb ] [ 文A ] [ Reading text…        esc ] [ ■ ]
private struct AnnotateAIDockTranslateStatusRow: View {
  @ObservedObject var state: AnnotateState
  let maxWidth: CGFloat

  private static let minimumWidth: CGFloat = 120
  /// Orb, icon, stop and paddings.
  private static let chromeWidth: CGFloat = 110
  private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

  private var status: String {
    switch state.autoTranslatePhase {
    case .reading, .idle: L10n.AnnotateTranslate.reading
    case .translating, .resolving: L10n.Translate.translating
    }
  }

  /// Hug the longest phase text so the glass doesn't resize between phases.
  private var statusWidth: CGFloat {
    let longest = [L10n.AnnotateTranslate.reading, L10n.Translate.translating]
      .map { ceil(($0 as NSString).size(withAttributes: [.font: Self.font]).width) }
      .max() ?? 0
    let upper = max(maxWidth - Self.chromeWidth, Self.minimumWidth)
    return min(max(longest + 8, Self.minimumWidth), upper)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      Image(systemName: state.autoTranslateRegion == nil ? "translate" : "text.viewfinder")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(LiquidGlassTokens.inkBody)
        .frame(width: AnnotateAIDockView.itemHeight, height: AnnotateAIDockView.itemHeight)

      AnnotateAIDockStatusLine(text: status)
        .frame(width: statusWidth, height: AnnotateAIDockView.itemHeight, alignment: .leading)

      Text("esc")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(LiquidGlassTokens.inkFaint)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.07))
        )
        .frame(height: AnnotateAIDockView.itemHeight)
        .padding(.horizontal, 4)
        .help(L10n.AnnotateTranslate.cancelHint)
        .accessibilityHidden(true)

      AnnotateAIDockRoundButton(symbol: "stop.fill", isProminent: false, help: L10n.Common.cancel) {
        state.cancelAutoTranslate()
      }
    }
    .accessibilityElement(children: .contain)
  }
}

/// Live status while the agent works: the text in body ink with a band of the AI hues
/// passing through it, like the dock's reading rim.
struct AnnotateAIDockStatusLine: View {
  let text: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let label = Text(text.isEmpty ? L10n.AnnotateAI.statusThinking : text)
      .font(.system(size: 13, weight: .medium))
    label
      .lineLimit(1)
      .foregroundStyle(LiquidGlassTokens.inkBody)
      .overlay {
        if !reduceMotion {
          TimelineView(.animation) { timeline in
            GeometryReader { proxy in
              let cycle = 1.8
              let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
              let band = max(proxy.size.width * 0.45, 60)
              LinearGradient(
                stops: [
                  .init(color: .clear, location: 0),
                  .init(color: TranslationCardMotion.rimHues[0], location: 0.3),
                  .init(color: TranslationCardMotion.rimHues[2], location: 0.55),
                  .init(color: TranslationCardMotion.rimHues[3], location: 0.75),
                  .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
              )
              .frame(width: band)
              .offset(x: -band + (proxy.size.width + band) * t)
            }
          }
          .mask(label.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading))
          .allowsHitTesting(false)
        }
      }
      .id(text)
      .transition(.opacity)
      .animation(.easeInOut(duration: 0.2), value: text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel(text)
  }
}

/// Circular send / stop button at the trailing end of the prompt.
struct AnnotateAIDockRoundButton: View {
  let symbol: String
  let isProminent: Bool
  let help: String
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(isProminent && isEnabled ? Color.white : LiquidGlassTokens.inkPrimary)
        .frame(width: 26, height: 26)
        .background(
          Circle().fill(
            isProminent && isEnabled
              ? Color.accentColor
              : Color.primary.opacity(isHovered ? 0.16 : 0.1)
          )
        )
        .opacity(isEnabled ? 1 : 0.45)
        .frame(width: AnnotateAIDockView.itemHeight, height: AnnotateAIDockView.itemHeight)
        .contentShape(Circle())
    }
    .buttonStyle(AnnotateAIDockPressStyle())
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering && isEnabled }
    }
    .help(help)
    .accessibilityLabel(help)
  }
}

// MARK: - Translate section

private struct AnnotateAIDockTranslateSection: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject var shortcuts: AnnotateShortcutManager

  private var canRun: Bool { state.canAutoTranslate && !state.isAutoTranslateRunning }

  var body: some View {
    HStack(spacing: 2) {
      AnnotateAIDockItem(
        icon: "translate",
        title: L10n.AnnotateTranslate.dockTranslate,
        isActive: state.isAutoTranslateRunning && state.autoTranslateRegion == nil,
        help: help(L10n.AnnotateTranslate.translateWholeImage, .autoTranslate)
      ) {
        state.autoTranslate()
      }
      .disabled(!canRun)

      AnnotateAIDockItem(
        icon: "text.viewfinder",
        title: L10n.AnnotateTranslate.dockArea,
        isActive: state.isTranslateAreaSelecting
          || (state.isAutoTranslateRunning && state.autoTranslateRegion != nil),
        help: help(
          state.isTranslateAreaSelecting ? L10n.AnnotateTranslate.cancelAreaSelection : L10n.AnnotateTranslate.translateArea,
          .translateArea
        )
      ) {
        state.toggleTranslateAreaSelection()
      }
      .disabled(!canRun)

      AnnotateAIDockMenuButton(help: L10n.Translate.targetLanguageLabel, makeMenu: languageMenu) { isOpen in
        HStack(spacing: 5) {
          Image(systemName: "globe")
            .font(.system(size: 12, weight: .medium))
          Text(state.autoTranslateTarget.displayName)
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
      }
      .disabled(state.isAutoTranslateRunning)

      AnnotateAIDockMenuButton(help: L10n.AnnotateTranslate.options, makeMenu: optionsMenu) { _ in
        Image(systemName: "ellipsis")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: AnnotateAIDockView.itemHeight)
      }
    }
  }

  private func help(_ title: String, _ kind: AnnotateActionShortcutKind) -> String {
    guard shortcuts.isActionShortcutEnabled(for: kind),
          let config = shortcuts.shortcut(for: kind) else { return title }
    return "\(title) (\(config.displayString))"
  }

  private func languageMenu() -> NSMenu {
    let menu = NSMenu()
    let current = state.autoTranslateTarget
    for language in TranslationLanguage.all.sorted(by: { $0.displayName < $1.displayName }) {
      let item = ClosureMenuItem(title: language.displayName, keyEquivalent: "") { [weak state] in
        state?.setAutoTranslateTarget(language)
      }
      item.state = language == current ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func optionsMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    if state.isAutoTranslateRunning {
      let cancel = ClosureMenuItem(title: L10n.Common.cancel, keyEquivalent: "") { [weak state] in
        state?.cancelAutoTranslate()
      }
      cancel.image = symbol("stop.circle")
      menu.addItem(cancel)
      menu.addItem(.separator())
    }

    let engine = NSMenuItem(title: engineDescription, action: nil, keyEquivalent: "")
    engine.image = symbol(isRemoteEngine ? "network" : "lock.laptopcomputer")
    engine.isEnabled = false
    menu.addItem(engine)

    let settings = ClosureMenuItem(title: L10n.Translate.openSettings, keyEquivalent: "") {
      AnnotateState.openTranslationSettings()
    }
    settings.image = symbol("gearshape")
    menu.addItem(settings)

    menu.addItem(.separator())

    let export = ClosureMenuItem(title: L10n.AnnotateTranslate.includeInExport, keyEquivalent: "") { [weak state] in
      guard let state else { return }
      state.setIncludesTranslationsInExport(!state.includesTranslationsInExport)
    }
    export.image = symbol("square.and.arrow.up")
    export.state = state.includesTranslationsInExport ? .on : .off
    menu.addItem(export)

    let remove = ClosureMenuItem(title: L10n.AnnotateTranslate.removeTranslations, keyEquivalent: "") { [weak state] in
      state?.removeAllTranslations()
    }
    remove.image = symbol("trash")
    remove.isEnabled = state.translationAnnotationCount > 0 && !state.isAutoTranslateRunning
    menu.addItem(remove)
    return menu
  }

  private func symbol(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)
  }

  private var isRemoteEngine: Bool {
    if case .remote = TranslationEngineResolver().resolve() { return true }
    return false
  }

  private var engineDescription: String {
    switch TranslationEngineResolver().resolve() {
    case .apple:
      return L10n.AnnotateTranslate.engineApple
    case .remote(let model):
      return L10n.AnnotateTranslate.engineRemote(model.name)
    case .unavailable:
      return L10n.Translate.requiresMacOS15Title
    }
  }
}

// MARK: - Provider menu

/// The provider chip's menu, shared by every AI dock: current provider, the choices
/// (Automatic, Apple Intelligence when ready, custom endpoints, agent CLIs), New
/// Conversation and AI Settings.
@MainActor
enum AnnotateAIDockProviderMenu {
  static func make(
    provider: AgentProvider?,
    selection: AgentProviderSelection,
    isRunning: Bool,
    hasConversation: Bool,
    /// `nil` = when Apple Intelligence is ready on this Mac.
    showsAppleIntelligence: Bool? = nil,
    onSelect: @escaping (AgentProviderSelection) -> Void,
    onNewConversation: @escaping () -> Void
  ) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let current = NSMenuItem(title: provider?.displayName ?? L10n.AnnotateAI.notConfigured, action: nil, keyEquivalent: "")
    current.image = menuImage(symbol: provider?.symbolName ?? "exclamationmark.circle", logo: provider?.logoImageName)
    current.isEnabled = false
    menu.addItem(current)
    menu.addItem(.separator())

    var choices: [(title: String, symbol: String, logo: String?, value: AgentProviderSelection)] = [
      (L10n.AnnotateAI.automatic, "sparkles", nil, .automatic),
    ]
    if showsAppleIntelligence ?? AnnotateAgentAppleIntelligence.isAvailable || selection == .appleIntelligence {
      choices.append(("Apple Intelligence", "apple.intelligence", nil, .appleIntelligence))
    }
    for model in CustomOCRModelStore.shared.models {
      choices.append((model.name, "network", nil, .endpoint(model.id)))
    }
    // Agent CLIs found on this Mac (the selected one stays listed even if it went missing).
    let installedCLIs = AnnotateAgentCLIDetector.shared.installed
    for kind in AnnotateAgentCLIKind.allCases where installedCLIs[kind] != nil || selection == .cli(kind) {
      choices.append((kind.displayName, "terminal", kind.logoImageName, .cli(kind)))
    }
    for choice in choices {
      let item = ClosureMenuItem(title: choice.title, keyEquivalent: "") {
        onSelect(choice.value)
      }
      item.image = menuImage(symbol: choice.symbol, logo: choice.logo)
      item.state = choice.value == selection ? .on : .off
      item.isEnabled = !isRunning
      menu.addItem(item)
    }

    menu.addItem(.separator())
    let newConversation = ClosureMenuItem(title: L10n.AnnotateAI.newConversation, keyEquivalent: "") {
      onNewConversation()
    }
    newConversation.image = NSImage(systemSymbolName: "plus.bubble", accessibilityDescription: nil)
    newConversation.isEnabled = hasConversation && !isRunning
    menu.addItem(newConversation)
    let settings = ClosureMenuItem(title: L10n.AnnotateAI.settings, keyEquivalent: "") {
      AnnotateAgentAISettings.open()
    }
    settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    menu.addItem(settings)
    return menu
  }

  /// A provider's brand mark at menu size, else its SF Symbol.
  static func menuImage(symbol: String, logo: String?) -> NSImage? {
    if let logo, let image = NSImage(named: logo)?.copy() as? NSImage {
      image.size = NSSize(width: 16, height: 16)
      return image
    }
    return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
  }
}

// MARK: - Building blocks

/// A provider's icon: its maker's mark when it has one (agent CLIs), else its SF Symbol.
/// Template marks take the surrounding ink; Claude's keeps its brand color.
struct AnnotateAgentProviderIcon: View {
  let symbolName: String
  let logoImageName: String?
  var size: CGFloat = 13

  var body: some View {
    if let logoImageName {
      Image(logoImageName)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    } else {
      Image(systemName: symbolName)
        .font(.system(size: size - 1, weight: .medium))
    }
  }
}

/// Icon + label segment with a hover glass capsule; accent-tinted while its action is active.
private struct AnnotateAIDockItem: View {
  let icon: String
  let title: String
  var isActive: Bool = false
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
        Text(title)
          .lineLimit(1)
      }
      .padding(.horizontal, 11)
    }
    .buttonStyle(AnnotateAIDockItemStyle(isActive: isActive))
    .help(help)
  }
}

/// A dock segment that pops a native menu just above itself (the dock sits at the bottom).
struct AnnotateAIDockMenuButton<Label: View>: View {
  let help: String
  let makeMenu: () -> NSMenu
  @ViewBuilder let label: (Bool) -> Label

  @State private var anchor = MenuAnchor()
  @State private var isOpen = false

  var body: some View {
    Button {
      present()
    } label: {
      label(isOpen)
    }
    .buttonStyle(AnnotateAIDockItemStyle(isActive: isOpen))
    .background(MenuAnchorView(anchor: anchor))
    .help(help)
  }

  private func present() {
    guard let view = anchor.view else { return }
    let menu = makeMenu()
    isOpen = true
    let top = view.isFlipped ? -6 : view.bounds.height + 6
    // Position the menu's bottom edge just above the segment.
    let origin = NSPoint(x: 0, y: top)
    menu.popUp(positioning: nil, at: origin, in: view)
    isOpen = false
  }
}

struct AnnotateAIDockItemStyle: ButtonStyle {
  var isActive: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    AnnotateAIDockItemBody(configuration: configuration, isActive: isActive)
  }
}

struct AnnotateAIDockItemBody: View {
  let configuration: ButtonStyleConfiguration
  let isActive: Bool

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  var body: some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(foreground)
      .frame(minWidth: AnnotateAIDockView.itemHeight)
      .frame(height: AnnotateAIDockView.itemHeight)
      .background {
        Capsule(style: .continuous)
          .fill(fill)
      }
      .contentShape(Capsule(style: .continuous))
      .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
      .onHover { hovering in
        withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering && isEnabled }
      }
      .onChange(of: isEnabled) { enabled in
        if !enabled { isHovered = false }
      }
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
      .animation(LiquidGlassTokens.settleSpring, value: isActive)
  }

  private var fill: Color {
    if isActive { return Color.accentColor.opacity(0.22) }
    if configuration.isPressed && isEnabled { return Color.primary.opacity(0.12) }
    return Color.primary.opacity(isHovered ? 0.08 : 0)
  }

  private var foreground: Color {
    guard isEnabled else { return LiquidGlassTokens.inkFaint }
    if isActive { return .accentColor }
    return isHovered ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkBody
  }
}

struct AnnotateAIDockPressStyle: ButtonStyle {
  var pressedScale: CGFloat = 0.92

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? pressedScale : 1)
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }
}

struct AnnotateAIDockHairline: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.12))
      .frame(width: 1, height: 18)
      // Same height as the items so the bottom-aligned dock row centers the rule.
      .frame(height: AnnotateAIDockView.itemHeight)
      .padding(.horizontal, 5)
  }
}
