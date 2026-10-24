//
//  OutputWriter.swift
//  SnapzyCLICore
//
//  Applies `--output` on the client side: the app writes into its own staging
//  directory and the CLI moves files where the caller asked. Writing from the
//  CLI keeps the caller's own sandbox and folder permissions in charge.
//

import Foundation
import SnapzyCLIProtocol

public enum OutputDestination: Equatable, Sendable {
  /// No `--output`: leave files in Snapzy's staging directory.
  case staging
  /// `--output -`: stream the single file's bytes to stdout.
  case standardOutput
  /// `--output dir/` or an existing directory: keep staging file names.
  case directory(URL)
  /// `--output file.png`: exact path; `file-1.png`, `file-2.png`… for several files.
  case file(URL)

  public static func resolve(
    _ argument: String?,
    currentDirectory: URL,
    fileManager: FileManager = .default
  ) -> OutputDestination {
    guard let argument, !argument.isEmpty else { return .staging }
    if argument == "-" { return .standardOutput }

    let url = URL(fileURLWithPath: argument, relativeTo: currentDirectory).standardizedFileURL
    var isDirectory: ObjCBool = false
    let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    if argument.hasSuffix("/") || (exists && isDirectory.boolValue) {
      return .directory(URL(fileURLWithPath: url.path, isDirectory: true))
    }
    return .file(url)
  }
}

public struct OutputWriter {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func apply(
    _ result: CLICaptureResult,
    to destination: OutputDestination,
    force: Bool,
    writeStandardOutput: (Data) throws -> Void
  ) throws -> CLICaptureResult {
    switch destination {
    case .staging:
      result
    case .standardOutput:
      try stream(result, writeStandardOutput: writeStandardOutput)
    case .directory, .file:
      try move(result, targets: targetURLs(for: result.files, destination: destination), force: force)
    }
  }

  func targetURLs(for files: [CLICapturedFile], destination: OutputDestination) -> [URL] {
    switch destination {
    case .staging, .standardOutput:
      return files.map { URL(fileURLWithPath: $0.path) }
    case .directory(let directory):
      return files.map { directory.appendingPathComponent(URL(fileURLWithPath: $0.path).lastPathComponent) }
    case .file(let url):
      guard files.count > 1 else { return [url] }
      let stem = url.deletingPathExtension().lastPathComponent
      let pathExtension = url.pathExtension
      let parent = url.deletingLastPathComponent()
      return files.indices.map { index in
        let name = "\(stem)-\(index + 1)"
        let candidate = parent.appendingPathComponent(name)
        return pathExtension.isEmpty ? candidate : candidate.appendingPathExtension(pathExtension)
      }
    }
  }

  private func stream(_ result: CLICaptureResult,
                      writeStandardOutput: (Data) throws -> Void) throws -> CLICaptureResult {
    guard result.files.count == 1, let file = result.files.first else {
      throw CLIError(
        .invalidArguments,
        "Cannot stream \(result.files.count) captures to stdout",
        hint: "Pass a directory or file path to --output, or capture a single display"
      )
    }

    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: file.path))
    } catch {
      throw CLIError(.internal, "Could not read \(file.path): \(error.localizedDescription)")
    }
    // The image is in memory now; remove the staged copy even if the reader
    // closes the pipe early (`| head`) or the write fails.
    defer { try? fileManager.removeItem(atPath: file.path) }
    try writeStandardOutput(data)

    var streamed = result
    streamed.files[0].path = "-"
    return streamed
  }

  /// Checks what can be known before capturing, so an existing `--output`
  /// file fails fast instead of after the screen was already taken.
  public func preflight(_ destination: OutputDestination, force: Bool) throws {
    guard !force, case .file(let url) = destination, fileManager.fileExists(atPath: url.path) else { return }
    throw Self.existingFileError(url)
  }

  /// Copies, then removes the staged source best-effort: the caller may be
  /// sandboxed with read-only access to Snapzy's staging folder, and the app
  /// sweeps leftovers after 24 hours.
  private func move(_ result: CLICaptureResult, targets: [URL], force: Bool) throws -> CLICaptureResult {
    if !force, let existing = targets.first(where: { fileManager.fileExists(atPath: $0.path) }) {
      throw CLIError(
        .invalidArguments,
        "\(existing.path) already exists",
        hint: Self.stagedFilesHint(result, prefix: Self.forceHint)
      )
    }

    var written = result
    for (index, target) in targets.enumerated() {
      let source = URL(fileURLWithPath: result.files[index].path)
      do {
        try place(source, at: target)
      } catch {
        throw CLIError(
          .internal,
          "Could not write \(target.path): \(error.localizedDescription)",
          hint: Self.stagedFilesHint(result, prefix: nil)
        )
      }
      try? fileManager.removeItem(at: source)
      written.files[index].path = target.path
    }
    return written
  }

  /// Copies next to the target first, then swaps it in, so a failed copy
  /// never leaves `--force` with the old file deleted and no new one.
  private func place(_ source: URL, at target: URL) throws {
    let directory = target.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let temporary = directory.appendingPathComponent(".\(target.lastPathComponent).snapzy-\(UUID().uuidString)")
    try fileManager.copyItem(at: source, to: temporary)
    do {
      if fileManager.fileExists(atPath: target.path) {
        _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: target)
      }
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error
    }
  }

  private static let forceHint = "Pass --force to overwrite"

  private static func existingFileError(_ url: URL) -> CLIError {
    CLIError(.invalidArguments, "\(url.path) already exists", hint: forceHint)
  }

  private static func stagedFilesHint(_ result: CLICaptureResult, prefix: String?) -> String {
    let paths = result.files.map(\.path).joined(separator: ", ")
    let staged = "The capture is still at \(paths)"
    guard let prefix else { return staged }
    return "\(prefix). \(staged)"
  }
}
