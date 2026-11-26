//
//  QuickAccessActionPerformer.swift
//  Snapzy
//
//  Milestone 6: Quick Access card actions with side effects run the same
//  automation step handlers as automations (principle 3: one implementation).
//    Copy          → `copyFile` (or the cloud link as text once uploaded)
//    Upload        → `upload` + `copyLink(.url)`
//  Card UI (animation, sounds, dismissal) stays with the card and the manager;
//  save / reveal / pin / delete stay in `QuickAccessManager`: they move the
//  card's own temp file and history record, which no step does.
//  Runs are not logged: a card button is not an automation run.
//

import Foundation

@MainActor
final class QuickAccessActionPerformer {
  static let shared = QuickAccessActionPerformer()

  private let makeEnvironment: (_ replacingCloudKey: String?) -> AutomationRunEnvironment

  init(environment: ((_ replacingCloudKey: String?) -> AutomationRunEnvironment)? = nil) {
    makeEnvironment = environment ?? { QuickAccessActionEnvironment(replacingCloudKey: $0) }
  }

  /// Copies the item: its cloud link when it has one, else the file (image
  /// data for a screenshot, a file reference for a video / GIF).
  func copy(_ item: QuickAccessItem) async {
    let environment = makeEnvironment(nil)
    if let cloudURL = item.cloudURL {
      _ = environment.copyText(cloudURL.absoluteString)
      return
    }
    var state = makeState(for: item)
    do {
      try await CopyFileStepHandler().run(.copyFile, files: [item.url], state: &state, environment: environment)
    } catch {
      DiagnosticLogger.shared.logError(.clipboard, error, "Quick access copy failed", context: ["fileName": item.url.lastPathComponent])
    }
  }

  /// Uploads the item (replacing its previous cloud object, if any), sets the
  /// card's cloud link and copies the URL.
  @discardableResult
  func upload(_ item: QuickAccessItem) async throws -> CloudUploadResult {
    let environment = makeEnvironment(item.cloudKey)
    var state = makeState(for: item)
    try await UploadStepHandler().run(
      .upload(AutomationUploadConfig()),
      files: [item.url],
      state: &state,
      environment: environment
    )
    try await CopyLinkStepHandler().run(
      .copyLink(AutomationLinkTemplate(style: .url)),
      files: [item.url],
      state: &state,
      environment: environment
    )
    guard let result = state.uploadResult else { throw AutomationStepError.noLink }
    return result
  }

  /// A one-file run state bound to the card, so steps update it (cloud link).
  private func makeState(for item: QuickAccessItem) -> AutomationRunState {
    let runID = UUID()
    let kind: AutomationFileKind = AutomationFileKind.of(item.url) ?? (item.isVideo ? .video : .image)
    let context = AutomationRunContext(
      runID: runID,
      automationID: runID,
      automationName: "",
      invocation: .quickAccess,
      startedAt: Date(),
      appName: nil,
      windowTitle: nil,
      bundleID: nil,
      captureMode: nil,
      workingDirectory: AutomationRunContext.workingDirectory(for: runID)
    )
    var state = AutomationRunState(
      runID: runID,
      automation: Automation(id: runID, name: "", source: .input, steps: []),
      files: [AutomationFile(url: item.url, kind: kind)],
      context: context
    )
    state.quickAccessItemIDs[item.url] = item.id
    return state
  }
}

/// Live services; a re-upload replaces the card's previous cloud object.
@MainActor
private final class QuickAccessActionEnvironment: LiveAutomationRunEnvironment {
  private let replacingCloudKey: String?

  init(replacingCloudKey: String?) {
    self.replacingCloudKey = replacingCloudKey
    super.init()
  }

  override func upload(_ url: URL) async throws -> CloudUploadResult {
    try await CloudShareService.shared.upload(fileURL: url, replacingKey: replacingCloudKey)
  }
}
