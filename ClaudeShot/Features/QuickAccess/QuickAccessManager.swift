//
//  QuickAccessManager.swift
//  ClaudeShot
//
//  State management for quick access screenshot stack
//

import AppKit
import Combine
import Foundation
import SwiftUI

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
  @Published var showCloudUpload: Bool = true {
    didSet {
      UserDefaults.standard.set(showCloudUpload, forKey: Keys.showCloudUpload)
    }
  }

  // MARK: - Configuration

  let maxVisibleItems = 5

  // MARK: - Private

  private let panelController = QuickAccessPanelController()
  private var dismissTimers: [UUID: Task<Void, Never>] = [:]
  private var cancellables = Set<AnyCancellable>()

  // MARK: - UserDefaults Keys (preserved for backward compatibility)

  private enum Keys {
    static let enabled = "floatingScreenshot.enabled"
    static let position = "floatingScreenshot.position"
    static let autoDismissEnabled = "floatingScreenshot.autoDismissEnabled"
    static let autoDismissDelay = "floatingScreenshot.autoDismissDelay"
    static let overlayScale = "floatingScreenshot.overlayScale"
    static let dragDropEnabled = "floatingScreenshot.dragDropEnabled"
    static let showCloudUpload = "floatingScreenshot.showCloudUpload"
  }

  // MARK: - Init

  private init() {
    loadSettings()
    setupBindings()
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
    showCloudUpload =
      UserDefaults.standard.object(forKey: Keys.showCloudUpload) as? Bool ?? true
  }

  private func setupBindings() {
    // Update panel size when items change
    $items
      .receive(on: DispatchQueue.main)
      .sink { [weak self] items in
        self?.updatePanelSize()
      }
      .store(in: &cancellables)
  }

  // MARK: - Public Methods

  /// Add a new screenshot to the quick access stack
  func addScreenshot(url: URL) async {
    guard isEnabled else { return }
    let result = await ThumbnailGenerator.generate(from: url)
    guard let thumbnail = result.thumbnail else { return }

    let item = QuickAccessItem(url: url, thumbnail: thumbnail)

    // Remove oldest if at max capacity (oldest is now at the end)
    if items.count >= maxVisibleItems {
      if let oldestId = items.last?.id {
        removeScreenshot(id: oldestId)
      }
    }

    let wasEmpty = items.isEmpty
    items.insert(item, at: 0)

    // Show panel if this is first item
    if wasEmpty {
      showPanel()
    }

    // Start auto-dismiss timer
    if autoDismissEnabled {
      startDismissTimer(for: item.id)
    }
  }

  /// Add a new video recording to the quick access stack
  func addVideo(url: URL) async {
    guard isEnabled else { return }
    let result = await ThumbnailGenerator.generate(from: url)
    guard let thumbnail = result.thumbnail else { return }

    // Use actual duration or nil (will show no badge if duration unavailable)
    let item = QuickAccessItem(url: url, thumbnail: thumbnail, duration: result.duration ?? 0)

    if items.count >= maxVisibleItems {
      if let oldestId = items.last?.id {
        removeItem(id: oldestId)
      }
    }

    let wasEmpty = items.isEmpty
    items.insert(item, at: 0)

    if wasEmpty {
      showPanel()
    }

    if autoDismissEnabled {
      startDismissTimer(for: item.id)
    }
  }

  /// Remove an item (screenshot or video) from the stack
  func removeItem(id: UUID) {
    cancelDismissTimer(for: id)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
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

  /// Dismiss all screenshots
  func dismissAll() {
    for item in items {
      cancelDismissTimer(for: item.id)
    }
    items.removeAll()
    panelController.hide()
  }

  /// Copy item to clipboard (image or video file URL)
  func copyToClipboard(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }

    let url = item.url
    let isVideo = item.isVideo

    removeScreenshot(id: id)

    Task.detached(priority: .userInitiated) {
      await MainActor.run {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if isVideo {
          pasteboard.writeObjects([url as NSURL])
        } else {
          if let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
          }
        }
        NSSound(named: "Pop")?.play()
      }
    }
  }

  /// Delete item from disk and remove from stack
  func deleteItem(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }

    let url = item.url
    removeItem(id: id)

    Task.detached(priority: .userInitiated) {
      do {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      } catch {
        print("Failed to delete item: \(error.localizedDescription)")
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
    Task.detached(priority: .userInitiated) {
      await MainActor.run {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
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
    let size = calculatePanelSize()
    panelController.show(stackView, size: size)
  }

  private func updatePanelSize() {
    guard !items.isEmpty else { return }
    let size = calculatePanelSize()
    panelController.updateSize(size)
  }

  private func calculatePanelSize() -> CGSize {
    let itemCount = max(1, items.count)
    let height =
      CGFloat(itemCount) * QuickAccessLayout.cardHeight
      + CGFloat(itemCount - 1) * QuickAccessLayout.cardSpacing
      + QuickAccessLayout.containerPadding * 2
    let width = QuickAccessLayout.cardWidth + QuickAccessLayout.containerPadding * 2
    return CGSize(width: width, height: height)
  }

  private func startDismissTimer(for id: UUID) {
    let delay = autoDismissDelay
    let task = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self?.removeScreenshot(id: id)
      }
    }
    dismissTimers[id] = task
  }

  private func cancelDismissTimer(for id: UUID) {
    dismissTimers[id]?.cancel()
    dismissTimers.removeValue(forKey: id)
  }
}
