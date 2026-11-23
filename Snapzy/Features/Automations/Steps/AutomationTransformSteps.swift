//
//  AutomationTransformSteps.swift
//  Snapzy
//
//  Steps that turn a file into a new one: canvas preset, resize, convert,
//  strip metadata, video → GIF. Each writes into the run's working directory
//  and swaps the payload file; the capture itself is never modified.
//

import Foundation

/// Runs a nonisolated file transform off the main actor.
private func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
  try await Task.detached(priority: .userInitiated, operation: work).value
}

private extension AutomationRunState {
  /// Base name for a working file derived from `url`.
  func workingBaseName(for url: URL) -> String {
    let original = payload.files.first { $0.url == url }?.original ?? url
    return original.deletingPathExtension().lastPathComponent
  }

  func prepareWorkingDirectory() throws -> URL {
    try FileManager.default.createDirectory(at: context.workingDirectory, withIntermediateDirectories: true)
    return context.workingDirectory
  }
}

private func mapTransformError(_ error: Error) -> Error {
  switch error {
  case AutomationImageTransformError.unreadable: AutomationStepError.noFile
  case AutomationImageTransformError.encodeFailed: AutomationStepError.renderFailed
  default: error
  }
}

struct ApplyCanvasPresetStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .applyCanvasPreset(let config) = action else { return }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    for file in files {
      let destination = try state.context.makeWorkingFile(
        baseName: state.workingBaseName(for: file),
        fileExtension: file.pathExtension
      )
      let session = try environment.applyCanvasPreset(config.presetID, source: file, destination: destination)
      guard FileManager.default.fileExists(atPath: destination.path) else {
        // The preset leaves the image unchanged: keep the current file.
        continue
      }
      state.replace(file, with: destination, kind: .image)
      if let session {
        state.sessionData[destination] = session
      }
    }
  }
}

struct ResizeStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment _: AutomationRunEnvironment
  ) async throws {
    guard case .resize(let config) = action else { return }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    let directory = try state.prepareWorkingDirectory()
    for file in files {
      let baseName = state.workingBaseName(for: file)
      do {
        let result = try await offMain {
          try AutomationImageTransforms.resize(file, config: config, into: directory, baseName: baseName)
        }
        state.replace(file, with: result.url, kind: .image)
        if result.fellBackToPNG {
          state.warnings.append(L10n.Automations.warningPNGFallback)
        }
      } catch {
        throw mapTransformError(error)
      }
    }
  }
}

struct ConvertStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .convert(let config) = action else { return }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    let settings: QuickAccessOptimizeSettings
    if let presetID = config.optimizePresetID {
      guard let preset = environment.optimizeSettings(presetID: presetID) else {
        throw AutomationStepError.failed(L10n.Automations.errorOptimizePresetMissing)
      }
      settings = preset
    } else {
      settings = config.optimizeSettings
    }

    let directory = try state.prepareWorkingDirectory()
    for file in files {
      let baseName = state.workingBaseName(for: file)
      do {
        let result = try await offMain {
          try AutomationImageTransforms.convert(file, settings: settings, into: directory, baseName: baseName)
        }
        try Task.checkCancellation()
        state.replace(file, with: result.url, kind: .image)
        if result.fellBackToPNG {
          state.warnings.append(L10n.Automations.warningPNGFallback)
        }
        if result.exceedsFileSizeLimit {
          state.warnings.append(L10n.Automations.warningFileSizeLimit)
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw mapTransformError(error)
      }
    }
  }
}

struct StripMetadataStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment _: AutomationRunEnvironment
  ) async throws {
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    let directory = try state.prepareWorkingDirectory()
    for file in files {
      let baseName = state.workingBaseName(for: file)
      do {
        let result = try await offMain {
          try AutomationImageTransforms.stripMetadata(file, into: directory, baseName: baseName)
        }
        state.replace(file, with: result.url, kind: .image)
      } catch {
        throw mapTransformError(error)
      }
    }
  }
}

struct ConvertToGIFStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.video] }

  func produces(_: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    given.subtracting([.video]).union([.gif])
  }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .convertToGIF(let config) = action else { return }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    for file in files {
      // Convert a clone inside the working directory: the converter writes the
      // GIF next to its input and must never touch the export folder.
      let clone = try state.context.makeWorkingFile(
        baseName: state.workingBaseName(for: file),
        fileExtension: file.pathExtension
      )
      try FileManager.default.copyItem(at: file, to: clone)
      defer { try? FileManager.default.removeItem(at: clone) }
      let gif = try await environment.convertToGIF(clone, config: config)
      try Task.checkCancellation()
      state.replace(file, with: gif, kind: .gif)
    }
  }
}
