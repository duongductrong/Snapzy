//
//  AutomationStepHandlers.swift
//  Snapzy
//
//  One handler per step kind. Handlers only wrap existing services through
//  `AutomationRunEnvironment`; the runner owns ordering, failures and fallback.
//

import Foundation

/// Mutable state threaded through a run's steps.
struct AutomationRunState {
  let runID: UUID
  let automation: Automation
  let files: [URL]
  var sessionData: [URL: AnnotationSessionData] = [:]
  var quickAccessItemIDs: [URL: UUID] = [:]
  var didCopyImage = false
  /// Pasteboard change count right after this run's latest write. A link is only
  /// written when nothing else touched the pasteboard since (the user may have
  /// copied something while the upload was running).
  var ownPasteboardChangeCount: Int?
  var uploadResult: CloudUploadResult?
  var linkText: String?
  var didCopyLink = false
  var uploadFailure: AutomationUploadFailure?
  var wantsNotification = false

  var primaryFile: URL? { files.first }
}

enum AutomationUploadFailure: Equatable {
  case notConfigured
  case failed(String)
}

enum AutomationStepError: LocalizedError {
  case cloudNotConfigured
  case noFile

  var errorDescription: String? {
    switch self {
    case .cloudNotConfigured: "Cloud upload is not configured"
    case .noFile: "No capture file"
    }
  }
}

@MainActor
protocol AutomationStepHandler {
  func run(_ action: AutomationStepAction, state: inout AutomationRunState, environment: AutomationRunEnvironment) async throws
}

@MainActor
enum AutomationStepRegistry {
  static func handler(for kind: AutomationStepKind) -> AutomationStepHandler {
    switch kind {
    case .copyImage: CopyImageStepHandler()
    case .uploadAndCopyLink: UploadAndCopyLinkStepHandler()
    case .showQuickAccess: ShowQuickAccessStepHandler()
    case .openAnnotate: OpenAnnotateStepHandler()
    case .notify: NotifyStepHandler()
    }
  }
}

struct CopyImageStepHandler: AutomationStepHandler {
  func run(_: AutomationStepAction, state: inout AutomationRunState, environment: AutomationRunEnvironment) async throws {
    guard !state.files.isEmpty else { throw AutomationStepError.noFile }
    state.ownPasteboardChangeCount = environment.copyImages(state.files)
    state.didCopyImage = true
  }
}

struct UploadAndCopyLinkStepHandler: AutomationStepHandler {
  func run(_ action: AutomationStepAction, state: inout AutomationRunState, environment: AutomationRunEnvironment) async throws {
    guard case .uploadAndCopyLink(let format) = action else { return }
    guard environment.isCloudConfigured else { throw AutomationStepError.cloudNotConfigured }
    // Multi-display captures upload the first display only; one link per run.
    guard let file = state.primaryFile else { throw AutomationStepError.noFile }

    let result = try await environment.upload(file)
    state.uploadResult = result
    if let itemID = state.quickAccessItemIDs[file] {
      environment.setCloudLink(quickAccessItemID: itemID, result: result)
    }

    let text = CloudShareService.linkText(for: result.publicURL, fileURL: file, format: format)
    state.linkText = text
    let untouched = state.ownPasteboardChangeCount.map { $0 == environment.pasteboardChangeCount } ?? true
    if untouched {
      state.ownPasteboardChangeCount = environment.copyText(text)
      state.didCopyLink = true
    }
  }
}

struct ShowQuickAccessStepHandler: AutomationStepHandler {
  func run(_: AutomationStepAction, state: inout AutomationRunState, environment: AutomationRunEnvironment) async throws {
    for file in state.files where state.quickAccessItemIDs[file] == nil {
      guard let itemID = await environment.showQuickAccess(file, sessionData: state.sessionData[file]) else { continue }
      state.quickAccessItemIDs[file] = itemID
      if file == state.primaryFile, let result = state.uploadResult {
        environment.setCloudLink(quickAccessItemID: itemID, result: result)
      }
    }
  }
}

struct OpenAnnotateStepHandler: AutomationStepHandler {
  func run(_: AutomationStepAction, state: inout AutomationRunState, environment: AutomationRunEnvironment) async throws {
    guard let file = state.primaryFile else { throw AutomationStepError.noFile }
    environment.openAnnotate(file, quickAccessItemID: state.quickAccessItemIDs[file], sessionData: state.sessionData[file])
  }
}

struct NotifyStepHandler: AutomationStepHandler {
  func run(_: AutomationStepAction, state: inout AutomationRunState, environment _: AutomationRunEnvironment) async throws {
    // Posted once by the runner after every step ran, so it can report the outcome.
    state.wantsNotification = true
  }
}
