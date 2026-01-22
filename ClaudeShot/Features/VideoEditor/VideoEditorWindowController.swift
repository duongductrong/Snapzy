//
//  VideoEditorWindowController.swift
//  ClaudeShot
//
//  Controller managing video editor window lifecycle
//

import AppKit
import SwiftUI

/// Manages video editor window lifecycle
@MainActor
final class VideoEditorWindowController: NSWindowController, NSWindowDelegate {

  private var sourceURL: URL?
  private var state: VideoEditorState?
  private var isExporting: Bool = false
  private var exportProgress: Float = 0
  private var isEmptyState: Bool = false

  /// Callback when video is loaded in empty state
  var onVideoLoaded: ((URL) -> Void)?

  /// Initialize with QuickAccessItem (existing behavior)
  init(item: QuickAccessItem) {
    self.sourceURL = item.url
    self.state = VideoEditorState(url: item.url)
    self.isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with URL directly (for drag & drop from external sources)
  init(url: URL) {
    self.sourceURL = url
    self.state = VideoEditorState(url: url)
    self.isEmptyState = false

    super.init(window: Self.createWindow())
    window?.delegate = self
    setupContent()
  }

  /// Initialize with empty state (for drag & drop workflow)
  override init(window: NSWindow?) {
    self.sourceURL = nil
    self.state = nil
    self.isEmptyState = true

    super.init(window: Self.createWindow())
    self.window?.delegate = self
    setupEmptyContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func createWindow() -> VideoEditorWindow {
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let windowWidth: CGFloat = 800
    let windowHeight: CGFloat = 600

    let origin = NSPoint(
      x: (screen.frame.width - windowWidth) / 2,
      y: (screen.frame.height - windowHeight) / 2
    )

    return VideoEditorWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )
  }

  private func setupContent() {
    guard let state = state else {
      setupEmptyContent()
      return
    }

    let mainView = VideoEditorMainView(
      state: state,
      onSave: { [weak self] in self?.showSaveConfirmation() },
      onSaveAs: { [weak self] in self?.performSaveAsCopy() },
      onCancel: { [weak self] in self?.handleCancel() }
    )
    window?.contentView = NSHostingView(rootView: mainView)
  }

  private func setupEmptyContent() {
    let emptyView = VideoEditorEmptyStateView { [weak self] url in
      self?.onVideoLoaded?(url)
    }
    window?.contentView = NSHostingView(rootView: emptyView)
  }

  func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Empty state can always close
    guard let state = state else { return true }

    guard state.hasUnsavedChanges else {
      state.pause()
      return true
    }

    showUnsavedChangesAlert(for: sender)
    return false
  }

  // MARK: - Unsaved Changes Alert

  private func showUnsavedChangesAlert(for window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = "Unsaved Changes"
    alert.informativeText = "You have unsaved trim changes. Do you want to save before closing?"
    alert.alertStyle = .warning

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don't Save")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.showSaveConfirmation()

      case .alertSecondButtonReturn:
        self.forceClose()

      default:
        break
      }
    }
  }

  // MARK: - Save Confirmation

  private func showSaveConfirmation() {
    guard let window = self.window, let state = state else { return }

    let alert = NSAlert()
    alert.messageText = "Save Trimmed Video"
    alert.informativeText = "How would you like to save the trimmed video \"\(state.filename)\"?"
    alert.alertStyle = .informational

    alert.addButton(withTitle: "Replace Original")
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.performReplaceOriginal()

      case .alertSecondButtonReturn:
        self.performSaveAsCopy()

      default:
        break
      }
    }
  }

  // MARK: - Export Actions

  private func performReplaceOriginal() {
    guard let state = state else { return }

    isExporting = true
    exportProgress = 0

    Task {
      do {
        try await VideoEditorExporter.replaceOriginal(state: state) { [weak self] progress in
          Task { @MainActor in
            self?.exportProgress = progress
          }
        }
        state.markAsSaved()
        forceClose()
      } catch {
        showExportError(error)
      }
      isExporting = false
    }
  }

  private func performSaveAsCopy() {
    guard let state = state else { return }

    isExporting = true
    exportProgress = 0

    Task {
      do {
        _ = try await VideoEditorExporter.saveAsCopy(state: state) { [weak self] progress in
          Task { @MainActor in
            self?.exportProgress = progress
          }
        }
        state.markAsSaved()
        forceClose()
      } catch {
        showExportError(error)
      }
      isExporting = false
    }
  }

  private func showExportError(_ error: Error) {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Export Failed"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: window)
  }

  private func forceClose() {
    state?.pause()
    state?.hasUnsavedChanges = false
    window?.close()
  }

  // MARK: - Cancel Action

  private func handleCancel() {
    guard let window = self.window else { return }

    if let state = state, state.hasUnsavedChanges {
      showUnsavedChangesAlert(for: window)
    } else {
      forceClose()
    }
  }
}
