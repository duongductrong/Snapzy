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

  // Shortcut mode activation
  private let shortcutConfig = RecordingAnnotationShortcutConfig.shared
  private var globalFlagsMonitor: Any?
  private var localFlagsMonitor: Any?
  private var holdTimer: Timer?
  private var isModifierHeld = false

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
    startModifierMonitor()
  }

  deinit {
    // NSEvent.removeMonitor is thread-safe, safe from nonisolated deinit
    if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
    if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
    holdTimer?.invalidate()
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

  // MARK: - Modifier Hold Detection

  private func startModifierMonitor() {
    // Global monitor — works when overlay is NOT key window
    globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      Task { @MainActor in self?.handleFlagsChanged(event) }
    }
    // Local monitor — works when overlay IS key window
    localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      Task { @MainActor in self?.handleFlagsChanged(event) }
      return event
    }
  }

  func stopModifierMonitor() {
    if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
    if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
    holdTimer?.invalidate()
    holdTimer = nil
    annotationState.isShortcutModeActive = false
  }

  private func handleFlagsChanged(_ event: NSEvent) {
    let requiredFlag = shortcutConfig.modifier.flag
    let isPressed = event.modifierFlags.contains(requiredFlag)

    if isPressed {
      // Modifier just pressed — start hold timer
      guard !isModifierHeld else { return }
      isModifierHeld = true

      let duration = shortcutConfig.holdDuration
      holdTimer?.invalidate()
      holdTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
        Task { @MainActor in
          self?.annotationState.isShortcutModeActive = true
        }
      }
    } else {
      // Modifier released — deactivate shortcut mode
      isModifierHeld = false
      holdTimer?.invalidate()
      holdTimer = nil
      annotationState.isShortcutModeActive = false
    }
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
