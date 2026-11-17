//
//  VideoEditorAIDockView.swift
//  Snapzy
//
//  Floating AI dock at the bottom center of the Video Editor player, in the same
//  glass and motion as the Annotate AI dock (its building blocks are shared). At
//  rest it is the AI orb; the orb or ⌘K grows it into the prompt:
//
//    [ orb ] [ Describe how to edit the video…   ] [ ◉ ⌄ ] [ ↑ ]
//
//  While the agent works the field becomes a live status line, Stop replaces Send
//  and the dock carries the reading rim. The result pill sits above the dock.
//

import AppKit
import SwiftUI

struct VideoEditorAIDockView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var agent: VideoEditorAgentController
  /// Widest the dock may grow (the player width minus margins).
  let maxWidth: CGFloat

  init(state: VideoEditorState, maxWidth: CGFloat) {
    self.state = state
    _agent = ObservedObject(wrappedValue: state.agent)
    self.maxWidth = maxWidth
  }

  @State private var promptGlow: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var expandAnimation: Animation {
    reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.86)
  }

  private var isPrompt: Bool { agent.isPromptPresented }

  private var dockShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
  }

  var body: some View {
    VStack(spacing: 10) {
      VideoEditorAgentNoticePill(agent: agent, state: state)
      if agent.isAvailable || agent.isRunning {
        dock
          .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
      }
    }
    .animation(.easeOut(duration: 0.18), value: agent.isAvailable)
  }

  private var dock: some View {
    HStack(alignment: .bottom, spacing: 0) {
      AnnotateAIDockOrb(
        isExpanded: isPrompt,
        isWorking: agent.isRunning,
        label: L10n.VideoEditorAI.askHelp
      ) {
        withAnimation(expandAnimation) { agent.togglePrompt() }
      }
      .disabled(agent.isRunning)

      if isPrompt {
        VideoEditorAIDockPromptRow(agent: agent, maxWidth: maxWidth)
          .transition(promptTransition)
      }
    }
    .padding(AnnotateAIDockView.inset)
    .frame(minHeight: AnnotateAIDockView.height)
    .clipShape(dockShape)
    .liquidGlassSurface(
      shape: dockShape,
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.04,
      highlight: .none,
      withRimLighting: true
    )
    .overlay {
      if agent.isRunning {
        TranslationReadingRim(shape: dockShape)
          .transition(.opacity)
      }
    }
    .overlay {
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
    .animation(.easeInOut(duration: 0.25), value: agent.isRunning)
    .animation(expandAnimation, value: isPrompt)
    .onChange(of: isPrompt) { presented in
      if presented { flashPromptGlow() }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.VideoEditorAI.askHelp)
  }

  private func flashPromptGlow() {
    guard !reduceMotion else { return }
    promptGlow = 0.9
    withAnimation(.easeOut(duration: 0.7).delay(0.15)) { promptGlow = 0 }
  }

  /// The field slides out of the orb; it leaves quickly with a little blur.
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

// MARK: - Prompt row

private struct VideoEditorAIDockPromptRow: View {
  @ObservedObject var agent: VideoEditorAgentController
  let maxWidth: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let minimumFieldWidth: CGFloat = 180
  private static let maximumFieldWidth: CGFloat = 340
  /// Width changes snap to this step so typing doesn't resize the glass on every key.
  private static let fieldWidthStep: CGFloat = 16
  /// Orb, provider, send and paddings.
  private static let chromeWidth: CGFloat = 140

  private var placeholderText: String {
    agent.hasConversation ? L10n.AnnotateAI.followUpPlaceholder : L10n.VideoEditorAI.placeholder
  }

  private var fieldWidth: CGFloat {
    let available = maxWidth - Self.chromeWidth
    var content = Self.textWidth(placeholderText)
    content = max(content, Self.textWidth(agent.isRunning ? agent.status : agent.draft))
    let stepped = ((content + 8) / Self.fieldWidthStep).rounded(.up) * Self.fieldWidthStep
    let upper = max(min(Self.maximumFieldWidth, available), Self.minimumFieldWidth)
    return min(max(stepped, Self.minimumFieldWidth), upper)
  }

  private static func textWidth(_ text: String) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    return ceil((text as NSString).size(withAttributes: [.font: AnnotateAIDockPromptField.font]).width)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ZStack(alignment: .leading) {
        // Mounted through a run (hidden under the status line) so the caret comes back after.
        AnnotateAIDockPromptField(
          text: $agent.draft,
          placeholder: placeholderText,
          focusRequest: agent.promptFocusRequest,
          isActive: !agent.isRunning,
          onSubmit: { agent.submit() },
          onEscape: { agent.handleEscape() }
        )
        .frame(height: AnnotateAIDockView.itemHeight)
        .accessibilityLabel(L10n.VideoEditorAI.askHelp)
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
  }

  private var providerChip: some View {
    let provider = agent.provider
    return AnnotateAIDockMenuButton(help: provider?.displayName ?? L10n.AnnotateAI.notConfigured, makeMenu: providerMenu) { _ in
      HStack(spacing: 5) {
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
      // Apple Intelligence can't edit videos yet.
      showsAppleIntelligence: false,
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

// MARK: - Result pill

/// Result of the last prompt, above the dock: summary, Undo, close. Hidden while running.
struct VideoEditorAgentNoticePill: View {
  @ObservedObject var agent: VideoEditorAgentController
  /// Observed so Undo disappears once the user edits on their own.
  @ObservedObject var state: VideoEditorState
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
  private func content(_ notice: VideoEditorAgentController.Notice) -> some View {
    HStack(spacing: 10) {
      switch notice {
      case .finished(let message, _):
        AnnotateAgentGlyph(size: 12)
        Text(message)
          .lineLimit(2)
          .frame(maxWidth: 420, alignment: .leading)
        undoButton
      case .stopped(let count):
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

  /// Gone once the user edits on their own (the run's step is no longer the latest).
  @ViewBuilder
  private var undoButton: some View {
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
