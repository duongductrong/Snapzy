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

/// Callback type for displays that should be prepared during a selection session.
typealias AreaSelectionDisplayActivationHandler = (CGDirectDisplayID) -> Void

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
  private var liveFallbackDisplayIDs = Set<CGDirectDisplayID>()
  private var interactionMode: AreaSelectionInteractionMode = .manualRegion
  private var allowsApplicationWindowSelection = false
  private var applicationConfiguration: AreaSelectionApplicationConfiguration?
  private var displayActivationHandler: AreaSelectionDisplayActivationHandler?
  private var windowSelectionSnapshot: WindowSelectionSnapshot?
  private var windowSelectionTask: Task<Void, Never>?
  private var selectionSessionID = UUID()
  private var activeWindow: AreaSelectionWindow?
  private var keyboardOwnerDisplayID: CGDirectDisplayID?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  private var requestedDisplayActivationIDs = Set<CGDirectDisplayID>()
  private var deferredBackdropDisplayIDs = Set<CGDirectDisplayID>()
  private var manualSelectionStartPoint: CGPoint?
  private var manualSelectionCurrentPoint: CGPoint?
  private weak var manualSelectionSourceWindow: AreaSelectionWindow?
  private var manualSelectionLocalMonitor: Any?

  /// Whether the overlay should be dismissed immediately after a selection is made.
  /// When `false`, the caller is responsible for calling `cancelSelection()` to dismiss.
  private(set) var dismissesAfterSelection = true

  func setDismissesAfterSelection(_ value: Bool) {
    dismissesAfterSelection = value
  }

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
          DiagnosticLogger.shared.log(
            .debug,
            .capture,
            "Area selection pooled window frame resynced",
            context: ["displayID": "\(displayID)"]
          )
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

  /// Reset window interaction state without hiding.
  private func resetPooledWindows() {
    for (_, window) in windowPool {
      window.setReceivesKeyboardInput(false)
      window.overlayView.resetSelection()
      window.overlayView.clearBackdrop()
    }
    activeWindow = nil
  }

  /// Hide all pooled windows.
  private func hidePooledWindows() {
    for (_, window) in windowPool {
      window.orderOut(nil)
    }
  }

  /// Deactivate all windows (hide, don't close)
  private func deactivatePooledWindows() {
    resetPooledWindows()
    hidePooledWindows()
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
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    completion: @escaping AreaSelectionResultCompletion
  ) {
    startSelection(
      mode: mode,
      backdrops: backdrops,
      applicationConfiguration: nil,
      initialInteractionMode: initialInteractionMode,
      completion: completion
    )
  }

  func startSelection(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration?,
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    onDisplayActivationRequested: AreaSelectionDisplayActivationHandler? = nil,
    completion: @escaping AreaSelectionResultCompletion
  ) {
    self.completion = nil
    completionWithMode = nil
    completionWithResult = completion
    startSelectionSession(
      mode: mode,
      backdrops: backdrops,
      applicationConfiguration: applicationConfiguration,
      initialInteractionMode: initialInteractionMode,
      onDisplayActivationRequested: onDisplayActivationRequested
    )
  }

  private func startSelectionSession(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration? = nil,
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    onDisplayActivationRequested: AreaSelectionDisplayActivationHandler? = nil
  ) {
    // Always clean up prior session's monitors to prevent orphaned leaks
    removeEscapeMonitors()
    clearManualSelectionTracking(render: false)
    cancelWindowSelectionTask()
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Area selection session started",
      context: [
        "mode": "\(mode)",
        "backdropCount": "\(backdrops.count)",
        "applicationSelection": applicationConfiguration == nil ? "false" : "true",
      ]
    )

    selectionMode = mode
    selectionBackdrops = backdrops
    liveFallbackDisplayIDs.removeAll()
    self.applicationConfiguration = applicationConfiguration
    displayActivationHandler = onDisplayActivationRequested
    requestedDisplayActivationIDs.removeAll()
    deferredBackdropDisplayIDs.removeAll()
    allowsApplicationWindowSelection = applicationConfiguration != nil
    interactionMode = applicationConfiguration == nil ? .manualRegion : initialInteractionMode
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
      selectionBackdrops.isEmpty || selectionBackdrops[displayID] != nil || liveFallbackDisplayIDs.contains(displayID)
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
    switch selectionMode {
    case .screenshot, .scrollingCapture:
      return CaptureOverlayShortcutSettings.matchesApplicationCaptureShortcut(event)
    case .recording:
      return CaptureOverlayShortcutSettings.matchesRecordingApplicationCaptureShortcut(event)
    }
  }

  private func toggleInteractionMode() {
    guard manualSelectionStartPoint == nil,
          !windowPool.values.contains(where: { $0.overlayView.isManualSelectionInProgress }) else {
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

  func applyBackdrop(_ backdrop: AreaSelectionBackdrop, for displayID: CGDirectDisplayID) {
    let shouldDeferVisualBackdrop = manualSelectionStartPoint != nil
      && selectionBackdrops[displayID] == nil
    liveFallbackDisplayIDs.remove(displayID)
    selectionBackdrops[displayID] = backdrop
    guard let window = windowPool[displayID] else { return }
    if shouldDeferVisualBackdrop {
      // Avoid a visible freeze jump when a secondary display finishes snapshotting mid-drag.
      deferredBackdropDisplayIDs.insert(displayID)
    } else {
      deferredBackdropDisplayIDs.remove(displayID)
      window.overlayView.applyBackdrop(backdrop)
    }
    window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
    window.overlayView.activatePendingSelectionIfNeeded()
    window.overlayView.refreshCursor()
    renderManualSelectionIfNeeded()
  }

  func enableLiveFallbackSelection(for displayID: CGDirectDisplayID) {
    liveFallbackDisplayIDs.insert(displayID)
    guard let window = windowPool[displayID] else { return }
    window.overlayView.clearBackdrop()
    window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
    window.overlayView.activatePendingSelectionIfNeeded()
    window.overlayView.refreshCursor()
    renderManualSelectionIfNeeded()
  }

  func withDisplayOverlayHidden<T>(
    for displayID: CGDirectDisplayID,
    perform work: () -> T
  ) -> T {
    guard let window = windowPool[displayID], window.isVisible else {
      return work()
    }

    // Capture-excluded overlays can stay visible without being baked into the snapshot.
    if window.sharingType == .none {
      return work()
    }

    window.orderOut(nil)
    let result = work()
    window.orderFrontRegardless()
    window.activateKeyboardInputIfNeeded()
    window.overlayView.refreshCursor()
    return result
  }

  private func requestDisplayActivationIfNeeded(for window: AreaSelectionWindow) {
    guard interactionMode == .manualRegion else { return }
    guard selectionMode == .screenshot else { return }
    guard let displayID = window.displayID else { return }
    if enableLiveSelectionDuringManualDrag(for: displayID) {
      return
    }
    requestDisplayActivationIfNeeded(for: displayID)
  }

  private func requestDisplayActivationIfNeeded(for displayID: CGDirectDisplayID) {
    guard selectionBackdrops[displayID] == nil else { return }
    guard requestedDisplayActivationIDs.insert(displayID).inserted else { return }
    displayActivationHandler?(displayID)
  }

  private func completeSelection(target: AreaSelectionTarget, from window: AreaSelectionWindow) {
    let rect = target.rect
    let intersectingDisplayIDs = displayIDsIntersecting(rect)
    let displayID = target.windowTarget?.displayID
      ?? primaryDisplayID(for: rect, fallback: window.displayID)
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Area selection completed",
      context: [
        "mode": "\(selectionMode)",
        "displayID": displayID.map { "\($0)" } ?? "unknown",
        "target": target.windowTarget == nil ? "region" : "window",
      ]
    )
    removeManualSelectionMonitor()
    removeEscapeMonitors()
    cancelWindowSelectionTask()
    resetPooledWindows()
    if dismissesAfterSelection {
      hidePooledWindows()
    }
    completion?(rect)
    completionWithMode?(rect, selectionMode)
    if let displayID {
      let displayIDs = target.windowTarget.map { Set([$0.displayID]) } ?? intersectingDisplayIDs
      completionWithResult?(
        AreaSelectionResult(
          target: target,
          displayID: displayID,
          mode: selectionMode,
          displayIDs: displayIDs.isEmpty ? [displayID] : displayIDs
        )
      )
    } else {
      completionWithResult?(nil)
    }
    resetCallbacks()
    dismissesAfterSelection = true
  }

  /// Cancel the current selection
  func cancelSelection() {
    DiagnosticLogger.shared.log(.info, .capture, "Area selection cancelled", context: ["mode": "\(selectionMode)"])
    clearManualSelectionTracking(render: false)
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
    liveFallbackDisplayIDs.removeAll()
    requestedDisplayActivationIDs.removeAll()
    deferredBackdropDisplayIDs.removeAll()
    applicationConfiguration = nil
    displayActivationHandler = nil
    allowsApplicationWindowSelection = false
    interactionMode = .manualRegion
    windowSelectionSnapshot = nil
    keyboardOwnerDisplayID = nil
  }

  private func beginManualSelection(at screenPoint: CGPoint, from window: AreaSelectionWindow) {
    guard interactionMode == .manualRegion else { return }
    guard let displayID = window.displayID, selectionEnabled(for: displayID) else {
      requestDisplayActivationIfNeeded(for: window)
      return
    }

    manualSelectionStartPoint = screenPoint
    manualSelectionCurrentPoint = screenPoint
    manualSelectionSourceWindow = window
    activeWindow = window
    installManualSelectionMonitorIfNeeded()
    requestDisplayActivationForManualSelection()
    renderManualSelectionIfNeeded()
  }

  private func updateManualSelection(to screenPoint: CGPoint) {
    guard manualSelectionStartPoint != nil else { return }
    manualSelectionCurrentPoint = screenPoint
    requestDisplayActivationForManualSelection()
    renderManualSelectionIfNeeded()
  }

  private func endManualSelection(at screenPoint: CGPoint) {
    guard manualSelectionStartPoint != nil else { return }
    manualSelectionCurrentPoint = screenPoint
    removeManualSelectionMonitor()

    guard let rect = manualSelectionRect, rect.width > 5, rect.height > 5 else {
      clearManualSelectionTracking(render: true)
      return
    }

    let sourceWindow = manualSelectionSourceWindow
      ?? activeWindow
      ?? window(containing: screenPoint)
      ?? window(containing: rect.origin)
    guard let sourceWindow else {
      clearManualSelectionTracking(render: true)
      return
    }

    manualSelectionStartPoint = nil
    manualSelectionCurrentPoint = nil
    manualSelectionSourceWindow = nil
    completeSelection(target: .rect(rect), from: sourceWindow)
  }

  private var manualSelectionRect: CGRect? {
    guard let start = manualSelectionStartPoint,
          let current = manualSelectionCurrentPoint else {
      return nil
    }
    return CGRect(
      x: min(start.x, current.x),
      y: min(start.y, current.y),
      width: abs(current.x - start.x),
      height: abs(current.y - start.y)
    )
  }

  private func installManualSelectionMonitorIfNeeded() {
    guard manualSelectionLocalMonitor == nil else { return }
    manualSelectionLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp]
    ) { [weak self] event in
      switch event.type {
      case .leftMouseDragged:
        let mouseLocation = NSEvent.mouseLocation
        MainActor.assumeIsolated {
          self?.updateManualSelection(to: mouseLocation)
        }
        return nil
      case .leftMouseUp:
        let mouseLocation = NSEvent.mouseLocation
        MainActor.assumeIsolated {
          self?.endManualSelection(at: mouseLocation)
        }
        return nil
      default:
        return event
      }
    }
  }

  private func removeManualSelectionMonitor() {
    if let monitor = manualSelectionLocalMonitor {
      NSEvent.removeMonitor(monitor)
      manualSelectionLocalMonitor = nil
    }
  }

  private func clearManualSelectionTracking(render: Bool) {
    removeManualSelectionMonitor()
    manualSelectionStartPoint = nil
    manualSelectionCurrentPoint = nil
    manualSelectionSourceWindow = nil
    if render {
      applyDeferredBackdropsIfPossible()
      for (_, window) in windowPool {
        window.overlayView.resetSelection()
      }
    }
  }

  private func applyDeferredBackdropsIfPossible() {
    guard manualSelectionStartPoint == nil else { return }
    for displayID in deferredBackdropDisplayIDs {
      guard let backdrop = selectionBackdrops[displayID],
            let window = windowPool[displayID] else {
        continue
      }
      window.overlayView.applyBackdrop(backdrop)
      window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
      window.overlayView.refreshCursor()
    }
    deferredBackdropDisplayIDs.removeAll()
  }

  private func renderManualSelectionIfNeeded() {
    let rect = manualSelectionRect
    let currentPoint = manualSelectionCurrentPoint
    for (_, window) in windowPool {
      window.overlayView.renderManualSelection(
        screenRect: rect,
        currentScreenPoint: currentPoint
      )
    }
  }

  private func requestDisplayActivationForManualSelection() {
    guard selectionMode == .screenshot else { return }
    let rect = manualSelectionRect
    let currentPoint = manualSelectionCurrentPoint
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      let shouldPrepare = currentPoint.map { screen.frame.contains($0) } == true
        || rect.map { screen.frame.intersects($0) } == true
      if shouldPrepare {
        if enableLiveSelectionDuringManualDrag(for: displayID) {
          continue
        }
        requestDisplayActivationIfNeeded(for: displayID)
      }
    }
  }

  @discardableResult
  private func enableLiveSelectionDuringManualDrag(for displayID: CGDirectDisplayID) -> Bool {
    guard manualSelectionStartPoint != nil else { return false }
    guard selectionBackdrops[displayID] == nil else { return false }
    guard liveFallbackDisplayIDs.insert(displayID).inserted else { return true }
    guard let window = windowPool[displayID] else { return true }
    window.overlayView.clearBackdrop()
    window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
    window.overlayView.refreshCursor()
    return true
  }

  private func displayIDsIntersecting(_ rect: CGRect) -> Set<CGDirectDisplayID> {
    Set(
      NSScreen.screens.compactMap { screen in
        guard screen.frame.intersects(rect) else { return nil }
        return screen.displayID
      }
    )
  }

  private func primaryDisplayID(for rect: CGRect, fallback: CGDirectDisplayID?) -> CGDirectDisplayID? {
    let bestMatch = NSScreen.screens
      .compactMap { screen -> (displayID: CGDirectDisplayID, area: CGFloat)? in
        guard let displayID = screen.displayID else { return nil }
        let intersection = screen.frame.intersection(rect)
        guard !intersection.isEmpty else { return nil }
        return (displayID, intersection.width * intersection.height)
      }
      .max { $0.area < $1.area }

    return bestMatch?.displayID ?? fallback
  }

  private func window(containing screenPoint: CGPoint) -> AreaSelectionWindow? {
    for screen in NSScreen.screens {
      guard screen.frame.contains(screenPoint),
            let displayID = screen.displayID,
            let window = windowPool[displayID] else {
        continue
      }
      return window
    }
    return nil
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

  func areaSelectionWindowDidRequestDisplayActivation(_ window: AreaSelectionWindow) {
    requestDisplayActivationIfNeeded(for: window)
  }

  func areaSelectionWindow(_ window: AreaSelectionWindow, manualSelectionBeganAt screenPoint: CGPoint) {
    beginManualSelection(at: screenPoint, from: window)
  }

  func areaSelectionWindow(_ window: AreaSelectionWindow, manualSelectionChangedTo screenPoint: CGPoint) {
    updateManualSelection(to: screenPoint)
  }

  func areaSelectionWindow(_ window: AreaSelectionWindow, manualSelectionEndedAt screenPoint: CGPoint) {
    endManualSelection(at: screenPoint)
  }
}

// MARK: - AreaSelectionWindowDelegate Protocol

protocol AreaSelectionWindowDelegate: AnyObject {
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectRect rect: CGRect)
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectWindow target: WindowCaptureTarget)
  func areaSelectionWindowDidCancel(_ window: AreaSelectionWindow)
  func areaSelectionWindowDidBecomeActive(_ window: AreaSelectionWindow)
  func areaSelectionWindow(_ window: AreaSelectionWindow, didReceiveKeyEvent event: NSEvent) -> Bool
  func areaSelectionWindowDidRequestDisplayActivation(_ window: AreaSelectionWindow)
  func areaSelectionWindow(_ window: AreaSelectionWindow, manualSelectionBeganAt screenPoint: CGPoint)
  func areaSelectionWindow(_ window: AreaSelectionWindow, manualSelectionChangedTo screenPoint: CGPoint)
  func areaSelectionWindow(_ window: AreaSelectionWindow, manualSelectionEndedAt screenPoint: CGPoint)
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
    self.sharingType = .none
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

  func overlayViewDidRequestDisplayActivation(_ view: AreaSelectionOverlayView) {
    selectionDelegate?.areaSelectionWindowDidRequestDisplayActivation(self)
  }

  func overlayView(_ view: AreaSelectionOverlayView, manualSelectionBeganAt point: CGPoint) {
    selectionDelegate?.areaSelectionWindow(self, manualSelectionBeganAt: convertToScreenPoint(point))
  }

  func overlayView(_ view: AreaSelectionOverlayView, manualSelectionChangedTo point: CGPoint) {
    selectionDelegate?.areaSelectionWindow(self, manualSelectionChangedTo: convertToScreenPoint(point))
  }

  func overlayView(_ view: AreaSelectionOverlayView, manualSelectionEndedAt point: CGPoint) {
    selectionDelegate?.areaSelectionWindow(self, manualSelectionEndedAt: convertToScreenPoint(point))
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

  private func convertToScreenPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: frame.origin.x + point.x,
      y: frame.origin.y + point.y
    )
  }
}

// MARK: - AreaSelectionOverlayViewDelegate Protocol

protocol AreaSelectionOverlayViewDelegate: AnyObject {
  func overlayView(_ view: AreaSelectionOverlayView, didSelectRect rect: CGRect)
  func overlayView(_ view: AreaSelectionOverlayView, didSelectWindow target: WindowCaptureTarget)
  func overlayViewDidCancel(_ view: AreaSelectionOverlayView)
  func overlayViewDidRequestDisplayActivation(_ view: AreaSelectionOverlayView)
  func overlayView(_ view: AreaSelectionOverlayView, manualSelectionBeganAt point: CGPoint)
  func overlayView(_ view: AreaSelectionOverlayView, manualSelectionChangedTo point: CGPoint)
  func overlayView(_ view: AreaSelectionOverlayView, manualSelectionEndedAt point: CGPoint)
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
  private var pendingSelectionStartPoint: CGPoint?
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
  private var sizeIndicatorBackgroundLayer: CALayer!
  private var sizeIndicatorTextLayer: CATextLayer!
  private var modeHintBackgroundLayer: CALayer!
  private var modeHintTextLayer: CATextLayer!

  private static let hiddenManualRegionCursor: NSCursor = {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 1,
      pixelsHigh: 1,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 4,
      bitsPerPixel: 32
    )
    if let rep {
      if let bitmapData = rep.bitmapData {
        for offset in 0..<(rep.bytesPerRow * rep.pixelsHigh) {
          bitmapData[offset] = 0
        }
      }
      image.addRepresentation(rep)
    }
    return NSCursor(image: image, hotSpot: .zero)
  }()

  private static let applicationWindowCursor: NSCursor = {
    let pointSize: CGFloat = 16
    let baseConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    let whiteConfig = baseConfig.applying(
      NSImage.SymbolConfiguration(paletteColors: [.white])
    )
    let blackConfig = baseConfig.applying(
      NSImage.SymbolConfiguration(paletteColors: [.black])
    )

    guard
      let whiteSymbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(whiteConfig),
      let blackSymbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(blackConfig)
    else {
      return .pointingHand
    }

    let padding: CGFloat = 5
    let canvasSize = NSSize(
      width: whiteSymbol.size.width + padding * 2,
      height: whiteSymbol.size.height + padding * 2
    )
    let composed = NSImage(size: canvasSize)
    composed.lockFocus()

    // Stamp the black symbol at 1px offsets around the center to form a dark
    // outline halo. This guarantees contrast against both bright and dark
    // window backgrounds without relying on a soft shadow that can wash out
    // against pure white.
    let haloOffsets: [(CGFloat, CGFloat)] = [
      (-1, 0), (1, 0), (0, -1), (0, 1),
      (-1, -1), (1, -1), (-1, 1), (1, 1),
    ]
    for (dx, dy) in haloOffsets {
      blackSymbol.draw(
        at: NSPoint(x: padding + dx, y: padding + dy),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
      )
    }

    whiteSymbol.draw(
      at: NSPoint(x: padding, y: padding),
      from: .zero,
      operation: .sourceOver,
      fraction: 1.0
    )

    composed.unlockFocus()

    return NSCursor(
      image: composed,
      hotSpot: NSPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    )
  }()

  // Appearance constants
  private let dimColor = NSColor.black.withAlphaComponent(0.4)
  private let crosshairColor = NSColor.white.withAlphaComponent(0.6)
  private let selectionBorderColor = NSColor.white
  private let selectionBorderWidth: CGFloat = 2.0
  private let crosshairIndicatorSize: CGFloat = 10.0
  private let crosshairIndicatorLineWidth: CGFloat = 1.5
  private let crosshairIndicatorCenterRadius: CGFloat = 6.0
  private let overlayFont = NSFont.systemFont(ofSize: 12, weight: .medium)
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

    // Horizontal crosshair line (hidden - using compact indicator instead)
    horizontalCrosshairLayer = CAShapeLayer()
    horizontalCrosshairLayer.strokeColor = crosshairColor.cgColor
    horizontalCrosshairLayer.lineWidth = 1.0
    horizontalCrosshairLayer.isHidden = true
    horizontalCrosshairLayer.actions = disabledActions
    rootLayer.addSublayer(horizontalCrosshairLayer)

    // Vertical crosshair line (hidden - using compact indicator instead)
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

    sizeIndicatorBackgroundLayer = CALayer()
    sizeIndicatorBackgroundLayer.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
    sizeIndicatorBackgroundLayer.cornerRadius = 4
    sizeIndicatorBackgroundLayer.actions = disabledActions
    sizeIndicatorBackgroundLayer.isHidden = true
    rootLayer.addSublayer(sizeIndicatorBackgroundLayer)

    sizeIndicatorTextLayer = CATextLayer()
    configureOverlayTextLayer(sizeIndicatorTextLayer)
    rootLayer.addSublayer(sizeIndicatorTextLayer)

    modeHintBackgroundLayer = CALayer()
    modeHintBackgroundLayer.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
    modeHintBackgroundLayer.cornerRadius = 8
    modeHintBackgroundLayer.actions = disabledActions
    modeHintBackgroundLayer.isHidden = true
    rootLayer.addSublayer(modeHintBackgroundLayer)

    modeHintTextLayer = CATextLayer()
    configureOverlayTextLayer(modeHintTextLayer)
    rootLayer.addSublayer(modeHintTextLayer)

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
    delegate?.overlayViewDidRequestDisplayActivation(self)
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
    pendingSelectionStartPoint = nil
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
    hideSizeIndicator()
    dimLayer.mask = nil
    dimLayer.frame = bounds

    CATransaction.commit()

    // Update interaction state immediately
    if selectionEnabled {
      refreshInteractionState()
      refreshActiveCursor()
    }

    updateModeHint()
  }

  func setSelectionEnabled(_ enabled: Bool) {
    let wasSelectionEnabled = selectionEnabled
    selectionEnabled = enabled
    if enabled, !wasSelectionEnabled {
      initializeCrosshairAtCurrentMousePosition()
      refreshInteractionState()
    } else if !enabled {
      isSelecting = false
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      crosshairIndicatorLayer.isHidden = true
      selectionBorderLayer.isHidden = true
      hideSizeIndicator()
      dimLayer.mask = nil
      CATransaction.commit()
    }
    refreshActiveCursor()
  }

  func activatePendingSelectionIfNeeded() {
    guard selectionEnabled, interactionMode == .manualRegion else { return }
    guard let pendingSelectionStartPoint else { return }
    self.pendingSelectionStartPoint = nil
    isSelecting = true
    delegate?.overlayView(self, manualSelectionBeganAt: pendingSelectionStartPoint)
    delegate?.overlayView(self, manualSelectionChangedTo: currentMousePosition)
  }

  func applyBackdrop(_ backdrop: AreaSelectionBackdrop) {
    let imageSize = CGSize(
      width: CGFloat(backdrop.image.width) / max(backdrop.scaleFactor, 1),
      height: CGFloat(backdrop.image.height) / max(backdrop.scaleFactor, 1)
    )
    let layerImage = NSImage(cgImage: backdrop.image, size: imageSize)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.frame = bounds
    snapshotLayer.contents = layerImage
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
    hideSizeIndicator()
    CATransaction.commit()

    // Rebuild tracking areas for new bounds
    updateTrackingAreas()
    updateModeHint()
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
    hideSizeIndicator()
    CATransaction.commit()
    updateModeHint()
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

  private var screenScaleFactor: CGFloat {
    window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
  }

  private var overlayTextAttributes: [NSAttributedString.Key: Any] {
    [
      .font: overlayFont,
      .foregroundColor: NSColor.white,
    ]
  }

  private func configureOverlayTextLayer(_ textLayer: CATextLayer) {
    textLayer.actions = disabledActions
    textLayer.font = overlayFont as CTFont
    textLayer.fontSize = overlayFont.pointSize
    textLayer.foregroundColor = NSColor.white.cgColor
    textLayer.alignmentMode = .left
    textLayer.contentsScale = screenScaleFactor
    textLayer.truncationMode = .none
    textLayer.isWrapped = false
    textLayer.isHidden = true
  }

  private func updateTextLayerScales() {
    let scale = screenScaleFactor
    sizeIndicatorTextLayer.contentsScale = scale
    modeHintTextLayer.contentsScale = scale
  }

  private func hideSizeIndicator() {
    sizeIndicatorBackgroundLayer.isHidden = true
    sizeIndicatorTextLayer.isHidden = true
  }

  private func updateSizeIndicator(for rect: CGRect, measuredSize: CGSize? = nil) {
    let displayedSize = measuredSize ?? rect.size
    let sizeText = "\(Int(displayedSize.width)) x \(Int(displayedSize.height))"
    let attributes = overlayTextAttributes
    let textSize = sizeText.size(withAttributes: attributes)
    let padding: CGFloat = 6
    var backgroundRect = CGRect(
      x: rect.maxX - textSize.width - padding * 2 - 4,
      y: rect.minY - textSize.height - padding - 8,
      width: textSize.width + padding * 2,
      height: textSize.height + padding
    )

    if backgroundRect.minY < bounds.minY {
      backgroundRect.origin.y = rect.maxY + 4
    }
    if backgroundRect.maxY > bounds.maxY {
      backgroundRect.origin.y = max(bounds.minY + 4, rect.minY - textSize.height - padding - 8)
    }
    if backgroundRect.maxX > bounds.maxX {
      backgroundRect.origin.x = rect.minX
    }

    let edgeInset: CGFloat = 4
    if backgroundRect.width <= bounds.width - edgeInset * 2 {
      backgroundRect.origin.x = min(
        max(backgroundRect.origin.x, bounds.minX + edgeInset),
        bounds.maxX - backgroundRect.width - edgeInset
      )
    } else {
      backgroundRect.origin.x = bounds.minX + edgeInset
    }

    updateTextLayerScales()
    sizeIndicatorBackgroundLayer.frame = backgroundRect
    sizeIndicatorBackgroundLayer.isHidden = false
    sizeIndicatorTextLayer.string = sizeText
    sizeIndicatorTextLayer.frame = CGRect(
      x: backgroundRect.minX + padding,
      y: backgroundRect.minY + padding / 2,
      width: textSize.width,
      height: textSize.height
    )
    sizeIndicatorTextLayer.isHidden = false
  }

  private func updateModeHint() {
    guard allowsApplicationWindowSelection else {
      modeHintBackgroundLayer.isHidden = true
      modeHintTextLayer.isHidden = true
      return
    }

    let shortcut: CaptureOverlayShortcut?
    switch selectionMode {
    case .screenshot, .scrollingCapture:
      shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    case .recording:
      shortcut = CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
    }

    guard let shortcut, !shortcut.isIndependent else {
      modeHintBackgroundLayer.isHidden = true
      modeHintTextLayer.isHidden = true
      return
    }

    let hint = interactionMode == .manualRegion
      ? L10n.ScreenCapture.applicationModeHint(shortcut.displayString)
      : L10n.ScreenCapture.manualModeHint(shortcut.displayString)
    let attributes = overlayTextAttributes
    let hintSize = hint.size(withAttributes: attributes)
    let padding = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    let backgroundRect = CGRect(
      x: (bounds.width - hintSize.width) / 2 - padding.left,
      y: 24,
      width: hintSize.width + padding.left + padding.right,
      height: hintSize.height + padding.top + padding.bottom
    )

    updateTextLayerScales()
    modeHintBackgroundLayer.frame = backgroundRect
    modeHintBackgroundLayer.isHidden = false
    modeHintTextLayer.string = hint
    modeHintTextLayer.frame = CGRect(
      x: backgroundRect.minX + padding.left,
      y: backgroundRect.minY + padding.bottom - 1,
      width: hintSize.width,
      height: hintSize.height
    )
    modeHintTextLayer.isHidden = false
  }

  func setAllowsApplicationWindowSelection(_ allowsApplicationWindowSelection: Bool) {
    self.allowsApplicationWindowSelection = allowsApplicationWindowSelection
    updateModeHint()
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
    updateModeHint()
  }

  func renderManualSelection(screenRect: CGRect?, currentScreenPoint: CGPoint?) {
    guard interactionMode == .manualRegion else { return }

    let localCurrentPoint: CGPoint?
    if let currentScreenPoint, let window = self.window {
      let pointInWindow = window.convertPoint(fromScreen: currentScreenPoint)
      localCurrentPoint = convert(pointInWindow, from: nil)
      currentMousePosition = localCurrentPoint ?? currentMousePosition
    } else {
      localCurrentPoint = nil
    }

    guard let screenRect, !screenRect.isEmpty else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
      hideSizeIndicator()
      if let localCurrentPoint, bounds.contains(localCurrentPoint), selectionEnabled {
        crosshairIndicatorLayer.isHidden = false
        crosshairIndicatorLayer.path = createCrosshairIndicatorPath(at: localCurrentPoint)
      } else {
        crosshairIndicatorLayer.isHidden = true
      }
      CATransaction.commit()
      return
    }

    let localRect = convertToLocalRect(screenRect).intersection(bounds)
    let showsCurrentPointer = localCurrentPoint.map { bounds.contains($0) } == true

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    horizontalCrosshairLayer.isHidden = true
    verticalCrosshairLayer.isHidden = true
    crosshairIndicatorLayer.isHidden = !showsCurrentPointer
    if let localCurrentPoint, showsCurrentPointer {
      crosshairIndicatorLayer.path = createCrosshairIndicatorPath(at: localCurrentPoint)
    }

    if localRect.isEmpty {
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
      hideSizeIndicator()
    } else {
      selectionBorderLayer.isHidden = false
      selectionBorderLayer.path = CGPath(rect: localRect, transform: nil)
      updateDimLayerMask(for: localRect)
      if showsCurrentPointer {
        updateSizeIndicator(for: localRect, measuredSize: screenRect.size)
      } else {
        hideSizeIndicator()
      }
    }
    CATransaction.commit()
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
      if !isSelecting {
        selectionBorderLayer.isHidden = true
        updateCrosshairLayers()
      }
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
    hideSizeIndicator()

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
    updateModeHint()
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
    let point = convert(event.locationInWindow, from: nil)
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else {
      if interactionMode == .manualRegion {
        pendingSelectionStartPoint = point
      }
      return
    }
    switch interactionMode {
    case .manualRegion:
      isSelecting = true
      delegate?.overlayView(self, manualSelectionBeganAt: point)
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else {
      if pendingSelectionStartPoint != nil {
        currentMousePosition = point
      }
      return
    }
    switch interactionMode {
    case .manualRegion:
      guard isSelecting else { return }
      delegate?.overlayView(self, manualSelectionChangedTo: point)
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else {
      pendingSelectionStartPoint = nil
      return
    }

    switch interactionMode {
    case .manualRegion:
      guard isSelecting else { return }
      isSelecting = false

      delegate?.overlayView(self, manualSelectionEndedAt: point)
    case .applicationWindow:
      updateWindowHover(at: point)
      if let hoveredWindowCandidate {
        delegate?.overlayView(self, didSelectWindow: hoveredWindowCandidate.target)
      }
    }
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else { return }
    activeCursor.set()
    switch interactionMode {
    case .manualRegion:
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
    return interactionMode == .manualRegion
      ? Self.hiddenManualRegionCursor
      : Self.applicationWindowCursor
  }

  var isManualSelectionInProgress: Bool {
    interactionMode == .manualRegion && isSelecting
  }
}
