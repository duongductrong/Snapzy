//
//  RecordingToolbarWindow.swift
//  ZapShot
//
//  Floating window container for recording toolbar and status bar
//

import AppKit
import SwiftUI

enum RecordingToolbarMode {
  case preRecord
  case recording
}

@MainActor
final class RecordingToolbarWindow: NSWindow {

  private var anchorRect: CGRect
  private var mode: RecordingToolbarMode = .preRecord
  private var hostingView: NSHostingView<AnyView>?

  // Callbacks
  var onRecord: (() -> Void)?
  var onCancel: (() -> Void)?
  var onStop: (() -> Void)?

  // State
  var selectedFormat: VideoFormat

  init(anchorRect: CGRect) {
    self.anchorRect = anchorRect

    // Load format from preferences (default to mov if not set)
    if let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingFormat),
       let format = VideoFormat(rawValue: formatString) {
      self.selectedFormat = format
    } else {
      self.selectedFormat = .mov
    }

    super.init(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    showPreRecordToolbar()
  }

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    // Use popUpMenu level to ensure toolbar is above the region overlay (.floating)
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hasShadow = false
    isReleasedWhenClosed = false
  }

  func showPreRecordToolbar() {
    mode = .preRecord

    let binding = Binding<VideoFormat>(
      get: { [weak self] in self?.selectedFormat ?? .mov },
      set: { [weak self] in self?.selectedFormat = $0 }
    )

    let view = RecordingToolbarView(
      selectedFormat: binding,
      onRecord: { [weak self] in self?.onRecord?() },
      onCancel: { [weak self] in self?.onCancel?() }
    )

    setContent(AnyView(view))
    positionBelowRect(anchorRect)
  }

  func showRecordingStatusBar(recorder: ScreenRecordingManager) {
    mode = .recording

    let view = RecordingStatusBarView(
      recorder: recorder,
      onStop: { [weak self] in self?.onStop?() }
    )

    setContent(AnyView(view))
    positionBelowRect(anchorRect)
  }

  private func setContent(_ view: AnyView) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
    contentView = hosting
    hostingView = hosting

    setContentSize(hosting.fittingSize)
  }

  private func positionBelowRect(_ rect: CGRect) {
    guard let size = contentView?.fittingSize else { return }

    // Position centered below the selection rect
    let x = rect.midX - size.width / 2
    let y = rect.minY - size.height - 20

    // Ensure minimum distance from screen edge
    let safeY = max(y, 40)

    // Clamp X to screen bounds
    var safeX = x
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      safeX = max(screenFrame.minX + 10, min(x, screenFrame.maxX - size.width - 10))
    }

    setFrameOrigin(CGPoint(x: safeX, y: safeY))
    orderFrontRegardless()
  }

  func updateAnchorRect(_ rect: CGRect) {
    anchorRect = rect
    positionBelowRect(rect)
  }
}
