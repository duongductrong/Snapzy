//
//  AgentProvider.swift
//  Snapzy
//
//  The seam between a Snapzy AI prompt (Annotate, Video Editor) and whoever answers
//  it: Apple Intelligence, a custom endpoint, or an agent CLI. A provider gets the
//  prompt plus the conversation so far and drives the surface only through
//  `AgentSession.callTool`, which paces calls so the user can follow along.
//

import CoreGraphics
import Foundation

/// One finished prompt in the current conversation.
nonisolated struct AgentTurn: Equatable {
  let prompt: String
  /// The agent's own summary of what it did.
  let reply: String
  /// The agent CLI's conversation id, so the next turn can resume it.
  var providerSessionID: String? = nil
}

nonisolated struct AgentRequest {
  let prompt: String
  /// Earlier turns of this conversation, oldest first.
  let history: [AgentTurn]
  /// `get_scene` output at the start of the run (JSON), so a provider can skip the first round trip.
  let sceneJSON: String
  /// The same scene as a value, for providers that must shrink it (Apple Intelligence's 4K context).
  var scene: (any AgentScene)? = nil
  /// The surface's picture (Annotate: the screenshot without annotations), for providers that can look at it.
  var image: CGImage? = nil
  /// The previous turn's agent CLI conversation, when it can be resumed.
  var resumeSessionID: String? = nil
}

/// Where a provider sends the screenshot when it runs off the Mac. The user agrees once per `id`.
nonisolated struct AgentRemoteDestination: Equatable {
  enum Kind: Equatable {
    /// An HTTP endpoint; `host` is where the data goes.
    case endpoint
    /// An agent CLI on this Mac that forwards to its own model provider and may load the
    /// user's MCP servers and hooks.
    case agentCLI
  }

  let id: String
  let name: String
  let host: String
  var kind: Kind = .endpoint
}

nonisolated enum AgentProviderError: Error, Equatable {
  /// Nothing is configured (no Apple Intelligence, no endpoint, no CLI).
  case notConfigured
  /// The provider ran but could not finish; the message is shown to the user.
  case failed(String)
  /// The provider can't run until something is set up (CLI missing, Apple Intelligence
  /// off). Shown like `failed`, with a way to open AI settings.
  case needsSetup(String)
}

@MainActor
protocol AgentProvider: AnyObject {
  /// Short name for the provider chip ("Apple Intelligence", "OpenCode", …).
  var displayName: String { get }
  /// SF Symbol for the provider chip.
  var symbolName: String { get }
  /// Brand mark in the asset catalog, shown instead of `symbolName` when set.
  var logoImageName: String? { get }

  /// Set when the screenshot and its text leave the Mac (endpoint, CLI). `nil` = on-device.
  var remoteDestination: AgentRemoteDestination? { get }

  /// Runs one prompt. Returns the agent's one-line summary. Must honour task cancellation.
  func run(_ request: AgentRequest, session: AgentSession) async throws -> String
}

extension AgentProvider {
  var remoteDestination: AgentRemoteDestination? { nil }
  var logoImageName: String? { nil }
}

/// Providers return the full reply (`full`); one-line surfaces (Annotate's result pill)
/// shorten it with `oneLine`.
nonisolated enum AgentReplyFormatter {
  static let maximumLength = 160
  /// The Video Editor panel shows the whole reply; this only guards against runaway output.
  static let maximumFullLength = 2000

  /// Trimmed, wrapping quotes dropped, line breaks kept (the panel renders inline markdown).
  static func full(_ text: String) -> String {
    let trimmed = text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maximumFullLength else { return trimmed }
    return String(trimmed.prefix(maximumFullLength - 1)) + "…"
  }

  static func oneLine(_ text: String) -> String {
    let oneLine = text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let trimmed = oneLine
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”*`"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maximumLength else { return trimmed }
    return String(trimmed.prefix(maximumLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
  }
}

/// What a provider may do while running: call tools and say what it is doing.
@MainActor
final class AgentSession {
  /// Shortest gap between two changes, so a fast provider still reads as "working".
  static let minimumChangeInterval: TimeInterval = 0.32

  private let toolbox: AgentToolbox
  private let pacingEnabled: Bool
  private let onToolCall: (String) -> Void
  private let onStatus: (String) -> Void
  private var lastChange: Date?
  /// Cleared by the controller when the run ends or is stopped. A provider that keeps
  /// calling afterwards (a process or stream that ignores task cancellation) gets
  /// `CancellationError` and can no longer touch the canvas.
  private(set) var isActive = true
  /// Set by providers that keep a conversation of their own (agent CLIs).
  var providerSessionID: String?
  /// Successful changing tool calls so far, so a provider knows whether a retry is safe.
  private(set) var changeCount = 0

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  func invalidate() {
    isActive = false
  }

  /// `onToolCall` gets the tool name before the call runs (unknown names included).
  init(
    toolbox: AgentToolbox,
    pacingEnabled: Bool,
    onToolCall: @escaping (String) -> Void,
    onStatus: @escaping (String) -> Void = { _ in }
  ) {
    self.toolbox = toolbox
    self.pacingEnabled = pacingEnabled
    self.onToolCall = onToolCall
    self.onStatus = onStatus
  }

  var surface: AgentSurface { toolbox.surface }
  var toolSpecs: [AgentToolSpec] { toolbox.toolSpecs }

  /// Read-only calls are not paced and not counted as changes (the toolbox decides for unknown names).
  func isReadOnly(_ name: String) -> Bool {
    toolbox.isReadOnly(name)
  }

  func callTool(_ name: String, arguments: String) async throws -> AgentToolResult {
    guard isActive else { throw CancellationError() }
    try Task.checkCancellation()
    let readOnly = toolbox.isReadOnly(name)
    onToolCall(name)
    if pacingEnabled, !readOnly, let lastChange {
      let wait = Self.minimumChangeInterval - Date().timeIntervalSince(lastChange)
      if wait > 0 {
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      }
    }
    try Task.checkCancellation()
    guard isActive else { throw CancellationError() }
    let result = await toolbox.execute(name: name, argumentsJSON: arguments)
    if !readOnly {
      lastChange = Date()
      if !result.isError { changeCount += 1 }
    }
    return result
  }

  /// Free-form progress from the provider ("Starting OpenCode…").
  func report(_ status: String) {
    guard isActive else { return }
    onStatus(status)
  }
}

/// Which provider the user picked. Persisted as a string so CLI kinds (phase 5) fit in.
nonisolated enum AgentProviderSelection: Equatable {
  /// Apple Intelligence when ready; never an off-device provider.
  case automatic
  case appleIntelligence
  /// A custom endpoint from the shared OCR/Translate endpoint list.
  case endpoint(UUID)
  /// An agent CLI on this Mac (Claude Code, Codex, OpenCode).
  case cli(AnnotateAgentCLIKind)

  init(persistedValue: String?) {
    switch persistedValue {
    case "apple": self = .appleIntelligence
    case let value? where value.hasPrefix("cli:"):
      if let kind = AnnotateAgentCLIKind(rawValue: String(value.dropFirst("cli:".count))) {
        self = .cli(kind)
      } else {
        self = .automatic
      }
    case let value? where value.hasPrefix("endpoint:"):
      if let id = UUID(uuidString: String(value.dropFirst("endpoint:".count))) {
        self = .endpoint(id)
      } else {
        self = .automatic
      }
    default: self = .automatic
    }
  }

  var persistedValue: String {
    switch self {
    case .automatic: "automatic"
    case .appleIntelligence: "apple"
    case .endpoint(let id): "endpoint:\(id.uuidString)"
    case .cli(let kind): "cli:\(kind.rawValue)"
    }
  }
}

/// Picks the provider for a prompt. The choice is app-wide (Settings › AI), shared by
/// every surface. `automatic` = the surface's on-device provider (Apple Intelligence) when
/// it is ready. Endpoint and CLI providers are opt-in and never chosen automatically,
/// since they send the surface's data off the Mac.
@MainActor
enum AgentProviderResolver {
  /// Debug builds: `YES` forces the mock, `NO` disables it. Unset = mock only when
  /// nothing else is available, so the UI stays testable on any Mac.
  static let mockProviderDefaultsKey = "annotateAgent.useMockProvider"

  static func selection(defaults: UserDefaults = .standard) -> AgentProviderSelection {
    AgentProviderSelection(persistedValue: defaults.string(forKey: PreferencesKeys.annotateAgentProvider))
  }

  static func setSelection(_ selection: AgentProviderSelection, defaults: UserDefaults = .standard) {
    defaults.set(selection.persistedValue, forKey: PreferencesKeys.annotateAgentProvider)
  }

  /// - Parameters:
  ///   - onDevice: the surface's on-device provider, `nil` when it can't run here.
  ///   - mock: the surface's debug stand-in (ignored in release builds).
  static func resolve(
    defaults: UserDefaults = .standard,
    endpoints: [CustomOCRModel]? = nil,
    onDevice: () -> AgentProvider?,
    mock: () -> AgentProvider?
  ) -> AgentProvider? {
    #if DEBUG
    let mockSetting = defaults.object(forKey: mockProviderDefaultsKey) == nil
      ? nil
      : defaults.bool(forKey: mockProviderDefaultsKey)
    if mockSetting == true, let mock = mock() {
      return mock
    }
    #endif
    let provider: AgentProvider?
    switch selection(defaults: defaults) {
    case .endpoint(let id):
      // A removed endpoint falls back to automatic rather than leaving the prompt dead.
      if let model = (endpoints ?? CustomOCRModelStore.shared.models).first(where: { $0.id == id }) {
        provider = AgentEndpointProvider(model: model, defaults: defaults)
      } else {
        provider = onDevice()
      }
    case .cli(let kind):
      // Not installed is reported by the run itself, with what to do about it.
      provider = AgentCLIProvider(kind: kind, defaults: defaults)
    case .automatic, .appleIntelligence:
      provider = onDevice()
    }
    if let provider { return provider }
    #if DEBUG
    if mockSetting == nil {
      return mock()
    }
    #endif
    return nil
  }

  /// Something besides the on-device model can answer: an endpoint, an installed CLI, or a
  /// CLI the user picked (its run explains what is missing).
  static var hasOffDeviceProvider: Bool {
    !CustomOCRModelStore.shared.models.isEmpty
      || !AnnotateAgentCLIDetector.shared.installed.isEmpty
      || { if case .cli = selection() { return true } else { return false } }()
  }
}
