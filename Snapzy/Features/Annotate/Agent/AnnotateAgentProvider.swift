//
//  AnnotateAgentProvider.swift
//  Snapzy
//
//  The seam between the Annotate AI prompt and whoever answers it: Apple
//  Intelligence, a custom endpoint, or an agent CLI (phases 3–5). A provider gets
//  the prompt plus the conversation so far and drives the canvas only through
//  `AnnotateAgentSession.callTool`, which paces calls so the user can follow along.
//

import Foundation

/// One finished prompt in the current conversation.
nonisolated struct AnnotateAgentTurn: Equatable {
  let prompt: String
  /// The agent's own summary of what it did.
  let reply: String
}

nonisolated struct AnnotateAgentRequest: Equatable {
  let prompt: String
  /// Earlier turns of this conversation, oldest first.
  let history: [AnnotateAgentTurn]
  /// `get_scene` output at the start of the run (JSON), so a provider can skip the first round trip.
  let sceneJSON: String
  /// The same scene as a value, for providers that must shrink it (Apple Intelligence's 4K context).
  var scene: AnnotateAgentScene? = nil
}

nonisolated enum AnnotateAgentProviderError: Error, Equatable {
  /// Nothing is configured (no Apple Intelligence, no endpoint, no CLI).
  case notConfigured
  /// The provider ran but could not finish; the message is shown to the user.
  case failed(String)
}

@MainActor
protocol AnnotateAgentProvider: AnyObject {
  /// Short name for the provider chip ("Apple Intelligence", "OpenCode", …).
  var displayName: String { get }
  /// SF Symbol for the provider chip.
  var symbolName: String { get }

  /// Runs one prompt. Returns the agent's one-line summary. Must honour task cancellation.
  func run(_ request: AnnotateAgentRequest, session: AnnotateAgentSession) async throws -> String
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
    }
    return result
  }

  /// Free-form progress from the provider ("Starting OpenCode…").
  func report(_ status: String) {
    guard isActive else { return }
    onStatus(status)
  }
}

/// Picks the provider for a prompt. `automatic` = Apple Intelligence when the
/// on-device model is ready. Endpoint and CLI providers (phases 4–5) are opt-in and
/// never chosen automatically, since they send the screenshot off the Mac.
@MainActor
enum AnnotateAgentProviderResolver {
  /// Debug builds: `YES` forces the mock, `NO` disables it. Unset = mock only when
  /// Apple Intelligence is unavailable, so the UI stays testable on any Mac.
  static let mockProviderDefaultsKey = "annotateAgent.useMockProvider"

  static func resolve(defaults: UserDefaults = .standard) -> AnnotateAgentProvider? {
    #if DEBUG
    let mockSetting = defaults.object(forKey: mockProviderDefaultsKey) == nil
      ? nil
      : defaults.bool(forKey: mockProviderDefaultsKey)
    if mockSetting == true {
      return AnnotateAgentMockProvider()
    }
    #endif
    if let apple = AnnotateAgentAppleIntelligence.makeProviderIfAvailable() {
      return apple
    }
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
    return AnnotateAgentAppleIntelligence.isAvailable
    #endif
  }
}
