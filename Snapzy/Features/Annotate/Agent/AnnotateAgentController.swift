//
//  AnnotateAgentController.swift
//  Snapzy
//
//  UI state and run loop of the Annotate AI prompt, one per Annotate window.
//
//  - The dock shows the prompt while `isPromptPresented`; the canvas overlay draws
//    `marks` and the agent `cursor` while a run is in flight.
//  - Image analysis (OCR + rectangles) starts when the prompt opens, so it is usually
//    ready by the time the user sends.
//  - A conversation (toolbox ids, earlier turns) lives until the image changes or the
//    user starts a new one.
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AnnotateAgentController: ObservableObject {
  enum Phase: Equatable {
    case idle
    /// Waiting for image analysis and the provider's first step.
    case reading
    /// The provider is calling tools.
    case acting
  }

  enum Notice: Equatable {
    case finished(message: String, changeCount: Int, canUndo: Bool)
    case stopped(changeCount: Int, canUndo: Bool)
    case failed(message: String, offersSettings: Bool)
  }

  /// A highlight drawn on the canvas for a moment: where the agent looked or what it added.
  struct Mark: Identifiable, Equatable {
    enum Kind: Equatable { case target, added }
    let id = UUID()
    let kind: Kind
    /// Annotate space.
    let rect: CGRect
    let date: Date
  }

  /// The agent "pointer" flying between targets (annotate space).
  struct Cursor: Equatable {
    let from: CGPoint
    let to: CGPoint
    let movedAt: Date
  }

  static let markLifetime: TimeInterval = 1.1
  static let noticeLifetime: TimeInterval = 6

  @Published var isPromptPresented = false
  @Published var draft = ""
  /// Bumped whenever the prompt field should take the caret (the field watches it).
  @Published private(set) var promptFocusRequest = 0
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var status = ""
  @Published private(set) var notice: Notice?
  @Published private(set) var marks: [Mark] = []
  @Published private(set) var cursor: Cursor?
  @Published private(set) var turns: [AnnotateAgentTurn] = []

  private weak var state: AnnotateState?
  private let resolveProvider: @MainActor () -> AnnotateAgentProvider?
  private let pacingEnabled: Bool
  private let defaults: UserDefaults
  /// Asks before the first prompt goes to an off-device provider. `true` = send.
  private let confirmRemoteUse: @MainActor (AnnotateAgentRemoteDestination) async -> Bool
  private var isConfirmingRemoteUse = false

  /// The image the analysis belongs to. Held strongly: comparing addresses of freed images
  /// could mistake a new image for the old one.
  private var analyzedImage: NSImage?
  private var analysisTask: Task<AnnotateAgentImageAnalysis, Never>?
  private var toolbox: AnnotateAgentToolbox?
  /// Provider the current conversation was held with; a change made elsewhere (Settings › AI)
  /// starts a new conversation on the next prompt, like picking one in the dock.
  private var conversationSelection: AnnotateAgentProviderSelection?
  private var runTask: Task<Void, Never>?
  private var operationID: UUID?
  private var noticeTask: Task<Void, Never>?
  private var markCleanupTask: Task<Void, Never>?
  /// Annotations right after the last run, so its Undo is offered only while nothing else changed.
  private var annotationsAfterRun: [AnnotationItem]?
  private var canvasAfterRun: AnnotateAgentCanvasState?
  private var undoGenerationAfterRun: Int?
  /// The session of the run in flight; invalidated when it ends so late calls bounce.
  private var session: AnnotateAgentSession?
  /// The toolbox's run began (counters reset). Before that, a Stop has nothing to report.
  private var didBeginRun = false

  init(
    state: AnnotateState,
    pacingEnabled: Bool = true,
    defaults: UserDefaults = .standard,
    resolveProvider: (@MainActor () -> AnnotateAgentProvider?)? = nil,
    confirmRemoteUse: (@MainActor (AnnotateAgentRemoteDestination) async -> Bool)? = nil
  ) {
    self.state = state
    self.pacingEnabled = pacingEnabled
    self.defaults = defaults
    self.resolveProvider = resolveProvider ?? { AnnotateAgentProviderResolver.resolve() }
    self.confirmRemoteUse = confirmRemoteUse ?? { await AnnotateAgentController.askRemoteUse($0) }
    AnnotateAgentCLIDetector.shared.refresh()
  }

  // MARK: - Derived

  var isRunning: Bool { phase != .idle }
  var hasConversation: Bool { !turns.isEmpty }
  var canSend: Bool {
    !isRunning && !isConfirmingRemoteUse && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var isAvailable: Bool {
    AnnotateAgentProviderResolver.isFeatureAvailable && (state?.canAutoTranslate ?? false)
  }

  var provider: AnnotateAgentProvider? { resolveProvider() }

  /// The run's Undo is meaningful only if the user hasn't edited since.
  var canUndoLastRun: Bool {
    guard !isRunning, let state, let after = annotationsAfterRun else { return false }
    if AnnotateAgentToolbox.differ(after, state.annotations) { return false }
    if let canvasAfterRun, canvasAfterRun != AnnotateAgentCanvasState(state: state) { return false }
    if let undoGenerationAfterRun, undoGenerationAfterRun != state.undoGeneration { return false }
    return true
  }

  // MARK: - Prompt presentation

  func presentPrompt() {
    guard isAvailable || isRunning else { return }
    if state?.editingTextAnnotationId != nil {
      state?.commitTextEditing()
    }
    state?.cancelAutoTranslateIfIdleSelection()
    isPromptPresented = true
    promptFocusRequest &+= 1
    prepareAnalysis()
    AnnotateAgentCLIDetector.shared.refresh()
  }

  /// Ignored while a run is in flight: the prompt row is where its status and Stop live.
  func dismissPrompt() {
    guard !isRunning else { return }
    isPromptPresented = false
  }

  func togglePrompt() {
    isPromptPresented ? dismissPrompt() : presentPrompt()
  }

  /// Puts the caret back in an open prompt (⌘K while focus is on the canvas).
  func focusPrompt() {
    guard isPromptPresented else { return }
    promptFocusRequest &+= 1
  }

  /// Esc inside the field: clear the draft first, then leave the prompt. Stops a run.
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
    guard !prompt.isEmpty, !isRunning, !isConfirmingRemoteUse, let state, state.hasImage, !state.isAutoTranslateRunning else {
      return
    }
    guard let provider = resolveProvider() else {
      showNotice(.failed(message: L10n.AnnotateAI.notConfigured, offersSettings: true))
      return
    }
    // The screenshot leaves the Mac: ask once per provider, then send what was typed.
    if let destination = provider.remoteDestination, !hasRemoteConsent(destination) {
      isConfirmingRemoteUse = true
      Task { [weak self] in
        guard let self else { return }
        let allowed = await self.confirmRemoteUse(destination)
        self.isConfirmingRemoteUse = false
        guard allowed else { return }
        self.recordRemoteConsent(destination)
        self.submit()
      }
      return
    }

    resetContextIfImageChanged()
    if let conversationSelection, conversationSelection != providerSelection {
      turns = []
      toolbox = nil
    }
    conversationSelection = providerSelection
    prepareAnalysis()
    draft = ""
    dismissNotice()
    clearRunResult()
    didBeginRun = false
    marks = []
    cursor = nil
    status = L10n.AnnotateAI.statusReading
    phase = .reading

    let operationID = UUID()
    self.operationID = operationID
    DiagnosticLogger.shared.log(.info, .annotate, "AI prompt started", context: [
      "provider": provider.displayName,
      "turn": "\(turns.count + 1)",
    ])

    runTask = Task { [weak self] in
      await self?.run(prompt: prompt, provider: provider, operationID: operationID)
    }
  }

  func stop() {
    guard isRunning, operationID != nil else { return }
    runTask?.cancel()
    runTask = nil
    operationID = nil
    // Before the toolbox began this run its counters still describe the previous one.
    let summary = didBeginRun ? toolbox?.finishRun() : nil
    endRun()
    let changes = summary?.changeCount ?? 0
    rememberRunResult(summary)
    showNotice(.stopped(changeCount: changes, canUndo: changes > 0))
    DiagnosticLogger.shared.log(.info, .annotate, "AI prompt stopped", context: ["changes": "\(changes)"])
  }

  /// Undo for the last run: annotation changes via the editor's undo, canvas settings via the snapshot.
  func undoLastRun() {
    guard let state, canUndoLastRun else { return }
    if lastRunRecordedUndo {
      state.undo()
    }
    toolbox?.revertCanvasChanges()
    clearRunResult()
    // The agent should not build on changes that were just taken back.
    if !turns.isEmpty { turns.removeLast() }
    dismissNotice()
  }

  func startNewConversation() {
    guard !isRunning else { return }
    turns = []
    toolbox = nil
    dismissNotice()
  }

  var providerSelection: AnnotateAgentProviderSelection {
    AnnotateAgentProviderResolver.selection(defaults: defaults)
  }

  /// A different provider starts a new conversation: it never saw the earlier turns.
  func selectProvider(_ selection: AnnotateAgentProviderSelection) {
    guard !isRunning, !isConfirmingRemoteUse, selection != providerSelection else { return }
    AnnotateAgentProviderResolver.setSelection(selection, defaults: defaults)
    objectWillChange.send()
    turns = []
    toolbox = nil
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

  private var lastRunRecordedUndo = false

  private func run(prompt: String, provider: AnnotateAgentProvider, operationID: UUID) async {
    let analysis = await analysisTask?.value ?? .empty
    guard isCurrent(operationID) else { return }
    guard let state else {
      self.operationID = nil
      endRun()
      return
    }

    let toolbox = self.toolbox ?? AnnotateAgentToolbox(state: state, analysis: analysis)
    toolbox.updateAnalysis(analysis)
    self.toolbox = toolbox
    toolbox.onEvent = { [weak self] event in self?.handle(event) }
    toolbox.beginRun()
    didBeginRun = true

    let session = AnnotateAgentSession(
      toolbox: toolbox,
      pacingEnabled: pacingEnabled,
      onToolStart: { [weak self] tool in
        guard let self, self.isCurrent(operationID) else { return }
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
    let request = AnnotateAgentRequest(
      prompt: prompt,
      history: turns,
      sceneJSON: toolbox.execute(name: AnnotateAgentToolName.getScene.rawValue, argumentsJSON: "{}").text,
      scene: toolbox.scene(),
      // Only off-device providers look at pixels today; on-device ones read the scene.
      image: provider.remoteDestination == nil
        ? nil
        : state.effectiveSourceImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      resumeSessionID: turns.last?.providerSessionID
    )

    do {
      let reply = try await provider.run(request, session: session)
      guard isCurrent(operationID) else { return }
      self.operationID = nil
      let summary = toolbox.finishRun()
      endRun()
      rememberRunResult(summary)
      turns.append(AnnotateAgentTurn(prompt: prompt, reply: reply, providerSessionID: session.providerSessionID))
      let message = reply.trimmingCharacters(in: .whitespacesAndNewlines)
      showNotice(.finished(
        message: message.isEmpty
          ? (summary.changeCount == 0 ? L10n.AnnotateAI.noChanges : L10n.AnnotateAI.changes(summary.changeCount))
          : message,
        changeCount: summary.changeCount,
        canUndo: summary.changeCount > 0
      ))
      DiagnosticLogger.shared.log(.info, .annotate, "AI prompt finished", context: ["changes": "\(summary.changeCount)"])
    } catch {
      guard isCurrent(operationID) else { return }
      self.operationID = nil
      let summary = toolbox.finishRun()
      endRun()
      rememberRunResult(summary)
      if error is CancellationError {
        showNotice(.stopped(changeCount: summary.changeCount, canUndo: summary.changeCount > 0))
        return
      }
      let message: String
      var offersSettings = false
      switch error {
      case AnnotateAgentProviderError.notConfigured:
        message = L10n.AnnotateAI.notConfigured
        offersSettings = true
      case AnnotateAgentProviderError.failed(let detail):
        message = detail
      case AnnotateAgentProviderError.needsSetup(let detail):
        message = detail
        offersSettings = true
      default:
        message = L10n.AnnotateAI.failed
      }
      showNotice(.failed(message: message, offersSettings: offersSettings))
      DiagnosticLogger.shared.log(.warning, .annotate, "AI prompt failed", context: ["error": "\(error)"])
    }
  }

  private func isCurrent(_ operationID: UUID) -> Bool {
    self.operationID == operationID && !Task.isCancelled
  }

  private func endRun() {
    session?.invalidate()
    session = nil
    phase = .idle
    status = ""
    cursor = nil
    toolbox?.onEvent = nil
    scheduleMarkCleanup()
  }

  private func rememberRunResult(_ summary: AnnotateAgentRunSummary?) {
    guard let summary, summary.changeCount > 0, let state else {
      clearRunResult()
      return
    }
    annotationsAfterRun = state.annotations
    canvasAfterRun = summary.didChangeCanvas ? AnnotateAgentCanvasState(state: state) : nil
    undoGenerationAfterRun = summary.recordedUndo ? state.undoGeneration : nil
    lastRunRecordedUndo = summary.recordedUndo
  }

  private func clearRunResult() {
    annotationsAfterRun = nil
    canvasAfterRun = nil
    undoGenerationAfterRun = nil
    lastRunRecordedUndo = false
  }

  // MARK: - Remote consent

  private func hasRemoteConsent(_ destination: AnnotateAgentRemoteDestination) -> Bool {
    defaults.stringArray(forKey: PreferencesKeys.annotateAgentConsentedProviders)?.contains(destination.id) ?? false
  }

  private func recordRemoteConsent(_ destination: AnnotateAgentRemoteDestination) {
    var ids = defaults.stringArray(forKey: PreferencesKeys.annotateAgentConsentedProviders) ?? []
    guard !ids.contains(destination.id) else { return }
    ids.append(destination.id)
    defaults.set(ids, forKey: PreferencesKeys.annotateAgentConsentedProviders)
  }

  /// Sheet on the Annotate window (app-modal when there is none).
  private static func askRemoteUse(_ destination: AnnotateAgentRemoteDestination) async -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = L10n.AnnotateAI.consentTitle(destination.name)
    // Agent CLIs also run with the user's own MCP servers and hooks: say so up front.
    switch destination.kind {
    case .agentCLI:
      alert.informativeText = L10n.AnnotateAI.consentMessageCLI(destination.name)
    case .endpoint:
      alert.informativeText = L10n.AnnotateAI.consentMessage(destination.host)
    }
    alert.addButton(withTitle: L10n.AnnotateAI.consentSend)
    alert.addButton(withTitle: L10n.Common.cancel)
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
      return alert.runModal() == .alertFirstButtonReturn
    }
    return await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: window) { response in
        continuation.resume(returning: response == .alertFirstButtonReturn)
      }
    }
  }

  // MARK: - Overlay feedback

  private func handle(_ event: AnnotateAgentToolboxEvent) {
    let now = Date()
    switch event {
    case .targetResolved(let rect):
      let point = CGPoint(x: rect.midX, y: rect.midY)
      let from = currentCursorPoint(at: now) ?? point
      cursor = Cursor(from: from, to: point, movedAt: now)
      if !rect.isEmpty {
        appendMark(Mark(kind: .target, rect: rect, date: now))
      }
    case .annotationAdded(let id):
      if let item = state?.annotations.first(where: { $0.id == id }) {
        appendMark(Mark(kind: .added, rect: item.bounds, date: now))
      }
    case .annotationsUpdated(let ids):
      for item in state?.annotations.filter({ ids.contains($0.id) }) ?? [] {
        appendMark(Mark(kind: .added, rect: item.bounds, date: now))
      }
    case .annotationsRemoved, .canvasChanged:
      break
    }
  }

  private func appendMark(_ mark: Mark) {
    let cutoff = mark.date.addingTimeInterval(-Self.markLifetime)
    marks = marks.filter { $0.date > cutoff } + [mark]
  }

  /// Where the cursor is drawn right now (it eases from `from` to `to`).
  func currentCursorPoint(at date: Date) -> CGPoint? {
    guard let cursor else { return nil }
    let t = min(max(date.timeIntervalSince(cursor.movedAt) / Self.cursorFlightDuration, 0), 1)
    let eased = 1 - pow(1 - t, 3)
    return CGPoint(
      x: cursor.from.x + (cursor.to.x - cursor.from.x) * eased,
      y: cursor.from.y + (cursor.to.y - cursor.from.y) * eased
    )
  }

  static let cursorFlightDuration: TimeInterval = 0.3

  private func scheduleMarkCleanup() {
    markCleanupTask?.cancel()
    markCleanupTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64((Self.markLifetime + 0.1) * 1_000_000_000))
      guard !Task.isCancelled, let self, !self.isRunning else { return }
      self.marks = []
    }
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
    case .finished(let message, _, _): text = message
    case .stopped(let count, _): text = count > 0 ? "\(L10n.AnnotateAI.stopped), \(L10n.AnnotateAI.changes(count))" : L10n.AnnotateAI.stopped
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

  // MARK: - Image context

  private func prepareAnalysis() {
    // Load the on-device model while the user types (no-op without Apple Intelligence).
    AnnotateAgentAppleIntelligence.prewarm()
    resetContextIfImageChanged()
    guard analysisTask == nil, let image = state?.effectiveSourceImage else { return }
    analyzedImage = image
    let language = AppLanguageManager.shared.activeOCRLanguageIdentifier
    analysisTask = Task {
      await AnnotateAgentImageAnalysis.analyze(image: image, languageIdentifier: language)
    }
  }

  /// A new image (rotate, crop apply, cut-out, replace) makes ids and analysis stale.
  private func resetContextIfImageChanged() {
    guard let image = state?.effectiveSourceImage else { return }
    guard let analyzedImage, analyzedImage !== image, !isRunning else { return }
    analysisTask?.cancel()
    analysisTask = nil
    self.analyzedImage = nil
    toolbox = nil
    turns = []
  }

  // MARK: - Status text

  static func status(for tool: AnnotateAgentToolName) -> String? {
    switch tool {
    case .getScene: nil
    case .findText: L10n.AnnotateAI.statusFindingText
    case .addBox: L10n.AnnotateAI.statusBox
    case .addOval: L10n.AnnotateAI.statusOval
    case .addArrow: L10n.AnnotateAI.statusArrow
    case .addLine: L10n.AnnotateAI.statusLine
    case .addText: L10n.AnnotateAI.statusText
    case .addHighlight: L10n.AnnotateAI.statusHighlight
    case .addBlur: L10n.AnnotateAI.statusBlur
    case .addSpotlight: L10n.AnnotateAI.statusSpotlight
    case .addCounter: L10n.AnnotateAI.statusCounter
    case .addWatermark: L10n.AnnotateAI.statusWatermark
    case .updateAnnotation, .select: L10n.AnnotateAI.statusEdit
    case .deleteAnnotations: L10n.AnnotateAI.statusDelete
    case .arrange: L10n.AnnotateAI.statusArrange
    case .setCanvas: L10n.AnnotateAI.statusCanvas
    }
  }
}

extension AnnotateState {
  /// Translate Area waits for a drag; opening the prompt ends that wait.
  func cancelAutoTranslateIfIdleSelection() {
    if isTranslateAreaSelecting {
      endTranslateAreaSelection()
    }
  }
}

/// The canvas settings a run can change, to tell whether the user touched them since.
struct AnnotateAgentCanvasState: Equatable {
  let backgroundStyle: BackgroundStyle
  let padding: CGFloat
  let inset: CGFloat
  let shadowIntensity: CGFloat
  let cornerRadius: CGFloat
  let imageAlignment: ImageAlignment

  init(state: AnnotateState) {
    backgroundStyle = state.backgroundStyle
    padding = state.padding
    inset = state.inset
    shadowIntensity = state.shadowIntensity
    cornerRadius = state.cornerRadius
    imageAlignment = state.imageAlignment
  }
}
