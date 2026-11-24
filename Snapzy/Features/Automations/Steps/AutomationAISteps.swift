//
//  AutomationAISteps.swift
//  Snapzy
//
//  Milestone 6 AI steps.
//  - Redact (trust: local): Vision text recognition + the Annotate sensitive
//    data detector, plus on-device face / body detection. Covers what it
//    finds with pixelate / blur / a solid box. Nothing leaves the Mac; the
//    run log keeps a region count, never the text.
//  - AI Describe (`aiAnnotate`, trust: network): the user's AI provider
//    (endpoint or agent CLI) looks at the image and writes text for the
//    prompt (alt text by default). The text becomes `{text}`. Sending the
//    screenshot needs the one-time remote consent; drawing on the image is a
//    follow-up (the Annotate agent needs a window today).
//

import AppKit
import Foundation

/// A region to cover, in pixels with a bottom-left origin.
struct AutomationRedactionRegion: Equatable, Sendable {
  let category: AutomationRedactConfig.Category
  let rect: CGRect
}

// MARK: - Handlers

struct RedactStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .redact(let config) = action else { return }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    guard !config.categories.isEmpty else {
      state.stepDetail = L10n.Automations.logRedactedCount(0)
      return
    }
    var total = 0
    for file in files {
      let regions = try await environment.detectSensitiveRegions(in: file, config: config)
      try Task.checkCancellation()
      // Nothing found: the image goes on untouched.
      guard !regions.isEmpty else { continue }
      total += regions.count
      let directory = try state.prepareWorkingDirectory()
      let baseName = state.workingBaseName(for: file)
      let rects = regions.map(\.rect)
      do {
        let result = try await offMain {
          try AutomationImageTransforms.redact(file, regions: rects, style: config.style, into: directory, baseName: baseName)
        }
        state.replace(file, with: result.url, kind: .image)
        if result.fellBackToPNG {
          state.warnings.append(L10n.Automations.warningPNGFallback)
        }
      } catch {
        throw mapTransformError(error)
      }
    }
    state.stepDetail = L10n.Automations.logRedactedCount(total)
  }
}

struct AIAnnotateStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func produces(_: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    given.union([.text])
  }

  /// The image goes to the user's AI provider.
  var trust: AutomationTrustTier { .network }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .aiAnnotate(let config) = action else { return }
    guard let file = files.first else { throw AutomationStepError.noFile }
    guard !config.trimmedPrompt.isEmpty else { throw AutomationStepError.noText }
    let text = try await environment.describeImage(
      file,
      config: config,
      interactive: !state.context.invocation.isExternal
    )
    try Task.checkCancellation()
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AutomationStepError.noTextFound }
    state.payload.text = trimmed
  }
}

// MARK: - Live services

extension AutomationRunEnvironment {
  func detectSensitiveRegions(in url: URL, config: AutomationRedactConfig) async throws -> [AutomationRedactionRegion] {
    try await AutomationSensitiveDataScanner.scan(url, config: config)
  }

  func describeImage(_ url: URL, config: AutomationAIAnnotateConfig, interactive: Bool) async throws -> String {
    try await AutomationImageDescriber.describe(url, config: config, interactive: interactive)
  }
}

@MainActor
enum AutomationSensitiveDataScanner {
  static func scan(_ url: URL, config: AutomationRedactConfig) async throws -> [AutomationRedactionRegion] {
    guard let cgImage = QuickAccessImageOptimizer.loadImage(at: url) else { throw AutomationStepError.noFile }
    // Point size = pixel size, so the detector's regions are already in pixels.
    let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    let service = AnnotateSensitiveRedactionService.shared
    var regions: [AutomationRedactionRegion] = []
    let wanted = Set(config.categories)

    func add(_ result: AnnotateSensitiveRedactionResult) {
      for region in result.regions {
        let category = AutomationRedactConfig.Category(region.kind)
        guard wanted.contains(category) else { continue }
        regions.append(AutomationRedactionRegion(category: category, rect: region.bounds))
      }
    }

    if !config.textCategories.isEmpty {
      add(try await service.detectRegions(in: image))
    }
    if config.detectsFaces {
      add(try await service.detectVisualRegions(in: image, target: .faces))
    }
    if config.detectsPeople {
      add(try await service.detectVisualRegions(in: image, target: .people))
    }
    return regions
  }
}

// MARK: - AI Describe

@MainActor
enum AutomationImageDescriber {
  /// Consent scope: agreeing for Annotate doesn't cover automations, which send
  /// every capture they run on without the user looking at it first.
  static let consentScope = "automation"

  static func provider(for selection: AutomationAIAnnotateConfig.Provider) -> AgentProvider? {
    switch selection {
    case .settings:
      return AgentProviderResolver.resolve(onDevice: { nil }, mock: { nil })
    case .endpoint(let id):
      return CustomOCRModelStore.shared.models.first { $0.id == id }.map { AgentEndpointProvider(model: $0) }
    case .cli(let raw):
      return AnnotateAgentCLIKind(rawValue: raw).map { AgentCLIProvider(kind: $0) }
    }
  }

  static func describe(_ url: URL, config: AutomationAIAnnotateConfig, interactive: Bool) async throws -> String {
    guard let image = QuickAccessImageOptimizer.loadImage(at: url) else { throw AutomationStepError.noFile }
    guard let provider = provider(for: config.provider) else {
      throw AutomationStepError.failed(L10n.Automations.errorAINotConfigured)
    }
    if let destination = provider.remoteDestination {
      let consent = AgentRemoteConsent(defaults: .standard, scope: consentScope)
      if !consent.has(destination) {
        // A run nobody is watching (CLI, Shortcuts, URL) can't ask.
        guard interactive, await askConsent(destination) else {
          throw AutomationStepError.failed(L10n.Automations.errorAIConsent(destination.name))
        }
        consent.record(destination)
      }
    }

    let toolbox = AutomationDescribeToolbox()
    let session = AgentSession(toolbox: toolbox, pacingEnabled: false, onToolCall: { _ in })
    defer { session.invalidate() }
    let request = AgentRequest(prompt: config.trimmedPrompt, history: [], sceneJSON: "{}", image: image)

    let reply = try await withThrowingTaskGroup(of: String?.self) { group in
      group.addTask { @MainActor in
        try await provider.run(request, session: session)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(AutomationAIAnnotateConfig.timeoutSeconds) * 1_000_000_000)
        return nil
      }
      defer { group.cancelAll() }
      guard let first = try await group.next(), let text = first else {
        throw AutomationStepError.timedOut(AutomationAIAnnotateConfig.timeoutSeconds)
      }
      return text
    }
    return toolbox.result ?? reply
  }

  static func askConsent(_ destination: AgentRemoteDestination) async -> Bool {
    await AgentRemoteConsent.ask(
      destination,
      title: L10n.Automations.aiConsentTitle(destination.name),
      endpointMessage: L10n.Automations.aiConsentMessage(destination.host),
      cliMessage: L10n.Automations.aiConsentMessageCLI(destination.name)
    )
  }
}

/// One tool: hand back the text. Models that answer in prose work too (the reply is used).
@MainActor
final class AutomationDescribeToolbox: AgentToolbox {
  static let toolName = "write_result"
  private(set) var result: String?

  let surface = AgentSurface(
    id: "automation",
    logCategory: .action,
    instructions: """
    You are a step in a Snapzy automation. You get one screenshot and a request about it. \
    Look at the image and answer the request. Call write_result once with the final text \
    (plain text, no preamble). Do not ask questions: nobody can answer them.
    """,
    toolsModeNote: "Call write_result with your answer.",
    planModeHint: "One write_result op with the answer.",
    cliModeNote: "Use the write_result tool to hand back the answer.",
    snapshotToolDescription: "Returns the screenshot.",
    imageAttachedNote: "The screenshot is attached.",
    imageOnRequestNote: "The screenshot is available through the snapshot tool."
  )

  var toolSpecs: [AgentToolSpec] {
    [AgentToolSpec(
      name: Self.toolName,
      description: "Hand back the final text for the request.",
      parametersJSON: #"{"type":"object","properties":{"text":{"type":"string","description":"The answer"}},"required":["text"]}"#
    )]
  }

  func isReadOnly(_: String) -> Bool { false }

  func execute(name: String, argumentsJSON: String) async -> AgentToolResult {
    guard name == Self.toolName else { return .failure(message: "Unknown tool \(name). Only write_result exists.") }
    guard let data = argumentsJSON.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let text = object["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return .failure(message: "write_result needs a non-empty \"text\".") }
    result = text
    return .success(["ok": true])
  }
}
