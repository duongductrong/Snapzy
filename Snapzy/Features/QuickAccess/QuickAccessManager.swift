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
  }

  // MARK: - Public Methods

  /// Add a new screenshot to the quick access stack
  func addScreenshot(url: URL) async {
    guard isEnabled else { return }
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
      }
      items.insert(item, at: 0)
    }

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
    guard isEnabled else { return }
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
  }

  /// Remove an item (screenshot or video) from the stack
  func removeItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else {
      cancelDismissTimer(for: id)
      editingItemIds.remove(id)
      return
    }

    // Auto-delete temp files on dismiss (unsaved captures)
    if tempCaptureManager.isTempFile(item.url) {
      let url = item.url
      DiagnosticLogger.shared.log(.info, .action, "[QuickAccess] Dismiss temp file (auto-delete): \(url.lastPathComponent)")
      print("[Snapzy:QuickAccess] Dismiss temp file (auto-delete): \(url.lastPathComponent)")
      Task { @MainActor in
        tempCaptureManager.deleteTempFile(at: url)
      }
    } else {
      DiagnosticLogger.shared.log(.info, .action, "[QuickAccess] Dismiss saved file: \(item.url.lastPathComponent)")
      print("[Snapzy:QuickAccess] Dismiss saved file: \(item.url.lastPathComponent)")
    }

    cancelDismissTimer(for: id)
    editingItemIds.remove(id)
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
    cancelDismissTimer(for: id)
    editingItemIds.remove(id)
    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
      items.removeAll { $0.id == id }
    }
    if items.isEmpty {
      panelController.hide()
    }
  }

  /// Update processing state for an item (used during GIF conversion)
  func updateProcessingState(id: UUID, state: QuickAccessProcessingState) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].processingState = state
  }

  /// Replace item URL and thumbnail after processing (e.g. GIF conversion)
  func updateItemURL(id: UUID, newURL: URL, newThumbnail: NSImage? = nil) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let existing = items[index]
    let thumbnail = newThumbnail ?? existing.thumbnail
    items[index] = QuickAccessItem(
      id: existing.id,
      url: newURL,
      thumbnail: thumbnail,
      capturedAt: existing.capturedAt,
      itemType: existing.itemType,
      duration: existing.duration
    )
  }

  /// Dismiss all screenshots
  func dismissAll() {
    for item in items {
      cancelDismissTimer(for: item.id)
    }
    items.removeAll()
    editingItemIds.removeAll()
    panelController.hide()
  }

  /// Copy item to clipboard (image or video file URL)
  func copyToClipboard(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }

    let url = item.url
    let isVideo = item.isVideo

    // Load data and write to clipboard BEFORE removing the card.
    // removeItem/removeScreenshot deletes temp files, which would cause
    // NSImage(contentsOf:) to fail if done after removal.
    let fileAccess = fileAccessManager.beginAccessingURL(url)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    if isVideo {
      pasteboard.writeObjects([url as NSURL])
    } else {
      if let image = NSImage(contentsOf: url) {
        pasteboard.writeObjects([image])
      } else {
        logger.error("Failed to load image for clipboard: \(url.lastPathComponent)")
      }
    }

    fileAccess.stop()

    // Remove card from UI without deleting the temp file (same as drag-to-app).
    dismissCard(id: id)

    // For images, clipboard holds pixel data in memory — safe to delete temp file.
    // For videos, clipboard holds a file URL reference — file must stay on disk
    // so the receiving app can read it. Orphaned temp files are cleaned on next launch.
    if !isVideo, tempCaptureManager.isTempFile(url) {
      tempCaptureManager.deleteTempFile(at: url)
    }

    NSSound(named: "Pop")?.play()
  }

  /// Delete item from disk and remove from stack
  func deleteItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }

    let url = item.url
    let isTempFile = tempCaptureManager.isTempFile(url)
    DiagnosticLogger.shared.log(.info, .action, "[QuickAccess] Delete item (temp=\(isTempFile)): \(url.lastPathComponent)")
    print("[Snapzy:QuickAccess] Delete item (temp=\(isTempFile)): \(url.lastPathComponent)")
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
        }
      }
    }
  }

  /// Open screenshot in Finder
  func openInFinder(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }

    // Capture URL before removal
    let url = item.url

    // Remove immediately - animation starts now
    removeScreenshot(id: id)

    // Async Finder reveal
    DiagnosticLogger.shared.log(.info, .action, "[QuickAccess] Open in Finder: \(url.lastPathComponent)")
    print("[Snapzy:QuickAccess] Open in Finder: \(url.lastPathComponent)")
    Task { @MainActor in
      let fileAccess = fileAccessManager.beginAccessingURL(url)
      defer { fileAccess.stop() }
      NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
  }

  /// Save a temp capture file to the permanent export location, then reveal in Finder
  func saveItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }
    let tempURL = item.url
    DiagnosticLogger.shared.log(.info, .action, "[QuickAccess] Manual save triggered: \(tempURL.lastPathComponent)")
    print("[Snapzy:QuickAccess] Manual save triggered: \(tempURL.lastPathComponent)")

    // Remove card immediately (don't trigger temp file deletion since we're saving)
    cancelDismissTimer(for: id)
    editingItemIds.remove(id)
    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
      items.removeAll { $0.id == id }
    }
    if items.isEmpty {
      panelController.hide()
    }

    // Move file from temp to export location
    Task { @MainActor in
      if let savedURL = tempCaptureManager.saveToExportLocation(tempURL: tempURL) {
        let fileAccess = fileAccessManager.beginAccessingURL(savedURL)
        defer { fileAccess.stop() }
        NSWorkspace.shared.selectFile(savedURL.path, inFileViewerRootedAtPath: "")
      }
    }
  }

  /// Update position setting
  func setPosition(_ newPosition: QuickAccessPosition) {
    position = newPosition
  }

  // MARK: - Private Methods

  private func showPanel() {
    let stackView = QuickAccessStackView(manager: self)
    let size = calculateMaxPanelSize()
    panelController.show(stackView, size: size)
  }

  /// Fixed max-size panel — never resizes, prevents SwiftUI re-layout jitter
  private func calculateMaxPanelSize() -> CGSize {
    let itemCount = maxVisibleItems
    let height =
      CGFloat(itemCount) * QuickAccessLayout.cardHeight
      + CGFloat(itemCount - 1) * QuickAccessLayout.cardSpacing
      + QuickAccessLayout.containerPadding * 2
    let width = QuickAccessLayout.cardWidth + QuickAccessLayout.containerPadding * 2
    return CGSize(width: width, height: height)
  }

  private func startDismissTimer(for id: UUID) {
    let delay = autoDismissDelay
    let timer = QuickAccessCountdownTimer(duration: delay) { [weak self] in
      self?.removeScreenshot(id: id)
    }
    dismissTimers[id] = timer
    timer.start()

    // If an edit session is active, pause this new card if it's newer than an edited item
    if !editingItemIds.isEmpty, let newIndex = items.firstIndex(where: { $0.id == id }) {
      for editId in editingItemIds {
        if let editIndex = items.firstIndex(where: { $0.id == editId }), newIndex < editIndex {
          timer.pause()
          break
        }
      }
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
    // Don't resume if the item should stay paused due to an active editing session
    guard !isItemPausedByEditing(id) else { return }
    dismissTimers[id]?.resume()
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

    // Pause the edited item + items at lower indices (captured after, newer)
    for i in 0...editIndex {
      dismissTimers[items[i].id]?.pause()
    }
  }

  /// Resume countdown for an item done editing + all items captured after it (newer/above)
  func resumeCountdownForEditingItem(_ id: UUID) {
    editingItemIds.remove(id)

    if let editIndex = items.firstIndex(where: { $0.id == id }) {
      // Item still exists — resume it + items at lower indices (newer)
      for i in 0...editIndex {
        let itemId = items[i].id
        guard !editingItemIds.contains(itemId) else { continue }
        dismissTimers[itemId]?.resume()
      }
    } else {
      // Edited item was already removed (swiped/dismissed during editing).
      // Resume all remaining items that aren't held by another editor.
      for item in items {
        guard !editingItemIds.contains(item.id) else { continue }
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
          duration: existing.duration
        )
        logger.info("Thumbnail retry succeeded for \(url.lastPathComponent)")
      }
    }
  }
}
