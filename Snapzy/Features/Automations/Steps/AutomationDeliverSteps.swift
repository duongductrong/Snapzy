//
//  AutomationDeliverSteps.swift
//  Snapzy
//
//  Steps that hand the result to the user: upload, copy link / text, save to
//  a folder, reveal in Finder, pin to screen.
//

import Foundation

struct UploadStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.files }

  func produces(_: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    given.union([.link])
  }

  var trust: AutomationTrustTier { .network }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    let destination: AutomationUploadDestination
    if case .upload(let config) = action { destination = config.destination } else { destination = .default }
    guard environment.isUploadConfigured(destination) else {
      throw destination == .default ? AutomationStepError.cloudNotConfigured : AutomationStepError.uploaderMissing
    }
    // Multi-display captures upload the first display only; one link per run.
    guard let file = files.first else { throw AutomationStepError.noFile }

    let result = try await environment.upload(file, destination: destination)
    try Task.checkCancellation()
    state.uploadResult = result
    state.payload.link = result.publicURL
    state.linkText = result.publicURL.absoluteString
    state.lastDelivery = .linkReady
    if let itemID = state.quickAccessItemIDs[file] {
      environment.setCloudLink(quickAccessItemID: itemID, result: result)
    }
  }
}

struct CopyLinkStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.link] }

  func run(
    _ action: AutomationStepAction,
    files _: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .copyLink(let template) = action else { return }
    guard let link = state.payload.link else { throw AutomationStepError.noLink }
    let text = Self.text(for: template, link: link, state: state)
    state.linkText = text
    if AutomationStepCopy.copyText(text, state: &state, environment: environment) {
      state.didCopyLink = true
      state.lastDelivery = .linkCopied
    } else {
      state.lastDelivery = .linkReady
    }
  }

  static func text(for template: AutomationLinkTemplate, link: URL, state: AutomationRunState) -> String {
    // The upload step sends the first file; the link describes it.
    let file = state.primaryFile
    switch template.style {
    case .url:
      return link.absoluteString
    case .markdown:
      guard let file else { return "[\(link.lastPathComponent)](\(link.absoluteString))" }
      return CloudShareService.linkText(
        for: link,
        fileURL: file,
        format: .markdown,
        isImage: state.kind(of: file) != .video
      )
    case .html, .bbcode, .custom:
      return state.variables().render(template.template, escape: template.escape)
    }
  }
}

struct CopyTextStepHandler: AutomationStepHandler {
  /// `{text}` needs recognized text; any other template only needs something to describe.
  func accepts(_ action: AutomationStepAction) -> Set<AutomationPayloadKind> {
    guard case .copyText(let template) = action else { return [.text] }
    if template.usesText { return [.text] }
    if template.usesLink { return [.link] }
    return AutomationPayloadKind.all
  }

  func run(
    _ action: AutomationStepAction,
    files _: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .copyText(let template) = action else { return }
    if template.usesText, state.payload.text == nil { throw AutomationStepError.noText }
    let text = state.variables().render(template.template)
    if AutomationStepCopy.copyText(text, state: &state, environment: environment) {
      state.didCopyText = true
      state.lastDelivery = .textCopied
    }
  }
}

struct SaveToFolderStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.files }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .saveToFolder(let config) = action else { return }
    guard let ref = config.folder else { throw AutomationStepError.folderUnavailable }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    let folder = try environment.resolveFolder(ref)

    var lastSaved: URL?
    for (index, file) in files.enumerated() {
      var variables = state.variables()
      variables["{file.name}"] = file.lastPathComponent
      variables["{file.basename}"] = file.deletingPathExtension().lastPathComponent
      variables["{file.ext}"] = file.pathExtension
      let rendered = CaptureOutputNaming.sanitizedBaseName(variables.render(config.nameTemplate))
      var baseName = rendered.isEmpty ? file.deletingPathExtension().lastPathComponent : rendered
      if files.count > 1 { baseName += "_\(index + 1)" }

      // Never overwrite the capture (or any input) itself: retry needs it.
      let protected = Set(state.payload.files.map(\.original.standardizedFileURL.path) + state.inputFiles.map(\.standardizedFileURL.path))
      var conflict = config.conflict
      if conflict == .overwrite {
        let target = folder.appendingPathComponent(baseName).appendingPathExtension(file.pathExtension)
        if protected.contains(target.standardizedFileURL.path) { conflict = .uniquify }
      }
      let destination = try Self.destination(
        in: folder,
        baseName: baseName,
        fileExtension: file.pathExtension,
        conflict: conflict
      )
      // Marked first: a folder watch on this folder must never run on it (loop).
      AutomationFileOriginTracker.shared.markWritten([destination])
      try Self.copy(file, to: destination, overwrite: conflict == .overwrite)
      lastSaved = destination
    }

    if let lastSaved {
      state.payload.savedFile = lastSaved
      state.payload.savedFolder = folder
      state.lastDelivery = .saved(lastSaved)
    }
  }

  static func destination(
    in folder: URL,
    baseName: String,
    fileExtension: String,
    conflict: AutomationConflictPolicy
  ) throws -> URL {
    // `baseName` may contain sub-folders (`img/{date}`).
    let target = folder.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
    let directory = target.deletingLastPathComponent()
    let folderPath = folder.standardizedFileURL.path
    let directoryPath = directory.standardizedFileURL.path
    guard directoryPath == folderPath || directoryPath.hasPrefix(folderPath + "/") else {
      throw AutomationStepError.folderUnavailable
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    switch conflict {
    case .overwrite:
      return target
    case .uniquify:
      return CaptureOutputNaming.makeUniqueFileURL(
        in: directory,
        baseName: target.deletingPathExtension().lastPathComponent,
        fileExtension: fileExtension
      )
    }
  }

  /// Copies (never moves); an overwrite replaces atomically.
  static func copy(_ source: URL, to destination: URL, overwrite: Bool) throws {
    let fileManager = FileManager.default
    if overwrite, fileManager.fileExists(atPath: destination.path) {
      let staging = destination.deletingLastPathComponent()
        .appendingPathComponent(".snapzy-\(UUID().uuidString)-\(destination.lastPathComponent)")
      try fileManager.copyItem(at: source, to: staging)
      _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
    } else {
      try fileManager.copyItem(at: source, to: destination)
    }
  }
}

struct RevealStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.files }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    if let saved = state.payload.savedFile {
      environment.reveal([saved])
      return
    }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    // A working copy disappears after the run; show the file it came from.
    let originals = files.map { file in state.payload.files.first { $0.url == file }?.original ?? file }
    environment.reveal(originals)
  }
}

struct PinStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard let file = files.first else { throw AutomationStepError.noFile }
    guard await environment.pin(file) else { throw AutomationStepError.failed(L10n.Automations.errorPinFailed) }
    state.retain([file])
  }
}
