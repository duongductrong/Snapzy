//
//  VideoEditorAgentController.swift
//  Snapzy
//
//  UI state and run loop of the Video Editor AI prompt, one per editor window.
//
//  - The dock shows the prompt while `isPromptPresented`; while a run is in flight the
//    field becomes a status line and the editor locks authoring (play stays live).
//  - A run is one undo group (`VideoEditorAgentToolbox.beginRun/finishRun`): the result
//    pill's Undo, or ⌘Z, takes the whole prompt back.
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

@MainActor
final class VideoEditorAgentController: ObservableObject {
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

    var id: String { rawValue }

    var tool: VideoEditorAgentToolName {
      switch self {
      case .removeSilences: .removeSilences
      case .speedUpIdle: .speedUpIdle
      case .autoZoom: .autoZoomActivity
      }
    }

    var title: String {
      switch self {
      case .removeSilences: L10n.VideoEditorAI.suggestionSilences
      case .speedUpIdle: L10n.VideoEditorAI.suggestionIdle
      case .autoZoom: L10n.VideoEditorAI.suggestionAutoZoom
      }
    }

    var symbolName: String {
      switch self {
      case .removeSilences: "waveform.badge.minus"
      case .speedUpIdle: "forward.fill"
      case .autoZoom: "plus.magnifyingglass"
      }
    }
  }

  static let noticeLifetime: TimeInterval = 6
  /// Consent asked for Annotate does not cover video: it sends different data.
  static let consentScope = "video"

  @Published var isPromptPresented = false
  @Published var draft = ""
  /// Bumped whenever the prompt field should take the caret (the field watches it).
  @Published private(set) var promptFocusRequest = 0
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var status = ""
  @Published private(set) var notice: Notice?
  @Published private(set) var turns: [AgentTurn] = []

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
  /// Single-key editing shortcuts (S, Z, I, O, Delete) stand down while the prompt is open,
  /// so typing in it never splits or deletes, and while a run holds the timeline.
  var allowsPlainKeyShortcuts: Bool { !isPromptPresented && !isRunning }

  var canSend: Bool {
    !isRunning && !isConfirmingRemoteUse && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// GIFs can only be resized, so the AI has nothing to do there. Without a provider the
  /// dock still shows when a quick action can run.
  var isAvailable: Bool {
    guard let state, !state.isGIF else { return false }
    return VideoEditorAgentProviderResolver.isFeatureAvailable || !quickActions.isEmpty
  }

  /// Quick actions the open video has the data for: audio for silences, the recorded cursor
  /// for idle parts and activity zooms.
  var quickActions: [QuickAction] {
    guard let state, !state.isGIF, !state.clips.isEmpty else { return [] }
    var actions: [QuickAction] = []
    if !state.audioTrackRoles.isEmpty { actions.append(.removeSilences) }
    if state.hasMouseTrackingData { actions += [.speedUpIdle, .autoZoom] }
    return actions
  }

  /// Chips show over an empty, idle prompt.
  var showsQuickActions: Bool {
    isPromptPresented && !isRunning && !isConfirmingRemoteUse && notice == nil
      && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !quickActions.isEmpty
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
    promptFocusRequest &+= 1
    AnnotateAgentCLIDetector.shared.refresh()
    if let state { analyzer.prewarm(state) }
    // Load the on-device model while the user types (no-op without Apple Intelligence).
    VideoEditorAgentAppleIntelligence.prewarm()
  }

  /// Ignored while a run is in flight: the prompt row is where its status and Stop live.
  func dismissPrompt() {
    guard !isRunning else { return }
    isPromptPresented = false
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
      showNotice(.failed(message: L10n.VideoEditorAI.busy, offersSettings: false))
      return
    }
    guard let provider = resolveProvider() else {
      showNotice(.failed(message: L10n.VideoEditorAI.notConfigured, offersSettings: true))
      return
    }
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
    showNotice(.stopped(changeCount: changes))
    DiagnosticLogger.shared.log(.info, .editor, "Video AI prompt stopped", context: ["changes": "\(changes)"])
  }

  /// Undo for the last run: its whole undo group in one step.
  func undoLastRun() {
    guard let state, canUndoLastRun else { return }
    state.undo()
    undoEntryAfterRun = nil
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
    toolbox = nil
  }

  private func run(prompt: String, provider: AgentProvider, operationID: UUID) async {
    guard isCurrent(operationID) else { return }
    guard let state else {
      self.operationID = nil
      endRun()
      return
    }

    let toolbox = self.toolbox ?? VideoEditorAgentToolbox(state: state, analyzer: analyzer)
    self.toolbox = toolbox
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
      showNotice(.failed(message: message, offersSettings: offersSettings))
      DiagnosticLogger.shared.log(.warning, .editor, "Video AI prompt failed", context: ["error": "\(error)"])
    }
  }

  // MARK: - Quick actions

  /// Runs one one-step tool directly: on-device, no provider, no consent. One undo step.
  func runQuickAction(_ action: QuickAction) {
    guard !isRunning, !isConfirmingRemoteUse, let state else { return }
    guard !state.isGIF, !state.isExporting, !state.clips.isEmpty else {
      showNotice(.failed(message: L10n.VideoEditorAI.busy, offersSettings: false))
      return
    }
    state.pause()
    dismissNotice()
    undoEntryAfterRun = nil
    lastRunAddedTurn = false
    didBeginRun = false
    status = L10n.VideoEditorAI.statusAnalyzing
    phase = .reading

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
    do {
      _ = try await analyzer.activity(for: state)
    } catch {
      guard isCurrent(operationID) else { return }
      self.operationID = nil
      endRun()
      showNotice(.failed(message: L10n.AnnotateAI.failed, offersSettings: false))
      return
    }
    guard isCurrent(operationID) else { return }

    let toolbox = self.toolbox ?? VideoEditorAgentToolbox(state: state, analyzer: analyzer)
    self.toolbox = toolbox
    toolbox.beginRun()
    didBeginRun = true
    status = Self.status(for: action.tool) ?? status
    phase = .acting
    let result = await toolbox.execute(name: action.tool.rawValue, argumentsJSON: "{}")
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
      showNotice(.failed(message: payload["error"] as? String ?? L10n.AnnotateAI.failed, offersSettings: false))
    } else {
      showNotice(.finished(message: Self.quickMessage(action, payload: payload), changeCount: summary.changeCount))
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
    case .deleteClip: L10n.VideoEditorAI.statusDelete
    case .addZoom: L10n.VideoEditorAI.statusZoom
    case .updateZoom, .removeZoom: L10n.VideoEditorAI.statusEditZoom
    case .addSpeed, .updateSpeed, .removeSpeed: L10n.VideoEditorAI.statusSpeed
    case .setBackground: L10n.VideoEditorAI.statusBackground
    case .setAudio: L10n.VideoEditorAI.statusAudio
    case .getActivity: L10n.VideoEditorAI.statusAnalyzing
    case .removeSilences: L10n.VideoEditorAI.statusSilences
    case .speedUpIdle: L10n.VideoEditorAI.statusIdle
    case .autoZoomActivity: L10n.VideoEditorAI.statusAutoZoom
    }
  }
}
