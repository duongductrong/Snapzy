//
//  AutomationInvocation.swift
//  Snapzy
//
//  Types shared by every trigger that launches an automation: who started it,
//  how the automation is referenced, the files handed in, and the outcome.
//

import Foundation
import UniformTypeIdentifiers

/// What started a run. External invocations need `Automation.externalInvocation`.
enum AutomationInvocation: String, Sendable {
  case hotkey
  case urlScheme
  case cli
  case menuBar
  case quickAccess
  case history
  case appIntent
  /// "Retry" on a failure notification (internal; re-runs on the run's input files).
  case retry

  var isExternal: Bool {
    self == .urlScheme || self == .cli || self == .appIntent
  }
}

/// An automation addressed by id, or by name (trimmed, case-insensitive).
enum AutomationRef: Equatable, Sendable {
  case id(UUID)
  case name(String)

  init(_ raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let id = UUID(uuidString: trimmed) {
      self = .id(id)
    } else {
      self = .name(trimmed)
    }
  }
}

/// The kind of a file an automation runs on. Steps declare which kinds they accept.
enum AutomationFileKind: String, CaseIterable, Sendable {
  case image
  case video
  case gif

  static func of(_ url: URL) -> AutomationFileKind? {
    guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
    if type.conforms(to: .gif) { return .gif }
    if type.conforms(to: .image) { return .image }
    if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
    return nil
  }
}

/// Files a trigger hands in. The automation's capture source is skipped and the
/// steps run on these files instead; the originals are never modified.
struct AutomationInput: Sendable {
  var files: [URL]
  /// The files already have a History entry (Quick Access, History), so the run adds none.
  var isAlreadyInHistory: Bool
  /// The Quick Access card the run started from; steps reuse it instead of adding a card.
  var sourceQuickAccessItemID: UUID?

  init(files: [URL], isAlreadyInHistory: Bool, sourceQuickAccessItemID: UUID? = nil) {
    self.files = files
    self.isAlreadyInHistory = isAlreadyInHistory
    self.sourceQuickAccessItemID = sourceQuickAccessItemID
  }
}

enum AutomationLaunchRejection: Error, Equatable, Sendable {
  case notFound
  case ambiguousName([UUID])
  case disabled
  case externalNotAllowed
  case urlSchemeDisabled
  case unsupportedSource
  case needsFile
  case unsupportedFile(String)
  case noStepAcceptsFile(AutomationFileKind)
  case fileMissing(String)
  case permissionRequired
  case captureInProgress
  /// The clipboard holds no image (clipboard-image source).
  case clipboardEmpty
  /// A step has nothing to work on (e.g. Translate before OCR).
  case invalidChain
  /// Imported with network / script steps; open it in the editor and save to allow it.
  case needsReview
  /// Script / Shortcut steps are off (Settings → Automations → Advanced).
  case codeStepsDisabled
  /// URL scheme / Shortcuts may not run script steps without the second opt-in.
  case externalCodeNotAllowed

  /// Stable identifier for logs and the CLI.
  var code: String {
    switch self {
    case .notFound: "not_found"
    case .ambiguousName: "ambiguous_name"
    case .disabled: "disabled"
    case .externalNotAllowed: "external_not_allowed"
    case .urlSchemeDisabled: "url_scheme_disabled"
    case .unsupportedSource: "unsupported_source"
    case .needsFile: "needs_file"
    case .unsupportedFile: "unsupported_file"
    case .noStepAcceptsFile: "no_step_accepts_file"
    case .fileMissing: "file_missing"
    case .permissionRequired: "permission_required"
    case .captureInProgress: "capture_in_progress"
    case .clipboardEmpty: "clipboard_empty"
    case .invalidChain: "invalid_chain"
    case .needsReview: "needs_review"
    case .codeStepsDisabled: "code_steps_disabled"
    case .externalCodeNotAllowed: "external_code_not_allowed"
    }
  }
}

/// Sendable summary of a finished run, returned to the CLI and Shortcuts.
struct AutomationRunReport: Equatable, Sendable {
  let runID: UUID
  let automationID: UUID
  /// The captured or handed-in files.
  let files: [URL]
  /// The uploaded link text (URL or Markdown), when a step produced one.
  let link: String?
  let message: String
  let isError: Bool
  /// OCR / translation output, when a step produced text.
  let text: String?
  /// What the run delivered: the saved file, else the final (possibly transformed) files.
  let outputFiles: [URL]

  init(
    runID: UUID,
    automationID: UUID,
    files: [URL],
    link: String?,
    message: String,
    isError: Bool,
    text: String? = nil,
    outputFiles: [URL]? = nil
  ) {
    self.runID = runID
    self.automationID = automationID
    self.files = files
    self.link = link
    self.message = message
    self.isError = isError
    self.text = text
    self.outputFiles = outputFiles ?? files
  }
}

enum AutomationLaunchOutcome: Equatable, Sendable {
  case finished(AutomationRunReport)
  /// The capture was cancelled (or saved no file) before any step ran.
  case cancelled
  case rejected(AutomationLaunchRejection)
}

/// Places that list automations for the user to pick from.
enum AutomationTriggerSlot: Sendable {
  case menuBar
  case quickAccess
  case history
  /// URL scheme, CLI and Shortcuts.
  case external
}

@MainActor
extension Automation {
  /// True when at least one enabled step can work on a file of `kind`.
  func acceptsFile(of kind: AutomationFileKind) -> Bool {
    activeActions.contains { AutomationStepRegistry.accepts($0, kind) }
  }
}
