//
//  AnnotateAgentProvider.swift
//  Snapzy
//
//  The seam between the Annotate AI prompt and whoever answers it: Apple
//  Intelligence, a custom endpoint, or an agent CLI (phases 3–5). A provider gets
//  the prompt plus the conversation so far and drives the canvas only through
//  `AnnotateAgentSession.callTool`, which paces calls so the user can follow along.
//

import CoreGraphics
import Foundation

/// One finished prompt in the current conversation.
nonisolated struct AnnotateAgentTurn: Equatable {
  let prompt: String
  /// The agent's own summary of what it did.
  let reply: String
  /// The agent CLI's conversation id, so the next turn can resume it.
  var providerSessionID: String? = nil
}

nonisolated struct AnnotateAgentRequest: Equatable {
  let prompt: String
  /// Earlier turns of this conversation, oldest first.
  let history: [AnnotateAgentTurn]
  /// `get_scene` output at the start of the run (JSON), so a provider can skip the first round trip.
  let sceneJSON: String
  /// The same scene as a value, for providers that must shrink it (Apple Intelligence's 4K context).
  var scene: AnnotateAgentScene? = nil
  /// The screenshot (no annotations), for providers that can look at it.
  var image: CGImage? = nil
  /// The previous turn's agent CLI conversation, when it can be resumed.
  var resumeSessionID: String? = nil
}

/// Where a provider sends the screenshot when it runs off the Mac. The user agrees once per `id`.
nonisolated struct AnnotateAgentRemoteDestination: Equatable {
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

nonisolated enum AnnotateAgentProviderError: Error, Equatable {
  /// Nothing is configured (no Apple Intelligence, no endpoint, no CLI).
  case notConfigured
  /// The provider ran but could not finish; the message is shown to the user.
  case failed(String)
  /// The provider can't run until something is set up (CLI missing, Apple Intelligence
  /// off). Shown like `failed`, with a way to open AI settings.
  case needsSetup(String)
}

@MainActor
protocol AnnotateAgentProvider: AnyObject {
  /// Short name for the provider chip ("Apple Intelligence", "OpenCode", …).
  var displayName: String { get }
  /// SF Symbol for the provider chip.
  var symbolName: String { get }

  /// Set when the screenshot and its text leave the Mac (endpoint, CLI). `nil` = on-device.
  var remoteDestination: AnnotateAgentRemoteDestination? { get }

  /// Runs one prompt. Returns the agent's one-line summary. Must honour task cancellation.
  func run(_ request: AnnotateAgentRequest, session: AnnotateAgentSession) async throws -> String
}

extension AnnotateAgentProvider {
  var remoteDestination: AnnotateAgentRemoteDestination? { nil }
}

/// The result pill shows one line: lists and markdown wrappers dropped, kept short.
nonisolated enum AnnotateAgentReplyFormatter {
  static let maximumLength = 160

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
final class AnnotateAgentSession {
  /// Shortest gap between two canvas changes, so a fast provider still reads as "working".
  static let minimumChangeInterval: TimeInterval = 0.32

  private let toolbox: AnnotateAgentToolbox
  private let pacingEnabled: Bool
  private let onToolStart: (AnnotateAgentToolName?) -> Void
  private let onStatus: (String) -> Void
  private var lastChange: Date?
  /// Cleared by the controller when the run ends or is stopped. A provider that keeps
  /// calling afterwards (a process or stream that ignores task cancellation) gets
  /// `CancellationError` and can no longer touch the canvas.
  private(set) var isActive = true
  /// Set by providers that keep a conversation of their own (agent CLIs).
  var providerSessionID: String?
  /// Successful canvas-changing tool calls so far, so a provider knows whether a retry is safe.
  private(set) var changeCount = 0

  func invalidate() {
    isActive = false
  }

  init(
    toolbox: AnnotateAgentToolbox,
    pacingEnabled: Bool = true,
    onToolStart: @escaping (AnnotateAgentToolName?) -> Void = { _ in },
    onStatus: @escaping (String) -> Void = { _ in }
  ) {
    self.toolbox = toolbox
    self.pacingEnabled = pacingEnabled
    self.onToolStart = onToolStart
    self.onStatus = onStatus
  }

  func callTool(_ name: String, arguments: String) async throws -> AnnotateAgentToolResult {
    guard isActive else { throw CancellationError() }
    try Task.checkCancellation()
    let tool = AnnotateAgentToolName(rawValue: name)
    onToolStart(tool)
    if pacingEnabled, tool?.isReadOnly == false, let lastChange {
      let wait = Self.minimumChangeInterval - Date().timeIntervalSince(lastChange)
      if wait > 0 {
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      }
    }
    try Task.checkCancellation()
    guard isActive else { throw CancellationError() }
    let result = toolbox.execute(name: name, argumentsJSON: arguments)
    if tool?.isReadOnly == false {
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
nonisolated enum AnnotateAgentProviderSelection: Equatable {
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

/// Picks the provider for a prompt. `automatic` = Apple Intelligence when the
/// on-device model is ready. Endpoint and CLI providers are opt-in and never chosen
/// automatically, since they send the screenshot off the Mac.
@MainActor
enum AnnotateAgentProviderResolver {
  /// Debug builds: `YES` forces the mock, `NO` disables it. Unset = mock only when
  /// nothing else is available, so the UI stays testable on any Mac.
  static let mockProviderDefaultsKey = "annotateAgent.useMockProvider"

  static func selection(defaults: UserDefaults = .standard) -> AnnotateAgentProviderSelection {
    AnnotateAgentProviderSelection(persistedValue: defaults.string(forKey: PreferencesKeys.annotateAgentProvider))
  }

  static func setSelection(_ selection: AnnotateAgentProviderSelection, defaults: UserDefaults = .standard) {
    defaults.set(selection.persistedValue, forKey: PreferencesKeys.annotateAgentProvider)
  }

  static func resolve(
    defaults: UserDefaults = .standard,
    endpoints: [CustomOCRModel]? = nil
  ) -> AnnotateAgentProvider? {
    #if DEBUG
    let mockSetting = defaults.object(forKey: mockProviderDefaultsKey) == nil
      ? nil
      : defaults.bool(forKey: mockProviderDefaultsKey)
    if mockSetting == true {
      return AnnotateAgentMockProvider()
    }
    #endif
    let provider: AnnotateAgentProvider?
    switch selection(defaults: defaults) {
    case .endpoint(let id):
      // A removed endpoint falls back to automatic rather than leaving the prompt dead.
      if let model = (endpoints ?? CustomOCRModelStore.shared.models).first(where: { $0.id == id }) {
        provider = AnnotateAgentEndpointProvider(model: model, defaults: defaults)
      } else {
        provider = AnnotateAgentAppleIntelligence.makeProviderIfAvailable()
      }
    case .cli(let kind):
      // Not installed is reported by the run itself, with what to do about it.
      provider = AnnotateAgentCLIProvider(kind: kind, defaults: defaults)
    case .automatic, .appleIntelligence:
      provider = AnnotateAgentAppleIntelligence.makeProviderIfAvailable()
    }
    if let provider { return provider }
    #if DEBUG
    if mockSetting == nil {
      return AnnotateAgentMockProvider()
    }
    #endif
    return nil
  }

  /// The Ask entry point shows only when a provider can run on this Mac.
  static var isFeatureAvailable: Bool {
    #if DEBUG
    return true
    #else
    // Any configured endpoint counts: the provider menu in the prompt is where it gets picked.
    return AnnotateAgentAppleIntelligence.isAvailable
      || !CustomOCRModelStore.shared.models.isEmpty
      || !AnnotateAgentCLIDetector.shared.installed.isEmpty
      || { if case .cli = selection() { return true } else { return false } }()
    #endif
  }
}
