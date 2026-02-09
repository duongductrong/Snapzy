//
//  RecordingToolbarWindow.swift
//  Snapzy
//
//  Floating window container for recording toolbar and status bar
//

import AppKit
import Combine
import SwiftUI

enum RecordingToolbarMode {
  case preRecord
  case recording
}

// MARK: - Observable State

@MainActor
final class RecordingToolbarState: ObservableObject {
  @Published var selectedFormat: VideoFormat
  @Published var selectedQuality: VideoQuality
  @Published var captureAudio: Bool
  @Published var captureMicrophone: Bool
  @Published var captureMode: RecordingCaptureMode

  var onCaptureModeChanged: ((RecordingCaptureMode) -> Void)?

  init() {
    // Load format from preferences (default to mov if not set)
    if let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingFormat),
       let format = VideoFormat(rawValue: formatString) {
      self.selectedFormat = format
    } else {
      self.selectedFormat = .mov
    }

    // Load quality from preferences (default to high)
    if let qualityString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingQuality),
       let quality = VideoQuality(rawValue: qualityString) {
      self.selectedQuality = quality
    } else {
      self.selectedQuality = .high
    }

    // Load audio preference (default to true)
    self.captureAudio = UserDefaults.standard.object(forKey: PreferencesKeys.recordingCaptureAudio) as? Bool ?? true

    // Load microphone preference (default to false)
    self.captureMicrophone = UserDefaults.standard.object(forKey: PreferencesKeys.recordingCaptureMicrophone) as? Bool ?? false

    // Default capture mode is area
    self.captureMode = .area
  }
}

// MARK: - Toolbar Window

@MainActor
final class RecordingToolbarWindow: NSWindow {

  private var anchorRect: CGRect
  private var mode: RecordingToolbarMode = .preRecord
  private var hostingView: NSHostingView<AnyView>?
  private var effectView: NSVisualEffectView?

  // Callbacks
  var onRecord: (() -> Void)?
  var onCancel: (() -> Void)?
  var onDelete: (() -> Void)?
  var onRestart: (() -> Void)?
  var onStop: (() -> Void)?

  // Observable state for SwiftUI
  let state = RecordingToolbarState()
  let annotationState = RecordingAnnotationState()

  // Expose state properties for external access (read/write)
  var selectedFormat: VideoFormat {
    get { state.selectedFormat }
    set { state.selectedFormat = newValue }
  }
  var selectedQuality: VideoQuality {
    get { state.selectedQuality }
    set { state.selectedQuality = newValue }
  }
  var captureAudio: Bool {
    get { state.captureAudio }
    set { state.captureAudio = newValue }
  }
  var captureMicrophone: Bool {
    get { state.captureMicrophone }
    set { state.captureMicrophone = newValue }
  }
  var captureMode: RecordingCaptureMode {
    get { state.captureMode }
    set { state.captureMode = newValue }
  }

  // Callback for capture mode changes
  var onCaptureModeChanged: ((RecordingCaptureMode) -> Void)? {
    get { state.onCaptureModeChanged }
    set { state.onCaptureModeChanged = newValue }
  }

  init(anchorRect: CGRect) {
    self.anchorRect = anchorRect

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

    // Apply theme appearance at window level (mirrors AnnotateWindow.applyTheme)
    appearance = ThemeManager.shared.nsAppearance
  }

  func showPreRecordToolbar() {
    mode = .preRecord

    let view = RecordingToolbarView(
      state: state,
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
      annotationState: annotationState,
      onDelete: { [weak self] in self?.onDelete?() },
      onRestart: { [weak self] in self?.onRestart?() },
      onStop: { [weak self] in self?.onStop?() }
    )

    setContent(AnyView(view))
    positionBelowRect(anchorRect)
  }

  private func setContent(_ view: AnyView) {
    let themedView = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hosting = NSHostingView(rootView: AnyView(themedView))
    hosting.translatesAutoresizingMaskIntoConstraints = false

    // NSVisualEffectView provides native wallpaper-tinted material backing,
    // matching AnnotateWindow's adaptive background behavior.
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = ToolbarConstants.toolbarCornerRadius
    effect.layer?.masksToBounds = true

    // Make hosting view transparent so material shows through
    hosting.layer?.backgroundColor = .clear

    effect.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: effect.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
      hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
    ])

    // Size the effect view to match hosting content
    let fittingSize = hosting.fittingSize
    effect.frame = CGRect(origin: .zero, size: fittingSize)

    contentView = effect
    hostingView = hosting
    effectView = effect

    setContentSize(fittingSize)
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

  override var canBecomeKey: Bool { true }

  func updateAnchorRect(_ rect: CGRect) {
    anchorRect = rect
    positionBelowRect(rect)
  }
}
