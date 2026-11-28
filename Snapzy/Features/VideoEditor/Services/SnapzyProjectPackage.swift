//
//  SnapzyProjectPackage.swift
//  Snapzy
//
//  Self-contained, atomic `.snapzy` macOS document package engine for Video Editor
//  projects. Bundles unrendered primary media, secondary timeline video clips,
//  imported/detached multi-track audio clips, recording metadata + Studio sidecars,
//  and custom background wallpapers inside a single portable `<Name>.snapzy`
//  package directory while storing font references only (never redistributing or
//  auto-installing user-imported commercial font binaries).
//

import AppKit
import CoreMedia
import CryptoKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Package Errors

nonisolated enum SnapzyProjectPackageError: LocalizedError, Equatable {
  case invalidPackageURL(URL)
  case manifestMissing(URL)
  case manifestTooLarge(Int)
  case manifestCorrupted(String)
  case unsupportedSchemaVersion(Int)
  case invalidPackageLayout(String)
  case primaryMediaMissing(URL)
  case secondaryMediaMissing(URL)
  case audioMediaMissing(URL)
  case restoreFailedSaveBlocked
  case atomicReplaceFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidPackageURL(let url):
      "Invalid .snapzy project path: \(url.lastPathComponent)"
    case .manifestMissing(let url):
      "Missing manifest.json inside project package: \(url.lastPathComponent)"
    case .manifestTooLarge(let maxBytes):
      "Project metadata exceeds maximum allowed size (\(maxBytes / (1024 * 1024)) MB)."
    case .manifestCorrupted(let detail):
      "Corrupted .snapzy project manifest: \(detail)"
    case .unsupportedSchemaVersion(let version):
      "This .snapzy project requires a newer version of Snapzy (schema v\(version))."
    case .invalidPackageLayout(let detail):
      "Invalid .snapzy package structure: \(detail)"
    case .primaryMediaMissing(let url):
      "Primary video source could not be found: \(url.lastPathComponent)"
    case .secondaryMediaMissing(let url):
      "Inserted video clip could not be found: \(url.lastPathComponent)"
    case .audioMediaMissing(let url):
      "Audio clip source could not be found: \(url.lastPathComponent)"
    case .restoreFailedSaveBlocked:
      "Project timeline could not be restored cleanly; overwriting the original .snapzy file is blocked to prevent data loss. Use Save Project As instead."
    case .atomicReplaceFailed(let detail):
      "Could not atomically write .snapzy package: \(detail)"
    }
  }
}

// MARK: - Versioned Manifest

nonisolated struct SnapzyProjectManifest: Codable, Equatable {
  static let currentSchemaVersion = 1
  static let maxPlayheadSeconds: Double = 864_000

  var schemaVersion: Int
  var createdAt: Date
  var updatedAt: Date
  var appVersion: String
  var primaryMediaRelativePath: String
  var recordingMetadataRelativePath: String?
  var secondaryClipRelativePaths: [UUID: String]
  var audioClipRelativePaths: [UUID: String]
  /// Human-readable display names for referenced custom/installed font IDs (font binaries are never embedded).
  var referencedFontDisplayNames: [String: String]?
  var backgroundImageRelativePath: String?
  var cameraSidecarRelativePath: String?
  var cursorImagesRelativePath: String?
  var playheadSeconds: Double
  var editState: PersistedVideoEditorEditState

  init(
    schemaVersion: Int = SnapzyProjectManifest.currentSchemaVersion,
    createdAt: Date,
    updatedAt: Date,
    appVersion: String,
    primaryMediaRelativePath: String,
    recordingMetadataRelativePath: String? = nil,
    secondaryClipRelativePaths: [UUID: String] = [:],
    audioClipRelativePaths: [UUID: String] = [:],
    referencedFontDisplayNames: [String: String]? = nil,
    backgroundImageRelativePath: String? = nil,
    cameraSidecarRelativePath: String? = nil,
    cursorImagesRelativePath: String? = nil,
    playheadSeconds: Double = 0,
    editState: PersistedVideoEditorEditState
  ) {
    self.schemaVersion = schemaVersion
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.appVersion = String(appVersion.prefix(64))
    self.primaryMediaRelativePath = primaryMediaRelativePath
    self.recordingMetadataRelativePath = recordingMetadataRelativePath
    self.secondaryClipRelativePaths = secondaryClipRelativePaths
    self.audioClipRelativePaths = audioClipRelativePaths
    self.referencedFontDisplayNames = referencedFontDisplayNames
    self.backgroundImageRelativePath = backgroundImageRelativePath
    self.cameraSidecarRelativePath = cameraSidecarRelativePath
    self.cursorImagesRelativePath = cursorImagesRelativePath
    self.playheadSeconds = playheadSeconds.isFinite
      ? min(max(0, playheadSeconds), Self.maxPlayheadSeconds)
      : 0
    self.editState = editState
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case createdAt
    case updatedAt
    case appVersion
    case primaryMediaRelativePath
    case recordingMetadataRelativePath
    case secondaryClipRelativePaths
    case audioClipRelativePaths
    case referencedFontDisplayNames
    case embeddedFontDisplayNames
    case backgroundImageRelativePath
    case cameraSidecarRelativePath
    case cursorImagesRelativePath
    case playheadSeconds
    case editState
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    let rawVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? "1.0"
    appVersion = String(rawVersion.prefix(64))
    primaryMediaRelativePath = try c.decode(String.self, forKey: .primaryMediaRelativePath)
    recordingMetadataRelativePath = try c.decodeIfPresent(String.self, forKey: .recordingMetadataRelativePath)
    secondaryClipRelativePaths = try Self.decodeUUIDPathMap(from: c, forKey: .secondaryClipRelativePaths)
    audioClipRelativePaths = try Self.decodeUUIDPathMap(from: c, forKey: .audioClipRelativePaths)
    referencedFontDisplayNames = try c.decodeIfPresent([String: String].self, forKey: .referencedFontDisplayNames)
      ?? (c.decodeIfPresent([String: String].self, forKey: .embeddedFontDisplayNames))
    backgroundImageRelativePath = try c.decodeIfPresent(String.self, forKey: .backgroundImageRelativePath)
    cameraSidecarRelativePath = try c.decodeIfPresent(String.self, forKey: .cameraSidecarRelativePath)
    cursorImagesRelativePath = try c.decodeIfPresent(String.self, forKey: .cursorImagesRelativePath)
    let rawPlayhead = try c.decodeIfPresent(Double.self, forKey: .playheadSeconds) ?? 0
    playheadSeconds = rawPlayhead.isFinite
      ? min(max(0, rawPlayhead), Self.maxPlayheadSeconds)
      : 0
    editState = try c.decode(PersistedVideoEditorEditState.self, forKey: .editState)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(schemaVersion, forKey: .schemaVersion)
    try c.encode(createdAt, forKey: .createdAt)
    try c.encode(updatedAt, forKey: .updatedAt)
    try c.encode(appVersion, forKey: .appVersion)
    try c.encode(primaryMediaRelativePath, forKey: .primaryMediaRelativePath)
    try c.encodeIfPresent(recordingMetadataRelativePath, forKey: .recordingMetadataRelativePath)
    try c.encode(Self.encodeUUIDPathMap(secondaryClipRelativePaths), forKey: .secondaryClipRelativePaths)
    try c.encode(Self.encodeUUIDPathMap(audioClipRelativePaths), forKey: .audioClipRelativePaths)
    try c.encodeIfPresent(referencedFontDisplayNames, forKey: .referencedFontDisplayNames)
    try c.encodeIfPresent(backgroundImageRelativePath, forKey: .backgroundImageRelativePath)
    try c.encodeIfPresent(cameraSidecarRelativePath, forKey: .cameraSidecarRelativePath)
    try c.encodeIfPresent(cursorImagesRelativePath, forKey: .cursorImagesRelativePath)
    let clampedPlayhead = playheadSeconds.isFinite
      ? min(max(0, playheadSeconds), Self.maxPlayheadSeconds)
      : 0
    try c.encode(clampedPlayhead, forKey: .playheadSeconds)
    try c.encode(editState, forKey: .editState)
  }

  private static func encodeUUIDPathMap(_ map: [UUID: String]) -> [String: String] {
    Dictionary(map.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { first, _ in first })
  }

  private static func decodeUUIDPathMap(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> [UUID: String] {
    if let stringDict = try? container.decodeIfPresent([String: String].self, forKey: key) {
      guard stringDict.count <= 2_000 else {
        throw DecodingError.dataCorruptedError(
          forKey: key,
          in: container,
          debugDescription: "Manifest path map exceeds maximum item count"
        )
      }
      var resolved: [UUID: String] = [:]
      resolved.reserveCapacity(stringDict.count)
      for (rawUUID, path) in stringDict {
        guard let id = UUID(uuidString: rawUUID) else {
          throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Invalid UUID key in manifest map: \(rawUUID)"
          )
        }
        resolved[id] = path
      }
      return resolved
    }
    return try container.decodeIfPresent([UUID: String].self, forKey: key) ?? [:]
  }
}

// MARK: - Package Engine

nonisolated enum SnapzyProjectPackage {
  static let fileExtension = "snapzy"
  static let utTypeIdentifier = "com.trongduong.snapzy.project"
  static let manifestFileName = "manifest.json"
  static let mediaDirectoryName = "Media"
  static let recordingMetadataFileName = "recording-metadata.json"
  static let maxManifestBytes = 8_388_608 // 8 MB
  static let maxMetadataBytes = 8_388_608 // 8 MB

  @MainActor
  private static var registeredFontDisplayNamesStorage: [String: String] = [:]

  @MainActor
  static func registerReferencedFontNames(_ map: [String: String]) {
    for (rawKey, rawName) in map {
      let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty, !name.isEmpty else { continue }
      registeredFontDisplayNamesStorage[key] = String(name.prefix(128))
    }
  }

  @MainActor
  static func referencedFontDisplayName(for fontId: String) -> String? {
    registeredFontDisplayNamesStorage[fontId.trimmingCharacters(in: .whitespacesAndNewlines)]
  }

  struct LoadedProject: Equatable, Sendable {
    let packageURL: URL
    let manifest: SnapzyProjectManifest
    let sessionData: VideoEditorSessionData
    let playheadSeconds: Double
  }

  private struct SaveInputSnapshot: Sendable {
    let sessionData: VideoEditorSessionData
    let playheadSeconds: Double
    let existingPackageURL: URL?
    let studioCameraSidecarURL: URL?
    let studioCursorImagesSidecarURL: URL?
    let referencedFontNames: [String: String]
    let destinationURL: URL
  }

  static var projectUTType: UTType {
    UTType(utTypeIdentifier)
      ?? UTType(filenameExtension: fileExtension, conformingTo: .package)
      ?? .package
  }

  static func isProjectURL(_ url: URL) -> Bool {
    let resolved = (url as NSURL).filePathURL ?? url
    return resolved.pathExtension.lowercased() == fileExtension
  }

  /// Returns `true` if `url` is a `.snapzy` package or any file/folder nested inside one.
  static func isInsideProjectPackage(_ url: URL) -> Bool {
    enclosingProjectPackageURL(for: url) != nil
  }

  /// Resolves the enclosing `.snapzy` project package URL if `url` is a `.snapzy` package
  /// or points to media nested inside one (e.g. `MyProject.snapzy/Media/primary.mov`).
  static func enclosingProjectPackageURL(for url: URL) -> URL? {
    let resolved = ((url as NSURL).filePathURL ?? url).standardizedFileURL
    if resolved.pathExtension.lowercased() == fileExtension {
      return resolved
    }
    var current = resolved.deletingLastPathComponent()
    while current.path != "/", !current.path.isEmpty {
      if current.pathExtension.lowercased() == fileExtension {
        return current.standardizedFileURL
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        break
      }
      current = parent
    }
    return nil
  }

  static func normalizedPackageURL(_ url: URL) -> URL {
    let resolved = ((url as NSURL).filePathURL ?? url).standardizedFileURL
    if isProjectURL(resolved) {
      return resolved
    }
    return resolved.appendingPathExtension(fileExtension).standardizedFileURL
  }

  static func suggestedProjectFilename(for baseURL: URL) -> String {
    let rawBase = baseURL.deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanBase = rawBase.isEmpty ? "Untitled" : rawBase
    return "\(cleanBase).\(fileExtension)"
  }

  // MARK: - Bounded File Reading & Strict Unique-ID Validation

  static func readBoundedFileData(from url: URL, maxBytes: Int) throws -> Data {
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    } catch {
      throw SnapzyProjectPackageError.manifestCorrupted(error.localizedDescription)
    }
    guard values.isRegularFile == true else {
      throw SnapzyProjectPackageError.manifestCorrupted("Expected regular file at \(url.lastPathComponent)")
    }
    if let size = values.fileSize {
      guard size >= 0 else {
        throw SnapzyProjectPackageError.manifestCorrupted("Negative file size for \(url.lastPathComponent)")
      }
      if size > maxBytes {
        throw SnapzyProjectPackageError.manifestTooLarge(maxBytes)
      }
    }
    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
      throw SnapzyProjectPackageError.manifestCorrupted(error.localizedDescription)
    }
    if data.count > maxBytes {
      throw SnapzyProjectPackageError.manifestTooLarge(maxBytes)
    }
    return data
  }

  /// Strictly rejects duplicate item IDs across every persisted collection in an untrusted `.snapzy` manifest.
  private static func validateUniqueIDsInManifestJSON(_ data: Data) throws {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let editState = root["editState"] as? [String: Any]
    else {
      return
    }
    try assertUniqueStringIDs(in: editState["clips"] as? [[String: Any]], label: "clips")
    try assertUniqueStringIDs(in: editState["zoomSegments"] as? [[String: Any]], label: "zoomSegments")
    try assertUniqueStringIDs(in: editState["speedSegments"] as? [[String: Any]], label: "speedSegments")
    try assertUniqueStringIDs(in: editState["audioClips"] as? [[String: Any]], label: "audioClips")
    try assertUniqueStringIDs(in: editState["textOverlays"] as? [[String: Any]], label: "textOverlays")
    if let captions = editState["captions"] as? [String: Any] {
      try assertUniqueStringIDs(in: captions["segments"] as? [[String: Any]], label: "captions.segments")
    }
    if let cameraSettings = editState["cameraSettings"] as? [String: Any] {
      try assertUniqueStringIDs(
        in: cameraSettings["hiddenRanges"] as? [[String: Any]],
        label: "cameraSettings.hiddenRanges"
      )
    }
  }

  private static func validateUniqueIDsInRecordingMetadataJSON(_ data: Data) throws {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tracks = root["audioSourceTracks"] as? [[String: Any]]
    else {
      return
    }
    var seenTrackIDs = Set<Int>()
    var seenRoles = Set<String>()
    for item in tracks {
      if let tid = item["trackID"] as? Int, !seenTrackIDs.insert(tid).inserted {
        throw SnapzyProjectPackageError.manifestCorrupted(
          "Duplicate trackID '\(tid)' in recordingMetadata.audioSourceTracks"
        )
      }
      if let role = item["role"] as? String, !seenRoles.insert(role.lowercased()).inserted {
        throw SnapzyProjectPackageError.manifestCorrupted(
          "Duplicate role '\(role)' in recordingMetadata.audioSourceTracks"
        )
      }
      if let rawID = item["id"] as? String, !seenRoles.insert("id:\(rawID.lowercased())").inserted {
        throw SnapzyProjectPackageError.manifestCorrupted(
          "Duplicate ID '\(rawID)' in recordingMetadata.audioSourceTracks"
        )
      }
    }
  }

  private static func assertUniqueStringIDs(in items: [[String: Any]]?, label: String) throws {
    guard let items else { return }
    var seen = Set<String>()
    seen.reserveCapacity(items.count)
    for item in items {
      guard let rawID = item["id"] as? String else { continue }
      let normalized = rawID.lowercased()
      if !seen.insert(normalized).inserted {
        throw SnapzyProjectPackageError.manifestCorrupted("Duplicate ID '\(rawID)' in \(label)")
      }
    }
  }

  // MARK: - Snapshot Capture on MainActor + Off-Main Async Save

  @MainActor
  private static func makeSaveSnapshot(
    state: VideoEditorState,
    existingSourceSnapshotURL: URL?,
    existingPackageURL: URL?,
    to destinationURL: URL
  ) throws -> SaveInputSnapshot {
    let normalizedTarget = normalizedPackageURL(destinationURL)
    if state.sessionRestoreFailed,
       let existingPackageURL,
       normalizedPackageURL(existingPackageURL) == normalizedTarget {
      throw SnapzyProjectPackageError.restoreFailedSaveBlocked
    }

    let sourceSnapshotURL = existingSourceSnapshotURL ?? state.editingSourceURL
    var sessionData = VideoEditorSessionData.snapshot(
      from: state,
      sourceSnapshotURL: sourceSnapshotURL
    )
    if !state.isGIF, sessionData.clips.isEmpty {
      let dur = CMTimeGetSeconds(state.duration)
      if dur.isFinite, dur >= TimelineClip.minDuration {
        sessionData.clips = [TimelineClip(source: .primary, sourceDuration: dur)]
      }
    }

    let playhead = CMTimeGetSeconds(state.currentTime)
    var studioCameraURL: URL?
    var studioCursorDirURL: URL?
    if let camName = sessionData.recordingMetadata?.cameraSource?.fileName,
       let camURL = try? RecordingMetadataStore.sidecarURL(named: camName, kind: .camera),
       FileManager.default.fileExists(atPath: camURL.path) {
      studioCameraURL = camURL
    }
    if let cursorFolder = sessionData.recordingMetadata?.cursorCapture?.imagesFolderName,
       let cursorURL = try? RecordingMetadataStore.sidecarURL(named: cursorFolder, kind: .cursorImages),
       FileManager.default.fileExists(atPath: cursorURL.path) {
      studioCursorDirURL = cursorURL
    }

    let fontNames = registeredFontDisplayNamesStorage
    return SaveInputSnapshot(
      sessionData: sessionData,
      playheadSeconds: playhead.isFinite ? min(max(0, playhead), SnapzyProjectManifest.maxPlayheadSeconds) : 0,
      existingPackageURL: existingPackageURL,
      studioCameraSidecarURL: studioCameraURL,
      studioCursorImagesSidecarURL: studioCursorDirURL,
      referencedFontNames: fontNames,
      destinationURL: normalizedTarget
    )
  }

  /// Off-main-thread async project save used by interactive UI (`⌘S` / `⇧⌘S`) so copying large
  /// video files never blocks `@MainActor`.
  @MainActor
  static func saveAsync(
    state: VideoEditorState,
    existingSourceSnapshotURL: URL? = nil,
    existingPackageURL: URL? = nil,
    to destinationURL: URL
  ) async throws -> LoadedProject {
    let snapshot = try makeSaveSnapshot(
      state: state,
      existingSourceSnapshotURL: existingSourceSnapshotURL,
      existingPackageURL: existingPackageURL,
      to: destinationURL
    )

    let targetDirAccess = SandboxFileAccessManager.shared.beginAccessingURL(
      snapshot.destinationURL.deletingLastPathComponent()
    )
    let primaryAccess = SandboxFileAccessManager.shared.beginAccessingURL(snapshot.sessionData.sourceSnapshotURL)
    var extraAccesses: [SandboxFileAccessManager.ScopedAccess] = []
    if let existingPkg = snapshot.existingPackageURL {
      extraAccesses.append(SandboxFileAccessManager.shared.beginAccessingURL(existingPkg))
    }
    for clip in snapshot.sessionData.clips {
      if let clipURL = clip.url {
        extraAccesses.append(SandboxFileAccessManager.shared.beginAccessingURL(clipURL))
      }
    }
    defer {
      targetDirAccess.stop()
      primaryAccess.stop()
      extraAccesses.forEach { $0.stop() }
    }

    let loaded = try await Task.detached(priority: .userInitiated) {
      try writePackageInternal(
        sessionData: snapshot.sessionData,
        playheadSeconds: snapshot.playheadSeconds,
        existingPackageURL: snapshot.existingPackageURL,
        studioCameraSidecarURL: snapshot.studioCameraSidecarURL,
        studioCursorImagesSidecarURL: snapshot.studioCursorImagesSidecarURL,
        referencedFontNames: snapshot.referencedFontNames,
        to: snapshot.destinationURL
      )
    }.value

    if let names = loaded.manifest.referencedFontDisplayNames, !names.isEmpty {
      registerReferencedFontNames(names)
    }
    return loaded
  }

  /// Synchronous convenience wrapper for unit tests and CLI/scripted flows.
  @MainActor
  @discardableResult
  static func save(
    state: VideoEditorState,
    existingSourceSnapshotURL: URL? = nil,
    existingPackageURL: URL? = nil,
    to destinationURL: URL
  ) throws -> LoadedProject {
    let snapshot = try makeSaveSnapshot(
      state: state,
      existingSourceSnapshotURL: existingSourceSnapshotURL,
      existingPackageURL: existingPackageURL,
      to: destinationURL
    )

    let targetDirAccess = SandboxFileAccessManager.shared.beginAccessingURL(
      snapshot.destinationURL.deletingLastPathComponent()
    )
    let primaryAccess = SandboxFileAccessManager.shared.beginAccessingURL(snapshot.sessionData.sourceSnapshotURL)
    var extraAccesses: [SandboxFileAccessManager.ScopedAccess] = []
    if let existingPkg = snapshot.existingPackageURL {
      extraAccesses.append(SandboxFileAccessManager.shared.beginAccessingURL(existingPkg))
    }
    for clip in snapshot.sessionData.clips {
      if let clipURL = clip.url {
        extraAccesses.append(SandboxFileAccessManager.shared.beginAccessingURL(clipURL))
      }
    }
    defer {
      targetDirAccess.stop()
      primaryAccess.stop()
      extraAccesses.forEach { $0.stop() }
    }

    let loaded = try writePackageInternal(
      sessionData: snapshot.sessionData,
      playheadSeconds: snapshot.playheadSeconds,
      existingPackageURL: snapshot.existingPackageURL,
      studioCameraSidecarURL: snapshot.studioCameraSidecarURL,
      studioCursorImagesSidecarURL: snapshot.studioCursorImagesSidecarURL,
      referencedFontNames: snapshot.referencedFontNames,
      to: snapshot.destinationURL
    )
    if let names = loaded.manifest.referencedFontDisplayNames, !names.isEmpty {
      registerReferencedFontNames(names)
    }
    return loaded
  }

  // MARK: - Save (Direct from VideoEditorSessionData)

  @discardableResult
  static func save(
    sessionData: VideoEditorSessionData,
    playheadSeconds: Double = 0,
    existingPackageURL: URL? = nil,
    referencedFontNames: [String: String] = [:],
    to destinationURL: URL
  ) throws -> LoadedProject {
    let normalizedTarget = normalizedPackageURL(destinationURL)
    var studioCameraURL: URL?
    var studioCursorDirURL: URL?
    var fontNames = referencedFontNames
    if Thread.isMainThread {
      MainActor.assumeIsolated {
        if let camName = sessionData.recordingMetadata?.cameraSource?.fileName,
           let camURL = try? RecordingMetadataStore.sidecarURL(named: camName, kind: .camera),
           FileManager.default.fileExists(atPath: camURL.path) {
          studioCameraURL = camURL
        }
        if let cursorFolder = sessionData.recordingMetadata?.cursorCapture?.imagesFolderName,
           let cursorURL = try? RecordingMetadataStore.sidecarURL(named: cursorFolder, kind: .cursorImages),
           FileManager.default.fileExists(atPath: cursorURL.path) {
          studioCursorDirURL = cursorURL
        }
        for (k, v) in registeredFontDisplayNamesStorage where fontNames[k] == nil {
          fontNames[k] = v
        }
      }
    }

    return try writePackageInternal(
      sessionData: sessionData,
      playheadSeconds: playheadSeconds,
      existingPackageURL: existingPackageURL,
      studioCameraSidecarURL: studioCameraURL,
      studioCursorImagesSidecarURL: studioCursorDirURL,
      referencedFontNames: fontNames,
      to: normalizedTarget
    )
  }

  // MARK: - Load / Rehydrate (Sync & Off-Main Async)

  static func readManifest(from packageURL: URL) throws -> SnapzyProjectManifest {
    let normalizedURL = packageURL.standardizedFileURL
    guard isProjectURL(normalizedURL) else {
      throw SnapzyProjectPackageError.invalidPackageURL(normalizedURL)
    }
    let manifestURL = normalizedURL.appendingPathComponent(manifestFileName, isDirectory: false)
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw SnapzyProjectPackageError.manifestMissing(normalizedURL)
    }
    let data = try readBoundedFileData(from: manifestURL, maxBytes: maxManifestBytes)
    try validateUniqueIDsInManifestJSON(data)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(SnapzyProjectManifest.self, from: data)
    } catch {
      throw SnapzyProjectPackageError.manifestCorrupted(error.localizedDescription)
    }
  }

  /// Off-main-thread async project loader used by `VideoEditorManager.openProject` and rename flows.
  @MainActor
  static func loadAsync(from packageURL: URL) async throws -> LoadedProject {
    let normalizedURL = packageURL.standardizedFileURL
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(normalizedURL)
    defer { scopedAccess.stop() }

    let loaded = try await Task.detached(priority: .userInitiated) {
      try loadCore(from: normalizedURL)
    }.value

    if let names = loaded.manifest.referencedFontDisplayNames, !names.isEmpty {
      registerReferencedFontNames(names)
    }
    return loaded
  }

  static func load(from packageURL: URL) throws -> LoadedProject {
    let normalizedURL = packageURL.standardizedFileURL
    var scopedAccess: SandboxFileAccessManager.ScopedAccess?
    if Thread.isMainThread {
      scopedAccess = MainActor.assumeIsolated {
        SandboxFileAccessManager.shared.beginAccessingURL(normalizedURL)
      }
    }
    defer { scopedAccess?.stop() }

    let loaded = try loadCore(from: normalizedURL)
    if let names = loaded.manifest.referencedFontDisplayNames, !names.isEmpty {
      if Thread.isMainThread {
        MainActor.assumeIsolated {
          registerReferencedFontNames(names)
        }
      } else {
        Task { @MainActor in
          registerReferencedFontNames(names)
        }
      }
    }
    return loaded
  }

  private static func loadCore(from normalizedURL: URL) throws -> LoadedProject {
    let manifest = try readManifest(from: normalizedURL)
    guard manifest.schemaVersion >= 1 else {
      throw SnapzyProjectPackageError.manifestCorrupted("Invalid schemaVersion \(manifest.schemaVersion)")
    }
    guard manifest.schemaVersion <= SnapzyProjectManifest.currentSchemaVersion else {
      throw SnapzyProjectPackageError.unsupportedSchemaVersion(manifest.schemaVersion)
    }

    let fm = FileManager.default

    // 1. Primary media validation & resolution
    let primaryMediaURL = try resolveRelativePath(manifest.primaryMediaRelativePath, inside: normalizedURL)
    guard fm.fileExists(atPath: primaryMediaURL.path) else {
      throw SnapzyProjectPackageError.primaryMediaMissing(primaryMediaURL)
    }

    // 2. Rehydrate RecordingMetadata (bounded <= 8 MB + unique track ID check) + optional Studio sidecars.
    // Note: Font binaries are intentionally never installed from packages; missing fonts fall back to System Font.
    var recordingMetadata: RecordingMetadata?
    if let metaRelPath = manifest.recordingMetadataRelativePath {
      let metaURL = try resolveRelativePath(metaRelPath, inside: normalizedURL)
      if fm.fileExists(atPath: metaURL.path) {
        let metaData = try readBoundedFileData(from: metaURL, maxBytes: maxMetadataBytes)
        try validateUniqueIDsInRecordingMetadataJSON(metaData)
        let decodedMeta: RecordingMetadata
        do {
          decodedMeta = try JSONDecoder().decode(RecordingMetadata.self, from: metaData)
        } catch {
          throw SnapzyProjectPackageError.manifestCorrupted(error.localizedDescription)
        }
        var updatedMeta = decodedMeta
        if updatedMeta.audioSourceURL != nil {
          updatedMeta.audioSourceURL = primaryMediaURL
        }
        restoreStudioSidecarsIfNeeded(manifest: manifest, metadata: updatedMeta, packageURL: normalizedURL)
        recordingMetadata = updatedMeta
      }
    }

    // 3. Reconstruct base sessionData from persisted editState
    var sessionData = manifest.editState.sessionData(
      sourceSnapshotURL: primaryMediaURL,
      recordingMetadata: recordingMetadata
    )

    // 4. Remap all secondary TimelineClip `.file` URLs into `<packageURL>/Media/...`
    var remappedClips: [TimelineClip] = []
    remappedClips.reserveCapacity(sessionData.clips.count)
    for clip in sessionData.clips {
      switch clip.source {
      case .primary:
        remappedClips.append(clip)
      case .file:
        guard let relPath = manifest.secondaryClipRelativePaths[clip.id] else {
          throw SnapzyProjectPackageError.invalidPackageLayout(
            "Unmapped external clip \(clip.id.uuidString) is not allowed outside package boundary"
          )
        }
        let resolvedClipURL = try resolveRelativePath(relPath, inside: normalizedURL)
        guard fm.fileExists(atPath: resolvedClipURL.path) else {
          throw SnapzyProjectPackageError.secondaryMediaMissing(resolvedClipURL)
        }
        remappedClips.append(
          TimelineClip(
            id: clip.id,
            source: .file(url: resolvedClipURL),
            sourceDuration: clip.sourceDuration,
            sourceStart: clip.sourceStart,
            sourceEnd: clip.sourceEnd,
            slotStart: clip.slotStart,
            slotEnd: clip.slotEnd
          )
        )
      }
    }
    sessionData.clips = remappedClips

    // 5. Remap custom wallpaper / blurred background URL if embedded in package; never allow
    // an unmapped external file URL from an untrusted manifest to escape the package boundary.
    if let bgRelPath = manifest.backgroundImageRelativePath {
      let bgURL = try resolveRelativePath(bgRelPath, inside: normalizedURL)
      if fm.fileExists(atPath: bgURL.path) {
        switch sessionData.backgroundStyle {
        case .wallpaper:
          sessionData.backgroundStyle = .wallpaper(bgURL)
        case .blurred:
          sessionData.backgroundStyle = .blurred(bgURL)
        default:
          break
        }
      } else {
        switch sessionData.backgroundStyle {
        case .wallpaper, .blurred:
          sessionData.backgroundStyle = .none
        default:
          break
        }
      }
    } else {
      switch sessionData.backgroundStyle {
      case .wallpaper, .blurred:
        sessionData.backgroundStyle = .none
      default:
        break
      }
    }

    return LoadedProject(
      packageURL: normalizedURL,
      manifest: manifest,
      sessionData: sessionData,
      playheadSeconds: manifest.playheadSeconds
    )
  }

  // MARK: - Private Atomic Write Implementation

  private static func writePackageInternal(
    sessionData: VideoEditorSessionData,
    playheadSeconds: Double,
    existingPackageURL: URL?,
    studioCameraSidecarURL: URL?,
    studioCursorImagesSidecarURL: URL?,
    referencedFontNames: [String: String],
    to destinationURL: URL
  ) throws -> LoadedProject {
    let fm = FileManager.default
    guard isProjectURL(destinationURL) else {
      throw SnapzyProjectPackageError.invalidPackageURL(destinationURL)
    }

    let primarySourceURL = sessionData.sourceSnapshotURL
    guard fm.fileExists(atPath: primarySourceURL.path) else {
      throw SnapzyProjectPackageError.primaryMediaMissing(primarySourceURL)
    }

    let parentDirectory = destinationURL.deletingLastPathComponent()
    try fm.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

    let fallbackPkgURL: URL? = if let existingPackageURL, fm.fileExists(atPath: existingPackageURL.path) {
      existingPackageURL
    } else if fm.fileExists(atPath: destinationURL.path) {
      destinationURL
    } else {
      nil
    }
    let previousManifest = fallbackPkgURL.flatMap { try? readManifest(from: $0) }
    let previousCreatedAt = previousManifest?.createdAt ?? Date()
    let now = Date()

    let stagingDirectory = parentDirectory.appendingPathComponent(
      ".\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)",
      isDirectory: true
    )
    var didCommit = false
    defer {
      if !didCommit {
        try? fm.removeItem(at: stagingDirectory)
      }
    }

    let stagingMediaDir = stagingDirectory.appendingPathComponent(mediaDirectoryName, isDirectory: true)
    try fm.createDirectory(at: stagingMediaDir, withIntermediateDirectories: true)

    // 1. Copy primary media (uses APFS clonefile automatically on same volume)
    let primaryExt = sanitizedExtension(for: primarySourceURL, fallback: "mov")
    let primaryRelPath = "\(mediaDirectoryName)/primary.\(primaryExt)"
    let stagingPrimaryURL = stagingDirectory.appendingPathComponent(primaryRelPath, isDirectory: false)
    try fm.copyItem(at: primarySourceURL, to: stagingPrimaryURL)

    var copiedMediaByCanonicalPath: [String: String] = [
      canonicalPath(for: primarySourceURL): primaryRelPath,
    ]

    // 2. Copy all secondary TimelineClip `.file` media
    var secondaryClipRelativePaths: [UUID: String] = [:]
    var packagedClips: [TimelineClip] = []
    packagedClips.reserveCapacity(sessionData.clips.count)
    var mediaSlotCounter = 1

    for clip in sessionData.clips {
      switch clip.source {
      case .primary:
        packagedClips.append(clip)
      case .file(let rawClipSourceURL):
        let clipSourceURL: URL
        if fm.fileExists(atPath: rawClipSourceURL.path) {
          clipSourceURL = rawClipSourceURL
        } else if let fallbackPkgURL,
                  let prevRel = previousManifest?.secondaryClipRelativePaths[clip.id],
                  let prevURL = try? resolveRelativePath(prevRel, inside: fallbackPkgURL),
                  fm.fileExists(atPath: prevURL.path) {
          clipSourceURL = prevURL
        } else {
          throw SnapzyProjectPackageError.secondaryMediaMissing(rawClipSourceURL)
        }
        let canon = canonicalPath(for: clipSourceURL)
        let relPath: String
        if let existingRel = copiedMediaByCanonicalPath[canon] {
          relPath = existingRel
        } else {
          let ext = sanitizedExtension(for: clipSourceURL, fallback: "mov")
          let stem = sanitizedFileStem(for: clipSourceURL, fallback: "clip")
          let hash = shortHash(for: canon)
          let candidateRel = String(
            format: "%@/clip-%02d-%@-%@.%@",
            mediaDirectoryName,
            mediaSlotCounter,
            hash,
            stem,
            ext
          )
          mediaSlotCounter += 1
          let destFileURL = stagingDirectory.appendingPathComponent(candidateRel, isDirectory: false)
          try fm.copyItem(at: clipSourceURL, to: destFileURL)
          copiedMediaByCanonicalPath[canon] = candidateRel
          relPath = candidateRel
        }
        secondaryClipRelativePaths[clip.id] = relPath
        let targetPackagedURL = destinationURL.appendingPathComponent(relPath, isDirectory: false)
        packagedClips.append(
          TimelineClip(
            id: clip.id,
            source: .file(url: targetPackagedURL),
            sourceDuration: clip.sourceDuration,
            sourceStart: clip.sourceStart,
            sourceEnd: clip.sourceEnd,
            slotStart: clip.slotStart,
            slotEnd: clip.slotEnd
          )
        )
      }
    }

    let audioClipRelativePaths = previousManifest?.audioClipRelativePaths ?? [:]

    // 3. Write RecordingMetadata & optional Studio sidecars
    var recordingMetadataRelPath: String?
    var cameraSidecarRelPath: String?
    var cursorImagesRelPath: String?
    if var metadata = sessionData.recordingMetadata {
      if metadata.audioSourceURL != nil {
        metadata.audioSourceURL = destinationURL.appendingPathComponent(primaryRelPath, isDirectory: false)
      }
      let metaRel = "\(mediaDirectoryName)/\(recordingMetadataFileName)"
      let metaURL = stagingDirectory.appendingPathComponent(metaRel, isDirectory: false)
      let metaEncoder = JSONEncoder()
      metaEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try metaEncoder.encode(metadata).write(to: metaURL, options: .atomic)
      recordingMetadataRelPath = metaRel

      if let camURL = studioCameraSidecarURL,
         let camName = metadata.cameraSource?.fileName,
         isSafeSinglePathComponent(camName),
         fm.fileExists(atPath: camURL.path) {
        let sidecarsDir = stagingMediaDir
          .appendingPathComponent("Sidecars", isDirectory: true)
          .appendingPathComponent("CameraSources", isDirectory: true)
        try fm.createDirectory(at: sidecarsDir, withIntermediateDirectories: true)
        let rel = "\(mediaDirectoryName)/Sidecars/CameraSources/\(camName)"
        try? fm.copyItem(at: camURL, to: stagingDirectory.appendingPathComponent(rel))
        cameraSidecarRelPath = rel
      } else if let fallbackPkgURL,
                let prevRel = previousManifest?.cameraSidecarRelativePath,
                let prevURL = try? resolveRelativePath(prevRel, inside: fallbackPkgURL),
                fm.fileExists(atPath: prevURL.path) {
        let destSidecar = stagingDirectory.appendingPathComponent(prevRel)
        try fm.createDirectory(at: destSidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: prevURL, to: destSidecar)
        cameraSidecarRelPath = prevRel
      }

      if let cursorDir = studioCursorImagesSidecarURL,
         let folderName = metadata.cursorCapture?.imagesFolderName,
         isSafeSinglePathComponent(folderName),
         fm.fileExists(atPath: cursorDir.path) {
        let sidecarsDir = stagingMediaDir
          .appendingPathComponent("Sidecars", isDirectory: true)
          .appendingPathComponent("CursorImages", isDirectory: true)
        try fm.createDirectory(at: sidecarsDir, withIntermediateDirectories: true)
        let rel = "\(mediaDirectoryName)/Sidecars/CursorImages/\(folderName)"
        try? fm.copyItem(at: cursorDir, to: stagingDirectory.appendingPathComponent(rel))
        cursorImagesRelPath = rel
      } else if let fallbackPkgURL,
                let prevRel = previousManifest?.cursorImagesRelativePath,
                let prevURL = try? resolveRelativePath(prevRel, inside: fallbackPkgURL),
                fm.fileExists(atPath: prevURL.path) {
        let destSidecar = stagingDirectory.appendingPathComponent(prevRel)
        try fm.createDirectory(at: destSidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: prevURL, to: destSidecar)
        cursorImagesRelPath = prevRel
      }
    }

    // 5. Copy custom wallpaper / blurred background image if applicable
    var backgroundImageRelPath: String?
    var packagedBackgroundStyle = sessionData.backgroundStyle
    let resolveBackgroundURL: (URL) -> URL? = { bgURL in
      if bgURL.isFileURL, fm.fileExists(atPath: bgURL.path) {
        return bgURL
      }
      if let fallbackPkgURL,
         let prevRel = previousManifest?.backgroundImageRelativePath,
         let prevURL = try? resolveRelativePath(prevRel, inside: fallbackPkgURL),
         fm.fileExists(atPath: prevURL.path) {
        return prevURL
      }
      return nil
    }
    switch sessionData.backgroundStyle {
    case .wallpaper(let bgURL):
      if let resolvedBg = resolveBackgroundURL(bgURL) {
        let ext = sanitizedExtension(for: resolvedBg, fallback: "jpg")
        let rel = "\(mediaDirectoryName)/background.\(ext)"
        try fm.copyItem(at: resolvedBg, to: stagingDirectory.appendingPathComponent(rel, isDirectory: false))
        backgroundImageRelPath = rel
        packagedBackgroundStyle = .wallpaper(destinationURL.appendingPathComponent(rel, isDirectory: false))
      }
    case .blurred(let bgURL):
      if let resolvedBg = resolveBackgroundURL(bgURL) {
        let ext = sanitizedExtension(for: resolvedBg, fallback: "jpg")
        let rel = "\(mediaDirectoryName)/background.\(ext)"
        try fm.copyItem(at: resolvedBg, to: stagingDirectory.appendingPathComponent(rel, isDirectory: false))
        backgroundImageRelPath = rel
        packagedBackgroundStyle = .blurred(destinationURL.appendingPathComponent(rel, isDirectory: false))
      }
    default:
      break
    }

    // 6. Merge font reference display names (never copying font binaries into `.snapzy`)
    var mergedFontNames = previousManifest?.referencedFontDisplayNames ?? [:]
    for (k, v) in referencedFontNames {
      mergedFontNames[k] = v
    }

    // 7. Build clean packaged SessionData -> PersistedVideoEditorEditState
    var packagedSession = sessionData
    packagedSession.clips = packagedClips
    packagedSession.backgroundStyle = packagedBackgroundStyle
    let persistedEditState = PersistedVideoEditorEditState(sessionData: packagedSession)

    let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    let manifest = SnapzyProjectManifest(
      schemaVersion: SnapzyProjectManifest.currentSchemaVersion,
      createdAt: previousCreatedAt,
      updatedAt: now,
      appVersion: appVersion,
      primaryMediaRelativePath: primaryRelPath,
      recordingMetadataRelativePath: recordingMetadataRelPath,
      secondaryClipRelativePaths: secondaryClipRelativePaths,
      audioClipRelativePaths: audioClipRelativePaths,
      referencedFontDisplayNames: mergedFontNames.isEmpty ? nil : mergedFontNames,
      backgroundImageRelativePath: backgroundImageRelPath,
      cameraSidecarRelativePath: cameraSidecarRelPath,
      cursorImagesRelativePath: cursorImagesRelPath,
      playheadSeconds: playheadSeconds,
      editState: persistedEditState
    )

    // 8. Write & flush manifest.json, then round-trip validate BEFORE replacing destination!
    let stagingManifestURL = stagingDirectory.appendingPathComponent(manifestFileName, isDirectory: false)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifestData = try encoder.encode(manifest)
    try manifestData.write(to: stagingManifestURL, options: .atomic)

    let verifiedData = try readBoundedFileData(from: stagingManifestURL, maxBytes: maxManifestBytes)
    try validateUniqueIDsInManifestJSON(verifiedData)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let verifiedManifest = try decoder.decode(SnapzyProjectManifest.self, from: verifiedData)
    guard verifiedManifest.schemaVersion == SnapzyProjectManifest.currentSchemaVersion,
          fm.fileExists(atPath: stagingPrimaryURL.path)
    else {
      throw SnapzyProjectPackageError.manifestCorrupted("Post-write staging verification failed")
    }

    // 9. Mark directory as a macOS package before atomic swap
    var stagingResourceURL = stagingDirectory
    var pkgValues = URLResourceValues()
    pkgValues.isPackage = true
    try? stagingResourceURL.setResourceValues(pkgValues)

    do {
      if fm.fileExists(atPath: destinationURL.path) {
        _ = try fm.replaceItemAt(destinationURL, withItemAt: stagingDirectory)
      } else {
        try fm.moveItem(at: stagingDirectory, to: destinationURL)
      }
      didCommit = true
    } catch {
      throw SnapzyProjectPackageError.atomicReplaceFailed(error.localizedDescription)
    }

    // 10. Assert package bit & asynchronously refresh Finder icon without blocking or deadlocking main thread
    applyPackageIcon(to: destinationURL)

    return try loadCore(from: destinationURL)
  }

  private static func applyPackageIcon(to packageURL: URL) {
    var targetURL = packageURL
    var values = URLResourceValues()
    values.isPackage = true
    try? targetURL.setResourceValues(values)

    let uiWork: @Sendable () -> Void = {
      let iconImage: NSImage? = {
        if let icnsURL = Bundle.main.url(forResource: "SnapzyProjectIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icnsURL) {
          return image
        }
        return NSImage(named: "SnapzyProjectIcon")
      }()
      if let iconImage {
        _ = NSWorkspace.shared.setIcon(iconImage, forFile: packageURL.path, options: [])
      }
      NSWorkspace.shared.noteFileSystemChanged(packageURL.path)
      NSWorkspace.shared.noteFileSystemChanged(packageURL.deletingLastPathComponent().path)
    }

    if Thread.isMainThread {
      uiWork()
    } else {
      DispatchQueue.main.async(execute: uiWork)
    }
  }

  private static func restoreStudioSidecarsIfNeeded(
    manifest: SnapzyProjectManifest,
    metadata: RecordingMetadata,
    packageURL: URL
  ) {
    let fm = FileManager.default
    guard let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return
    }
    if let camRel = manifest.cameraSidecarRelativePath,
       let camName = metadata.cameraSource?.fileName,
       isSafeSinglePathComponent(camName),
       let pkgCamURL = try? resolveRelativePath(camRel, inside: packageURL),
       let camVals = try? pkgCamURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
       camVals.isRegularFile == true,
       camVals.isSymbolicLink != true {
      let camDir = appSupportURL
        .appendingPathComponent("Snapzy/Captures/RecordingMetadata/CameraSources", isDirectory: true)
      let targetCamURL = camDir.appendingPathComponent(camName, isDirectory: false)
      if !fm.fileExists(atPath: targetCamURL.path) {
        try? fm.createDirectory(at: camDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: pkgCamURL, to: targetCamURL)
      }
    }

    if let cursorRel = manifest.cursorImagesRelativePath,
       let folderName = metadata.cursorCapture?.imagesFolderName,
       isSafeSinglePathComponent(folderName),
       let pkgCursorURL = try? resolveRelativePath(cursorRel, inside: packageURL),
       let dirVals = try? pkgCursorURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
       dirVals.isDirectory == true,
       dirVals.isSymbolicLink != true {
      let cursorRootDir = appSupportURL
        .appendingPathComponent("Snapzy/Captures/RecordingMetadata/CursorImages", isDirectory: true)
      let targetCursorURL = cursorRootDir.appendingPathComponent(folderName, isDirectory: true)
      if !fm.fileExists(atPath: targetCursorURL.path),
         let entries = try? fm.contentsOfDirectory(
           at: pkgCursorURL,
           includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
           options: [.skipsHiddenFiles]
         ),
         entries.count <= 256 {
        var totalBytes = 0
        var safeFiles: [URL] = []
        for entry in entries {
          guard let v = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                v.isRegularFile == true,
                v.isSymbolicLink != true,
                let sz = v.fileSize,
                sz >= 0
          else {
            safeFiles.removeAll()
            break
          }
          totalBytes += sz
          if totalBytes > 33_554_432 {
            safeFiles.removeAll()
            break
          }
          safeFiles.append(entry)
        }
        if !safeFiles.isEmpty {
          try? fm.createDirectory(at: targetCursorURL, withIntermediateDirectories: true)
          for file in safeFiles {
            let dst = targetCursorURL.appendingPathComponent(file.lastPathComponent, isDirectory: false)
            try? fm.copyItem(at: file, to: dst)
          }
        }
      }
    }
  }

  // MARK: - Path Security & Sanitization

  static func resolveRelativePath(_ relativePath: String, inside packageURL: URL) throws -> URL {
    let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !trimmed.hasPrefix("/"),
          !trimmed.hasPrefix("~")
    else {
      throw SnapzyProjectPackageError.invalidPackageLayout("Disallowed relative path: \(relativePath)")
    }

    let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !components.isEmpty,
          !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else {
      throw SnapzyProjectPackageError.invalidPackageLayout("Invalid relative path components: \(relativePath)")
    }

    let rootResolved = packageURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = components.reduce(packageURL.standardizedFileURL) { partial, component in
      partial.appendingPathComponent(component)
    }.resolvingSymlinksInPath()

    let rootPrefix = rootResolved.path.hasSuffix("/") ? rootResolved.path : rootResolved.path + "/"
    guard candidate.path.hasPrefix(rootPrefix) else {
      throw SnapzyProjectPackageError.invalidPackageLayout("Path escapes .snapzy boundary: \(relativePath)")
    }
    return candidate
  }

  private static func isSafeSinglePathComponent(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
  }

  private static func canonicalPath(for url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func shortHash(for string: String) -> String {
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
  }

  private static func sanitizedExtension(for url: URL, fallback: String) -> String {
    let ext = url.pathExtension.lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    return ext.isEmpty ? fallback : ext
  }

  private static func sanitizedFileStem(for url: URL, fallback: String) -> String {
    let raw = url.deletingPathExtension().lastPathComponent
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    if raw.isEmpty {
      return fallback
    }
    return String(raw.prefix(32))
  }
}
