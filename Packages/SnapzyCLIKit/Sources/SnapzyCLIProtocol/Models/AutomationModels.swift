//
//  AutomationModels.swift
//  SnapzyCLIProtocol
//
//  Params and results for `automation.*` (protocol 1.1). An automation is
//  referenced by id or name; `automation.run` either starts its capture and
//  waits for the user's selection, or runs its steps on files the CLI passes.
//

import Foundation

/// One automation as `snapzy automation list` shows it.
public struct CLIAutomationSummary: Codable, Sendable, Equatable {
  public let id: String
  public let name: String
  /// `area`, `fullscreen`, `activeWindow`, `applicationWindow`, `input` (runs only
  /// on files passed with `--file`), or `unsupported` (written by a newer Snapzy).
  public let source: String
  /// Enabled step kinds in run order, such as `copyImage` or `uploadAndCopyLink`.
  public let steps: [String]
  public let enabled: Bool
  /// "Allow URL scheme, command line and Shortcuts" is on, so `automation run` may start it.
  public let external: Bool

  public init(id: String, name: String, source: String, steps: [String], enabled: Bool, external: Bool) {
    self.id = id
    self.name = name
    self.source = source
    self.steps = steps
    self.enabled = enabled
    self.external = external
  }

  /// `automation run` can start it right now (apart from permissions and other captures).
  public var isRunnable: Bool {
    enabled && external
  }
}

public struct CLIAutomationList: Codable, Sendable, Equatable {
  /// Every automation; runnable ones (enabled and external) first, then in Settings order.
  public let automations: [CLIAutomationSummary]

  public init(automations: [CLIAutomationSummary]) {
    self.automations = automations
  }
}

public struct CLIAutomationRunParams: Codable, Sendable, Equatable {
  /// Automation id (UUID) or name (trimmed, case-insensitive).
  public let ref: String
  /// Absolute paths. When present the capture is skipped and the steps run on these files.
  public let files: [String]?

  public init(ref: String, files: [String]? = nil) {
    self.ref = ref
    self.files = files
  }
}

public enum CLIAutomationRunState: String, Codable, Sendable, CaseIterable {
  /// The steps ran; `isError` tells whether one of them failed.
  case finished
  /// The capture was cancelled (or saved nothing) before any step ran.
  case cancelled

  /// Unknown values from a newer app read as `finished`; `isError` still carries failure.
  public init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = CLIAutomationRunState(rawValue: rawValue) ?? .finished
  }
}

public struct CLIAutomationRunResult: Codable, Sendable, Equatable {
  public let runId: String
  public let automationId: String
  public let state: CLIAutomationRunState
  /// Files the run produced or worked on (the capture, or the files passed in).
  public let files: [String]
  /// Uploaded link text (URL or Markdown) when a step produced one.
  public let link: String?
  /// Snapzy's one-line summary, in the app's language.
  public let message: String
  /// A step failed (for example the upload), even if earlier steps succeeded.
  public let isError: Bool

  public init(
    runId: String,
    automationId: String,
    state: CLIAutomationRunState,
    files: [String] = [],
    link: String? = nil,
    message: String = "",
    isError: Bool = false
  ) {
    self.runId = runId
    self.automationId = automationId
    self.state = state
    self.files = files
    self.link = link
    self.message = message
    self.isError = isError
  }
}
