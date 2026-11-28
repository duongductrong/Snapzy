//
//  VideoEditorAgentController.swift
//  Snapzy
//
//  UI state and run loop of the Video Editor AI prompt, one per editor window.
//
//  - The AI panel (right sidebar) shows while `isPromptPresented`; while a run is in flight
//    the editor locks authoring (play stays live).
//  - `messages` is what the panel lists: prompts, replies and each reply's edits as steps.
//  - A run is one undo group (`VideoEditorAgentToolbox.beginRun/finishRun`): the reply's
//    Undo, or ⌘Z, takes the whole prompt back.
//  - A conversation (toolbox ids, earlier turns) lives until the user starts a new one
//    or picks another provider.
//
//  Same shape as `AnnotateAgentController`, minus the canvas parts (image analysis,
//  marks, cursor). A shared run controller is worth extracting once the two settle.
//

import AppKit
import Combine
import CoreMedia
import Foundation
import SwiftUI

@MainActor
final class VideoEditorAgentController: ObservableObject {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  enum Phase: Equatable {
    case idle
    /// Waiting for the provider's first step.
    case reading
    /// The provider is changing the timeline.
    case acting
  }

  enum Notice: Equatable {
    case finished(message: String, changeCount: Int)
    case stopped(changeCount: Int)
    case failed(message: String, offersSettings: Bool)
  }

  /// One-click edits worked out in the app, no model needed (chips above an empty prompt).
  enum QuickAction: String, CaseIterable, Identifiable {
    case removeSilences
    case speedUpIdle
    case autoZoom
    /// Studio recordings with clicks: zoom on each burst of clicks.
    case clickZoom
    /// Captions from the speech, while the video has none.
    case captions

    var id: String { rawValue }

    var tool: VideoEditorAgentToolName {
      switch self {
      case .removeSilences: .removeSilences
      case .speedUpIdle: .speedUpIdle
      case .autoZoom, .clickZoom: .autoZoomActivity
      case .captions: .generateCaptions
      }
    }

    var argumentsJSON: String {
      self == .clickZoom ? #"{"source":"clicks"}"# : "{}"
    }

    var title: String {
      switch self {
      case .removeSilences: L10n.VideoEditorAI.suggestionSilences
      case .speedUpIdle: L10n.VideoEditorAI.suggestionIdle
      case .autoZoom: L10n.VideoEditorAI.suggestionAutoZoom
      case .clickZoom: L10n.VideoEditorAI.suggestionClickZoom
      case .captions: L10n.VideoEditorAI.suggestionCaptions
      }
    }

    var symbolName: String {
      switch self {
      case .removeSilences: "waveform.badge.minus"
      case .speedUpIdle: "forward.fill"
      case .autoZoom: "plus.magnifyingglass"
      case .clickZoom: "cursorarrow.click.2"
      case .captions: "captions.bubble"
      }
    }
  }

  static let noticeLifetime: TimeInterval = 6
  /// Consent asked for Annotate does not cover video: it sends different data.
  /// "media": screen text, speech and frames joined the timeline in phase 6, so an earlier
  /// yes for the timeline alone is asked again.
  static let consentScope = "video-media"

  /// The prompt text, in its own store: only the prompt field observes it, so a keystroke
  /// re-renders the field alone instead of every view observing the controller.
  final class Draft: ObservableObject {
    @Published var text = ""

    /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
    /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
    nonisolated deinit {}
  }

  @Published var isPromptPresented = false
  let draftStore = Draft()
  /// Whether the draft holds more than whitespace. Published only when that flips, for the
  /// send button and the dock's quick-action chips.
  @Published private(set) var hasDraftText = false

  var draft: String {
    get { draftStore.text }
    set {
      guard draftStore.text != newValue else { return }
      draftStore.text = newValue
      let hasText = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      if hasDraftText != hasText { hasDraftText = hasText }
    }
  }

  /// Two-way binding for the prompt field that keeps `hasDraftText` in step.
  var draftBinding: Binding<String> {
    Binding(get: { [draftStore] in draftStore.text }, set: { [weak self] in self?.draft = $0 })
  }
  /// Bumped whenever the prompt field should take the caret (the field watches it).
  @Published private(set) var promptFocusRequest = 0
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var status = ""
  @Published private(set) var notice: Notice?
  @Published private(set) var turns: [AgentTurn] = []
  /// The conversation as the panel shows it (quick actions included).
  @Published private(set) var messages: [VideoEditorAgentMessage] = []
  /// The prompt field holds the keyboard; single-key editing shortcuts stand down.
  @Published var isPromptFieldFocused = false
  /// Why the last send or quick action could not start (no provider, busy). Shown over the composer.
  @Published private(set) var composerError: ComposerError?

  struct ComposerError: Equatable {
    let message: String
    let offersSettings: Bool
  }

  private weak var state: VideoEditorState?
  private let resolveProvider: @MainActor () -> AgentProvider?
  private let pacingEnabled: Bool
  private let defaults: UserDefaults
  /// Asks before the first prompt goes to an off-device provider. `true` = send.
  private let confirmRemoteUse: @MainActor (AgentRemoteDestination) async -> Bool
  @Published private(set) var isConfirmingRemoteUse = false

  private var toolbox: VideoEditorAgentToolbox?
  /// Lives with the window, so the recording is analyzed once across conversations.
  let analyzer = VideoEditorAgentAnalyzer()
  /// Provider the current conversation was held with; a change made elsewhere (Settings › AI)
  /// starts a new conversation on the next prompt.
  private var conversationSelection: AgentProviderSelection?
  private var runTask: Task<Void, Never>?
  private var operationID: UUID?
  private var noticeTask: Task<Void, Never>?
  /// The session of the run in flight; invalidated when it ends so late calls bounce.
  private var session: AgentSession?
  /// The toolbox's run began (undo group open). Before that, a Stop has nothing to close.
  private var didBeginRun = false
  /// The undo entry the last run pushed. Undo is offered while it is still the latest.
  private var undoEntryAfterRun: EditorAction?
  /// Only a finished run adds a turn; undoing a stopped or failed one keeps the history.
  private var lastRunAddedTurn = false
  /// The assistant message the run in flight writes into.
  private var replyMessageID: UUID?

  init(
    state: VideoEditorState,
    pacingEnabled: Bool = true,
    defaults: UserDefaults = .standard,
    resolveProvider: (@MainActor () -> AgentProvider?)? = nil,
    confirmRemoteUse: (@MainActor (AgentRemoteDestination) async -> Bool)? = nil
  ) {
    self.state = state
    self.pacingEnabled = pacingEnabled
    self.defaults = defaults
    self.resolveProvider = resolveProvider ?? { VideoEditorAgentProviderResolver.resolve(defaults: defaults) }
    self.confirmRemoteUse = confirmRemoteUse ?? { await VideoEditorAgentController.askRemoteUse($0) }
  }

  // MARK: - Derived

  var isRunning: Bool { phase != .idle }
  var hasConversation: Bool { !turns.isEmpty }
  /// Single-key editing shortcuts (S, Z, I, O, Delete) stand down while the prompt field has
  /// the keyboard, so typing in it never splits or deletes, and while a run holds the timeline.
  var allowsPlainKeyShortcuts: Bool { !(isPromptPresented && isPromptFieldFocused) && !isRunning }
  var hasMessages: Bool { !messages.isEmpty }

  var canSend: Bool {
    !isRunning && !isConfirmingRemoteUse && hasDraftText
  }

  /// GIFs can only be resized, so the AI has nothing to do there. Without a provider the
  /// dock still shows when a quick action can run.
  var isAvailable: Bool {
    guard let state, !state.isGIF else { return false }
    return VideoEditorAgentProviderResolver.isFeatureAvailable || !quickActions.isEmpty
  }

  /// Quick actions the open video has the data for: audio for silences, the recorded cursor
  /// for idle parts and activity zooms (click zooms when a Studio recording captured clicks),
  /// speech for captions while there are none.
  var quickActions: [QuickAction] {
    guard let state, !state.isGIF, !state.clips.isEmpty else { return [] }
    var actions: [QuickAction] = []
    if !state.audioTrackRoles.isEmpty { actions.append(.removeSilences) }
    let hasClicks = state.recordingMetadata?.cursorCapture?.clicks.contains { $0.phase == .down } == true
    if state.hasMouseTrackingData { actions.append(.speedUpIdle) }
    if hasClicks {
      actions.append(.clickZoom)
    } else if state.hasMouseTrackingData {
      actions.append(.autoZoom)
    }
    if state.canGenerateCaptions, state.captions.isEmpty { actions.append(.captions) }
    return actions
  }

  /// Where the assistant shows (Settings › AI). Read live so a change applies to open editors.
  var layout: VideoEditorAILayout { VideoEditorAILayout.current(defaults) }

  /// Quick actions show in the panel's empty state, or as chips over the dock's empty, idle prompt.
  var showsQuickActions: Bool { showsQuickActions(for: quickActions) }

  private func showsQuickActions(for actions: [QuickAction]) -> Bool {
    guard isPromptPresented, !isRunning, !isConfirmingRemoteUse, !actions.isEmpty else { return false }
    switch layout {
    case .sidebar:
      return messages.isEmpty
    case .dock:
      return notice == nil && !hasDraftText
    }
  }

  // MARK: - Snapshots
  //
  // The editor chrome and the panel's transcript each subscribe to a small Equatable snapshot
  // instead of observing the whole controller, so typing in the prompt (`draft` changes on every
  // key) never re-renders the editor, toolbar or conversation.

  /// What the editor around the assistant needs: presentation, the run lock, shortcut gating.
  struct Chrome: Equatable {
    var isPromptPresented = false
    var isRunning = false
    var allowsPlainKeyShortcuts = true
  }

  var chrome: Chrome {
    Chrome(
      isPromptPresented: isPromptPresented,
      isRunning: isRunning,
      allowsPlainKeyShortcuts: allowsPlainKeyShortcuts
    )
  }

  /// What the panel's conversation shows. `status` only while a run is in flight.
  struct Transcript: Equatable {
    var messages: [VideoEditorAgentMessage] = []
    var status = ""
    var undoableMessageID: UUID?
    var isRunning = false
    var quickActions: [QuickAction] = []
    var showsQuickActions = false
  }

  var transcript: Transcript {
    let actions = quickActions
    return Transcript(
      messages: messages,
      status: isRunning ? status : "",
      undoableMessageID: undoableMessageID,
      isRunning: isRunning,
      quickActions: actions,
      showsQuickActions: showsQuickActions(for: actions)
    )
  }

  /// `objectWillChange` fires before the new value lands, so snapshots are read on the next
  /// main-queue turn, when every property is settled. Undo-stack changes also matter
  /// (Undo disappears once the user edits on their own).
  private lazy var settledChanges: AnyPublisher<Void, Never> = {
    var sources: [AnyPublisher<Void, Never>] = [objectWillChange.map { _ in () }.eraseToAnyPublisher()]
    if let state { sources.append(state.$canUndo.map { _ in () }.eraseToAnyPublisher()) }
    // One snapshot pass per main-queue turn: `presentPrompt` alone writes three
    // properties, and each used to rebuild every snapshot (quick actions included) and add
    // a hop before the editor could start the panel slide.
    return Publishers.MergeMany(sources)
      .debounce(for: .zero, scheduler: DispatchQueue.main)
      .share()
      .eraseToAnyPublisher()
  }()

  lazy var chromePublisher: AnyPublisher<Chrome, Never> = settledChanges
    .compactMap { [weak self] in self?.chrome }
    .removeDuplicates()
    .eraseToAnyPublisher()

  lazy var transcriptPublisher: AnyPublisher<Transcript, Never> = settledChanges
    .compactMap { [weak self] in self?.transcript }
    .removeDuplicates()
    .eraseToAnyPublisher()

  /// Whether the run's Undo is still offered, for the dock's result pill.
  lazy var canUndoLastRunPublisher: AnyPublisher<Bool, Never> = settledChanges
    .compactMap { [weak self] in self?.canUndoLastRun }
    .removeDuplicates()
    .eraseToAnyPublisher()

  /// The id of the reply whose changes Undo would take back.
  var undoableMessageID: UUID? {
    canUndoLastRun ? messages.last(where: { $0.role == .assistant })?.id : nil
  }

  var provider: AgentProvider? { resolveProvider() }

  var providerSelection: AgentProviderSelection {
    AgentProviderResolver.selection(defaults: defaults)
  }

  /// The run's Undo is meaningful only while its step is still the latest on the stack.
  var canUndoLastRun: Bool {
    guard !isRunning, let state, let entry = undoEntryAfterRun else { return false }
    return state.lastUndoEntry == entry
  }

  // MARK: - Prompt presentation

  func presentPrompt() {
    guard isAvailable || isRunning else { return }
    isPromptPresented = true
    isPromptFieldFocused = true
    promptFocusRequest &+= 1
    schedulePrewarm()
  }

  /// Records where the keyboard is, publishing only real changes (AppKit reports focus
  /// repeatedly, and every publish re-renders the views observing the controller).
  func setPromptFieldFocused(_ focused: Bool) {
    guard isPromptFieldFocused != focused else { return }
    isPromptFieldFocused = focused
  }

  private var prewarmWork: DispatchWorkItem?

  /// Starts the background work the first prompt needs (CLI scan, the recording's analysis,
  /// the on-device model) once the panel has finished sliding in, so it doesn't compete with
  /// the animation for the main thread and the CPU.
  private func schedulePrewarm() {
    prewarmWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.isPromptPresented else { return }
      AnnotateAgentCLIDetector.shared.refresh()
      if let state = self.state { self.analyzer.prewarm(state) }
      // Load the on-device model while the user types (no-op without Apple Intelligence).
      VideoEditorAgentAppleIntelligence.prewarm()
    }
    prewarmWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.prewarmDelay, execute: work)
  }

  /// After the panel's slide-in has settled (spring ~0.32 s, started one turn after ⌘K),
  /// so the prewarm's main-thread setup never lands in the last frames of the slide.
  static let prewarmDelay: TimeInterval = 0.6

  /// Hides the panel; a run in flight keeps going (the toolbar button shows it working).
  /// The dock stays up through a run: its prompt row is where the status and Stop live.
  func dismissPrompt() {
    if isRunning, layout == .dock { return }
    isPromptPresented = false
    isPromptFieldFocused = false
  }

  /// Puts the caret in the prompt field (a click on the composer, an example prompt).
  func focusPrompt() {
    guard isPromptPresented else { return presentPrompt() }
    isPromptFieldFocused = true
    promptFocusRequest &+= 1
  }

  func togglePrompt() {
    isPromptPresented ? dismissPrompt() : presentPrompt()
  }

  /// ⌘K: open the prompt, put the caret back in it, or close it when it already has the caret.
  func handleShortcut(isFieldEditing: Bool) {
    if !isPromptPresented {
      presentPrompt()
    } else if isFieldEditing {
      dismissPrompt()
    } else {
      promptFocusRequest &+= 1
    }
  }

  /// Esc inside the field: stop a run, else clear the draft, else leave the prompt.
  func handleEscape() {
    if isRunning {
      stop()
    } else if !draft.isEmpty {
      draft = ""
    } else {
      dismissPrompt()
    }
  }

  // MARK: - Running

  func submit() {
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !isRunning, !isConfirmingRemoteUse, let state else { return }
    guard !state.isGIF, !state.isExporting, !state.clips.isEmpty else {
      composerError = ComposerError(message: L10n.VideoEditorAI.busy, offersSettings: false)
      showNotice(.failed(message: L10n.VideoEditorAI.busy, offersSettings: false))
      return
    }
    guard let provider = resolveProvider() else {
      composerError = ComposerError(message: L10n.VideoEditorAI.notConfigured, offersSettings: true)
      showNotice(.failed(message: L10n.VideoEditorAI.notConfigured, offersSettings: true))
      return
    }
    composerError = nil
    // The timeline leaves the Mac: ask once per provider, then send what was typed.
    if let destination = provider.remoteDestination, !remoteConsent.has(destination) {
      isConfirmingRemoteUse = true
      Task { [weak self] in
        guard let self else { return }
        let allowed = await self.confirmRemoteUse(destination)
        self.isConfirmingRemoteUse = false
        guard allowed else { return }
        self.remoteConsent.record(destination)
        self.submit()
      }
      return
    }

    if let conversationSelection, conversationSelection != providerSelection {
      resetConversation()
    }
    conversationSelection = providerSelection
    // Clicks on the player or Space while typing would otherwise compete with the run.
    state.pause()
    draft = ""
    dismissNotice()
    undoEntryAfterRun = nil
    lastRunAddedTurn = false
    didBeginRun = false
    status = L10n.VideoEditorAI.statusReading
    phase = .reading
    messages.append(.user(prompt))
    beginReply()

    let operationID = UUID()
    self.operationID = operationID
    DiagnosticLogger.shared.log(.info, .editor, "Video AI prompt started", context: [
      "provider": provider.displayName,
      "turn": "\(turns.count + 1)",
    ])

    runTask = Task { [weak self] in
      await self?.run(prompt: prompt, provider: provider, operationID: operationID)
    }
  }

  /// Keeps what the run already changed; the pill offers Undo for it.
  func stop() {
    guard isRunning, operationID != nil else { return }
    runTask?.cancel()
    runTask = nil
    operationID = nil
    let summary = didBeginRun ? toolbox?.finishRun() : nil
    endRun()
    let changes = summary?.changeCount ?? 0
    undoEntryAfterRun = summary?.undoEntry
    finishReply(outcome: .stopped, text: "", changeCount: changes)
    showNotice(.stopped(changeCount: changes))
    DiagnosticLogger.shared.log(.info, .editor, "Video AI prompt stopped", context: ["changes": "\(changes)"])
  }

  /// Undo for the last run: its whole undo group in one step.
  func undoLastRun() {
    guard let state, canUndoLastRun else { return }
    state.undo()
    undoEntryAfterRun = nil
    if let index = messages.lastIndex(where: { $0.role == .assistant }) {
      messages[index].isUndone = true
    }
    // The agent should not build on changes that were just taken back.
    if lastRunAddedTurn, !turns.isEmpty { turns.removeLast() }
    lastRunAddedTurn = false
    dismissNotice()
  }

  func startNewConversation() {
    guard !isRunning else { return }
    resetConversation()
    dismissNotice()
  }

  /// A different provider starts a new conversation: it never saw the earlier turns.
  func selectProvider(_ selection: AgentProviderSelection) {
    guard !isRunning, !isConfirmingRemoteUse, selection != providerSelection else { return }
    AgentProviderResolver.setSelection(selection, defaults: defaults)
    objectWillChange.send()
    resetConversation()
    dismissNotice()
  }

  func dismissComposerError() {
    composerError = nil
  }

  func dismissNotice() {
    noticeTask?.cancel()
    notice = nil
  }

  /// Keeps the result up while hovered.
  func holdNotice(_ isHeld: Bool) {
    noticeTask?.cancel()
    guard !isHeld, notice != nil else { return }
    scheduleNoticeDismissal()
  }

  private func resetConversation() {
    turns = []
    messages = []
    toolbox = nil
    undoEntryAfterRun = nil
  }

  // MARK: - Transcript

  private func beginReply(quickActionTitle: String? = nil) {
    let reply = VideoEditorAgentMessage.pendingReply(quickActionTitle: quickActionTitle)
    replyMessageID = reply.id
    messages.append(reply)
  }

  private func updateReply(_ change: (inout VideoEditorAgentMessage) -> Void) {
    guard let replyMessageID, let index = messages.firstIndex(where: { $0.id == replyMessageID }) else { return }
    change(&messages[index])
  }

  private func finishReply(outcome: VideoEditorAgentMessage.Outcome, text: String, changeCount: Int) {
    updateReply {
      $0.outcome = outcome
      $0.text = text
      $0.changeCount = changeCount
    }
    replyMessageID = nil
  }

  private func makeToolbox(_ state: VideoEditorState) -> VideoEditorAgentToolbox {
    if let toolbox { return toolbox }
    let toolbox = VideoEditorAgentToolbox(state: state, analyzer: analyzer)
    toolbox.onExecuted = { [weak self] tool, arguments, result in
      guard let self, let step = VideoEditorAgentStepDescriber.step(for: tool, argumentsJSON: arguments, result: result) else { return }
      self.updateReply { $0.steps.append(step) }
    }
    self.toolbox = toolbox
    return toolbox
  }

  private func run(prompt: String, provider: AgentProvider, operationID: UUID) async {
    guard isCurrent(operationID) else { return }
    guard let state else {
      self.operationID = nil
      endRun()
      finishReply(outcome: .failed(offersSettings: false), text: L10n.AnnotateAI.failed, changeCount: 0)
      return
    }

    let toolbox = makeToolbox(state)
    toolbox.beginRun()
    didBeginRun = true

    let session = AgentSession(
      toolbox: toolbox,
      pacingEnabled: pacingEnabled,
      onToolCall: { [weak self] name in
        guard let self, self.isCurrent(operationID) else { return }
        let tool = VideoEditorAgentToolName(rawValue: name)
        if let tool, let text = Self.status(for: tool) {
          self.status = text
        }
        if tool?.isReadOnly == false {
          self.phase = .acting
        }
      },
      onStatus: { [weak self] text in
        guard let self, self.isCurrent(operationID) else { return }
        self.status = text
      }
    )
    self.session = session
    let timeline = await toolbox.execute(name: VideoEditorAgentToolName.getTimeline.rawValue, argumentsJSON: "{}")
    let request = AgentRequest(
      prompt: prompt,
      history: turns,
      sceneJSON: timeline.text,
      scene: toolbox.scene(),
      // Text only for now; frames come with vision (phase 6).
      image: nil,
      resumeSessionID: turns.last?.providerSessionID
    )

    do {
      guard !timeline.isError else { throw AgentProviderError.failed(L10n.VideoEditorAI.busy) }
      let reply = try await provider.run(request, session: session)
      guard isCurrent(operationID) else { return }
      self.operationID = nil
      let summary = toolbox.finishRun()
      endRun()
      undoEntryAfterRun = summary.undoEntry
      turns.append(AgentTurn(prompt: prompt, reply: reply, providerSessionID: session.providerSessionID))
      lastRunAddedTurn = true
      let message = AgentReplyFormatter.oneLine(reply)
      let fullReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
      finishReply(
        outcome: .finished,
        text: fullReply.isEmpty
          ? (summary.changeCount == 0 ? L10n.AnnotateAI.noChanges : L10n.AnnotateAI.changes(summary.changeCount))
          : fullReply,
        changeCount: summary.changeCount
      )
      showNotice(.finished(
        message: message.isEmpty
          ? (summary.changeCount == 0 ? L10n.AnnotateAI.noChanges : L10n.AnnotateAI.changes(summary.changeCount))
          : message,
        changeCount: summary.changeCount
      ))
      DiagnosticLogger.shared.log(.info, .editor, "Video AI prompt finished", context: ["changes": "\(summary.changeCount)"])
    } catch {
      guard isCurrent(operationID) else { return }
      self.operationID = nil
      let summary = toolbox.finishRun()
      endRun()
      undoEntryAfterRun = summary.undoEntry
      if error is CancellationError {
        finishReply(outcome: .stopped, text: "", changeCount: summary.changeCount)
        showNotice(.stopped(changeCount: summary.changeCount))
        return
      }
      let message: String
      var offersSettings = false
      switch error {
      case AgentProviderError.notConfigured:
        message = L10n.VideoEditorAI.notConfigured
        offersSettings = true
      case AgentProviderError.failed(let detail):
        message = detail
      case AgentProviderError.needsSetup(let detail):
        message = detail
        offersSettings = true
      default:
        message = L10n.AnnotateAI.failed
      }
      finishReply(outcome: .failed(offersSettings: offersSettings), text: message, changeCount: summary.changeCount)
      showNotice(.failed(message: message, offersSettings: offersSettings))
      DiagnosticLogger.shared.log(.warning, .editor, "Video AI prompt failed", context: ["error": "\(error)"])
    }
  }

  // MARK: - Quick actions

  /// Runs one one-step tool directly: on-device, no provider, no consent. One undo step.
  func runQuickAction(_ action: QuickAction) {
    guard !isRunning, !isConfirmingRemoteUse, let state else { return }
    guard !state.isGIF, !state.isExporting, !state.clips.isEmpty else {
      composerError = ComposerError(message: L10n.VideoEditorAI.busy, offersSettings: false)
      showNotice(.failed(message: L10n.VideoEditorAI.busy, offersSettings: false))
      return
    }
    composerError = nil
    state.pause()
    dismissNotice()
    undoEntryAfterRun = nil
    lastRunAddedTurn = false
    didBeginRun = false
    status = L10n.VideoEditorAI.statusAnalyzing
    phase = .reading
    beginReply(quickActionTitle: action.title)

    let operationID = UUID()
    self.operationID = operationID
    DiagnosticLogger.shared.log(.info, .editor, "Video AI quick action started", context: ["action": action.rawValue])
    runTask = Task { [weak self] in
      await self?.runQuick(action, operationID: operationID)
    }
  }

  private func runQuick(_ action: QuickAction, operationID: UUID) async {
    guard isCurrent(operationID), let state else { return }
    // Analyze before the undo group opens, so a Stop while listening changes nothing.
    if action.tool.needsAnalysis {
      do {
        _ = try await analyzer.activity(for: state)
      } catch {
        guard isCurrent(operationID) else { return }
        self.operationID = nil
        endRun()
        finishReply(outcome: .failed(offersSettings: false), text: L10n.AnnotateAI.failed, changeCount: 0)
        showNotice(.failed(message: L10n.AnnotateAI.failed, offersSettings: false))
        return
      }
    }
    guard isCurrent(operationID) else { return }

    let toolbox = makeToolbox(state)
    toolbox.beginRun()
    didBeginRun = true
    status = Self.status(for: action.tool) ?? status
    phase = .acting
    let result = await toolbox.execute(name: action.tool.rawValue, argumentsJSON: action.argumentsJSON)
    guard isCurrent(operationID) else { return }
    self.operationID = nil

    let payload = (try? JSONSerialization.jsonObject(with: Data(result.text.utf8))) as? [String: Any] ?? [:]
    if let first = Self.firstChange(in: payload) {
      state.seek(to: CMTime(seconds: first, preferredTimescale: 600))
    }
    let summary = toolbox.finishRun()
    endRun()
    undoEntryAfterRun = summary.undoEntry
    if result.isError {
      let message = payload["error"] as? String ?? L10n.AnnotateAI.failed
      finishReply(outcome: .failed(offersSettings: false), text: message, changeCount: summary.changeCount)
      showNotice(.failed(message: message, offersSettings: false))
    } else {
      let message = Self.quickMessage(action, payload: payload)
      // The one step already says what happened; the reply text would repeat it.
      finishReply(outcome: .finished, text: summary.changeCount > 0 ? "" : message, changeCount: summary.changeCount)
      showNotice(.finished(message: message, changeCount: summary.changeCount))
    }
    DiagnosticLogger.shared.log(.info, .editor, "Video AI quick action finished", context: [
      "action": action.rawValue, "changes": "\(summary.changeCount)",
    ])
  }

  /// Where the earliest edit of a one-step tool landed (cut points before them don't move).
  private static func firstChange(in payload: [String: Any]) -> Double? {
    if let removed = payload["removed"] as? [[Double]], let first = removed.first?.first { return first }
    if let added = payload["added"] as? [[String: Any]], let first = added.first?["start"] as? Double { return first }
    return nil
  }

  static func quickMessage(_ action: QuickAction, payload: [String: Any]) -> String {
    switch action {
    case .removeSilences:
      let count = payload["cuts"] as? Int ?? 0
      guard count > 0 else { return L10n.VideoEditorAI.noSilences }
      let seconds = (payload["removed_seconds"] as? Double) ?? 0
      return L10n.VideoEditorAI.removedSilences(count, String(format: "%.1f", seconds))
    case .speedUpIdle:
      let count = (payload["added"] as? [Any])?.count ?? 0
      return count > 0 ? L10n.VideoEditorAI.spedUpIdle(count) : L10n.VideoEditorAI.noIdle
    case .autoZoom:
      let count = (payload["added"] as? [Any])?.count ?? 0
      return count > 0 ? L10n.VideoEditorAI.addedZooms(count) : L10n.VideoEditorAI.noActivity
    case .clickZoom:
      let count = (payload["added"] as? [Any])?.count ?? 0
      return count > 0 ? L10n.VideoEditorAI.addedClickZooms(count) : L10n.VideoEditorAI.noClicks
    case .captions:
      return L10n.VideoEditorAI.stepCaptions(payload["captions"] as? Int ?? 0)
    }
  }

  private func isCurrent(_ operationID: UUID) -> Bool {
    self.operationID == operationID && !Task.isCancelled
  }

  private func endRun() {
    session?.invalidate()
    session = nil
    didBeginRun = false
    phase = .idle
    status = ""
  }

  // MARK: - Remote consent

  private var remoteConsent: AgentRemoteConsent {
    AgentRemoteConsent(defaults: defaults, scope: Self.consentScope)
  }

  private static func askRemoteUse(_ destination: AgentRemoteDestination) async -> Bool {
    await AgentRemoteConsent.ask(
      destination,
      title: L10n.VideoEditorAI.consentTitle(destination.name),
      endpointMessage: L10n.VideoEditorAI.consentMessage(destination.host),
      cliMessage: L10n.VideoEditorAI.consentMessageCLI(destination.name)
    )
  }

  // MARK: - Notice

  private func showNotice(_ notice: Notice) {
    self.notice = notice
    scheduleNoticeDismissal()
    announce(notice)
  }

  /// VoiceOver hears the result even though focus stays in the prompt.
  private func announce(_ notice: Notice) {
    let text: String
    switch notice {
    case .finished(let message, _): text = message
    case .stopped(let count): text = count > 0 ? "\(L10n.AnnotateAI.stopped), \(L10n.AnnotateAI.changes(count))" : L10n.AnnotateAI.stopped
    case .failed(let message, _): text = message
    }
    guard let element = NSApp.keyWindow ?? NSApp.mainWindow else { return }
    NSAccessibility.post(
      element: element,
      notification: .announcementRequested,
      userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
    )
  }

  private func scheduleNoticeDismissal() {
    noticeTask?.cancel()
    noticeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.noticeLifetime * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.notice = nil
    }
  }

  // MARK: - Status text

  static func status(for tool: VideoEditorAgentToolName) -> String? {
    switch tool {
    case .getTimeline, .seek: nil
    case .cutRange: L10n.VideoEditorAI.statusCut
    case .trimClip: L10n.VideoEditorAI.statusTrim
    case .split: L10n.VideoEditorAI.statusSplit
    case .moveClip: L10n.VideoEditorAI.statusMove
    case .deleteClip, .closeGaps: L10n.VideoEditorAI.statusDelete
    case .addZoom: L10n.VideoEditorAI.statusZoom
    case .updateZoom, .removeZoom: L10n.VideoEditorAI.statusEditZoom
    case .addSpeed, .updateSpeed, .removeSpeed: L10n.VideoEditorAI.statusSpeed
    case .setBackground: L10n.VideoEditorAI.statusBackground
    case .setAudio: L10n.VideoEditorAI.statusAudio
    case .getActivity: L10n.VideoEditorAI.statusAnalyzing
    case .removeSilences: L10n.VideoEditorAI.statusSilences
    case .speedUpIdle: L10n.VideoEditorAI.statusIdle
    case .autoZoomActivity: L10n.VideoEditorAI.statusAutoZoom
    case .getFrame: L10n.VideoEditorAI.statusLooking
    case .findOnScreen: L10n.VideoEditorAI.statusFinding
    case .getTranscript: L10n.VideoEditorAI.statusTranscribing
    case .setCursor: L10n.VideoEditorAI.statusCursor
    case .setCamera: L10n.VideoEditorAI.statusCamera
    case .generateCaptions: L10n.VideoEditorAI.statusCaptions
    case .editCaption, .addCaption, .removeCaptions, .replaceInCaptions: L10n.VideoEditorAI.statusEditCaption
    case .getCaptions: nil
    case .translateCaptions: L10n.VideoEditorAI.statusTranslateCaptions
    }
  }
}
