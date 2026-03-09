//
//  RecordingMetadata.swift
//  Snapzy
//
//  Internal metadata for recordings that need editor-only context.
//

import CoreGraphics
import Foundation
import os.log

private let recordingMetadataLogger = Logger(subsystem: "Snapzy", category: "RecordingMetadata")

struct RecordedMouseSample: Codable, Equatable {
  var time: TimeInterval
  var normalizedX: CGFloat
  var normalizedY: CGFloat
  var isInsideCapture: Bool

  var normalizedPoint: CGPoint {
    CGPoint(x: normalizedX, y: normalizedY)
  }
}

struct RecordingMetadata: Codable, Equatable {
  static let currentVersion = 1

  var version: Int
  var captureSize: CGSize
  var samplesPerSecond: Int
  var mouseSamples: [RecordedMouseSample]

  init(
    version: Int = RecordingMetadata.currentVersion,
    captureSize: CGSize,
    samplesPerSecond: Int,
    mouseSamples: [RecordedMouseSample]
  ) {
    self.version = version
    self.captureSize = captureSize
    self.samplesPerSecond = samplesPerSecond
    self.mouseSamples = mouseSamples
  }
}

@MainActor
enum RecordingMetadataStore {
  private struct StoreLocation {
    let entriesURL: URL
    let indexURL: URL
  }

  private struct MetadataIndex: Codable {
    var entries: [MetadataIndexEntry] = []
  }

  private struct MetadataIndexEntry: Codable, Equatable {
    var id: UUID
    var lastKnownPath: String
    var bookmarkData: Data
    var staleSince: Date?
  }

  private enum CleanupDisposition {
    case keep(MetadataIndexEntry)
    case delete
  }

  private static let appSupportFolderName = "Snapzy"
  private static let storeFolderName = "RecordingMetadata"
  private static let entriesFolderName = "Entries"
  private static let indexFileName = "index.json"
  private static let metadataFileExtension = "json"
  private static let legacySidecarExtension = "snapzy-recording.json"
  private static let orphanGracePeriod: TimeInterval = 24 * 60 * 60

  static func load(for videoURL: URL) -> RecordingMetadata? {
    do {
      let location = try requiredStoreLocation()
      var index = loadIndex(from: location)

      if let metadata = try loadStoredMetadata(for: videoURL, location: location, index: &index) {
        return metadata
      }

      if let metadata = try migrateLegacySidecarIfNeeded(for: videoURL, location: location, index: &index) {
        return metadata
      }
    } catch {
      recordingMetadataLogger.error("Failed to load recording metadata for \(videoURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    return nil
  }

  static func save(_ metadata: RecordingMetadata, for videoURL: URL) throws {
    let location = try requiredStoreLocation()
    var index = loadIndex(from: location)

    let existingEntry = resolveEntry(for: videoURL, index: index)?.entry
    let entry = try makeEntry(id: existingEntry?.id ?? UUID(), for: videoURL)
    let metadataURL = self.metadataURL(for: entry.id, location: location)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)
    try data.write(to: metadataURL, options: .atomic)

    upsert(entry: entry, into: &index)
    try saveIndex(index, to: location)
    try deleteLegacySidecarIfPresent(for: videoURL)
  }

  static func moveAssociation(from oldURL: URL, to newURL: URL) throws {
    let location = try requiredStoreLocation()
    var index = loadIndex(from: location)

    if let resolved = resolveEntry(for: oldURL, index: index) {
      let entry = try makeEntry(id: resolved.entry.id, for: newURL)
      index.entries[resolved.index] = entry
      try saveIndex(index, to: location)
      try deleteLegacySidecarIfPresent(for: oldURL)
      try deleteLegacySidecarIfPresent(for: newURL)
      return
    }

    if let metadata = try loadLegacySidecarMetadata(for: oldURL) {
      try save(metadata, for: newURL)
      try deleteLegacySidecarIfPresent(for: oldURL)
    }
  }

  static func delete(for videoURL: URL) throws {
    if let location = try storeLocation(createIfNeeded: false) {
      var index = loadIndex(from: location)

      if let resolved = resolveEntry(for: videoURL, index: index) {
        let metadataURL = self.metadataURL(for: resolved.entry.id, location: location)
        index.entries.remove(at: resolved.index)
        try saveIndex(index, to: location)

        if FileManager.default.fileExists(atPath: metadataURL.path) {
          try FileManager.default.removeItem(at: metadataURL)
        }
      }
    }

    try deleteLegacySidecarIfPresent(for: videoURL)
  }

  static func performOrphanCleanup(now: Date = Date()) throws {
    guard let location = try storeLocation(createIfNeeded: false) else {
      return
    }

    var index = loadIndex(from: location)
    var keptEntries: [MetadataIndexEntry] = []
    var metadataURLsToDelete: [URL] = []

    for entry in index.entries {
      let metadataURL = self.metadataURL(for: entry.id, location: location)

      guard FileManager.default.fileExists(atPath: metadataURL.path) else {
        metadataURLsToDelete.append(metadataURL)
        continue
      }

      switch cleanupDisposition(for: entry, now: now) {
      case .keep(let updatedEntry):
        keptEntries.append(updatedEntry)
      case .delete:
        metadataURLsToDelete.append(metadataURL)
      }
    }

    guard keptEntries != index.entries || !metadataURLsToDelete.isEmpty else {
      return
    }

    index.entries = keptEntries
    try saveIndex(index, to: location)

    for metadataURL in metadataURLsToDelete where FileManager.default.fileExists(atPath: metadataURL.path) {
      try? FileManager.default.removeItem(at: metadataURL)
    }
  }

  private static func storeLocation(createIfNeeded: Bool) throws -> StoreLocation? {
    guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      return nil
    }

    let rootURL = appSupportURL
      .appendingPathComponent(appSupportFolderName, isDirectory: true)
      .appendingPathComponent(storeFolderName, isDirectory: true)
    let entriesURL = rootURL.appendingPathComponent(entriesFolderName, isDirectory: true)
    let indexURL = rootURL.appendingPathComponent(indexFileName)

    if createIfNeeded {
      try FileManager.default.createDirectory(
        at: entriesURL,
        withIntermediateDirectories: true,
        attributes: nil
      )
    } else if !FileManager.default.fileExists(atPath: rootURL.path) {
      return nil
    }

    return StoreLocation(entriesURL: entriesURL, indexURL: indexURL)
  }

  private static func requiredStoreLocation() throws -> StoreLocation {
    if let location = try storeLocation(createIfNeeded: true) {
      return location
    }

    throw CocoaError(.fileNoSuchFile)
  }

  private static func loadIndex(from location: StoreLocation) -> MetadataIndex {
    guard FileManager.default.fileExists(atPath: location.indexURL.path),
          let data = try? Data(contentsOf: location.indexURL)
    else {
      return MetadataIndex()
    }

    do {
      return try JSONDecoder().decode(MetadataIndex.self, from: data)
    } catch {
      recordingMetadataLogger.error("Failed to decode metadata index at \(location.indexURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return MetadataIndex()
    }
  }

  private static func saveIndex(_ index: MetadataIndex, to location: StoreLocation) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(index)
    try data.write(to: location.indexURL, options: .atomic)
  }

  private static func loadStoredMetadata(
    for videoURL: URL,
    location: StoreLocation,
    index: inout MetadataIndex
  ) throws -> RecordingMetadata? {
    guard let resolved = resolveEntry(for: videoURL, index: index) else {
      return nil
    }

    let metadataURL = self.metadataURL(for: resolved.entry.id, location: location)
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      index.entries.remove(at: resolved.index)
      try saveIndex(index, to: location)
      return nil
    }

    let data = try Data(contentsOf: metadataURL)
    let metadata = try JSONDecoder().decode(RecordingMetadata.self, from: data)

    if index.entries[resolved.index] != resolved.entry {
      index.entries[resolved.index] = resolved.entry
      try saveIndex(index, to: location)
    }

    return metadata
  }

  private static func resolveEntry(
    for videoURL: URL,
    index: MetadataIndex
  ) -> (index: Int, entry: MetadataIndexEntry)? {
    let targetPath = normalizedPath(for: videoURL)

    if let exactIndex = index.entries.firstIndex(where: { $0.lastKnownPath == targetPath }) {
      return (exactIndex, refreshedEntry(index.entries[exactIndex], with: videoURL))
    }

    for (indexPosition, entry) in index.entries.enumerated() {
      guard let bookmarkedURL = resolveBookmarkedURL(for: entry) else { continue }
      guard normalizedPath(for: bookmarkedURL) == targetPath else { continue }
      return (indexPosition, refreshedEntry(entry, with: videoURL))
    }

    return nil
  }

  private static func upsert(entry: MetadataIndexEntry, into index: inout MetadataIndex) {
    if let existingIndex = index.entries.firstIndex(where: { $0.id == entry.id }) {
      index.entries[existingIndex] = entry
    } else {
      index.entries.append(entry)
    }
  }

  private static func makeEntry(id: UUID, for videoURL: URL) throws -> MetadataIndexEntry {
    MetadataIndexEntry(
      id: id,
      lastKnownPath: normalizedPath(for: videoURL),
      bookmarkData: try videoBookmarkData(for: videoURL),
      staleSince: nil
    )
  }

  private static func refreshedEntry(_ entry: MetadataIndexEntry, with videoURL: URL) -> MetadataIndexEntry {
    var refreshed = entry
    refreshed.lastKnownPath = normalizedPath(for: videoURL)
    refreshed.staleSince = nil

    if let bookmarkData = try? videoBookmarkData(for: videoURL) {
      refreshed.bookmarkData = bookmarkData
    }

    return refreshed
  }

  private static func videoBookmarkData(for videoURL: URL) throws -> Data {
    try SandboxFileAccessManager.shared.withScopedAccess(to: videoURL) {
      try videoURL.standardizedFileURL.bookmarkData(
        options: [.minimalBookmark],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    }
  }

  private static func resolveBookmarkedURL(for entry: MetadataIndexEntry) -> URL? {
    var isStale = false

    do {
      return try URL(
        resolvingBookmarkData: entry.bookmarkData,
        options: [.withoutUI, .withoutMounting],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      .standardizedFileURL
      .resolvingSymlinksInPath()
    } catch {
      return nil
    }
  }

  private static func cleanupDisposition(
    for entry: MetadataIndexEntry,
    now: Date
  ) -> CleanupDisposition {
    if let bookmarkedURL = resolveBookmarkedURL(for: entry),
       FileManager.default.fileExists(atPath: bookmarkedURL.path)
    {
      return .keep(refreshedCleanupEntry(entry, resolvedURL: bookmarkedURL))
    }

    let lastKnownURL = URL(fileURLWithPath: entry.lastKnownPath)
    if FileManager.default.fileExists(atPath: lastKnownURL.path) {
      return .keep(refreshedCleanupEntry(entry, resolvedURL: lastKnownURL))
    }

    guard let staleSince = entry.staleSince else {
      var staleEntry = entry
      staleEntry.staleSince = now
      return .keep(staleEntry)
    }

    if now.timeIntervalSince(staleSince) >= orphanGracePeriod {
      return .delete
    }

    return .keep(entry)
  }

  private static func refreshedCleanupEntry(
    _ entry: MetadataIndexEntry,
    resolvedURL: URL
  ) -> MetadataIndexEntry {
    var refreshed = entry
    refreshed.lastKnownPath = normalizedPath(for: resolvedURL)
    refreshed.staleSince = nil

    if let bookmarkData = try? videoBookmarkData(for: resolvedURL) {
      refreshed.bookmarkData = bookmarkData
    }

    return refreshed
  }

  private static func normalizedPath(for videoURL: URL) -> String {
    videoURL.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func metadataURL(for id: UUID, location: StoreLocation) -> URL {
    location.entriesURL
      .appendingPathComponent(id.uuidString)
      .appendingPathExtension(metadataFileExtension)
  }

  private static func migrateLegacySidecarIfNeeded(
    for videoURL: URL,
    location: StoreLocation,
    index: inout MetadataIndex
  ) throws -> RecordingMetadata? {
    guard let metadata = try loadLegacySidecarMetadata(for: videoURL) else {
      return nil
    }

    let entry = try makeEntry(id: UUID(), for: videoURL)
    let metadataURL = self.metadataURL(for: entry.id, location: location)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)

    try data.write(to: metadataURL, options: .atomic)
    upsert(entry: entry, into: &index)
    try saveIndex(index, to: location)
    try deleteLegacySidecarIfPresent(for: videoURL)

    return metadata
  }

  private static func loadLegacySidecarMetadata(for videoURL: URL) throws -> RecordingMetadata? {
    let sidecarURL = legacySidecarURL(for: videoURL)

    return try SandboxFileAccessManager.shared.withScopedAccess(to: sidecarURL.deletingLastPathComponent()) {
      guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
        return nil
      }

      let data = try Data(contentsOf: sidecarURL)
      return try JSONDecoder().decode(RecordingMetadata.self, from: data)
    }
  }

  private static func deleteLegacySidecarIfPresent(for videoURL: URL) throws {
    let sidecarURL = legacySidecarURL(for: videoURL)

    try SandboxFileAccessManager.shared.withScopedAccess(to: sidecarURL.deletingLastPathComponent()) {
      guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return }
      try FileManager.default.removeItem(at: sidecarURL)
    }
  }

  private static func legacySidecarURL(for videoURL: URL) -> URL {
    videoURL
      .deletingPathExtension()
      .appendingPathExtension(legacySidecarExtension)
  }
}
