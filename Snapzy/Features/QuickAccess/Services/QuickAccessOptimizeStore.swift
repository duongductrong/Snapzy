//
//  QuickAccessOptimizeStore.swift
//  Snapzy
//
//  Applies an Optimize level to a Quick Access capture in place and keeps the
//  untouched original so any level — including "Original" — can be picked again
//  without stacking lossy re-encodes. Originals live only while the card does.
//

import AppKit
import Combine
import Foundation

/// The levels on offer for one capture, measured against its original.
struct QuickAccessOptimizePlan: Equatable {
  let source: QuickAccessOptimizeSourceInfo
  let levels: [QuickAccessOptimizeLevel]
  /// Fraction currently written to disk (`1` when untouched).
  let currentFraction: CGFloat
  let originalByteCount: Int?
  let fileExtension: String
}

@MainActor
final class QuickAccessOptimizeStore {
  static let shared = QuickAccessOptimizeStore()

  nonisolated enum OptimizeError: Error {
    case unsupportedFile
    case unreadableSource
    case encodingFailed
  }

  private struct Original {
    let backupURL: URL
    let byteCount: Int?
  }

  private var originals: [UUID: Original] = [:]
  private var appliedFractions: [UUID: CGFloat] = [:]
  private var inFlightItemIDs: Set<UUID> = []
  private var itemsCancellable: AnyCancellable?
  private let fileManager = FileManager.default

  private lazy var backupDirectory: URL = {
    let directory = fileManager.temporaryDirectory
      .appendingPathComponent("QuickAccessOptimizeOriginals", isDirectory: true)
    // Originals from a previous run belong to cards that no longer exist.
    try? fileManager.removeItem(at: directory)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }()

  private init() {}

  // MARK: - Queries

  func canOptimize(_ item: QuickAccessItem) -> Bool {
    !item.isVideo && QuickAccessImageOptimizer.supports(url: item.url)
  }

  func isOptimizing(_ itemID: UUID) -> Bool {
    inFlightItemIDs.contains(itemID)
  }

  func currentFraction(for itemID: UUID) -> CGFloat {
    appliedFractions[itemID] ?? 1
  }

  /// The levels for `item`, read from the file header only (cheap enough for a menu).
  func plan(for item: QuickAccessItem) -> QuickAccessOptimizePlan? {
    guard canOptimize(item) else { return nil }
    observeItemsIfNeeded()

    let original = originals[item.id]
    let sourceURL = original?.backupURL ?? item.url
    let access = original == nil ? SandboxFileAccessManager.shared.beginAccessingURL(sourceURL) : nil
    defer { access?.stop() }

    let fallbackScale = NSScreen.main?.backingScaleFactor ?? 2
    guard let info = QuickAccessImageOptimizer.sourceInfo(at: sourceURL, fallbackScale: fallbackScale) else {
      return nil
    }

    return QuickAccessOptimizePlan(
      source: info,
      levels: QuickAccessImageOptimizer.levels(for: info),
      currentFraction: currentFraction(for: item.id),
      originalByteCount: original?.byteCount ?? Self.byteCount(at: sourceURL),
      fileExtension: item.url.pathExtension.lowercased()
    )
  }

  /// Encodes every reduced level off the main actor, reporting each as it lands.
  func estimate(
    plan: QuickAccessOptimizePlan,
    for item: QuickAccessItem,
    onResult: @escaping @MainActor (QuickAccessOptimizeLevel, Data?) -> Void
  ) -> Task<Void, Never> {
    let sourceURL = originals[item.id]?.backupURL ?? item.url
    let reducedLevels = plan.levels.filter { !$0.isOriginal }
    let fileExtension = plan.fileExtension

    let access = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)

    return Task.detached(priority: .userInitiated) {
      let original = QuickAccessImageOptimizer.loadImage(at: sourceURL)
      access.stop()
      guard let original else {
        for level in reducedLevels {
          await onResult(level, nil)
        }
        return
      }

      await withTaskGroup(of: (QuickAccessOptimizeLevel, Data?).self) { group in
        for level in reducedLevels {
          group.addTask {
            guard !Task.isCancelled else { return (level, nil) }
            return (level, QuickAccessImageOptimizer.render(level, from: original, fileExtension: fileExtension))
          }
        }
        for await (level, data) in group {
          guard !Task.isCancelled else { return }
          await onResult(level, data)
        }
      }
    }
  }

  // MARK: - Apply

  /// Writes `level` over the capture's file. Pass `encodedData` from `estimate` to skip
  /// re-encoding; picking the original restores the untouched bytes.
  func apply(
    _ level: QuickAccessOptimizeLevel,
    to itemID: UUID,
    encodedData: Data? = nil
  ) async throws {
    let manager = QuickAccessManager.shared
    guard let item = manager.items.first(where: { $0.id == itemID }), canOptimize(item) else {
      throw OptimizeError.unsupportedFile
    }
    guard currentFraction(for: itemID) != level.fraction else { return }
    guard !inFlightItemIDs.contains(itemID) else { return }

    inFlightItemIDs.insert(itemID)
    manager.updateProcessingState(id: itemID, state: .processing(progress: nil))
    defer {
      inFlightItemIDs.remove(itemID)
      manager.updateProcessingState(id: itemID, state: .idle)
    }

    let targetURL = item.url
    let data: Data

    if level.isOriginal {
      guard let original = originals[itemID] else { return }
      data = try Data(contentsOf: original.backupURL)
    } else if let encodedData {
      data = encodedData
    } else {
      let sourceURL = originals[itemID]?.backupURL ?? targetURL
      let fileExtension = targetURL.pathExtension.lowercased()
      let access = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
      let rendered: Result<Data, OptimizeError> = await Task.detached(priority: .userInitiated) {
        defer { access.stop() }
        guard let image = QuickAccessImageOptimizer.loadImage(at: sourceURL) else {
          return .failure(.unreadableSource)
        }
        guard let data = QuickAccessImageOptimizer.render(level, from: image, fileExtension: fileExtension) else {
          return .failure(.encodingFailed)
        }
        return .success(data)
      }.value
      data = try rendered.get()
    }

    if originals[itemID] == nil {
      try preserveOriginal(of: targetURL, for: itemID)
    }

    try SandboxFileAccessManager.shared.withScopedAccess(to: targetURL.deletingLastPathComponent()) {
      try data.write(to: targetURL, options: .atomic)
    }

    appliedFractions[itemID] = level.fraction
    // The in-memory editor session still holds the old pixels; reopening the editor
    // must load the optimized file instead of silently restoring them on save.
    AnnotateManager.shared.clearSessionData(for: itemID)
    CaptureHistoryStore.shared.markFileChanged(at: targetURL)
    if item.cloudURL != nil {
      manager.markCloudStale(id: itemID)
    }
    await manager.refreshItemThumbnail(id: itemID)

    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access capture optimized",
      context: [
        "itemId": itemID.uuidString,
        "fraction": "\(level.fraction)",
        "pixels": level.dimensionsLabel,
        "bytes": "\(data.count)",
      ]
    )
  }

  /// Fire-and-forget entry point for UI callers: failures are logged and surfaced
  /// as a toast instead of being thrown back into a menu or button action.
  func applyReportingFailure(
    _ level: QuickAccessOptimizeLevel,
    to itemID: UUID,
    encodedData: Data? = nil
  ) {
    Task { @MainActor in
      do {
        try await apply(level, to: itemID, encodedData: encodedData)
      } catch {
        DiagnosticLogger.shared.logError(
          .action,
          error,
          "Quick access optimize failed",
          context: ["itemId": itemID.uuidString, "fraction": "\(level.fraction)"]
        )
        QuickAccessSound.failed.play()
        AppToastManager.shared.show(message: L10n.QuickAccess.optimizeFailed, style: .error)
      }
    }
  }

  // MARK: - Originals

  private func preserveOriginal(of url: URL, for itemID: UUID) throws {
    let backupURL = backupDirectory
      .appendingPathComponent(itemID.uuidString)
      .appendingPathExtension(url.pathExtension)
    try? fileManager.removeItem(at: backupURL)
    try SandboxFileAccessManager.shared.withScopedAccess(to: url) {
      try fileManager.copyItem(at: url, to: backupURL)
    }
    originals[itemID] = Original(backupURL: backupURL, byteCount: Self.byteCount(at: backupURL))
  }

  private func discard(itemID: UUID) {
    appliedFractions.removeValue(forKey: itemID)
    guard let original = originals.removeValue(forKey: itemID) else { return }
    try? fileManager.removeItem(at: original.backupURL)
  }

  /// Originals follow card lifetime: whichever path removes a card (dismiss, delete,
  /// countdown, drag-out) drops its original here.
  private func observeItemsIfNeeded() {
    guard itemsCancellable == nil else { return }
    itemsCancellable = QuickAccessManager.shared.$items
      .receive(on: DispatchQueue.main)
      .sink { [weak self] items in
        guard let self else { return }
        let liveIDs = Set(items.map(\.id))
        let tracked = Set(self.originals.keys).union(self.appliedFractions.keys)
        for staleID in tracked.subtracting(liveIDs) {
          self.discard(itemID: staleID)
        }
      }
  }

  private static func byteCount(at url: URL) -> Int? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
  }
}
