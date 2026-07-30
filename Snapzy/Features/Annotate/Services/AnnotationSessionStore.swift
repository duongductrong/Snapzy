//
//  AnnotationSessionStore.swift
//  Snapzy
//
//  Sidecar persistence for committed editable annotation sessions.
//

import CryptoKit
import Foundation

@MainActor
final class AnnotationSessionStore {
  static let shared = AnnotationSessionStore()

  private let fileManager: FileManager
  private nonisolated let rootDirectory: URL

  init(
    rootDirectory: URL = AnnotationSessionStore.defaultRootDirectory(),
    fileManager: FileManager = .default
  ) {
    self.rootDirectory = rootDirectory
    self.fileManager = fileManager
  }

  func load(for sourceURL: URL) -> AnnotationSessionData? {
    let normalizedPath = Self.normalizedPath(for: sourceURL)
    let pathHash = Self.pathHash(for: normalizedPath)
    let directory = sessionDirectory(pathHash: pathHash)
    let manifestURL = directory.appendingPathComponent("manifest.json")

    guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
    guard let manifest = readManifest(at: manifestURL),
          manifest.schemaVersion == PersistedAnnotationSession.currentSchemaVersion,
          manifest.sourceFilePathHash == pathHash,
          manifest.sourceFilePath == normalizedPath,
          let currentSignature = fileSignature(for: sourceURL),
          currentSignature == manifest.sourceSignature else {
      return nil
    }

    do {
      let originalData = try Data(contentsOf: directory.appendingPathComponent(manifest.originalFileName))
      let cutoutData = try manifest.cutoutFileName.map {
        try Data(contentsOf: directory.appendingPathComponent($0))
      }
      let assetsDirectory = directory.appendingPathComponent("assets", isDirectory: true)
      var embeddedAssets: [UUID: Data] = [:]
      for (assetIdString, fileName) in manifest.embeddedAssetFileNames {
        guard let assetId = UUID(uuidString: assetIdString) else { continue }
        let data = try Data(contentsOf: assetsDirectory.appendingPathComponent(fileName))
        embeddedAssets[assetId] = data
      }
      return manifest.sessionData(
        originalImageData: originalData,
        cutoutImageData: cutoutData,
        embeddedImageAssetsData: embeddedAssets
      )
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar load failed")
      return nil
    }
  }

  @discardableResult
  func persist(_ sessionData: AnnotationSessionData, for sourceURL: URL) -> Bool {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    defer { scopedAccess.stop() }
    guard let signature = readFileSignature(for: sourceURL) else { return false }
    let manifest = buildManifest(sessionData, for: sourceURL, signature: signature)
    return persistWrite(manifest: manifest, sessionData: sessionData, for: sourceURL)
  }

  /// Off-main persist for the save-and-close background path: the multi-MB package
  /// write runs on the calling queue instead of the main thread.
  nonisolated func persistOffMain(_ sessionData: AnnotationSessionData, for sourceURL: URL) async -> Bool {
    let scopedAccess = await MainActor.run { SandboxFileAccessManager.shared.beginAccessingURL(sourceURL) }
    defer { scopedAccess.stop() }
    guard let signature = readFileSignature(for: sourceURL) else { return false }
    let manifest = await buildManifest(sessionData, for: sourceURL, signature: signature)
    return persistWrite(manifest: manifest, sessionData: sessionData, for: sourceURL)
  }

  /// Manifest construction is cheap and kept on main (the conversion init is @MainActor).
  @MainActor
  private func buildManifest(
    _ sessionData: AnnotationSessionData,
    for sourceURL: URL,
    signature: PersistedFileSignature
  ) -> PersistedAnnotationSession {
    let normalizedPath = Self.normalizedPath(for: sourceURL)
    let pathHash = Self.pathHash(for: normalizedPath)
    let directory = sessionDirectory(pathHash: pathHash)
    let previousCreatedAt = readManifest(
      at: directory.appendingPathComponent("manifest.json")
    )?.createdAt ?? Date()
    return PersistedAnnotationSession(
      sessionData: sessionData,
      sourceFilePath: normalizedPath,
      sourceFilePathHash: pathHash,
      sourceSignature: signature,
      createdAt: previousCreatedAt
    )
  }

  /// The heavy multi-MB package write. Runs on the caller's queue (main for the
  /// interactive path, a background queue for the save-and-close path).
  private nonisolated func persistWrite(
    manifest: PersistedAnnotationSession,
    sessionData: AnnotationSessionData,
    for sourceURL: URL
  ) -> Bool {
    let pathHash = Self.pathHash(for: Self.normalizedPath(for: sourceURL))
    let directory = sessionDirectory(pathHash: pathHash)
    do {
      try writePackage(
        manifest: manifest,
        sessionData: sessionData,
        to: directory
      )
      DiagnosticLogger.shared.log(
        .debug,
        .annotate,
        "Annotation sidecar persisted",
        context: ["fileName": sourceURL.lastPathComponent, "annotations": "\(sessionData.annotations.count)"]
      )
      return true
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar persist failed")
      return false
    }
  }

  @discardableResult
  func moveSession(from oldURL: URL, to newURL: URL) -> Bool {
    let oldPath = Self.normalizedPath(for: oldURL)
    let oldHash = Self.pathHash(for: oldPath)
    let oldDirectory = sessionDirectory(pathHash: oldHash)
    guard fileManager.fileExists(atPath: oldDirectory.path) else { return false }

    let newPath = Self.normalizedPath(for: newURL)
    let newHash = Self.pathHash(for: newPath)
    let newDirectory = sessionDirectory(pathHash: newHash)
    guard oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL else { return true }
    guard let signature = fileSignature(for: newURL),
          var manifest = readManifest(at: oldDirectory.appendingPathComponent("manifest.json")) else {
      return false
    }

    manifest.sourceFilePath = newPath
    manifest.sourceFilePathHash = newHash
    manifest.sourceSignature = signature
    manifest.updatedAt = Date()

    do {
      try ensureRootDirectory()
      if fileManager.fileExists(atPath: newDirectory.path) {
        try fileManager.removeItem(at: newDirectory)
      }
      try fileManager.moveItem(at: oldDirectory, to: newDirectory)
      try writeManifest(manifest, to: newDirectory.appendingPathComponent("manifest.json"))
      return true
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar move failed")
      return false
    }
  }

  func deleteSession(for sourceURL: URL) {
    let pathHash = Self.pathHash(for: Self.normalizedPath(for: sourceURL))
    let directory = sessionDirectory(pathHash: pathHash)
    guard fileManager.fileExists(atPath: directory.path) else { return }
    do {
      try fileManager.removeItem(at: directory)
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar delete failed")
    }
  }

  func cleanup(keepingScreenshotFilePaths paths: Set<String>) {
    guard let contents = try? fileManager.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return }

    let activePaths = Set(paths.map(Self.normalizedPath(forPath:)))
    for directory in contents {
      let manifestURL = directory.appendingPathComponent("manifest.json")
      guard let manifest = readManifest(at: manifestURL) else {
        try? fileManager.removeItem(at: directory)
        continue
      }

      let sourceURL = URL(fileURLWithPath: manifest.sourceFilePath)
      let shouldKeep = activePaths.contains(manifest.sourceFilePath)
        && fileManager.fileExists(atPath: manifest.sourceFilePath)
        && fileSignature(for: sourceURL) == manifest.sourceSignature
      if !shouldKeep {
        try? fileManager.removeItem(at: directory)
      }
    }
  }

  func deleteAllSessions() {
    guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
    do {
      try fileManager.removeItem(at: rootDirectory)
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar clear failed")
    }
  }

  func shouldPersist(for sourceURL: URL) -> Bool {
    let historyEnabled = CaptureHistoryStore.shared.userDefaults.snapzyHistoryEnabled
    return historyEnabled || CaptureHistoryStore.shared.hasRecord(forFilePath: sourceURL.path)
  }

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

  private nonisolated static func defaultRootDirectory() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("AnnotationSessions", isDirectory: true)
  }

  private nonisolated func sessionDirectory(pathHash: String) -> URL {
    rootDirectory.appendingPathComponent(pathHash, isDirectory: true)
  }

  private nonisolated func ensureRootDirectory() throws {
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
  }

  private func fileSignature(for sourceURL: URL) -> PersistedFileSignature? {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    defer { scopedAccess.stop() }
    return readFileSignature(for: sourceURL)
  }

  private nonisolated func readFileSignature(for sourceURL: URL) -> PersistedFileSignature? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path) else {
      return nil
    }
    let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let modifiedAtMs = Int64((modifiedAt * 1000).rounded())
    let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    return PersistedFileSignature(
      fileSize: fileSize,
      modifiedAtMilliseconds: modifiedAtMs,
      pathExtension: sourceURL.pathExtension.lowercased()
    )
  }

  private nonisolated func readManifest(at url: URL) -> PersistedAnnotationSession? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(PersistedAnnotationSession.self, from: data)
  }

  private nonisolated func writePackage(
    manifest: PersistedAnnotationSession,
    sessionData: AnnotationSessionData,
    to directory: URL
  ) throws {
    try ensureRootDirectory()
    let tempDirectory = rootDirectory.appendingPathComponent(
      ".\(directory.lastPathComponent).\(UUID().uuidString)",
      isDirectory: true
    )
    let assetsDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    do {
      try sessionData.originalImageData.write(
        to: tempDirectory.appendingPathComponent(manifest.originalFileName),
        options: .atomic
      )
      if let cutoutFileName = manifest.cutoutFileName, let cutoutImageData = sessionData.cutoutImageData {
        try cutoutImageData.write(to: tempDirectory.appendingPathComponent(cutoutFileName), options: .atomic)
      }
      for (assetIdString, fileName) in manifest.embeddedAssetFileNames {
        guard let assetId = UUID(uuidString: assetIdString),
              let data = sessionData.embeddedImageAssetsData[assetId] else { continue }
        try data.write(to: assetsDirectory.appendingPathComponent(fileName), options: .atomic)
      }
      try writeManifest(manifest, to: tempDirectory.appendingPathComponent("manifest.json"))
      if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
      }
      try FileManager.default.moveItem(at: tempDirectory, to: directory)
    } catch {
      try? FileManager.default.removeItem(at: tempDirectory)
      throw error
    }
  }

  private nonisolated func writeManifest(_ manifest: PersistedAnnotationSession, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(manifest).write(to: url, options: .atomic)
  }
}
