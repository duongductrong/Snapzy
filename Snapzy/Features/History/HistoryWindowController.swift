//
//  HistoryWindowController.swift
//  Snapzy
//
//  Manages the capture history browser window lifecycle
//

import AppKit
import SwiftUI

extension Notification.Name {
  static let historyCopySelection = Notification.Name("historyCopySelection")
}

final class HistoryWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if event.keyCode == 8 && flags == .command {
      if isTextInputActive {
        return super.performKeyEquivalent(with: event)
      }

      NotificationCenter.default.post(name: .historyCopySelection, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  private var isTextInputActive: Bool {
    guard let responder = firstResponder else { return false }
    return responder is NSTextView || responder is NSTextField
  }
}

/// Manages the capture history browser window
@MainActor
final class HistoryWindowController {
  static let shared = HistoryWindowController()

  private var window: NSWindow?

  private init() {}

  func showWindow() {
    if let existingWindow = window {
      existingWindow.appearance = ThemeManager.shared.nsAppearance
      if existingWindow.isMiniaturized {
        existingWindow.deminiaturize(nil)
      }
      existingWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let view = HistoryMainView()
    let hostingView = NSHostingView(rootView: view)

    let newWindow = HistoryWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = "History"
    newWindow.contentView = hostingView
    newWindow.minSize = NSSize(width: 600, height: 400)
    newWindow.setFrameAutosaveName("SnapzyHistoryWindow")
    newWindow.center()
    newWindow.isReleasedWhenClosed = false
    newWindow.makeKeyAndOrderFront(nil)

    newWindow.appearance = ThemeManager.shared.nsAppearance

    window = newWindow
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideWindow() {
    window?.orderOut(nil)
  }

  func copyToClipboard(_ records: [CaptureHistoryRecord]) {
    let existingRecords = records.filter(\.fileExists)
    guard !existingRecords.isEmpty else { return }

    if existingRecords.count == 1, let record = existingRecords.first {
      switch record.captureType {
      case .screenshot, .gif:
        ClipboardHelper.copyImage(from: record.fileURL)
      case .video:
        ClipboardHelper.copyFileURLs([record.fileURL])
      }
      return
    }

    ClipboardHelper.copyFileURLs(existingRecords.map(\.fileURL))
  }

  func openItem(_ record: CaptureHistoryRecord) {
    guard record.fileExists else { return }

    hideWindow()
    HistoryFloatingManager.shared.hide()

    switch record.captureType {
    case .screenshot:
      AnnotateManager.shared.openAnnotation(url: record.fileURL)
    case .video, .gif:
      VideoEditorManager.shared.openEditor(for: record.fileURL)
    }
  }
}
