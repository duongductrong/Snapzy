//
//  VideoEditorAIPanelView.swift
//  Snapzy
//
//  The Video Editor AI assistant as a right sidebar. The toolbar's AI button or ⌘K
//  shows it; it keeps the conversation while the user edits on their own. One of two
//  layouts (Settings › AI › Video Editor); the other is the floating VideoEditorAIDockView.
//
//    ┌ ✦ AI Assistant            ✎  × ┐   header on the toolbar line; × replaces the AI toggle
//    │  empty: one-click edits,        │
//    │  example prompts                │
//    │                   [ prompt ]    │   user bubble
//    │  ✦ reply text                   │   assistant reply
//    │   ✂ Cut 0:10.0 – 0:15.0  −5 s › │   edit steps; click = move the playhead there
//    │   ⊕ Zoom 2× at 0:12.0    2 s  › │
//    │   2 changes · Undo              │
//    ├─────────────────────────────────┤
//    │ Describe how to edit…           │   composer
//    │ ◉ Provider ⌄              [↑]   │
//    └─────────────────────────────────┘
//

import AppKit
import CoreMedia
import SwiftUI

/// Observes nothing itself: the header and composer observe the agent, the transcript follows
/// an Equatable snapshot. Typing re-renders only the composer; playback and timeline edits
/// re-render nothing here.
struct VideoEditorAIPanelView: View {
  private let state: VideoEditorState
  private let agent: VideoEditorAgentController

  static let width: CGFloat = 340
  /// Gap between the floating panel and the window edges (top, trailing, bottom).
  static let inset: CGFloat = 8

  /// Outer corner; everything inside is concentric with it (outer − inset).
  static let cornerRadius: CGFloat = Radius.panel
  /// Inner surfaces (composer, cards, bubbles, rows), concentric with the 8 pt composer inset.
  static let innerRadius: CGFloat = Radius.panel - 8
  static let tileRadius: CGFloat = 6

  private var panelShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
  }

  init(state: VideoEditorState) {
    self.state = state
    agent = state.agent
  }

  var body: some View {
    VStack(spacing: 0) {
      VideoEditorAIPanelHeader(agent: agent)
      VideoEditorAIHairline()
      VideoEditorAITranscriptView(agent: agent, onSeek: { [weak state] time in
        guard let state else { return }
        state.pause()
        state.seek(to: CMTime(seconds: time, preferredTimescale: 600))
      })
      VideoEditorAIComposer(agent: agent)
    }
    .frame(width: Self.width)
    .frame(maxHeight: .infinity)
    .clipShape(panelShape)
    .liquidGlassSurface(
      shape: panelShape,
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.04,
      layer: .backdrop,
      withRimLighting: true
    )
    .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.VideoEditorAI.panelTitle)
  }
}

// MARK: - Header

private struct VideoEditorAIPanelHeader: View {
  @ObservedObject var agent: VideoEditorAgentController

  /// The header row spans the toolbar band minus the top inset on each side, so its controls
  /// sit on the toolbar's centre line.
  private static var headerHeight: CGFloat {
    let toolbar = WindowSpacingConfiguration.default
    return toolbar.toolbarHeight + 2 * toolbar.toolbarVPadding - 2 * VideoEditorAIPanelView.inset
  }

  /// Trailing gap so the close button's trailing edge matches the toolbar's trailing padding.
  private static var headerTrailingPadding: CGFloat {
    WindowSpacingConfiguration.default.toolbarHPadding - VideoEditorAIPanelView.inset
  }

  var body: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      AnnotateAgentGlyph(size: 14)
      Text(L10n.VideoEditorAI.panelTitle)
        .font(.system(size: 13, weight: .semibold))
      Spacer(minLength: 0)
      // Same control as the toolbar, so the header reads as the toolbar continuing into the panel.
      ToolbarButton(icon: "square.and.pencil", isSelected: false) {
        withAnimation(.easeInOut(duration: 0.2)) { agent.startNewConversation() }
      }
      .disabled(agent.isRunning || !agent.hasMessages)
      .help(L10n.VideoEditorAI.newConversation)
      .accessibilityLabel(L10n.VideoEditorAI.newConversation)
      // Ends the toolbar line at the window's trailing padding, where the AI toggle was.
      ToolbarButton(icon: "xmark", isSelected: false) {
        agent.dismissPrompt()
      }
      .help(VideoEditorShortcutManager.shared.helpText(L10n.Common.close, for: .aiPrompt))
      .accessibilityLabel(L10n.Common.close)
    }
    .padding(.leading, 16)
    .padding(.trailing, Self.headerTrailingPadding)
    .frame(height: Self.headerHeight)
  }
}

// MARK: - Transcript

private struct VideoEditorAITranscriptView: View {
  let agent: VideoEditorAgentController
  let onSeek: (TimeInterval) -> Void

  @State private var snapshot = VideoEditorAgentController.Transcript()

  private static let bottomID = "video-editor-ai-bottom"

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: true) {
        LazyVStack(alignment: .leading, spacing: 14) {
          if snapshot.messages.isEmpty {
            VideoEditorAIEmptyState(agent: agent, snapshot: snapshot)
          } else {
            ForEach(snapshot.messages) { message in
              switch message.role {
              case .user:
                VideoEditorAIUserBubble(text: message.text)
                  .equatable()
                  .id(message.id)
              case .assistant:
                VideoEditorAIReplyView(
                  message: message,
                  // Only the reply in flight shows the status line.
                  status: message.outcome == .running ? snapshot.status : "",
                  canUndo: snapshot.undoableMessageID == message.id,
                  onUndo: { [weak agent] in agent?.undoLastRun() },
                  onSeek: onSeek
                )
                .equatable()
                .id(message.id)
              }
            }
          }
          Color.clear.frame(height: 1).id(Self.bottomID)
        }
        .padding(14)
      }
      .onChange(of: snapshot.messages) { _ in
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
      }
      .onAppear {
        snapshot = agent.transcript
        proxy.scrollTo(Self.bottomID, anchor: .bottom)
      }
    }
    .onReceive(agent.transcriptPublisher) { snapshot = $0 }
    .frame(maxHeight: .infinity)
  }
}

// MARK: - Empty state

private struct VideoEditorAIEmptyState: View {
  let agent: VideoEditorAgentController
  let snapshot: VideoEditorAgentController.Transcript

  private var examples: [String] {
    [
      L10n.VideoEditorAI.exampleCut,
      L10n.VideoEditorAI.exampleZoom,
      L10n.VideoEditorAI.exampleSpeed,
      L10n.VideoEditorAI.exampleBackground,
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        AnnotateAgentGlyph(size: 26)
        Text(L10n.VideoEditorAI.emptyTitle)
          .font(.system(size: 15, weight: .semibold))
        Text(L10n.VideoEditorAI.emptySubtitle)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 8)

      if snapshot.showsQuickActions {
        section(L10n.VideoEditorAI.quickActionsHeader) {
          ForEach(snapshot.quickActions) { action in
            VideoEditorAISuggestionRow(symbol: action.symbolName, title: action.title, trailingSymbol: "bolt.fill") {
              agent.runQuickAction(action)
            }
          }
        }
      }

      if VideoEditorAgentProviderResolver.isFeatureAvailable {
        section(L10n.VideoEditorAI.examplesHeader) {
          ForEach(examples, id: \.self) { example in
            VideoEditorAISuggestionRow(symbol: "text.bubble", title: example, trailingSymbol: "arrow.up.left") {
              agent.draft = example
              agent.focusPrompt()
            }
          }
        }
      }
    }
    .disabled(snapshot.isRunning)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.leading, 2)
      VStack(spacing: 4) { content() }
    }
  }
}

private struct VideoEditorAISuggestionRow: View {
  let symbol: String
  let title: String
  let trailingSymbol: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .frame(width: 18)
        Text(title)
          .font(.system(size: 12))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
        Image(systemName: trailingSymbol)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)
          .opacity(isHovered ? 1 : 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous)
          .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
      )
      .contentShape(RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
    }
    .help(title)
  }
}

// MARK: - Messages

private struct VideoEditorAIUserBubble: View, Equatable {
  let text: String

  var body: some View {
    HStack {
      Spacer(minLength: 40)
      Text(text)
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .textSelection(.enabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous)
            .fill(Color.accentColor)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(L10n.VideoEditorAI.you): \(text)")
  }
}

/// Equatable on what it shows (closures excluded), so a new step or status on the reply in
/// flight leaves earlier replies untouched.
private struct VideoEditorAIReplyView: View, Equatable {
  let message: VideoEditorAgentMessage
  let status: String
  let canUndo: Bool
  let onUndo: () -> Void
  let onSeek: (TimeInterval) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.message == rhs.message && lhs.status == rhs.status && lhs.canUndo == rhs.canUndo
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      avatar
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 8) {
        if let title = message.quickActionTitle {
          Label(title, systemImage: "bolt.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }

        if !message.steps.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(message.steps.enumerated()), id: \.element.id) { index, step in
              if index > 0 { Divider().padding(.leading, 34) }
              VideoEditorAIStepRow(step: step, isUndone: message.isUndone, onSeek: onSeek)
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous))
          .background(
            RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous)
              .fill(Color.primary.opacity(0.06))
          )
          .overlay(
            RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.08))
          )
          .transition(.opacity)
        }

        content

        if message.outcome != .running {
          footer
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .animation(.easeOut(duration: 0.2), value: message.steps.count)
    .animation(.easeOut(duration: 0.2), value: message.outcome)
  }

  @ViewBuilder
  private var avatar: some View {
    switch message.outcome {
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 12))
        .foregroundStyle(.orange)
    case .stopped:
      Image(systemName: "stop.circle.fill")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    case .running, .finished:
      AnnotateAgentGlyph(size: 14)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch message.outcome {
    case .running:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.8)
        AnnotateAIDockStatusLine(text: status)
      }
      .frame(height: 20)
    case .stopped:
      Text(L10n.AnnotateAI.stopped)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    case .failed(let offersSettings):
      VStack(alignment: .leading, spacing: 6) {
        Text(message.text)
          .font(.system(size: 13))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        if offersSettings {
          Button(L10n.AnnotateAI.settings) { AnnotateAgentAISettings.open() }
            .controlSize(.small)
        }
      }
    case .finished:
      if !message.text.isEmpty {
        Text(Self.markdown(message.text))
          .font(.system(size: 13))
          .foregroundStyle(message.isUndone ? .secondary : .primary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var footer: some View {
    let showsCount = message.changeCount > 0
    if showsCount || canUndo || message.isUndone {
      HStack(spacing: 8) {
        if message.isUndone {
          Label(L10n.VideoEditorAI.undone, systemImage: "arrow.uturn.backward")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        } else if showsCount {
          Label(L10n.AnnotateAI.changes(message.changeCount), systemImage: "checkmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        }
        Spacer(minLength: 0)
        if canUndo {
          Button {
            onUndo()
          } label: {
            Label(L10n.Common.undo, systemImage: "arrow.uturn.backward")
              .font(.system(size: 11, weight: .medium))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
  }

  /// Parsed once per reply text: re-parsing markdown on every render is the costliest thing here.
  private static var markdownCache: [String: AttributedString] = [:]

  private static func markdown(_ text: String) -> AttributedString {
    if let cached = markdownCache[text] { return cached }
    let parsed = (try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
    if markdownCache.count > 100 { markdownCache.removeAll(keepingCapacity: true) }
    markdownCache[text] = parsed
    return parsed
  }
}

private struct VideoEditorAIStepRow: View {
  let step: VideoEditorAgentStep
  let isUndone: Bool
  let onSeek: (TimeInterval) -> Void

  @State private var isHovered = false

  var body: some View {
    Button {
      if let time = step.time { onSeek(time) }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: step.symbolName)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(isUndone ? Color.secondary : Color.accentColor)
          .frame(width: 18, height: 18)
          .background(
            RoundedRectangle(cornerRadius: VideoEditorAIPanelView.tileRadius, style: .continuous)
              .fill((isUndone ? Color.secondary : Color.accentColor).opacity(0.14))
          )
        Text(step.title)
          .font(.system(size: 12, weight: .medium))
          .strikethrough(isUndone, color: .secondary)
          .foregroundStyle(isUndone ? .secondary : .primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 4)
        if let detail = step.detail {
          Text(detail)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if step.time != nil {
          Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
            .opacity(isHovered ? 1 : 0.4)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(isHovered && step.time != nil ? 0.05 : 0))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(step.time == nil)
    .onHover { hovering in isHovered = hovering }
    .help(step.time != nil ? L10n.VideoEditorAI.jumpHelp : step.title)
  }
}

// MARK: - Composer

private struct VideoEditorAIComposer: View {
  @ObservedObject var agent: VideoEditorAgentController

  private var placeholderText: String {
    agent.hasConversation ? L10n.AnnotateAI.followUpPlaceholder : L10n.VideoEditorAI.placeholder
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let error = agent.composerError {
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(error.message)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if error.offersSettings {
            Button(L10n.AnnotateAI.settings) {
              agent.dismissComposerError()
              AnnotateAgentAISettings.open()
            }
            .controlSize(.small)
          }
          Button {
            agent.dismissComposerError()
          } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help(L10n.Common.close)
        }
        .font(.system(size: 11))
        .transition(.opacity)
      }

      VStack(alignment: .leading, spacing: 6) {
        AnnotateAIDockPromptField(
          text: $agent.draft,
          placeholder: placeholderText,
          focusRequest: agent.promptFocusRequest,
          isActive: !agent.isRunning,
          onSubmit: { agent.submit() },
          onEscape: { agent.handleEscape() },
          onFocusChange: { [weak agent] focused in
            // Called from AppKit responder changes, possibly mid view update.
            DispatchQueue.main.async { agent?.isPromptFieldFocused = focused }
          }
        )
        .frame(height: 22)
        .accessibilityLabel(L10n.VideoEditorAI.askHelp)

        HStack(spacing: 4) {
          providerChip
          Spacer(minLength: 0)
          sendButton
        }
      }
      .padding(.leading, 10)
      .padding(.trailing, 4)
      .padding(.top, 8)
      .padding(.bottom, 4)
      .background(
        RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous)
          .fill(Color.primary.opacity(0.07))
      )
      .overlay(
        RoundedRectangle(cornerRadius: VideoEditorAIPanelView.innerRadius, style: .continuous)
          .strokeBorder(agent.isPromptFieldFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: 1)
      )
      .contentShape(Rectangle())
      .onTapGesture { agent.focusPrompt() }
    }
    .padding(8)
    .animation(.easeOut(duration: 0.15), value: agent.composerError)
    .animation(.easeOut(duration: 0.15), value: agent.isPromptFieldFocused)
  }

  private var providerChip: some View {
    let provider = agent.provider
    // Hug the content and match the 26pt send button so the chip doesn't stretch or tower over it.
    return AnnotateAIDockMenuButton(
      help: provider?.displayName ?? L10n.AnnotateAI.notConfigured,
      itemHeight: 26,
      makeMenu: providerMenu
    ) { _ in
      HStack(spacing: 5) {
        AnnotateAgentProviderIcon(
          symbolName: provider?.symbolName ?? "exclamationmark.circle",
          logoImageName: provider?.logoImageName
        )
        Text(provider?.displayName ?? L10n.AnnotateAI.notConfigured)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
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

// MARK: - Hairline

/// A soft separator that reads on glass (the system Divider is too heavy there).
private struct VideoEditorAIHairline: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.08))
      .frame(height: 1)
      .padding(.horizontal, 12)
  }
}
