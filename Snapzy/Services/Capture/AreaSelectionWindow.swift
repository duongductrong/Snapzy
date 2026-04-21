//
//  AreaSelectionWindow.swift
//  Snapzy
//
//  Overlay window for area selection with mouse
//  Optimized with window pooling and CALayer-based rendering for <150ms activation
//

import AppKit
import Foundation
import QuartzCore

/// Callback type for when area selection is completed
typealias AreaSelectionCompletion = (CGRect?) -> Void

/// Mode for area selection
enum SelectionMode {
  case screenshot
  case recording
  case scrollingCapture
}

/// Callback type with mode
typealias AreaSelectionCompletionWithMode = (CGRect?, SelectionMode) -> Void

// MARK: - NSScreen Extension for Display ID

extension NSScreen {
  /// Get the CGDirectDisplayID for this screen
  var displayID: CGDirectDisplayID? {
    guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      return nil
    }
    return CGDirectDisplayID(screenNumber.uint32Value)
  }
}

/// Controller for managing area selection overlay across all screens
/// Uses window pooling for instant activation (<150ms vs 400-600ms)
@MainActor
final class AreaSelectionController: NSObject {

  /// Shared instance for app-wide access
  static let shared = AreaSelectionController()

  // MARK: - Window Pool (Phase 1 Optimization)

  /// Pool of pre-allocated windows keyed by display ID
  private var windowPool: [CGDirectDisplayID: AreaSelectionWindow] = [:]

  /// Whether the window pool has been initialized
  private var isPoolReady = false

  /// Screen change observer token
  private var screenChangeObserver: NSObjectProtocol?

  // MARK: - Selection State

  private var completion: AreaSelectionCompletion?
  private var completionWithMode: AreaSelectionCompletionWithMode?
  private var completionWithResult: AreaSelectionResultCompletion?
  private var selectionMode: SelectionMode = .screenshot
  private var selectionBackdrops: [CGDirectDisplayID: AreaSelectionBackdrop] = [:]
  private var interactionMode: AreaSelectionInteractionMode = .manualRegion
  private var allowsApplicationWindowSelection = false
  private var applicationConfiguration: AreaSelectionApplicationConfiguration?
  private var windowSelectionSnapshot: WindowSelectionSnapshot?
  private var windowSelectionTask: Task<Void, Never>?
  private var selectionSessionID = UUID()
  private var activeWindow: AreaSelectionWindow?
  private var keyboardOwnerDisplayID: CGDirectDisplayID?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?

  // MARK: - Initialization

  private override init() {
    super.init()
  }

  // MARK: - Window Pool Management (Phase 1)

  /// Pre-allocate overlay windows for all screens
  /// Call this during app launch for instant selection activation
  func prepareWindowPool() {
    guard !isPoolReady else { return }

    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      let window = AreaSelectionWindow(screen: screen, pooled: true)
      window.selectionDelegate = self
      windowPool[displayID] = window
    }

    setupScreenChangeObserver()
    isPoolReady = true
  }

  /// Setup observer for screen configuration changes
  private func setupScreenChangeObserver() {
    screenChangeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshWindowPool()
      }
    }
  }

  /// Refresh window pool when screens change
  private func refreshWindowPool() {
    let currentDisplayIDs = Set(NSScreen.screens.compactMap { $0.displayID })
    let pooledDisplayIDs = Set(windowPool.keys)

    // Remove windows for disconnected displays
    for displayID in pooledDisplayIDs.subtracting(currentDisplayIDs) {
      windowPool[displayID]?.close()
      windowPool.removeValue(forKey: displayID)
    }

    // Add windows for new displays
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID,
            windowPool[displayID] == nil else { continue }
      let window = AreaSelectionWindow(screen: screen, pooled: true)
      window.selectionDelegate = self
      windowPool[displayID] = window
    }

    // Update frames for existing windows (screen may have moved/resized)
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID,
            let window = windowPool[displayID] else { continue }
      window.setFrame(screen.frame, display: true)
      window.overlayView.updateBounds(screen.frame)
    }
  }

  /// Activate all pooled windows (show instantly)
  private func activatePooledWindows() {
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      let allowsSelection = selectionEnabled(for: displayID)
      let receivesKeyboardInput = displayID == keyboardOwnerDisplayID

      if let window = windowPool[displayID] {
        // Sync frame to current screen position before showing
        if window.frame != screen.frame {
          window.setFrame(screen.frame, display: true)
          window.overlayView.updateBounds(screen.frame)
          print("[Snapzy:AreaSelection] activatePooledWindows() — resynced stale frame for display \(displayID)")
        }
        // Reset and show existing pooled window without stealing focus
        window.updateSelectionMode(selectionMode)
        if let backdrop = selectionBackdrops[displayID] {
          window.overlayView.applyBackdrop(backdrop)
        } else {
          window.overlayView.clearBackdrop()
        }
        window.overlayView.setAllowsApplicationWindowSelection(allowsApplicationWindowSelection)
        window.overlayView.setWindowSelectionSnapshot(windowSelectionSnapshot)
        window.overlayView.setInteractionMode(interactionMode, resetSelection: false)
        window.overlayView.setSelectionEnabled(allowsSelection)
        window.overlayView.resetSelection()
        window.setReceivesKeyboardInput(receivesKeyboardInput)
        window.selectionDelegate = self
        window.orderFrontRegardless()
        window.activateKeyboardInputIfNeeded()
        window.overlayView.refreshCursor()
      } else {
        // Fallback: create window if not pooled
        let window = AreaSelectionWindow(screen: screen, pooled: false)
        window.updateSelectionMode(selectionMode)
        if let backdrop = selectionBackdrops[displayID] {
          window.overlayView.applyBackdrop(backdrop)
        } else {
          window.overlayView.clearBackdrop()
        }
        window.overlayView.setAllowsApplicationWindowSelection(allowsApplicationWindowSelection)
        window.overlayView.setWindowSelectionSnapshot(windowSelectionSnapshot)
        window.overlayView.setInteractionMode(interactionMode, resetSelection: false)
        window.overlayView.setSelectionEnabled(allowsSelection)
        window.overlayView.resetSelection()
        window.setReceivesKeyboardInput(receivesKeyboardInput)
        window.selectionDelegate = self
        windowPool[displayID] = window
        window.orderFrontRegardless()
        window.activateKeyboardInputIfNeeded()
        window.overlayView.refreshCursor()
      }
    }
  }

  /// Deactivate all windows (hide, don't close)
  private func deactivatePooledWindows() {
    for (_, window) in windowPool {
      window.setReceivesKeyboardInput(false)
      window.orderOut(nil)
      window.overlayView.resetSelection()
      window.overlayView.clearBackdrop()
    }
    activeWindow = nil
  }

  // MARK: - Public API

  /// Start area selection mode (legacy - for screenshots)
  /// - Parameter completion: Called with the selected rect, or nil if cancelled
  func startSelection(completion: @escaping AreaSelectionCompletion) {
    completionWithMode = nil
    completionWithResult = nil
    self.completion = completion
    startSelectionSession(mode: .screenshot, backdrops: [:])
  }

  /// Start area selection with mode
  /// - Parameters:
  ///   - mode: The selection mode (screenshot or recording)
  ///   - completion: Called with the selected rect and mode, or nil if cancelled
  func startSelection(mode: SelectionMode, completion: @escaping AreaSelectionCompletionWithMode) {
    self.completion = nil
    completionWithResult = nil
    completionWithMode = completion
    startSelectionSession(mode: mode, backdrops: [:])
  }

  func startSelection(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    completion: @escaping AreaSelectionResultCompletion
  ) {
    startSelection(mode: mode, backdrops: backdrops, applicationConfiguration: nil, completion: completion)
  }

  func startSelection(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration?,
    completion: @escaping AreaSelectionResultCompletion
  ) {
    self.completion = nil
    completionWithMode = nil
    completionWithResult = completion
    startSelectionSession(mode: mode, backdrops: backdrops, applicationConfiguration: applicationConfiguration)
  }

  private func startSelectionSession(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration? = nil
  ) {
    // Always clean up prior session's monitors to prevent orphaned leaks
    removeEscapeMonitors()
    cancelWindowSelectionTask()
    print("[Snapzy:AreaSelection] startSelection(mode: \(mode)) — monitors cleaned, starting")

    selectionMode = mode
    selectionBackdrops = backdrops
    self.applicationConfiguration = applicationConfiguration
    allowsApplicationWindowSelection = mode == .screenshot && applicationConfiguration != nil
    interactionMode = .manualRegion
    windowSelectionSnapshot = nil
    selectionSessionID = UUID()
    keyboardOwnerDisplayID = resolvedKeyboardOwnerDisplayID()

    // Ensure pool is ready (lazy initialization if not called at app launch)
    if !isPoolReady {
      prepareWindowPool()
    }

    // Activate pooled windows (instant show)
    activatePooledWindows()
    startWindowSelectionPreparationIfNeeded()

    if keyboardOwnerDisplayID == nil {
      // Set up session key monitoring only when the overlay cannot own keyboard input directly.
      localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        if self?.handleSessionKeyEvent(event) == true {
          return nil
        }
        return event
      }

      // Global monitor for when app may not be fully active.
      globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard self?.isSessionKeyEvent(event) == true else { return }
        DispatchQueue.main.async {
          _ = self?.handleSessionKeyEvent(event)
        }
      }
    }
  }

  private func resolvedKeyboardOwnerDisplayID() -> CGDirectDisplayID? {
    guard selectionMode == .screenshot else { return nil }

    if selectionBackdrops.count == 1 {
      return selectionBackdrops.keys.first
    }

    return ScreenUtility.activeDisplayID()
  }

  private func selectionEnabled(for displayID: CGDirectDisplayID) -> Bool {
    switch interactionMode {
    case .manualRegion:
      selectionBackdrops.isEmpty || selectionBackdrops[displayID] != nil
    case .applicationWindow:
      allowsApplicationWindowSelection
    }
  }

  private func isSessionKeyEvent(_ event: NSEvent) -> Bool {
    event.keyCode == 53 || isApplicationToggleEvent(event)
  }

  private func handleSessionKeyEvent(_ event: NSEvent) -> Bool {
    if event.keyCode == 53 {  // Escape key
      cancelSelection()
      return true
    }

    guard isApplicationToggleEvent(event) else { return false }
    toggleInteractionMode()
    return true
  }

  private func isApplicationToggleEvent(_ event: NSEvent) -> Bool {
    guard allowsApplicationWindowSelection else { return false }
    guard event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty else {
      return false
    }
    return CaptureOverlayShortcutSettings.matchesApplicationCaptureShortcut(event)
  }

  private func toggleInteractionMode() {
    guard !windowPool.values.contains(where: { $0.overlayView.isManualSelectionInProgress }) else {
      return
    }
    let nextMode: AreaSelectionInteractionMode = interactionMode == .manualRegion
      ? .applicationWindow
      : .manualRegion
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Area selection interaction mode toggled",
      context: ["mode": nextMode == .manualRegion ? "manual" : "application"]
    )
    interactionMode = nextMode
    refreshPooledWindowsForInteractionModeChange()
  }

  private func refreshPooledWindowsForInteractionModeChange() {
    for (displayID, window) in windowPool {
      window.overlayView.setInteractionMode(interactionMode)
      window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
      window.overlayView.resetSelection()
    }
  }

  private func startWindowSelectionPreparationIfNeeded() {
    guard let applicationConfiguration else { return }
    let sessionID = selectionSessionID
    windowSelectionTask = Task { [weak self] in
      let snapshot = await WindowSelectionQueryService.prepareSnapshot(
        prefetchedContentTask: applicationConfiguration.prefetchedContentTask,
        excludeOwnApplication: applicationConfiguration.excludeOwnApplication
      )
      await MainActor.run {
        guard let self, self.selectionSessionID == sessionID else { return }
        self.windowSelectionSnapshot = snapshot
        for (_, window) in self.windowPool {
          window.overlayView.setWindowSelectionSnapshot(snapshot)
        }
      }
    }
  }

  private func cancelWindowSelectionTask() {
    windowSelectionTask?.cancel()
    windowSelectionTask = nil
  }

  private func completeSelection(target: AreaSelectionTarget, from window: AreaSelectionWindow) {
    let rect = target.rect
    let displayID = target.windowTarget?.displayID
      ?? window.displayID
      ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.displayID
    print("[Snapzy:AreaSelection] completeSelection(rect: \(rect))")
    removeEscapeMonitors()
    cancelWindowSelectionTask()
    deactivatePooledWindows()
    completion?(rect)
    completionWithMode?(rect, selectionMode)
    if let displayID {
      completionWithResult?(AreaSelectionResult(target: target, displayID: displayID, mode: selectionMode))
    } else {
      completionWithResult?(nil)
    }
    resetCallbacks()
  }

  /// Cancel the current selection
  func cancelSelection() {
    print("[Snapzy:AreaSelection] cancelSelection() called")
    removeEscapeMonitors()
    cancelWindowSelectionTask()
    deactivatePooledWindows()
    completion?(nil)
    completionWithMode?(nil, selectionMode)
    completionWithResult?(nil)
    resetCallbacks()
  }

  /// Complete selection with the given rect
  func completeSelection(rect: CGRect, from window: AreaSelectionWindow) {
    completeSelection(target: .rect(rect), from: window)
  }

  func completeSelection(windowTarget: WindowCaptureTarget, from window: AreaSelectionWindow) {
    completeSelection(target: .window(windowTarget), from: window)
  }

  private func removeEscapeMonitors() {
    if let monitor = localEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      localEscapeMonitor = nil
    }
    if let monitor = globalEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      globalEscapeMonitor = nil
    }
  }

  private func resetCallbacks() {
    completion = nil
    completionWithMode = nil
    completionWithResult = nil
    selectionBackdrops.removeAll()
    applicationConfiguration = nil
    allowsApplicationWindowSelection = false
    interactionMode = .manualRegion
    windowSelectionSnapshot = nil
    keyboardOwnerDisplayID = nil
  }

  deinit {
    if let observer = screenChangeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}

// MARK: - AreaSelectionWindowDelegate

extension AreaSelectionController: AreaSelectionWindowDelegate {
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectRect rect: CGRect) {
    completeSelection(rect: rect, from: window)
  }

  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectWindow target: WindowCaptureTarget) {
    completeSelection(windowTarget: target, from: window)
  }

  func areaSelectionWindowDidCancel(_ window: AreaSelectionWindow) {
    cancelSelection()
  }

  func areaSelectionWindowDidBecomeActive(_ window: AreaSelectionWindow) {
    activeWindow = window
  }

  func areaSelectionWindow(_ window: AreaSelectionWindow, didReceiveKeyEvent event: NSEvent) -> Bool {
    guard window.displayID == keyboardOwnerDisplayID else { return false }
    return handleSessionKeyEvent(event)
  }
}

// MARK: - AreaSelectionWindowDelegate Protocol

protocol AreaSelectionWindowDelegate: AnyObject {
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectRect rect: CGRect)
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectWindow target: WindowCaptureTarget)
  func areaSelectionWindowDidCancel(_ window: AreaSelectionWindow)
  func areaSelectionWindowDidBecomeActive(_ window: AreaSelectionWindow)
  func areaSelectionWindow(_ window: AreaSelectionWindow, didReceiveKeyEvent event: NSEvent) -> Bool
}

// MARK: - AreaSelectionWindow

/// Full-screen overlay panel for area selection
/// Uses NSPanel with .nonactivatingPanel to prevent background windows from deactivating/blurring
/// Supports pooled mode for instant activation
final class AreaSelectionWindow: NSPanel {

  weak var selectionDelegate: AreaSelectionWindowDelegate?

  let overlayView: AreaSelectionOverlayView
  private let targetScreen: NSScreen
  private var receivesKeyboardInput = false

  /// Initialize window for a screen
  /// - Parameters:
  ///   - screen: The screen this window covers
  ///   - pooled: If true, window starts hidden for pool pre-allocation
  init(screen: NSScreen, pooled: Bool = false) {
    self.targetScreen = screen
    self.overlayView = AreaSelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    // Configure as non-activating panel to prevent background windows from blurring
    self.isFloatingPanel = true
    self.isOpaque = false
    self.backgroundColor = .clear
    self.level = .screenSaver
    self.ignoresMouseEvents = false
    self.acceptsMouseMovedEvents = true
    self.isReleasedWhenClosed = false
    self.hasShadow = false
    self.hidesOnDeactivate = false
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    self.animationBehavior = .none  // Disable window animations for instant appearance
    self.becomesKeyOnlyIfNeeded = true

    // Set up content view
    self.contentView = overlayView
    overlayView.delegate = self
    overlayView.keyEventHandler = { [weak self] event in
      guard let self else { return false }
      return self.selectionDelegate?.areaSelectionWindow(self, didReceiveKeyEvent: event) ?? false
    }

    if pooled {
      // Pooled windows start hidden
      self.orderOut(nil)
    } else {
      // Non-pooled windows show immediately without stealing focus
      self.orderFrontRegardless()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateSelectionMode(_ mode: SelectionMode) {
    overlayView.selectionMode = mode
  }

  func setReceivesKeyboardInput(_ receivesKeyboardInput: Bool) {
    self.receivesKeyboardInput = receivesKeyboardInput
  }

  func activateKeyboardInputIfNeeded() {
    guard receivesKeyboardInput else { return }
    makeKey()
    makeFirstResponder(overlayView)
  }

  var displayID: CGDirectDisplayID? {
    targetScreen.displayID
  }

  // Non-activating: prevent stealing focus from other apps
  override var canBecomeKey: Bool { receivesKeyboardInput }
  override var canBecomeMain: Bool { false }
}

// MARK: - AreaSelectionOverlayViewDelegate

extension AreaSelectionWindow: AreaSelectionOverlayViewDelegate {
  func overlayView(_ view: AreaSelectionOverlayView, didSelectRect rect: CGRect) {
    // Convert from view coordinates to screen coordinates
    let screenRect = convertToScreenCoordinates(rect)
    selectionDelegate?.areaSelectionWindow(self, didSelectRect: screenRect)
  }

  func overlayView(_ view: AreaSelectionOverlayView, didSelectWindow target: WindowCaptureTarget) {
    selectionDelegate?.areaSelectionWindow(self, didSelectWindow: target)
  }

  func overlayViewDidCancel(_ view: AreaSelectionOverlayView) {
    selectionDelegate?.areaSelectionWindowDidCancel(self)
  }

  private func convertToScreenCoordinates(_ rect: CGRect) -> CGRect {
    // The rect is in window coordinates (bottom-left origin)
    // Convert to global screen coordinates (also bottom-left origin)
    let windowFrame = self.frame

    return CGRect(
      x: windowFrame.origin.x + rect.origin.x,
      y: windowFrame.origin.y + rect.origin.y,
      width: rect.width,
      height: rect.height
    )
  }
}

// MARK: - AreaSelectionOverlayViewDelegate Protocol

protocol AreaSelectionOverlayViewDelegate: AnyObject {
  func overlayView(_ view: AreaSelectionOverlayView, didSelectRect rect: CGRect)
  func overlayView(_ view: AreaSelectionOverlayView, didSelectWindow target: WindowCaptureTarget)
  func overlayViewDidCancel(_ view: AreaSelectionOverlayView)
}

// MARK: - AreaSelectionOverlayView

/// The view that handles drawing and mouse interaction
/// Uses CALayer-based rendering for 60fps crosshair movement (Phase 2 optimization)
final class AreaSelectionOverlayView: NSView {

  weak var delegate: AreaSelectionOverlayViewDelegate?
  var keyEventHandler: ((NSEvent) -> Bool)?
  var selectionMode: SelectionMode = .screenshot {
    didSet {
      needsDisplay = true
    }
  }
  private var interactionMode: AreaSelectionInteractionMode = .manualRegion
  private var allowsApplicationWindowSelection = false

  // MARK: - Selection State

  private var isSelecting = false
  private var selectionStartPoint: CGPoint?
  private var selectionEndPoint: CGPoint?
  private var currentMousePosition: CGPoint = .zero
  private var windowSelectionSnapshot: WindowSelectionSnapshot?
  private var hoveredWindowCandidate: WindowSelectionCandidate?

  // MARK: - CALayer-based Rendering (Phase 2 Optimization)

  private var snapshotLayer: CALayer!
  private var dimLayer: CALayer!
  private var horizontalCrosshairLayer: CAShapeLayer!
  private var verticalCrosshairLayer: CAShapeLayer!
  private var selectionBorderLayer: CAShapeLayer!
  private var crosshairIndicatorLayer: CAShapeLayer!

  // Appearance constants
  private let dimColor = NSColor.black.withAlphaComponent(0.4)
  private let crosshairColor = NSColor.white.withAlphaComponent(0.6)
  private let selectionBorderColor = NSColor.white
  private let selectionBorderWidth: CGFloat = 2.0
  private let crosshairIndicatorSize: CGFloat = 10.0
  private let crosshairIndicatorLineWidth: CGFloat = 1.5
  private let crosshairIndicatorCenterRadius: CGFloat = 6.0
  private var selectionEnabled = true

  /// Disabled animations for instant layer updates
  private var disabledActions: [String: CAAction] {
    return [
      "position": NSNull(),
      "bounds": NSNull(),
      "path": NSNull(),
      "hidden": NSNull(),
      "opacity": NSNull(),
      "backgroundColor": NSNull(),
      "frame": NSNull(),
      "contents": NSNull(),
      "contentsScale": NSNull()
    ]
  }

  // MARK: - Initialization

  override init(frame: CGRect) {
    super.init(frame: frame)
    wantsLayer = true
    setupLayers()
    setupTrackingArea()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    wantsLayer = true
    setupLayers()
    setupTrackingArea()
  }

  // MARK: - Layer Setup

  private func setupLayers() {
    guard let rootLayer = layer else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    snapshotLayer = CALayer()
    snapshotLayer.frame = bounds
    snapshotLayer.contentsGravity = .resize
    snapshotLayer.actions = disabledActions
    snapshotLayer.isHidden = true
    rootLayer.addSublayer(snapshotLayer)

    // Dim overlay layer (full screen semi-transparent)
    dimLayer = CALayer()
    dimLayer.backgroundColor = dimColor.cgColor
    dimLayer.frame = bounds
    dimLayer.actions = disabledActions
    rootLayer.addSublayer(dimLayer)

    // Horizontal crosshair line (hidden - using cursor instead)
    horizontalCrosshairLayer = CAShapeLayer()
    horizontalCrosshairLayer.strokeColor = crosshairColor.cgColor
    horizontalCrosshairLayer.lineWidth = 1.0
    horizontalCrosshairLayer.isHidden = true
    horizontalCrosshairLayer.actions = disabledActions
    rootLayer.addSublayer(horizontalCrosshairLayer)

    // Vertical crosshair line (hidden - using cursor instead)
    verticalCrosshairLayer = CAShapeLayer()
    verticalCrosshairLayer.strokeColor = crosshairColor.cgColor
    verticalCrosshairLayer.lineWidth = 1.0
    verticalCrosshairLayer.isHidden = true
    verticalCrosshairLayer.actions = disabledActions
    rootLayer.addSublayer(verticalCrosshairLayer)

    // Selection border layer
    selectionBorderLayer = CAShapeLayer()
    selectionBorderLayer.strokeColor = selectionBorderColor.cgColor
    selectionBorderLayer.fillColor = nil
    selectionBorderLayer.lineWidth = selectionBorderWidth
    selectionBorderLayer.isHidden = true
    selectionBorderLayer.actions = disabledActions
    rootLayer.addSublayer(selectionBorderLayer)

    // Crosshair indicator at mouse position (like CleanShot X)
    crosshairIndicatorLayer = CAShapeLayer()
    crosshairIndicatorLayer.strokeColor = NSColor.white.cgColor
    crosshairIndicatorLayer.fillColor = nil
    crosshairIndicatorLayer.lineWidth = crosshairIndicatorLineWidth
    crosshairIndicatorLayer.lineCap = .round
    crosshairIndicatorLayer.actions = disabledActions
    crosshairIndicatorLayer.shadowColor = NSColor.black.cgColor
    crosshairIndicatorLayer.shadowOffset = .zero
    crosshairIndicatorLayer.shadowRadius = 2
    crosshairIndicatorLayer.shadowOpacity = 0.5
    rootLayer.addSublayer(crosshairIndicatorLayer)

    CATransaction.commit()
  }

  // MARK: - Tracking Area

  private func setupTrackingArea() {
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
  }

  // MARK: - Cursor

  override func cursorUpdate(with event: NSEvent) {
    activeCursor.set()
  }

  override func mouseEntered(with event: NSEvent) {
    activeCursor.set()
  }

  override func mouseExited(with event: NSEvent) {
    NSCursor.arrow.set()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: activeCursor)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    setupTrackingArea()
  }

  private func refreshActiveCursor() {
    window?.invalidateCursorRects(for: self)
    activeCursor.set()
  }

  func refreshCursor() {
    refreshActiveCursor()
  }

  // MARK: - Public Methods

  /// Reset selection state for window pool reuse
  func resetSelection() {
    isSelecting = false
    selectionStartPoint = nil
    selectionEndPoint = nil
    hoveredWindowCandidate = nil

    // Initialize crosshair at current mouse position immediately
    if selectionEnabled {
      initializeCrosshairAtCurrentMousePosition()
    } else {
      currentMousePosition = .zero
    }

    // Rebuild tracking areas for current bounds (prevents stale hit-testing)
    updateTrackingAreas()

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Keep crosshair layers hidden (using indicator instead)
    horizontalCrosshairLayer.isHidden = true
    verticalCrosshairLayer.isHidden = true
    selectionBorderLayer.isHidden = true
    crosshairIndicatorLayer.isHidden = !selectionEnabled || interactionMode != .manualRegion
    dimLayer.mask = nil
    dimLayer.frame = bounds

    CATransaction.commit()

    // Update interaction state immediately
    if selectionEnabled {
      refreshInteractionState()
      refreshActiveCursor()
    }

    needsDisplay = true
  }

  func setSelectionEnabled(_ enabled: Bool) {
    selectionEnabled = enabled
    refreshActiveCursor()
  }

  func applyBackdrop(_ backdrop: AreaSelectionBackdrop) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.frame = bounds
    snapshotLayer.contents = backdrop.image
    snapshotLayer.contentsScale = backdrop.scaleFactor
    snapshotLayer.isHidden = false
    CATransaction.commit()
  }

  func clearBackdrop() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.contents = nil
    snapshotLayer.contentsScale = 1.0
    snapshotLayer.isHidden = true
    CATransaction.commit()
  }

  /// Initialize crosshair at current mouse position (called on activation)
  private func initializeCrosshairAtCurrentMousePosition() {
    // Get the current mouse location in screen coordinates
    let mouseLocationInScreen = NSEvent.mouseLocation

    // Convert to window coordinates, then to view coordinates
    if let window = self.window {
      let mouseLocationInWindow = window.convertPoint(fromScreen: mouseLocationInScreen)
      currentMousePosition = convert(mouseLocationInWindow, from: nil)
    } else {
      // Fallback: use screen coordinates relative to view frame
      currentMousePosition = CGPoint(
        x: mouseLocationInScreen.x - frame.origin.x,
        y: mouseLocationInScreen.y - frame.origin.y
      )
    }
  }

  /// Update bounds when screen configuration changes
  func updateBounds(_ newFrame: CGRect) {
    frame = CGRect(origin: .zero, size: newFrame.size)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.frame = bounds
    dimLayer.frame = bounds
    CATransaction.commit()

    // Rebuild tracking areas for new bounds
    updateTrackingAreas()
  }

  // MARK: - First Mouse

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    if keyEventHandler?(event) == true {
      return
    }
    super.keyDown(with: event)
  }

  // MARK: - Layout

  override func layout() {
    super.layout()

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.frame = bounds
    dimLayer.frame = bounds
    CATransaction.commit()
  }

  // MARK: - Drawing (Only for size indicator text)

  override func draw(_ dirtyRect: NSRect) {
    // Only draw size indicator - layers handle dim, crosshair, selection
    if isSelecting, let rect = calculateSelectionRect() {
      drawSizeIndicator(for: rect)
    }
    drawModeHint()
  }

  private func drawSizeIndicator(for rect: CGRect) {
    let sizeText = "\(Int(rect.width)) x \(Int(rect.height))"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white,
    ]

    let textSize = sizeText.size(withAttributes: attributes)
    let padding: CGFloat = 6
    var bgRect = CGRect(
      x: rect.maxX - textSize.width - padding * 2 - 4,
      y: rect.minY - textSize.height - padding - 8,
      width: textSize.width + padding * 2,
      height: textSize.height + padding
    )

    // Ensure text stays within bounds
    if bgRect.minY < 0 {
      bgRect.origin.y = rect.maxY + 4
    }
    if bgRect.maxX > bounds.maxX {
      bgRect.origin.x = rect.minX
    }

    // Draw background
    NSColor.black.withAlphaComponent(0.7).setFill()
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
    bgPath.fill()

    // Draw text
    let textPoint = CGPoint(x: bgRect.minX + padding, y: bgRect.minY + padding / 2)
    sizeText.draw(at: textPoint, withAttributes: attributes)
  }

  private func calculateSelectionRect() -> CGRect? {
    guard let start = selectionStartPoint, let end = selectionEndPoint else {
      return nil
    }
    let minX = min(start.x, end.x)
    let maxX = max(start.x, end.x)
    let minY = min(start.y, end.y)
    let maxY = max(start.y, end.y)

    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  // MARK: - CALayer Updates (60fps performance)

  private func updateCrosshairLayers() {
    guard selectionEnabled, interactionMode == .manualRegion else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      crosshairIndicatorLayer.isHidden = true
      CATransaction.commit()
      return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Update crosshair indicator position
    crosshairIndicatorLayer.isHidden = false
    let path = createCrosshairIndicatorPath(at: currentMousePosition)
    crosshairIndicatorLayer.path = path

    CATransaction.commit()
  }

  /// Creates a crosshair indicator path centered at the given point
  private func createCrosshairIndicatorPath(at point: CGPoint) -> CGPath {
    let size = crosshairIndicatorSize
    let path = CGMutablePath()

    // Vertical line
    path.move(to: CGPoint(x: point.x, y: point.y - size))
    path.addLine(to: CGPoint(x: point.x, y: point.y + size))

    // Horizontal line
    path.move(to: CGPoint(x: point.x - size, y: point.y))
    path.addLine(to: CGPoint(x: point.x + size, y: point.y))

    return path
  }

  private func updateSelectionLayers() {
    guard let rect = calculateSelectionRect() else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Hide crosshair indicator during selection
    crosshairIndicatorLayer.isHidden = true
    horizontalCrosshairLayer.isHidden = true
    verticalCrosshairLayer.isHidden = true

    // Show selection border
    selectionBorderLayer.isHidden = false
    selectionBorderLayer.path = CGPath(rect: rect, transform: nil)

    // Update dim layer mask to clear selection area
    updateDimLayerMask(for: rect)

    CATransaction.commit()

    // Trigger draw() only for size indicator text
    needsDisplay = true
  }

  private func updateDimLayerMask(for selectionRect: CGRect) {
    // Create mask that clears the selection area (even-odd fill rule)
    let maskLayer = CAShapeLayer()
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addRect(selectionRect)
    maskLayer.path = path
    maskLayer.fillRule = .evenOdd
    dimLayer.mask = maskLayer
  }

  private func drawModeHint() {
    guard selectionMode == .screenshot, allowsApplicationWindowSelection else { return }

    let shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcutDisplay
    let hint = interactionMode == .manualRegion
      ? L10n.ScreenCapture.applicationModeHint(shortcut)
      : L10n.ScreenCapture.manualModeHint(shortcut)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white,
    ]
    let hintSize = hint.size(withAttributes: attributes)
    let padding = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    let backgroundRect = CGRect(
      x: (bounds.width - hintSize.width) / 2 - padding.left,
      y: 24,
      width: hintSize.width + padding.left + padding.right,
      height: hintSize.height + padding.top + padding.bottom
    )

    NSColor.black.withAlphaComponent(0.68).setFill()
    NSBezierPath(roundedRect: backgroundRect, xRadius: 8, yRadius: 8).fill()
    hint.draw(
      at: CGPoint(x: backgroundRect.minX + padding.left, y: backgroundRect.minY + padding.bottom - 1),
      withAttributes: attributes
    )
  }

  func setAllowsApplicationWindowSelection(_ allowsApplicationWindowSelection: Bool) {
    self.allowsApplicationWindowSelection = allowsApplicationWindowSelection
    needsDisplay = true
  }

  func setInteractionMode(
    _ interactionMode: AreaSelectionInteractionMode,
    resetSelection: Bool = true
  ) {
    self.interactionMode = interactionMode
    if resetSelection {
      self.resetSelection()
    } else {
      refreshInteractionState()
    }
    refreshActiveCursor()
    needsDisplay = true
  }

  func setWindowSelectionSnapshot(_ windowSelectionSnapshot: WindowSelectionSnapshot?) {
    self.windowSelectionSnapshot = windowSelectionSnapshot
    if interactionMode == .applicationWindow {
      refreshInteractionState()
    }
  }

  private func refreshInteractionState() {
    switch interactionMode {
    case .manualRegion:
      hoveredWindowCandidate = nil
      dimLayer.mask = nil
      selectionBorderLayer.isHidden = true
      updateCrosshairLayers()
    case .applicationWindow:
      refreshWindowHover()
    }
  }

  private func refreshWindowHover() {
    guard selectionEnabled, interactionMode == .applicationWindow else {
      hoveredWindowCandidate = nil
      updateApplicationSelectionLayers()
      return
    }
    let localPoint: CGPoint
    if let window = self.window {
      let mouseLocationInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
      localPoint = convert(mouseLocationInWindow, from: nil)
    } else {
      localPoint = currentMousePosition
    }
    updateWindowHover(at: localPoint)
  }

  private func updateWindowHover(at point: CGPoint) {
    currentMousePosition = point
    guard window != nil else {
      hoveredWindowCandidate = nil
      updateApplicationSelectionLayers()
      return
    }
    let screenPoint = NSEvent.mouseLocation
    hoveredWindowCandidate = windowSelectionSnapshot?.hitTest(at: screenPoint)
    updateApplicationSelectionLayers()
  }

  private func updateApplicationSelectionLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    crosshairIndicatorLayer.isHidden = true
    horizontalCrosshairLayer.isHidden = true
    verticalCrosshairLayer.isHidden = true

    if let hoveredWindowCandidate {
      let localRect = convertToLocalRect(hoveredWindowCandidate.target.frame).intersection(bounds)
      if localRect.isEmpty {
        selectionBorderLayer.isHidden = true
        dimLayer.mask = nil
      } else {
        selectionBorderLayer.isHidden = false
        selectionBorderLayer.path = CGPath(rect: localRect, transform: nil)
        updateDimLayerMask(for: localRect)
      }
    } else {
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
    }

    CATransaction.commit()
    needsDisplay = true
  }

  private func convertToLocalRect(_ screenRect: CGRect) -> CGRect {
    guard let window = self.window else { return screenRect }
    return CGRect(
      x: screenRect.origin.x - window.frame.origin.x,
      y: screenRect.origin.y - window.frame.origin.y,
      width: screenRect.width,
      height: screenRect.height
    )
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    guard selectionEnabled else { return }
    let point = convert(event.locationInWindow, from: nil)
    switch interactionMode {
    case .manualRegion:
      selectionStartPoint = point
      selectionEndPoint = point
      isSelecting = true
      updateSelectionLayers()
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard selectionEnabled else { return }
    let point = convert(event.locationInWindow, from: nil)
    switch interactionMode {
    case .manualRegion:
      guard isSelecting else { return }
      selectionEndPoint = point
      updateSelectionLayers()
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard selectionEnabled else { return }
    let point = convert(event.locationInWindow, from: nil)

    switch interactionMode {
    case .manualRegion:
      guard isSelecting else { return }
      selectionEndPoint = point
      isSelecting = false

      if let selectionRect = calculateSelectionRect(),
        selectionRect.width > 5 && selectionRect.height > 5
      {
        delegate?.overlayView(self, didSelectRect: selectionRect)
      } else {
        // Reset selection state if too small
        resetSelection()
      }
    case .applicationWindow:
      updateWindowHover(at: point)
      if let hoveredWindowCandidate {
        delegate?.overlayView(self, didSelectWindow: hoveredWindowCandidate.target)
      }
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard selectionEnabled else { return }
    activeCursor.set()
    let point = convert(event.locationInWindow, from: nil)
    switch interactionMode {
    case .manualRegion:
      currentMousePosition = point
      if !isSelecting {
        updateCrosshairLayers()
      }
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    delegate?.overlayViewDidCancel(self)
  }

  private var activeCursor: NSCursor {
    guard selectionEnabled else { return .arrow }
    return interactionMode == .manualRegion ? .crosshair : .pointingHand
  }

  var isManualSelectionInProgress: Bool {
    interactionMode == .manualRegion && isSelecting
  }
}
