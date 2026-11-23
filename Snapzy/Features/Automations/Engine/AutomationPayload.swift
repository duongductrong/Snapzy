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
  /// Frontmost app when the run started (the captured app for window captures).
  let appName: String?
  /// Not captured yet (window captures don't report it to the runner); `{window.title}` renders empty.
  let windowTitle: String?
  /// `…/Captures/AutomationRuns/<runID>/`, created on first use.
  let workingDirectory: URL

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
