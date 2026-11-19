//
//  QuickAccessOptimizeStore.swift
//  Snapzy
//
//  Applies an Optimize level, preset or custom settings to a Quick Access capture
//  and keeps the untouched original so anything — including "Original" — can be
//  picked again without stacking lossy re-encodes. Originals live only while the
//  card does.
//

import AppKit
import Combine
import Foundation

/// The levels on offer for one capture, measured against its original.
struct QuickAccessOptimizePlan: Equatable {
  let source: QuickAccessOptimizeSourceInfo
  let levels: [QuickAccessOptimizeLevel]
  /// Fraction currently written to disk (`1` when untouched), or nil when custom
  /// settings or a preset produced the file.
  let currentFraction: CGFloat?
  let originalByteCount: Int?
  /// Extension of the untouched original, which levels keep.
  let fileExtension: String
}

/// What to write over a capture.
enum QuickAccessOptimizeRequest {
  /// A downscale level; `encodedData` from `estimate` skips re-encoding.
  case level(QuickAccessOptimizeLevel, encodedData: Data? = nil)
  /// Custom settings (from the editor or a preset); `rendering` skips re-rendering.
  case custom(QuickAccessOptimizeSettings, rendering: QuickAccessOptimizeRendering? = nil)
}

/// Everything the Custom editor needs to preview renders without touching the store.
struct QuickAccessOptimizeCustomSource {
  let sourceURL: URL
  let info: QuickAccessOptimizeSourceInfo
  let originalExtension: String
  let originalByteCount: Int?
}

@MainActor
final class QuickAccessOptimizeStore {
  static let shared = QuickAccessOptimizeStore()

  nonisolated enum OptimizeError: Error {
    case unsupportedFile
    case unreadableSource
    case encodingFailed
  }

  private enum AppliedState: Equatable {
    case level(CGFloat)
    case custom(QuickAccessOptimizeSettings)
  }

  private struct Original {
    let backupURL: URL
    /// Where the capture lived before the first optimize; restoring writes back here.
    let originalURL: URL
    let byteCount: Int?
  }

  private var originals: [UUID: Original] = [:]
  private var appliedStates: [UUID: AppliedState] = [:]
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

  /// Fraction on disk, `1` when untouched, nil when custom settings produced the file.
  func currentFraction(for itemID: UUID) -> CGFloat? {
    switch appliedStates[itemID] {
    case .none: 1
    case let .level(fraction): fraction
    case .custom: nil
    }
  }

  /// The levels for `item`, read from the file header only (cheap enough for a menu).
  func plan(for item: QuickAccessItem) -> QuickAccessOptimizePlan? {
    guard let source = customSource(for: item) else { return nil }
    return QuickAccessOptimizePlan(
      source: source.info,
      levels: QuickAccessImageOptimizer.levels(for: source.info),
      currentFraction: currentFraction(for: item.id),
      originalByteCount: source.originalByteCount,
      fileExtension: source.originalExtension
    )
  }

  /// The untouched source for `item` (its backup once optimized), header only.
  func customSource(for item: QuickAccessItem) -> QuickAccessOptimizeCustomSource? {
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
    return QuickAccessOptimizeCustomSource(
      sourceURL: sourceURL,
      info: info,
      originalExtension: (original?.originalURL ?? item.url).pathExtension.lowercased(),
      originalByteCount: original?.byteCount ?? Self.byteCount(at: sourceURL)
    )
  }

  /// Decodes the untouched pixels off the main actor.
  nonisolated static func loadImage(of source: QuickAccessOptimizeCustomSource) async -> CGImage? {
    let url = source.sourceURL
    let access = await SandboxFileAccessManager.shared.beginAccessingURL(url)
    return await Task.detached(priority: .userInitiated) {
      defer { access.stop() }
      return QuickAccessImageOptimizer.loadImage(at: url)
    }.value
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

  /// Writes `request` over the capture's file. Picking the original level restores
  /// the untouched bytes; a format change renames the file and follows it in the
  /// card and capture history.
  func apply(_ request: QuickAccessOptimizeRequest, to itemID: UUID) async throws {
    let manager = QuickAccessManager.shared
    guard let item = manager.items.first(where: { $0.id == itemID }), canOptimize(item) else {
      throw OptimizeError.unsupportedFile
    }
    if case let .level(level, _) = request, currentFraction(for: itemID) == level.fraction { return }
    guard !inFlightItemIDs.contains(itemID) else { return }

    inFlightItemIDs.insert(itemID)
    manager.updateProcessingState(id: itemID, state: .processing(progress: nil))
    defer {
      inFlightItemIDs.remove(itemID)
      manager.updateProcessingState(id: itemID, state: .idle)
    }

    let currentURL = item.url
    let originalURL = originals[itemID]?.originalURL ?? currentURL
    let originalExtension = originalURL.pathExtension.lowercased()
    let data: Data
    let fileExtension: String
    let state: AppliedState
    let logContext: [String: String]

    switch request {
    case let .level(level, encodedData):
      fileExtension = originalExtension
      state = .level(level.fraction)
      logContext = ["fraction": "\(level.fraction)", "pixels": level.dimensionsLabel]
      if level.isOriginal {
        guard let original = originals[itemID] else { return }
        data = try Data(contentsOf: original.backupURL)
      } else if let encodedData {
        data = encodedData
      } else {
        let sourceURL = originals[itemID]?.backupURL ?? currentURL
        let access = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
        let rendered: Result<Data, OptimizeError> = await Task.detached(priority: .userInitiated) {
          defer { access.stop() }
          guard let image = QuickAccessImageOptimizer.loadImage(at: sourceURL) else {
            return .failure(.unreadableSource)
          }
          guard let data = QuickAccessImageOptimizer.render(level, from: image, fileExtension: originalExtension) else {
            return .failure(.encodingFailed)
          }
          return .success(data)
        }.value
        data = try rendered.get()
      }

    case let .custom(settings, rendering):
      let result: QuickAccessOptimizeRendering
      if let rendering {
        result = rendering
      } else {
        guard let source = customSource(for: item) else { throw OptimizeError.unreadableSource }
        guard let image = await Self.loadImage(of: source) else { throw OptimizeError.unreadableSource }
        let rendered = await Task.detached(priority: .userInitiated) {
          QuickAccessImageOptimizer.render(
            settings,
            from: image,
            source: source.info,
            originalExtension: source.originalExtension
          )
        }.value
        guard let rendered else { throw OptimizeError.encodingFailed }
        result = rendered
      }
      data = result.data
      fileExtension = result.fileExtension
      state = .custom(settings.clamped)
      logContext = [
        "settings": settings.summary(originalExtension: originalExtension),
        "pixels": result.dimensionsLabel,
        "metLimit": "\(result.meetsFileSizeLimit)",
      ]
    }

    if originals[itemID] == nil {
      try preserveOriginal(of: currentURL, for: itemID)
    }

    let targetURL = destinationURL(
      forExtension: fileExtension,
      originalURL: originalURL,
      currentURL: currentURL
    )
    try SandboxFileAccessManager.shared.withScopedAccess(to: targetURL.deletingLastPathComponent()) {
      try data.write(to: targetURL, options: .atomic)
      if targetURL != currentURL {
        try? fileManager.removeItem(at: currentURL)
      }
    }

    if targetURL != currentURL {
      manager.updateItemURL(id: itemID, newURL: targetURL)
      CaptureHistoryStore.shared.updateFilePath(from: currentURL.path, to: targetURL.path)
    }

    appliedStates[itemID] = state
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
      context: logContext.merging([
        "itemId": itemID.uuidString,
        "bytes": "\(data.count)",
        "format": fileExtension,
      ]) { current, _ in current }
    )
  }

  /// Fire-and-forget entry point for UI callers: failures are logged and surfaced
  /// as a toast instead of being thrown back into a menu or button action.
  func applyReportingFailure(_ request: QuickAccessOptimizeRequest, to itemID: UUID) {
    Task { @MainActor in
      do {
        try await apply(request, to: itemID)
      } catch {
        DiagnosticLogger.shared.logError(
          .action,
          error,
          "Quick access optimize failed",
          context: ["itemId": itemID.uuidString]
        )
        QuickAccessSound.failed.play()
        AppToastManager.shared.show(message: L10n.QuickAccess.optimizeFailed, style: .error)
      }
    }
  }

  /// Same folder and name as the original, with the output's extension. Another
  /// file already sitting there is never overwritten; a numbered name is used instead.
  private func destinationURL(forExtension fileExtension: String, originalURL: URL, currentURL: URL) -> URL {
    if fileExtension == originalURL.pathExtension.lowercased() { return originalURL }
    let base = originalURL.deletingPathExtension()
    var candidate = base.appendingPathExtension(fileExtension)
    var counter = 2
    while candidate != currentURL, fileManager.fileExists(atPath: candidate.path) {
      candidate = base.deletingLastPathComponent()
        .appendingPathComponent("\(base.lastPathComponent) \(counter)")
        .appendingPathExtension(fileExtension)
      counter += 1
    }
    return candidate
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
    originals[itemID] = Original(
      backupURL: backupURL,
      originalURL: url,
      byteCount: Self.byteCount(at: backupURL)
    )
  }

  private func discard(itemID: UUID) {
    appliedStates.removeValue(forKey: itemID)
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
        let tracked = Set(self.originals.keys).union(self.appliedStates.keys)
        for staleID in tracked.subtracting(liveIDs) {
          self.discard(itemID: staleID)
        }
      }
  }

  private static func byteCount(at url: URL) -> Int? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
  }
}
