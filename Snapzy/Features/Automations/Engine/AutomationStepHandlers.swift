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
  var fileKinds: [URL: AutomationFileKind] = [:]
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

  init(runID: UUID, automation: Automation, files: [URL]) {
    self.runID = runID
    self.automation = automation
    self.files = files
  }

  var primaryFile: URL? { files.first }

  func kind(of file: URL) -> AutomationFileKind {
    fileKinds[file] ?? .image
  }

  /// True when every file is a still image (what "Image copied" means).
  var isImageOnly: Bool {
    files.allSatisfy { kind(of: $0) == .image }
  }
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
  /// File kinds the step can work on. The runner hands a step only those files
  /// and skips it when none are left.
  var accepts: Set<AutomationFileKind> { get }
  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws
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

  static func accepts(_ kind: AutomationStepKind, _ fileKind: AutomationFileKind) -> Bool {
    handler(for: kind).accepts.contains(fileKind)
  }
}

private let allFileKinds = Set(AutomationFileKind.allCases)

/// Copies the file: image data for one still image, a file reference for a
/// video / GIF or several files.
struct CopyImageStepHandler: AutomationStepHandler {
  var accepts: Set<AutomationFileKind> { allFileKinds }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    state.ownPasteboardChangeCount = AutomationStepCopy.copy(files, state: state, environment: environment)
    state.didCopyImage = true
  }
}

@MainActor
enum AutomationStepCopy {
  /// Writes `files` to the pasteboard the way their kind needs; returns the change count.
  static func copy(_ files: [URL], state: AutomationRunState, environment: AutomationRunEnvironment) -> Int {
    if files.count == 1, let file = files.first, state.kind(of: file) != .image {
      return environment.copyMedia(file)
    }
    return environment.copyImages(files)
  }
}

struct UploadAndCopyLinkStepHandler: AutomationStepHandler {
  var accepts: Set<AutomationFileKind> { allFileKinds }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .uploadAndCopyLink(let format) = action else { return }
    guard environment.isCloudConfigured else { throw AutomationStepError.cloudNotConfigured }
    // Multi-display captures upload the first display only; one link per run.
    guard let file = files.first else { throw AutomationStepError.noFile }

    let result = try await environment.upload(file)
    state.uploadResult = result
    if let itemID = state.quickAccessItemIDs[file] {
      environment.setCloudLink(quickAccessItemID: itemID, result: result)
    }

    let text = CloudShareService.linkText(
      for: result.publicURL,
      fileURL: file,
      format: format,
      isImage: state.kind(of: file) != .video
    )
    state.linkText = text
    let untouched = state.ownPasteboardChangeCount.map { $0 == environment.pasteboardChangeCount } ?? true
    if untouched {
      state.ownPasteboardChangeCount = environment.copyText(text)
      state.didCopyLink = true
    }
  }
}

struct ShowQuickAccessStepHandler: AutomationStepHandler {
  var accepts: Set<AutomationFileKind> { allFileKinds }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    for file in files where state.quickAccessItemIDs[file] == nil {
      guard let itemID = await environment.showQuickAccess(
        file,
        kind: state.kind(of: file),
        sessionData: state.sessionData[file]
      ) else { continue }
      state.quickAccessItemIDs[file] = itemID
      if file == state.primaryFile, let result = state.uploadResult {
        environment.setCloudLink(quickAccessItemID: itemID, result: result)
      }
    }
  }
}

struct OpenAnnotateStepHandler: AutomationStepHandler {
  var accepts: Set<AutomationFileKind> { [.image] }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard let file = files.first else { throw AutomationStepError.noFile }
    environment.openAnnotate(file, quickAccessItemID: state.quickAccessItemIDs[file], sessionData: state.sessionData[file])
  }
}

struct NotifyStepHandler: AutomationStepHandler {
  var accepts: Set<AutomationFileKind> { allFileKinds }

  func run(
    _: AutomationStepAction,
    files _: [URL],
    state: inout AutomationRunState,
    environment _: AutomationRunEnvironment
  ) async throws {
    // Posted once by the runner after every step ran, so it can report the outcome.
    state.wantsNotification = true
  }
}
