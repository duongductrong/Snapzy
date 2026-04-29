//
//  QuickAccessManager.swift
//  Snapzy
//
//  State management for quick access screenshot stack
//

import AppKit
import Combine
import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "Snapzy", category: "QuickAccessManager")

/// Manages the quick access screenshot preview stack
@MainActor
final class QuickAccessManager: ObservableObject {

  static let shared = QuickAccessManager()

  // MARK: - Published State

  @Published private(set) var items: [QuickAccessItem] = []
  @Published var position: QuickAccessPosition = .bottomRight {
    didSet {
      UserDefaults.standard.set(position.rawValue, forKey: Keys.position)
      panelController.updatePosition(position)
    }
  }
  @Published var isEnabled: Bool = true {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
      if !isEnabled {
        dismissAll()
      }
    }
  }
  @Published var autoDismissEnabled: Bool = true {
    didSet {
      UserDefaults.standard.set(autoDismissEnabled, forKey: Keys.autoDismissEnabled)
    }
  }
  @Published var autoDismissDelay: TimeInterval = 10 {
    didSet {
      UserDefaults.standard.set(autoDismissDelay, forKey: Keys.autoDismissDelay)
    }
  }
  @Published var overlayScale: Double = 1.0 {
    didSet {
      UserDefaults.standard.set(overlayScale, forKey: Keys.overlayScale)
      // Live-resize panel when slider changes
      if panelController.isVisible {
        panelController.updateSize(calculateMaxPanelSize())
      }
    }
  }
  @Published var dragDropEnabled: Bool = true {
    didSet {
      UserDefaults.standard.set(dragDropEnabled, forKey: Keys.dragDropEnabled)
    }
  }
  @Published var pauseCountdownOnHover: Bool = true {
    didSet {
      UserDefaults.standard.set(pauseCountdownOnHover, forKey: Keys.pauseCountdownOnHover)
    }
  }
  // MARK: - Configuration

  let maxVisibleItems = 5

  // MARK: - Private

  private let panelController = QuickAccessPanelController()
  private let fileAccessManager = SandboxFileAccessManager.shared
  private let tempCaptureManager = TempCaptureManager.shared
  private var dismissTimers: [UUID: QuickAccessCountdownTimer] = [:]
  /// Tracks which item IDs are currently being edited (paused by editor)
  private var editingItemIds: Set<UUID> = []
  /// Tracks items doing async work, such as GIF conversion or cloud upload.
  private var activityHoldItemIds: Set<UUID> = []

  // MARK: - UserDefaults Keys (preserved for backward compatibility)

  private enum Keys {
    static let enabled = "floatingScreenshot.enabled"
    static let position = "floatingScreenshot.position"
    static let autoDismissEnabled = "floatingScreenshot.autoDismissEnabled"
    static let autoDismissDelay = "floatingScreenshot.autoDismissDelay"
    static let overlayScale = "floatingScreenshot.overlayScale"
    static let dragDropEnabled = "floatingScreenshot.dragDropEnabled"
    static let pauseCountdownOnHover = "floatingScreenshot.pauseCountdownOnHover"
  }

  // MARK: - Init

  private init() {
    loadSettings()
  }

  private func loadSettings() {
    isEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true

    if let positionRaw = UserDefaults.standard.string(forKey: Keys.position),
      let savedPosition = QuickAccessPosition(rawValue: positionRaw)
    {
      position = savedPosition
    }

    autoDismissEnabled =
      UserDefaults.standard.object(forKey: Keys.autoDismissEnabled) as? Bool ?? true
    autoDismissDelay =
      UserDefaults.standard.object(forKey: Keys.autoDismissDelay) as? Double ?? 10
    overlayScale =
      UserDefaults.standard.object(forKey: Keys.overlayScale) as? Double ?? 1.0
    dragDropEnabled =
      UserDefaults.standard.object(forKey: Keys.dragDropEnabled) as? Bool ?? true
    pauseCountdownOnHover =
      UserDefaults.standard.object(forKey: Keys.pauseCountdownOnHover) as? Bool ?? true
    DiagnosticLogger.shared.log(
      .debug,
      .ui,
      "Quick access settings loaded",
      context: [
        "enabled": isEnabled ? "true" : "false",
        "position": position.rawValue,
        "autoDismiss": autoDismissEnabled ? "true" : "false",
        "delay": "\(autoDismissDelay)",
      ]
    )
  }

  // MARK: - Public Methods

  /// Add a new screenshot to the quick access stack
  func addScreenshot(url: URL) async {
    guard isEnabled else {
      DiagnosticLogger.shared.log(
        .debug,
        .action,
        "Quick access screenshot skipped; feature disabled",
        context: ["fileName": url.lastPathComponent]
      )
      return
    }
    let fileAccess = fileAccessManager.beginAccessingURL(url)
    defer { fileAccess.stop() }
    let result = await ThumbnailGenerator.generate(from: url)

    // Use placeholder if thumbnail generation failed
    let thumbnail: NSImage
    let needsRetry: Bool
    if let generated = result.thumbnail {
      thumbnail = generated
      needsRetry = false
    } else {
      logger.warning("Thumbnail failed for \(url.lastPathComponent), using placeholder")
      DiagnosticLogger.shared.log(
        .warning,
        .ui,
        "Quick access screenshot thumbnail failed; using placeholder",
        context: ["fileName": url.lastPathComponent]
      )
      thumbnail = ThumbnailGenerator.placeholderThumbnail()
      needsRetry = true
    }

    let item = QuickAccessItem(url: url, thumbnail: thumbnail)

    // Animate insertion explicitly — no implicit .animation on the stack
    let wasEmpty = items.isEmpty
    withAnimation(QuickAccessAnimations.cardInsert) {
      if items.count >= maxVisibleItems, let oldestId = items.last?.id {
        cancelDismissTimer(for: oldestId)
        items.removeLast()
        DiagnosticLogger.shared.log(
          .debug,
          .ui,
          "Quick access trimmed oldest item",
          context: ["maxVisibleItems": "\(maxVisibleItems)"]
        )
      }
      items.insert(item, at: 0)
    }
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access screenshot added",
      context: ["fileName": url.lastPathComponent, "itemCount": "\(items.count)"]
    )

    // Show panel if this is first item
    if wasEmpty {
      showPanel()
    }

    // Start auto-dismiss timer
    if autoDismissEnabled {
      startDismissTimer(for: item.id)
    }

    // Schedule background thumbnail retry if needed
    if needsRetry {
      scheduleThumbnailRetry(for: item.id, url: url)
    }
  }

  /// Add a new video recording to the quick access stack
  func addVideo(url: URL) async {
    guard isEnabled else {
      DiagnosticLogger.shared.log(
        .debug,
        .action,
        "Quick access video skipped; feature disabled",
        context: ["fileName": url.lastPathComponent]
      )
      return
    }
    let fileAccess = fileAccessManager.beginAccessingURL(url)
    defer { fileAccess.stop() }
    let result = await ThumbnailGenerator.generate(from: url)

    // Use placeholder if thumbnail generation failed
    let thumbnail: NSImage
    let needsRetry: Bool
    if let generated = result.thumbnail {
      thumbnail = generated
      needsRetry = false
    } else {
      logger.warning("Video thumbnail failed for \(url.lastPathComponent), using placeholder")
      DiagnosticLogger.shared.log(
        .warning,
        .ui,
        "Quick access video thumbnail failed; using placeholder",
        context: ["fileName": url.lastPathComponent]
      )
      thumbnail = ThumbnailGenerator.placeholderThumbnail()
      needsRetry = true
    }

    // Use actual duration or nil (will show no badge if duration unavailable)
    let item = QuickAccessItem(url: url, thumbnail: thumbnail, duration: result.duration ?? 0)

    // Animate insertion explicitly — no implicit .animation on the stack
    let wasEmpty = items.isEmpty
    withAnimation(QuickAccessAnimations.cardInsert) {
      if items.count >= maxVisibleItems, let oldestId = items.last?.id {
        cancelDismissTimer(for: oldestId)
        items.removeLast()
        DiagnosticLogger.shared.log(
          .debug,
          .ui,
          "Quick access trimmed oldest item",
          context: ["maxVisibleItems": "\(maxVisibleItems)"]
        )
      }
      items.insert(item, at: 0)
    }

    if wasEmpty {
      showPanel()
    }

    if autoDismissEnabled {
      startDismissTimer(for: item.id)
    }

    // Schedule background thumbnail retry if needed
    if needsRetry {
      scheduleThumbnailRetry(for: item.id, url: url)
    }
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access video added",
      context: [
        "fileName": url.lastPathComponent,
        "itemCount": "\(items.count)",
        "duration": "\(result.duration ?? 0)",
      ]
    )
  }

  /// Present a history record as a Quick Access card and return the session item.
  /// This intentionally restores through Quick Access even for manually opened
  /// history records, so editors get the same item-scoped save/session behavior
  /// as fresh captures.
  func restoreHistoryItem(_ record: CaptureHistoryRecord) async -> QuickAccessItem? {
    let url = record.fileURL

    if let existingItem = item(matching: url) {
      showPanelIfNeeded()
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "History restore reused quick access item",
        context: [
          "fileName": record.fileName,
          "type": record.captureType.rawValue,
          "itemId": existingItem.id.uuidString,
        ]
      )
      return existingItem
    }

    let fileAccess = fileAccessManager.beginAccessingURL(url)
    defer { fileAccess.stop() }

    guard FileManager.default.fileExists(atPath: url.path) else {
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "History restore skipped; file missing",
        context: ["fileName": record.fileName, "type": record.captureType.rawValue]
      )
      return nil
    }

    let result = await ThumbnailGenerator.generate(from: url)
    let thumbnail: NSImage
    let needsRetry: Bool
    if let generated = result.thumbnail {
      thumbnail = generated
      needsRetry = false
    } else {
      thumbnail = ThumbnailGenerator.placeholderThumbnail()
      needsRetry = true
      DiagnosticLogger.shared.log(
        .warning,
        .ui,
        "History restore thumbnail failed; using placeholder",
        context: ["fileName": record.fileName, "type": record.captureType.rawValue]
      )
    }

    let item: QuickAccessItem
    switch record.captureType {
    case .screenshot:
      item = QuickAccessItem(
        id: UUID(),
        url: url,
        thumbnail: thumbnail,
        capturedAt: record.capturedAt,
        itemType: .screenshot,
        duration: nil
      )
    case .video, .gif:
      item = QuickAccessItem(
        id: UUID(),
        url: url,
        thumbnail: thumbnail,
        capturedAt: record.capturedAt,
        itemType: .video,
        duration: record.duration ?? result.duration ?? 0
      )
    }

    insertRestoredHistoryItem(item, needsRetry: needsRetry, retryURL: url)
    DiagnosticLogger.shared.log(
      .info,
      .history,
      "History restored into quick access",
      context: [
        "fileName": record.fileName,
        "type": record.captureType.rawValue,
        "itemId": item.id.uuidString,
      ]
    )
    return item
  }

  /// Remove an item (screenshot or video) from the stack
  func removeItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else {
      cancelDismissTimer(for: id)
      editingItemIds.remove(id)
      activityHoldItemIds.remove(id)
      DiagnosticLogger.shared.log(
        .debug,
        .action,
        "Quick access remove requested for missing item",
        context: ["itemId": id.uuidString]
      )
      return
    }

    // Auto-delete temp files on dismiss (unsaved captures)
    // Skip deletion if history is enabled and the file has a history record —
    // the retention service will clean it up when the record ages out.
    if tempCaptureManager.isTempFile(item.url) {
      let url = item.url
      let historyEnabled = UserDefaults.standard.bool(forKey: PreferencesKeys.historyEnabled)
      let hasHistoryRecord = historyEnabled && CaptureHistoryStore.shared.hasRecord(forFilePath: url.path)

      if hasHistoryRecord {
        DiagnosticLogger.shared.log(
          .info,
          .action,
          "Quick access item dismissed; temp file preserved for history",
          context: ["fileName": url.lastPathComponent]
        )
      } else {
        DiagnosticLogger.shared.log(
          .info,
          .action,
          "Quick access item dismissed; temp file auto-delete requested",
          context: ["fileName": url.lastPathComponent]
        )
        Task { @MainActor in
          tempCaptureManager.deleteTempFile(at: url)
        }
      }
    } else {
      DiagnosticLogger.shared.log(
        .info,
        .action,
        "Quick access item dismissed; saved file retained",
        context: ["fileName": item.url.lastPathComponent]
      )
    }

    cancelDismissTimer(for: id)
    editingItemIds.remove(id)
    activityHoldItemIds.remove(id)
    // Clear annotation session cache for this item
    AnnotateManager.shared.clearSessionData(for: id)
    // Fast animation (0.15s) for immediate perceived response
    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
      items.removeAll { $0.id == id }
    }

    if items.isEmpty {
      panelController.hide()
    }
  }

  /// Remove a screenshot from the stack (backward compatible alias)
  func removeScreenshot(id: UUID) {
    removeItem(id: id)
  }

  /// Remove card from UI only — does NOT delete the underlying file.
  /// Used after drag-to-app so the receiving app can still read the file.
  /// Orphaned temp files get cleaned up on next launch via cleanupOrphanedFiles().
  func dismissCard(id: UUID) {
    DiagnosticLogger.shared.log(
      .debug,
      .action,
      "Quick access card dismissed without deleting file",
      context: ["itemId": id.uuidString]
    )
    cancelDismissTimer(for: id)
    editingItemIds.remove(id)
    activityHoldItemIds.remove(id)
    // Clear annotation session cache for this item
    AnnotateManager.shared.clearSessionData(for: id)
    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
      items.removeAll { $0.id == id }
    }
    if items.isEmpty {
      panelController.hide()
    }
  }

  /// Update processing state for an item (used during GIF conversion)
  func updateProcessingState(id: UUID, state: QuickAccessProcessingState) {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Quick access processing state update missed item",
        context: ["itemId": id.uuidString, "state": "\(state)"]
      )
      return
    }
    items[index].processingState = state
    DiagnosticLogger.shared.log(
      .debug,
      .action,
      "Quick access processing state changed",
      context: ["itemId": id.uuidString, "state": "\(state)"]
    )
    if state == .idle {
      resumeCountdownForActivity(id)
    } else {
      pauseCountdownForActivity(id)
    }
  }

  /// Replace item URL and thumbnail after processing (e.g. GIF conversion)
  func updateItemURL(id: UUID, newURL: URL, newThumbnail: NSImage? = nil) {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Quick access item URL update missed item",
        context: ["itemId": id.uuidString, "fileName": newURL.lastPathComponent]
      )
      return
    }
    let existing = items[index]
    let thumbnail = newThumbnail ?? existing.thumbnail
    items[index] = QuickAccessItem(
      id: existing.id,
      url: newURL,
      thumbnail: thumbnail,
      capturedAt: existing.capturedAt,
      itemType: existing.itemType,
      duration: existing.duration,
      cloudURL: existing.cloudURL,
      cloudKey: existing.cloudKey,
      isCloudStale: existing.isCloudStale
    )
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access item URL updated",
      context: ["itemId": id.uuidString, "fileName": newURL.lastPathComponent]
    )
  }

  /// Update thumbnail directly from an already-rendered image (synchronous, instant)
  /// Used after annotation save — avoids the slow ThumbnailGenerator pipeline.
  /// Preserves existing isCloudStale — callers should use markCloudStale(id:) if needed.
  func updateItemThumbnail(id: UUID, image: NSImage) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let existing = items[index]
    let maxSize: CGFloat = 200
    let thumbnail = scaleThumbnail(image, maxSize: maxSize)
    items[index] = QuickAccessItem(
      id: existing.id,
      url: existing.url,
      thumbnail: thumbnail,
      capturedAt: existing.capturedAt,
      itemType: existing.itemType,
      duration: existing.duration,
      cloudURL: existing.cloudURL,
      cloudKey: existing.cloudKey,
      isCloudStale: existing.isCloudStale
    )
    logger.info("Thumbnail updated directly for item \(id)")
  }

  /// Scale image to thumbnail size (synchronous, no file I/O)
  private func scaleThumbnail(_ image: NSImage, maxSize: CGFloat) -> NSImage {
    let originalSize = image.size
    guard originalSize.width > 0, originalSize.height > 0 else { return image }

    let scale: CGFloat
    if originalSize.width > originalSize.height {
      scale = min(maxSize / originalSize.width, 1.0)
    } else {
      scale = min(maxSize / originalSize.height, 1.0)
    }
    if scale >= 1.0 { return image }

    let newSize = CGSize(
      width: originalSize.width * scale,
      height: originalSize.height * scale
    )
    let thumbnail = NSImage(size: newSize)
    thumbnail.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: originalSize),
      operation: .copy,
      fraction: 1.0
    )
    thumbnail.unlockFocus()
    return thumbnail
  }

  /// Refresh thumbnail for an item after its image was updated on disk (e.g. annotation saved)
  func refreshItemThumbnail(id: UUID) async {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .debug,
        .ui,
        "Quick access thumbnail refresh skipped; item missing",
        context: ["itemId": id.uuidString]
      )
      return
    }
    let url = items[index].url
    let fileAccess = fileAccessManager.beginAccessingURL(url)
    defer { fileAccess.stop() }
    let result = await ThumbnailGenerator.generate(from: url)
    guard let newThumbnail = result.thumbnail else {
      logger.warning("Thumbnail refresh failed for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(
        .warning,
        .ui,
        "Quick access thumbnail refresh failed",
        context: ["fileName": url.lastPathComponent]
      )
      return
    }
    // Re-check index (item may have been removed during async thumbnail generation)
    guard let freshIndex = items.firstIndex(where: { $0.id == id }) else { return }
    let existing = items[freshIndex]
    items[freshIndex] = QuickAccessItem(
      id: existing.id,
      url: existing.url,
      thumbnail: newThumbnail,
      capturedAt: existing.capturedAt,
      itemType: existing.itemType,
      duration: existing.duration,
      cloudURL: existing.cloudURL,
      cloudKey: existing.cloudKey,
      isCloudStale: existing.isCloudStale
    )
    logger.info("Thumbnail refreshed for \(url.lastPathComponent)")
    DiagnosticLogger.shared.log(
      .debug,
      .ui,
      "Quick access thumbnail refreshed",
      context: ["fileName": url.lastPathComponent]
    )
  }

  /// Dismiss all screenshots
  func dismissAll() {
    let count = items.count
    for item in items {
      cancelDismissTimer(for: item.id)
      // Clear annotation session cache
      AnnotateManager.shared.clearSessionData(for: item.id)
    }
    items.removeAll()
    editingItemIds.removeAll()
    activityHoldItemIds.removeAll()
    panelController.hide()
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access dismissed all items",
      context: ["itemCount": "\(count)"]
    )
  }

  /// Copy item to clipboard (cloud link if available, otherwise image or video file URL)
  func copyToClipboard(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .clipboard,
        "Quick access clipboard copy missed item",
        context: ["itemId": id.uuidString]
      )
      return
    }

    // If cloud URL is available, copy the cloud link as text
    if let cloudURL = item.cloudURL {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(cloudURL.absoluteString, forType: .string)
      DiagnosticLogger.shared.log(
        .info,
        .clipboard,
        "Quick access copied cloud link to clipboard",
        context: ["fileName": item.url.lastPathComponent]
      )
      dismissCard(id: id)
      SoundManager.play("Pop")
      return
    }

    let url = item.url
    let isVideo = item.isVideo

    // Load data and write to clipboard BEFORE removing the card.
    // removeItem/removeScreenshot deletes temp files, which would cause
    // reads to fail if done after removal.
    if isVideo {
      let fileAccess = fileAccessManager.beginAccessingURL(url)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([url as NSURL])
      fileAccess.stop()
      DiagnosticLogger.shared.log(
        .info,
        .clipboard,
        "Quick access copied video file to clipboard",
        context: ["fileName": url.lastPathComponent]
      )
    } else {
      ClipboardHelper.copyImage(from: url)
      DiagnosticLogger.shared.log(
        .info,
        .clipboard,
        "Quick access copied image to clipboard",
        context: ["fileName": url.lastPathComponent]
      )
    }

    // Remove card from UI without deleting the temp file (same as drag-to-app).
    dismissCard(id: id)

    // File-based clipboard: the file must stay on disk so the receiving app
    // can read it at paste time. Orphaned temp files are cleaned on next launch.

    SoundManager.play("Pop")
  }

  /// Delete item from disk and remove from stack
  func deleteItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Quick access delete missed item",
        context: ["itemId": id.uuidString]
      )
      return
    }

    let url = item.url
    let isTempFile = tempCaptureManager.isTempFile(url)
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access delete requested",
      context: ["fileName": url.lastPathComponent, "temp": isTempFile ? "true" : "false"]
    )
    removeItem(id: id)

    // removeItem already handles temp file deletion,
    // for non-temp files we need to trash them
    if !isTempFile {
      Task { @MainActor in
        let fileAccess = fileAccessManager.beginAccessingURL(url)
        let directoryAccess = fileAccessManager.beginAccessingURL(url.deletingLastPathComponent())
        defer { fileAccess.stop() }
        defer { directoryAccess.stop() }

        do {
          try FileManager.default.trashItem(at: url, resultingItemURL: nil)
          if item.isVideo {
            try? RecordingMetadataStore.delete(for: url)
          }
        } catch {
          logger.error("Failed to delete item \(url.lastPathComponent): \(error.localizedDescription)")
          DiagnosticLogger.shared.logError(
            .fileAccess,
            error,
            "Quick access delete failed",
            context: ["fileName": url.lastPathComponent]
          )
        }
      }
    }
  }

  /// Open screenshot in Finder
  func openInFinder(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Quick access reveal in Finder missed item",
        context: ["itemId": id.uuidString]
      )
      return
    }

    // Capture URL before removal
    let url = item.url

    // Remove immediately - animation starts now
    removeScreenshot(id: id)

    // Async Finder reveal
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access reveal in Finder requested",
      context: ["fileName": url.lastPathComponent]
    )
    Task { @MainActor in
      let fileAccess = fileAccessManager.beginAccessingURL(url)
      defer { fileAccess.stop() }
      NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
  }

  /// Save a temp capture file to the permanent export location, then reveal in Finder
  func saveItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Quick access save missed item",
        context: ["itemId": id.uuidString]
      )
      return
    }
    let tempURL = item.url
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Quick access manual save requested",
      context: ["fileName": tempURL.lastPathComponent]
    )

    // Remove card immediately (don't trigger temp file deletion since we're saving)
    cancelDismissTimer(for: id)
    editingItemIds.remove(id)
    activityHoldItemIds.remove(id)
    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
      items.removeAll { $0.id == id }
    }
    if items.isEmpty {
      panelController.hide()
    }

    // Move file from temp to export location
    Task { @MainActor in
      if let savedURL = tempCaptureManager.saveToExportLocation(tempURL: tempURL) {
        // Update history records by original file path. QuickAccess item IDs are
        // independent from persisted history record IDs.
        CaptureHistoryStore.shared.updateFilePath(
          from: tempURL.path,
          to: savedURL.path
        )

        let captureType: CaptureType = item.isVideo ? .recording : .screenshot
        PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: captureType,
          url: savedURL
        )

        let fileAccess = fileAccessManager.beginAccessingURL(savedURL)
        defer { fileAccess.stop() }
        NSWorkspace.shared.selectFile(savedURL.path, inFileViewerRootedAtPath: "")
        DiagnosticLogger.shared.log(
          .info,
          .action,
          "Quick access manual save completed",
          context: ["fileName": savedURL.lastPathComponent]
        )
      } else {
        DiagnosticLogger.shared.log(
          .error,
          .fileAccess,
          "Quick access manual save failed",
          context: ["fileName": tempURL.lastPathComponent]
        )
      }
    }
  }

  /// Update position setting
  func setPosition(_ newPosition: QuickAccessPosition) {
    position = newPosition
    DiagnosticLogger.shared.log(
      .info,
      .preferences,
      "Quick access position changed",
      context: ["position": newPosition.rawValue]
    )
  }

  // MARK: - Private Methods

  private func showPanel() {
    let stackView = QuickAccessStackView(manager: self)
    let size = calculateMaxPanelSize()
    panelController.show(stackView, size: size)
    DiagnosticLogger.shared.log(
      .debug,
      .ui,
      "Quick access panel shown",
      context: ["itemCount": "\(items.count)"]
    )
  }

  private func showPanelIfNeeded() {
    guard !panelController.isVisible else { return }
    showPanel()
  }

  private func item(matching url: URL) -> QuickAccessItem? {
    let standardizedURL = url.standardizedFileURL
    return items.first { $0.url.standardizedFileURL == standardizedURL }
  }

  private func insertRestoredHistoryItem(
    _ item: QuickAccessItem,
    needsRetry: Bool,
    retryURL: URL
  ) {
    withAnimation(QuickAccessAnimations.cardInsert) {
      if items.count >= maxVisibleItems, let oldestId = items.last?.id {
        cancelDismissTimer(for: oldestId)
        items.removeLast()
        DiagnosticLogger.shared.log(
          .debug,
          .ui,
          "Quick access trimmed oldest item for history restore",
          context: ["maxVisibleItems": "\(maxVisibleItems)"]
        )
      }
      items.insert(item, at: 0)
    }

    showPanelIfNeeded()

    if autoDismissEnabled {
      startDismissTimer(for: item.id)
    }

    if needsRetry {
      scheduleThumbnailRetry(for: item.id, url: retryURL)
    }
  }

  /// Fixed max-size panel — never resizes, prevents SwiftUI re-layout jitter
  private func calculateMaxPanelSize() -> CGSize {
    let itemCount = maxVisibleItems
    let scale = CGFloat(overlayScale)
    let cardW = QuickAccessLayout.scaledCardWidth(scale)
    let cardH = QuickAccessLayout.scaledCardHeight(scale)
    let height =
      CGFloat(itemCount) * cardH
      + CGFloat(itemCount - 1) * QuickAccessLayout.cardSpacing
      + QuickAccessLayout.containerPadding * 2
    let width = cardW + QuickAccessLayout.containerPadding * 2
    return CGSize(width: width, height: height)
  }

  private func startDismissTimer(for id: UUID) {
    let delay = autoDismissDelay
    let timer = QuickAccessCountdownTimer(duration: delay) { [weak self] in
      self?.removeScreenshot(id: id)
    }
    dismissTimers[id] = timer
    timer.start()

    if isItemCountdownHeld(id) {
      timer.pause()
    }
  }

  private func cancelDismissTimer(for id: UUID) {
    dismissTimers[id]?.cancel()
    dismissTimers.removeValue(forKey: id)
  }

  // MARK: - Pause / Resume Countdown

  /// Pause countdown for a single item (used by hover)
  func pauseCountdown(for id: UUID) {
    dismissTimers[id]?.pause()
  }

  /// Resume countdown for a single item (used by hover un-hover)
  func resumeCountdown(for id: UUID) {
    // Don't resume if an editor, upload, or conversion still owns the countdown.
    guard !isItemCountdownHeld(id) else { return }
    dismissTimers[id]?.resume()
  }

  /// Pause countdown while an async activity is running for an item.
  func pauseCountdownForActivity(_ id: UUID) {
    activityHoldItemIds.insert(id)
    dismissTimers[id]?.pause()
  }

  /// Resume countdown after an async activity finishes, unless another hold remains.
  func resumeCountdownForActivity(_ id: UUID) {
    activityHoldItemIds.remove(id)
    guard !isItemCountdownHeld(id) else { return }
    dismissTimers[id]?.resume()
  }

  private func isItemCountdownHeld(_ id: UUID) -> Bool {
    activityHoldItemIds.contains(id) || isItemPausedByEditing(id)
  }

  /// Check if an item should remain paused because of an active editing session.
  /// True if the item itself is being edited, OR if it's newer (above) than any edited item.
  private func isItemPausedByEditing(_ id: UUID) -> Bool {
    guard !editingItemIds.isEmpty else { return false }
    if editingItemIds.contains(id) { return true }
    guard let itemIndex = items.firstIndex(where: { $0.id == id }) else { return false }
    for editId in editingItemIds {
      if let editIndex = items.firstIndex(where: { $0.id == editId }), itemIndex < editIndex {
        return true
      }
    }
    return false
  }

  /// Pause countdown for an item being edited + all items captured after it (newer/above)
  func pauseCountdownForEditingItem(_ id: UUID) {
    editingItemIds.insert(id)
    guard let editIndex = items.firstIndex(where: { $0.id == id }) else { return }
    DiagnosticLogger.shared.log(
      .debug,
      .action,
      "Quick access countdown paused for editing",
      context: ["itemId": id.uuidString, "affectedCount": "\(editIndex + 1)"]
    )

    // Pause the edited item + items at lower indices (captured after, newer)
    for i in 0...editIndex {
      dismissTimers[items[i].id]?.pause()
    }
  }

  /// Resume countdown for an item done editing + all items captured after it (newer/above)
  func resumeCountdownForEditingItem(_ id: UUID) {
    editingItemIds.remove(id)
    DiagnosticLogger.shared.log(
      .debug,
      .action,
      "Quick access countdown resumed after editing",
      context: ["itemId": id.uuidString]
    )

    if let editIndex = items.firstIndex(where: { $0.id == id }) {
      // Item still exists — resume it + items at lower indices (newer)
      for i in 0...editIndex {
        let itemId = items[i].id
        guard !isItemCountdownHeld(itemId) else { continue }
        dismissTimers[itemId]?.resume()
      }
    } else {
      // Edited item was already removed (swiped/dismissed during editing).
      // Resume all remaining items that aren't held by another editor.
      for item in items {
        guard !isItemCountdownHeld(item.id) else { continue }
        dismissTimers[item.id]?.resume()
      }
    }
  }

  /// Retry thumbnail generation in background and update item if successful
  private func scheduleThumbnailRetry(for id: UUID, url: URL) {
    Task { @MainActor in
      // Wait 500ms then retry
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !Task.isCancelled else { return }
      guard items.contains(where: { $0.id == id }) else { return }

      let fileAccess = fileAccessManager.beginAccessingURL(url)
      defer { fileAccess.stop() }

      let result = await ThumbnailGenerator.generate(from: url)
      guard let newThumbnail = result.thumbnail else {
        logger.error("Thumbnail retry also failed for \(url.lastPathComponent)")
        DiagnosticLogger.shared.log(
          .error,
          .ui,
          "Quick access thumbnail retry failed",
          context: ["fileName": url.lastPathComponent]
        )
        return
      }

      if let index = items.firstIndex(where: { $0.id == id }) {
        let existing = items[index]
        items[index] = QuickAccessItem(
          id: existing.id,
          url: existing.url,
          thumbnail: newThumbnail,
          capturedAt: existing.capturedAt,
          itemType: existing.itemType,
          duration: existing.duration,
          cloudURL: existing.cloudURL,
          cloudKey: existing.cloudKey,
          isCloudStale: existing.isCloudStale
        )
        logger.info("Thumbnail retry succeeded for \(url.lastPathComponent)")
        DiagnosticLogger.shared.log(
          .debug,
          .ui,
          "Quick access thumbnail retry succeeded",
          context: ["fileName": url.lastPathComponent]
        )
      }
    }
  }

  /// Set cloud URL and key for an item after successful upload
  func setCloudURL(id: UUID, url: URL, key: String) {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "Quick access cloud URL update missed item",
        context: ["itemId": id.uuidString]
      )
      return
    }
    items[index].cloudURL = url
    items[index].cloudKey = key
    items[index].isCloudStale = false
    DiagnosticLogger.shared.log(
      .info,
      .cloud,
      "Quick access cloud URL attached",
      context: ["itemId": id.uuidString, "fileName": items[index].url.lastPathComponent]
    )
  }

  /// Mark an item's cloud state as stale (local differs from cloud)
  func markCloudStale(id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "Quick access cloud stale mark missed item",
        context: ["itemId": id.uuidString]
      )
      return
    }
    guard items[index].cloudURL != nil else { return }
    items[index].isCloudStale = true
    DiagnosticLogger.shared.log(
      .debug,
      .cloud,
      "Quick access cloud state marked stale",
      context: ["itemId": id.uuidString, "fileName": items[index].url.lastPathComponent]
    )
  }
}
