//
//  RecordingAnnotationOverlayWindow.swift
//  Snapzy
//
//  Transparent NSWindow covering the recording area
//  Annotations drawn here are captured by ScreenCaptureKit
//  via exceptingWindows (re-included from excluded app)
//

import AppKit
import Combine

@MainActor
final class RecordingAnnotationOverlayWindow: NSWindow {

  let annotationState: RecordingAnnotationState
  private let canvasView: RecordingAnnotationCanvasView
  private var toolCancellable: AnyCancellable?
  private var refreshCancellable: AnyCancellable?

  init(recordingRect: CGRect, annotationState: RecordingAnnotationState) {
    self.annotationState = annotationState
    self.canvasView = RecordingAnnotationCanvasView(state: annotationState)

    super.init(
      contentRect: recordingRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    setupCanvas()
    observeState()
  }

  // MARK: - Configuration

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isReleasedWhenClosed = false
    // Between overlay (.floating) and toolbar (.popUpMenu)
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    // Start as pass-through (selection mode)
    ignoresMouseEvents = true
  }

  private func setupCanvas() {
    canvasView.frame = CGRect(origin: .zero, size: frame.size)
    canvasView.autoresizingMask = [.width, .height]
    contentView = canvasView
  }

  private func observeState() {
    // Toggle mouse interactivity based on tool
    toolCancellable = annotationState.$selectedTool
      .receive(on: RunLoop.main)
      .sink { [weak self] tool in
        guard let self else { return }
        let isSelection = (tool == .selection)
        self.ignoresMouseEvents = isSelection
        if !isSelection {
          self.makeKeyAndOrderFront(nil)
          self.makeFirstResponder(self.canvasView)
        }
      }

    // Refresh canvas when annotations change
    refreshCancellable = annotationState.$annotations
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.canvasView.refresh()
      }
  }

  // MARK: - Public

  func updateRecordingRect(_ rect: CGRect) {
    setFrame(rect, display: true)
  }

  /// The CGWindowID used for ScreenCaptureKit exceptingWindows
  var overlayWindowID: CGWindowID {
    CGWindowID(windowNumber)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
