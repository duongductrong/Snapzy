//
//  AutomationPayload.swift
//  Snapzy
//
//  What flows between steps: files (each with the original it came from),
//  recognized text, the uploaded link and values for templates. Transform
//  steps never modify a capture: they write into the run's working directory
//  and swap the payload file, so the original stays intact for retry.
//

import Foundation

struct AutomationFile: Equatable, Sendable {
  var url: URL
  var kind: AutomationFileKind
  /// The captured or handed-in file this one was derived from.
  let original: URL

  var isWorkingCopy: Bool { url != original }

  init(url: URL, kind: AutomationFileKind, original: URL? = nil) {
    self.url = url
    self.kind = kind
    self.original = original ?? url
  }
}

struct AutomationPayload: Equatable {
  var files: [AutomationFile]
  /// OCR / translation output.
  var text: String?
  /// Public URL of the last upload.
  var link: URL?
  /// The last file `saveToFolder` wrote and the folder it went into.
  var savedFile: URL?
  var savedFolder: URL?

  init(files: [AutomationFile]) {
    self.files = files
  }

  var kinds: Set<AutomationPayloadKind> {
    var kinds = Set(files.map { AutomationPayloadKind($0.kind) })
    if text != nil { kinds.insert(.text) }
    if link != nil { kinds.insert(.link) }
    return kinds
  }
}

/// Facts about a run that don't change while it runs.
struct AutomationRunContext {
  let runID: UUID
  let automationID: UUID
  let automationName: String
  let invocation: AutomationInvocation
  let startedAt: Date
  /// The captured window's app, else the frontmost app when the run was triggered.
  let appName: String?
  /// Window title, when the capture knows it (window captures).
  let windowTitle: String?
  /// Bundle id of the same app; `nil` for runs on handed-in files.
  let bundleID: String?
  /// The capture mode of a capture-sourced run; `nil` for handed-in files.
  let captureMode: AutomationCaptureMode?
  /// `…/Captures/AutomationRuns/<runID>/`, created on first use.
  let workingDirectory: URL

  init(
    runID: UUID,
    automationID: UUID,
    automationName: String,
    invocation: AutomationInvocation,
    startedAt: Date,
    appName: String?,
    windowTitle: String?,
    bundleID: String? = nil,
    captureMode: AutomationCaptureMode? = nil,
    workingDirectory: URL
  ) {
    self.runID = runID
    self.automationID = automationID
    self.automationName = automationName
    self.invocation = invocation
    self.startedAt = startedAt
    self.appName = appName
    self.windowTitle = windowTitle
    self.bundleID = bundleID
    self.captureMode = captureMode
    self.workingDirectory = workingDirectory
  }

  static func workingDirectory(for runID: UUID) -> URL {
    TempCaptureManager.tempCaptureRootDirectory()
      .appendingPathComponent("AutomationRuns", isDirectory: true)
      .appendingPathComponent(runID.uuidString, isDirectory: true)
  }

  /// A fresh file in the working directory: `<baseName>.<ext>`, uniquified.
  func makeWorkingFile(baseName: String, fileExtension: String) throws -> URL {
    try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    return CaptureOutputNaming.makeUniqueFileURL(
      in: workingDirectory,
      baseName: baseName,
      fileExtension: fileExtension
    )
  }
}
