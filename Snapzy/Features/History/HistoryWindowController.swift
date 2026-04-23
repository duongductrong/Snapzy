//
//  HistoryWindowController.swift
//  Snapzy
//
//  Manages the capture history browser window lifecycle
//

import AppKit

extension Notification.Name {
  static let historyCopySelection = Notification.Name("historyCopySelection")
  static let historyActivateSelection = Notification.Name("historyActivateSelection")
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

  private init() {}

  func showWindow() {
    HistoryFloatingManager.shared.showExpanded()
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideWindow() {
    HistoryFloatingManager.shared.hide()
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
    } else {
      ClipboardHelper.copyFileURLs(existingRecords.map(\.fileURL))
    }

    AppToastManager.shared.show(
      message: L10n.Common.copiedToClipboard,
      style: .success,
      duration: 1.6,
      variant: .compact
    )
  }

  func openItem(_ record: CaptureHistoryRecord) {
    guard record.fileExists else { return }

    HistoryFloatingManager.shared.hide()

    switch record.captureType {
    case .screenshot:
      AnnotateManager.shared.openAnnotation(url: record.fileURL)
    case .video, .gif:
      VideoEditorManager.shared.openEditor(for: record.fileURL)
    }
  }
}
