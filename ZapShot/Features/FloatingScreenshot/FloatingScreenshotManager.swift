//
//  FloatingScreenshotManager.swift
//  ZapShot
//
//  State management for floating screenshot stack
//

import AppKit
import Combine
import Foundation
import SwiftUI

/// Manages the floating screenshot preview stack
@MainActor
final class FloatingScreenshotManager: ObservableObject {

  static let shared = FloatingScreenshotManager()

  // MARK: - Published State

  @Published private(set) var items: [ScreenshotItem] = []
  @Published var position: FloatingPosition = .bottomRight {
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
  private let cardWidth: CGFloat = 200
  private let cardHeight: CGFloat = 112
  private let cardSpacing: CGFloat = 8
  private let containerPadding: CGFloat = 10

  // MARK: - Private

  private let panelController = FloatingPanelController()
  private var dismissTimers: [UUID: Task<Void, Never>] = [:]
  private var cancellables = Set<AnyCancellable>()

  // MARK: - UserDefaults Keys

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
      let savedPosition = FloatingPosition(rawValue: positionRaw)
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

  /// Add a new screenshot to the floating stack
  func addScreenshot(url: URL) async {
    guard isEnabled else { return }
    guard let thumbnail = await ThumbnailGenerator.generate(from: url) else { return }

    let item = ScreenshotItem(url: url, thumbnail: thumbnail)

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

  /// Remove a screenshot from the stack
  func removeScreenshot(id: UUID) {
    cancelDismissTimer(for: id)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
      items.removeAll { $0.id == id }
    }

    if items.isEmpty {
      panelController.hide()
    }
  }

  /// Dismiss all screenshots
  func dismissAll() {
    for item in items {
      cancelDismissTimer(for: item.id)
    }
    items.removeAll()
    panelController.hide()
  }

  /// Copy screenshot to clipboard
  func copyToClipboard(id: UUID) {
    guard let item = items.first(where: { $0.id == id }) else { return }

    // Capture URL before removal
    let url = item.url

    // Remove immediately - animation starts now
    removeScreenshot(id: id)

    // Async copy operation
    Task.detached(priority: .userInitiated) {
      guard let image = NSImage(contentsOf: url) else { return }
      await MainActor.run {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        NSSound(named: "Pop")?.play()
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
  func setPosition(_ newPosition: FloatingPosition) {
    position = newPosition
  }

  // MARK: - Private Methods

  private func showPanel() {
    let stackView = FloatingStackView(manager: self)
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
      CGFloat(itemCount) * cardHeight + CGFloat(itemCount - 1) * cardSpacing
      + containerPadding * 2
    let width = cardWidth + containerPadding * 2
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
