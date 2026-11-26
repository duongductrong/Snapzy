//
//  VideoEditorSessionStore.swift
//  Snapzy
//
//  Durable sidecar storage for non-destructive Video Editor sessions.
//

import CryptoKit
import Foundation

@MainActor
final class VideoEditorSessionStore {
  static let shared = VideoEditorSessionStore()

  struct PreparedSourceSnapshot: Sendable {
    let directoryURL: URL
    let sourceURL: URL
  }

  enum StoreError: LocalizedError {
    case sourceUnavailable(URL)
    case packageUnavailable
    case manifestTooLarge(Int)
    case sessionQuarantined

    var errorDescription: String? {
      switch self {
      case .sourceUnavailable(let url):
        "The original video source could not be preserved for continued editing: \(url.lastPathComponent)"
      case .packageUnavailable:
        "The editable video session could not be stored."
      case .manifestTooLarge:
        "The editable video session exceeded the maximum allowed manifest size."
      case .sessionQuarantined:
        "An existing video session could not be read and was quarantined to preserve its original recording."
      }
    }
  }

  private enum ManifestReadResult {
    case valid(PersistedVideoEditorSession)
    case missing
    case unreadable
  }

  nonisolated static let maxManifestBytes: Int = 33_554_432
  private nonisolated static let quarantineFolderName = "Quarantined"

  private nonisolated let rootDirectory: URL

  init(
    rootDirectory: URL = VideoEditorSessionStore.defaultRootDirectory()
  ) {
    self.rootDirectory = rootDirectory
  }

  // MARK: - Load

  /// Load a session only when the current media still matches the commit that
  /// created it. A nil result intentionally means “open this file as legacy media”.
  func load(for sourceURL: URL) -> VideoEditorSessionData? {
    let normalizedPath = Self.normalizedPath(for: sourceURL)
    let pathHash = Self.pathHash(for: normalizedPath)
    let directory = sessionDirectory(pathHash: pathHash)
    let manifestURL = directory.appendingPathComponent("manifest.json")

    let manifest: PersistedVideoEditorSession
    switch Self.inspectManifest(at: manifestURL) {
    case .valid(let decoded):
      manifest = decoded
    case .missing:
      if Self.directoryContainsSourceSnapshot(directory) {
        quarantineDirectory(directory, pathHash: pathHash)
      }
      return nil
    case .unreadable:
      quarantineDirectory(directory, pathHash: pathHash)
      return nil
    }

    guard manifest.schemaVersion == PersistedVideoEditorSession.currentSchemaVersion,
          manifest.sourceFilePath == normalizedPath,
          manifest.sourceFilePathHash == pathHash,
          let currentSignature = fileSignature(for: sourceURL),
          currentSignature == manifest.sourceSignature
    else {
      return nil
    }

    let sourceSnapshotURL = directory.appendingPathComponent(
      manifest.sourceSnapshotFileName,
      isDirectory: false
    )
    guard FileManager.default.fileExists(atPath: sourceSnapshotURL.path) else {
      return nil
    }

    return manifest.sessionData(sourceSnapshotURL: sourceSnapshotURL)
  }

  nonisolated func quarantinedDirectory(for sourceURL: URL) -> URL? {
    let pathHash = Self.pathHash(for: Self.normalizedPath(for: sourceURL))
    let candidate = quarantineRootDirectory.appendingPathComponent(pathHash, isDirectory: true)
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
  }

  nonisolated func hasQuarantinedSession(for sourceURL: URL) -> Bool {
    quarantinedDirectory(for: sourceURL) != nil
  }

  // MARK: - Source Snapshot

  /// Copy the current unrendered editor source into a pending package before the
  /// destination is replaced. The copy is deliberately off the main actor because
  /// recordings can be hundreds of megabytes.
  nonisolated func prepareSourceSnapshot(
    from sourceURL: URL,
    for targetURL: URL
  ) async throws -> PreparedSourceSnapshot {
    let sourceAccess = await MainActor.run {
      SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    }
    defer { sourceAccess.stop() }

    let scopedSourceURL = sourceAccess.url
    guard FileManager.default.fileExists(atPath: scopedSourceURL.path) else {
      throw StoreError.sourceUnavailable(sourceURL)
    }

    let normalizedTargetPath = Self.normalizedPath(for: targetURL)
    let pathHash = Self.pathHash(for: normalizedTargetPath)
    if quarantineIfUnreadableOrAlreadyQuarantined(pathHash: pathHash) {
      throw StoreError.sessionQuarantined
    }
    let pendingDirectory = rootDirectory.appendingPathComponent(
      ".\(pathHash).\(UUID().uuidString)",
      isDirectory: true
    )
    let sourceFileName = Self.sourceSnapshotFileName(for: scopedSourceURL)
    let pendingSourceURL = pendingDirectory.appendingPathComponent(sourceFileName)

    do {
      try FileManager.default.createDirectory(
        at: pendingDirectory,
        withIntermediateDirectories: true
      )
      try FileManager.default.copyItem(at: scopedSourceURL, to: pendingSourceURL)
      return PreparedSourceSnapshot(
        directoryURL: pendingDirectory,
        sourceURL: pendingSourceURL
      )
    } catch {
      try? FileManager.default.removeItem(at: pendingDirectory)
      throw error
    }
  }

  nonisolated func discardPreparedSourceSnapshot(_ prepared: PreparedSourceSnapshot) {
    guard prepared.directoryURL.deletingLastPathComponent().standardizedFileURL
      == rootDirectory.standardizedFileURL,
      prepared.directoryURL.lastPathComponent.hasPrefix(".")
    else {
      return
    }
    try? FileManager.default.removeItem(at: prepared.directoryURL)
  }

  /// Resolve the stable source URL for a committed session package. Callers may
  /// use this when a save started with a pending source snapshot: the pending
  /// directory is moved into this package after the manifest is written.
  nonisolated func committedSourceSnapshotURL(
    for sourceURL: URL,
    fileName: String
  ) -> URL {
    let pathHash = Self.pathHash(for: Self.normalizedPath(for: sourceURL))
    return sessionDirectory(pathHash: pathHash).appendingPathComponent(fileName)
  }

  // MARK: - Persist

  @discardableResult
  func persist(
    _ sessionData: VideoEditorSessionData,
    for sourceURL: URL,
    preparedSourceDirectory: URL? = nil
  ) -> Bool {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    defer { scopedAccess.stop() }
    guard let signature = Self.readFileSignature(for: scopedAccess.url) else { return false }

    let manifest = makeManifest(
      sessionData,
      for: sourceURL,
      signature: signature
    )
    return persistWrite(
      manifest: manifest,
      sessionData: sessionData,
      for: sourceURL,
      preparedSourceDirectory: preparedSourceDirectory
    )
  }

  /// Off-main variant used after export. With a prepared source package this only
  /// writes a small JSON manifest; the fallback path copies the source snapshot.
  nonisolated func persistOffMain(
    _ sessionData: VideoEditorSessionData,
    for sourceURL: URL,
    preparedSourceDirectory: URL? = nil
  ) async -> Bool {
    let scopedAccess = await MainActor.run {
      SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    }
    defer { scopedAccess.stop() }
    guard let signature = Self.readFileSignature(for: scopedAccess.url) else { return false }

    let manifest = makeManifest(
      sessionData,
      for: sourceURL,
      signature: signature
    )
    return persistWrite(
      manifest: manifest,
      sessionData: sessionData,
      for: sourceURL,
      preparedSourceDirectory: preparedSourceDirectory
    )
  }

  // MARK: - Ownership Changes

  @discardableResult
  func moveSession(from oldURL: URL, to newURL: URL) -> Bool {
    let oldPath = Self.normalizedPath(for: oldURL)
    let oldHash = Self.pathHash(for: oldPath)
    let oldDirectory = sessionDirectory(pathHash: oldHash)
    guard FileManager.default.fileExists(atPath: oldDirectory.path) else { return false }

    let newPath = Self.normalizedPath(for: newURL)
    let newHash = Self.pathHash(for: newPath)
    let newDirectory = sessionDirectory(pathHash: newHash)
    if oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL,
       quarantineIfUnreadableOrAlreadyQuarantined(pathHash: newHash) {
      return false
    }
    guard let signature = fileSignature(for: newURL),
          var manifest = Self.readManifest(
            at: oldDirectory.appendingPathComponent("manifest.json")
          )
    else {
      if case .unreadable = Self.inspectManifest(at: oldDirectory.appendingPathComponent("manifest.json")) {
        quarantineDirectory(oldDirectory, pathHash: oldHash)
      }
      return false
    }

    manifest.sourceFilePath = newPath
    manifest.sourceFilePathHash = newHash
    manifest.sourceSignature = signature
    manifest.updatedAt = Date()

    do {
      try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
      if oldDirectory.standardizedFileURL == newDirectory.standardizedFileURL {
        try Self.writeManifest(
          manifest,
          to: oldDirectory.appendingPathComponent("manifest.json")
        )
      } else {
        if FileManager.default.fileExists(atPath: newDirectory.path) {
          try FileManager.default.removeItem(at: newDirectory)
        }
        try FileManager.default.moveItem(at: oldDirectory, to: newDirectory)
        try Self.writeManifest(
          manifest,
          to: newDirectory.appendingPathComponent("manifest.json")
        )
      }
      return true
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Video Editor session move failed")
      return false
    }
  }

  func deleteSession(for sourceURL: URL) {
    let pathHash = Self.pathHash(for: Self.normalizedPath(for: sourceURL))
    let directory = sessionDirectory(pathHash: pathHash)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Video Editor session delete failed")
    }
  }

  func cleanup(keepingMediaFilePaths paths: Set<String>) {
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: [.isDirectoryKey]
    ) else {
      return
    }

    let activePaths = Set(paths.map(Self.normalizedPath(forPath:)))
    for directory in contents {
      let name = directory.lastPathComponent
      if name == Self.quarantineFolderName || name.hasPrefix(".") {
        continue
      }
      let manifestURL = directory.appendingPathComponent("manifest.json")
      let manifest: PersistedVideoEditorSession
      switch Self.inspectManifest(at: manifestURL) {
      case .valid(let decoded):
        manifest = decoded
      case .unreadable:
        quarantineDirectory(directory, pathHash: name)
        continue
      case .missing:
        if Self.directoryContainsSourceSnapshot(directory) {
          quarantineDirectory(directory, pathHash: name)
        } else {
          try? FileManager.default.removeItem(at: directory)
        }
        continue
      }

      let sourceURL = URL(fileURLWithPath: manifest.sourceFilePath)
      let sourceSnapshotURL = directory.appendingPathComponent(manifest.sourceSnapshotFileName)
      let shouldKeep = activePaths.contains(manifest.sourceFilePath)
        && FileManager.default.fileExists(atPath: sourceURL.path)
        && fileSignature(for: sourceURL) == manifest.sourceSignature
        && FileManager.default.fileExists(atPath: sourceSnapshotURL.path)
      if !shouldKeep {
        try? FileManager.default.removeItem(at: directory)
      }
    }
  }

  func deleteAllSessions() {
    guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return }
    do {
      try FileManager.default.removeItem(at: rootDirectory)
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Video Editor session clear failed")
    }
  }

  // MARK: - Paths and Signatures

  nonisolated static func normalizedPath(for sourceURL: URL) -> String {
    normalizedPath(forPath: sourceURL.standardizedFileURL.path)
  }

  nonisolated static func normalizedPath(forPath path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }

  nonisolated static func pathHash(for normalizedPath: String) -> String {
    let digest = SHA256.hash(data: Data(normalizedPath.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Private Persistence

  private nonisolated var quarantineRootDirectory: URL {
    rootDirectory.appendingPathComponent(Self.quarantineFolderName, isDirectory: true)
  }

  private nonisolated func sessionDirectory(pathHash: String) -> URL {
    rootDirectory.appendingPathComponent(pathHash, isDirectory: true)
  }

  private nonisolated static func directoryContainsSourceSnapshot(_ directory: URL) -> Bool {
    guard let items = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ) else {
      return false
    }
    return items.contains { url in
      let name = url.lastPathComponent
      return name == "source" || name.hasPrefix("source.")
    }
  }

  private nonisolated func quarantineDirectory(_ directory: URL, pathHash: String) {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    do {
      try FileManager.default.createDirectory(
        at: quarantineRootDirectory,
        withIntermediateDirectories: true
      )
      let primaryTarget = quarantineRootDirectory.appendingPathComponent(pathHash, isDirectory: true)
      let destination: URL = if FileManager.default.fileExists(atPath: primaryTarget.path) {
        quarantineRootDirectory.appendingPathComponent(
          "\(pathHash)-\(UUID().uuidString)",
          isDirectory: true
        )
      } else {
        primaryTarget
      }
      try FileManager.default.moveItem(at: directory, to: destination)
      DiagnosticLogger.shared.log(
        .warning,
        .editor,
        "Video Editor session quarantined because manifest was unreadable or oversized",
        context: ["directory": pathHash, "quarantine": destination.lastPathComponent]
      )
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Failed to quarantine unreadable Video Editor session")
    }
  }

  /// Returns `true` when `pathHash` already has a quarantined session or its live directory
  /// contains an unreadable/oversized manifest (quarantining it immediately instead of overwriting).
  private nonisolated func quarantineIfUnreadableOrAlreadyQuarantined(pathHash: String) -> Bool {
    let quarantined = quarantineRootDirectory.appendingPathComponent(pathHash, isDirectory: true)
    if FileManager.default.fileExists(atPath: quarantined.path) {
      return true
    }
    let directory = sessionDirectory(pathHash: pathHash)
    guard FileManager.default.fileExists(atPath: directory.path) else { return false }
    let manifestURL = directory.appendingPathComponent("manifest.json")
    switch Self.inspectManifest(at: manifestURL) {
    case .valid:
      return false
    case .unreadable:
      quarantineDirectory(directory, pathHash: pathHash)
      return true
    case .missing:
      if Self.directoryContainsSourceSnapshot(directory) {
        quarantineDirectory(directory, pathHash: pathHash)
        return true
      }
      return false
    }
  }

  private nonisolated func makeManifest(
    _ sessionData: VideoEditorSessionData,
    for sourceURL: URL,
    signature: PersistedFileSignature
  ) -> PersistedVideoEditorSession {
    let normalizedPath = Self.normalizedPath(for: sourceURL)
    let pathHash = Self.pathHash(for: normalizedPath)
    let directory = sessionDirectory(pathHash: pathHash)
    let previousCreatedAt = Self.readManifest(
      at: directory.appendingPathComponent("manifest.json")
    )?.createdAt ?? Date()

    return PersistedVideoEditorSession(
      sessionData: sessionData,
      sourceFilePath: normalizedPath,
      sourceFilePathHash: pathHash,
      sourceSignature: signature,
      sourceSnapshotFileName: Self.sourceSnapshotFileName(for: sessionData.sourceSnapshotURL),
      createdAt: previousCreatedAt
    )
  }

  private nonisolated func persistWrite(
    manifest: PersistedVideoEditorSession,
    sessionData: VideoEditorSessionData,
    for sourceURL: URL,
    preparedSourceDirectory: URL?
  ) -> Bool {
    let directory = sessionDirectory(pathHash: manifest.sourceFilePathHash)

    do {
      try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
      if quarantineIfUnreadableOrAlreadyQuarantined(pathHash: manifest.sourceFilePathHash) {
        throw StoreError.sessionQuarantined
      }

      if let preparedSourceDirectory {
        guard preparedSourceDirectory.deletingLastPathComponent().standardizedFileURL
          == rootDirectory.standardizedFileURL,
          FileManager.default.fileExists(
            atPath: preparedSourceDirectory.appendingPathComponent(
              manifest.sourceSnapshotFileName
            ).path
          )
        else {
          throw StoreError.packageUnavailable
        }

        try Self.writeManifest(
          manifest,
          to: preparedSourceDirectory.appendingPathComponent("manifest.json")
        )
        if FileManager.default.fileExists(atPath: directory.path) {
          try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.moveItem(at: preparedSourceDirectory, to: directory)
      } else if Self.isSnapshotInside(
        sessionData.sourceSnapshotURL,
        directory: directory
      ), FileManager.default.fileExists(atPath: sessionData.sourceSnapshotURL.path) {
        // Reopening and saving an existing session only needs an atomic manifest
        // update; the master source must remain byte-for-byte unchanged.
        try Self.writeManifest(
          manifest,
          to: directory.appendingPathComponent("manifest.json")
        )
      } else {
        let temporaryDirectory = rootDirectory.appendingPathComponent(
          ".\(directory.lastPathComponent).\(UUID().uuidString)",
          isDirectory: true
        )
        let sourceFileURL = temporaryDirectory.appendingPathComponent(
          manifest.sourceSnapshotFileName
        )
        try FileManager.default.createDirectory(
          at: temporaryDirectory,
          withIntermediateDirectories: true
        )
        do {
          try FileManager.default.copyItem(
            at: sessionData.sourceSnapshotURL,
            to: sourceFileURL
          )
          try Self.writeManifest(
            manifest,
            to: temporaryDirectory.appendingPathComponent("manifest.json")
          )
          if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
          }
          try FileManager.default.moveItem(at: temporaryDirectory, to: directory)
        } catch {
          try? FileManager.default.removeItem(at: temporaryDirectory)
          throw error
        }
      }

      DiagnosticLogger.shared.log(
        .debug,
        .editor,
        "Video Editor session persisted",
        context: [
          "fileName": sourceURL.lastPathComponent,
          "clips": "\(sessionData.clips.count)",
          "zooms": "\(sessionData.zoomSegments.count)",
          "speeds": "\(sessionData.speedSegments.count)",
        ]
      )
      return true
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Video Editor session persist failed")
      return false
    }
  }

  private nonisolated static func isSnapshotInside(_ sourceURL: URL, directory: URL) -> Bool {
    sourceURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
  }

  private nonisolated static func sourceSnapshotFileName(for sourceURL: URL) -> String {
    let fileExtension = sourceURL.pathExtension
    return fileExtension.isEmpty ? "source" : "source.\(fileExtension)"
  }

  private nonisolated static func defaultRootDirectory() -> URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("VideoEditorSessions", isDirectory: true)
  }

  private func fileSignature(for sourceURL: URL) -> PersistedFileSignature? {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    defer { scopedAccess.stop() }
    return Self.readFileSignature(for: scopedAccess.url)
  }

  private nonisolated static func readFileSignature(for sourceURL: URL) -> PersistedFileSignature? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path) else {
      return nil
    }
    let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return PersistedFileSignature(
      fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
      modifiedAtMilliseconds: Int64((modifiedAt * 1000).rounded()),
      pathExtension: sourceURL.pathExtension.lowercased()
    )
  }

  private nonisolated static func writeManifest(
    _ manifest: PersistedVideoEditorSession,
    to url: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(manifest)
    guard data.count <= maxManifestBytes else {
      throw StoreError.manifestTooLarge(data.count)
    }
    try data.write(to: url, options: .atomic)
  }

  private nonisolated static func readManifest(
    at url: URL
  ) -> PersistedVideoEditorSession? {
    if case .valid(let manifest) = inspectManifest(at: url) {
      return manifest
    }
    return nil
  }

  private nonisolated static func inspectManifest(
    at url: URL
  ) -> ManifestReadResult {
    guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else {
      return .missing
    }
    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
          values.isRegularFile == true,
          let fileSize = values.fileSize,
          fileSize > 0,
          fileSize <= maxManifestBytes,
          let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
          data.count <= maxManifestBytes
    else { return .unreadable }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let decoded = try? decoder.decode(PersistedVideoEditorSession.self, from: data) else {
      return .unreadable
    }
    return .valid(decoded)
  }
}
