//
//  RecordingToolbarWindow.swift
//  Snapzy
//
//  Floating window container for recording toolbar and status bar
//

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
private final class RecordingToolbarHostingView<Content: View>: NSHostingView<Content> {
  var onEscape: (() -> Void)?

  override var acceptsFirstResponder: Bool {
    true
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    guard event.keyCode == UInt16(kVK_Escape) else {
      super.keyDown(with: event)
      return
    }

    onEscape?()
  }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }
}

enum RecordingToolbarMode {
  case preRecord
  case recording
}

// MARK: - Recording Output Mode

enum RecordingOutputMode: String, CaseIterable {
  case video
  case gif

  var displayName: String {
    switch self {
    case .video: return L10n.RecordingToolbar.outputVideo
    case .gif: return L10n.RecordingToolbar.outputGIF
    }
  }

  var iconName: String {
    switch self {
    case .video: return "video"
    case .gif: return "photo.on.rectangle"
    }
  }
}

enum RecordingToolbarPreferences {
  static func selectedFormat(defaults: UserDefaults = .standard) -> VideoFormat {
    guard let formatString = defaults.string(forKey: PreferencesKeys.recordingFormat),
          let format = VideoFormat(rawValue: formatString)
    else {
      return .mov
    }
    return format
  }

  static func selectedQuality(defaults: UserDefaults = .standard) -> VideoQuality {
    guard let qualityString = defaults.string(forKey: PreferencesKeys.recordingQuality),
          let quality = VideoQuality(rawValue: qualityString)
    else {
      return .high
    }
    return quality
  }

  static func captureAudio(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.recordingCaptureAudio) as? Bool ?? true
  }

  static func captureMicrophone(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.recordingCaptureMicrophone) as? Bool ?? false
  }

  static func microphoneDeviceID(defaults: UserDefaults = .standard) -> String {
    RecordingMicrophoneDeviceProvider.storedDeviceID(defaults: defaults)
  }

  static func outputMode(defaults: UserDefaults = .standard) -> RecordingOutputMode {
    guard let modeString = defaults.string(forKey: PreferencesKeys.recordingOutputMode),
          let mode = RecordingOutputMode(rawValue: modeString)
    else {
      return .video
    }
    return mode
  }

  static func highlightClicks(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.recordingHighlightClicks) as? Bool ?? false
  }

  static func showKeystrokes(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.recordingShowKeystrokes) as? Bool ?? false
  }

  static func showCursor(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.recordingShowCursor) as? Bool ?? true
  }
}

enum RecordingToolbarPlacement {
  static let screenEdgeInset: CGFloat = 10
  static let outsideSelectionGap: CGFloat = 20
  static let insideSelectionBottomInset: CGFloat = 24

  static func frameOrigin(
    toolbarSize: CGSize,
    anchorRect rect: CGRect,
    screenFrame: CGRect
  ) -> CGPoint {
    let x = rect.midX - toolbarSize.width / 2
    let minX = screenFrame.minX + screenEdgeInset
    let maxX = screenFrame.maxX - toolbarSize.width - screenEdgeInset
    let safeX = max(minX, min(x, maxX))

    let minY = screenFrame.minY + screenEdgeInset
    let maxY = screenFrame.maxY - toolbarSize.height - screenEdgeInset
    let belowSelectionY = rect.minY - toolbarSize.height - outsideSelectionGap
    let preferredY = belowSelectionY >= minY
      ? belowSelectionY
      : rect.minY + insideSelectionBottomInset
    let safeY = max(minY, min(preferredY, maxY))

    return CGPoint(x: safeX, y: safeY)
  }
}

// MARK: - Observable State

@MainActor
final class RecordingToolbarState: ObservableObject {
  @Published var selectedFormat: VideoFormat
  @Published var selectedQuality: VideoQuality
  @Published var captureAudio: Bool
  @Published var captureMicrophone: Bool
  @Published var microphoneDeviceID: String
  @Published var captureMode: RecordingCaptureMode
  @Published var outputMode: RecordingOutputMode
  @Published var showCursor: Bool
  @Published var highlightClicks: Bool
  @Published var showKeystrokes: Bool
  @Published var isPreparingToRecord: Bool = false

  var onCaptureModeChanged: ((RecordingCaptureMode) -> Void)?

  init() {
    self.selectedFormat = RecordingToolbarPreferences.selectedFormat()
    self.selectedQuality = RecordingToolbarPreferences.selectedQuality()
    self.captureAudio = RecordingToolbarPreferences.captureAudio()
    self.captureMicrophone = RecordingToolbarPreferences.captureMicrophone()
    self.microphoneDeviceID = RecordingToolbarPreferences.microphoneDeviceID()
    self.captureMode = .area
    self.outputMode = RecordingToolbarPreferences.outputMode()
    self.showCursor = RecordingToolbarPreferences.showCursor()
    self.highlightClicks = RecordingToolbarPreferences.highlightClicks()
    self.showKeystrokes = RecordingToolbarPreferences.showKeystrokes()
  }
}

// MARK: - Toolbar Window

@MainActor
final class RecordingToolbarWindow: NSPanel {

  private var anchorRect: CGRect
  private var mode: RecordingToolbarMode = .preRecord
  private var hostingView: RecordingToolbarHostingView<AnyView>?
  private var effectView: NSVisualEffectView?
  private var cachedContentSize: CGSize?

  // Callbacks
  var onRecord: (() -> Void)?
  var onCapture: (() -> Void)?
  var onCancel: (() -> Void)?
  var onDelete: (() -> Void)?
  var onRestart: (() -> Void)?
  var onStop: (() -> Void)?

  /// Called when annotate button layout position is determined
  var onAnnotateButtonOffsetChanged: ((CGFloat) -> Void)?

  /// Center X offset of the annotate button relative to this window's left edge
  private(set) var annotateButtonCenterXOffset: CGFloat = 0

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
  var microphoneDeviceID: String {
    get { state.microphoneDeviceID }
    set { state.microphoneDeviceID = newValue }
  }
  var captureMode: RecordingCaptureMode {
    get { state.captureMode }
    set { state.captureMode = newValue }
  }
  var outputMode: RecordingOutputMode {
    get { state.outputMode }
    set { state.outputMode = newValue }
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
    sharingType = .none
    // Use popUpMenu level to ensure toolbar is above the region overlay (.floating)
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hasShadow = true
    isFloatingPanel = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false

    // Apply theme appearance at window level (mirrors AnnotateWindow.applyTheme)
    appearance = ThemeManager.shared.nsAppearance
  }

  func showPreRecordToolbar() {
    mode = .preRecord

    let view = RecordingToolbarView(
      state: state,
      onRecord: { [weak self] in self?.onRecord?() },
      onCapture: { [weak self] in self?.onCapture?() },
      onCancel: { [weak self] in self?.onCancel?() }
    )

    setContent(AnyView(view))
    showBelowRect(anchorRect)
  }

  func showRecordingStatusBar(recorder: ScreenRecordingManager) {
    mode = .recording

    let view = RecordingStatusBarView(
      recorder: recorder,
      annotationState: annotationState,
      onDelete: { [weak self] in self?.onDelete?() },
      onRestart: { [weak self] in self?.onRestart?() },
      onStop: { [weak self] in self?.onStop?() },
      onAnnotateButtonLayout: { [weak self] centerX in
        // centerX is relative to the SwiftUI view's coordinate space
        // Add horizontal padding to get offset relative to window edge
        let offset = centerX + ToolbarConstants.horizontalPadding
        self?.annotateButtonCenterXOffset = offset
        self?.onAnnotateButtonOffsetChanged?(offset)
      }
    )

    setContent(AnyView(view))
    showBelowRect(anchorRect)

    // Enable dragging in recording mode
    isMovableByWindowBackground = true
  }

  private func setContent(_ view: AnyView) {
    let themedView = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hosting = RecordingToolbarHostingView(rootView: AnyView(themedView))
    hosting.onEscape = { [weak self] in
      guard self?.mode == .preRecord else { return }
      self?.onCancel?()
    }
    hosting.translatesAutoresizingMaskIntoConstraints = false

    // NSVisualEffectView provides native wallpaper-tinted material backing,
    // matching AnnotateWindow's adaptive background behavior.
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = ToolbarConstants.toolbarCornerRadius
    effect.layer?.cornerCurve = .continuous
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
    cachedContentSize = fittingSize
    invalidateShadow()
  }

  private func positionBelowRect(_ rect: CGRect) {
    guard let size = cachedContentSize ?? contentView?.fittingSize else { return }

    // Find the screen containing the anchor rect (not NSScreen.main which is always primary)
    let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
      ?? ScreenUtility.activeScreen()
    let screenFrame = screen.visibleFrame

    let origin = RecordingToolbarPlacement.frameOrigin(
      toolbarSize: size,
      anchorRect: rect,
      screenFrame: screenFrame
    )

    setFrameOrigin(origin)
  }

  /// Position and order the window to the front (initial show only).
  private func showBelowRect(_ rect: CGRect) {
    positionBelowRect(rect)
    bringToFrontForInteraction()
  }

  func bringToFrontForInteraction() {
    NSApp.activate(ignoringOtherApps: true)
    orderFrontRegardless()
    makeKey()
    if let hostingView {
      makeFirstResponder(hostingView)
    }
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    guard mode == .preRecord, event.keyCode == UInt16(kVK_Escape) else {
      super.keyDown(with: event)
      return
    }

    onCancel?()
  }

  override func cancelOperation(_ sender: Any?) {
    guard mode == .preRecord else {
      super.cancelOperation(sender)
      return
    }

    onCancel?()
  }

  func updateAnchorRect(_ rect: CGRect) {
    anchorRect = rect
    positionBelowRect(rect)
  }
}
