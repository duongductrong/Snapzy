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

/// Callback type invoked when a frozen session should re-freeze its displays after a
/// Space/app/desktop transition settles. Only frozen screenshot sessions provide this;
/// its presence is the immutable frozen-vs-live discriminator (unlike the mutable
/// `selectionBackdrops` visibility, which the luma recapture overwrites).
typealias AreaSelectionTransitionRecaptureHandler = @MainActor () -> Void

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

/// Reason for triggering a backdrop recapture
enum RecaptureReason {
  case spaceChange
  case appActivation
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
  private var transitionRecaptureHandler: AreaSelectionTransitionRecaptureHandler?
  private var windowSelectionSnapshot: WindowSelectionSnapshot?
  private var windowSelectionTask: Task<Void, Never>?
  private var selectionSessionID = UUID()
  private var activeWindow: AreaSelectionWindow?
  private var keyboardOwnerDisplayID: CGDirectDisplayID?
  /// True while a selection overlay session is presented (from `startSelectionSession` until
  /// teardown via `resetCallbacks`). Read cross-actor by other overlays (e.g. `RecordingCoordinator`)
  /// to yield Escape to this topmost overlay. Deterministic — does not depend on window-key timing.
  private(set) var isPresenting = false
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  /// Drives "key-follows-pointer" for non-activated live sessions. Backdrop-less sessions (live
  /// screenshot, recording, OCR, cutout) deliberately skip `NSApp.activate` to avoid dimming the
  /// windows being captured, so the app stays inactive. While inactive, only the KEY overlay panel
  /// gets mouse-moved / cursor-rect handling — that is why the crosshair shows only on the display
  /// whose overlay was made key at session start. macOS never re-keys a nonactivating panel on
  /// hover, and (proven empirically) neither `NSEvent` monitors nor `NSCursor.set()` reliably reach
  /// a non-key overlay of an inactive app during idle hover. This lightweight timer polls the
  /// pointer location (no permission required, unlike a `CGEventTap`) and moves keyboard/key
  /// ownership to the overlay under the pointer, so that overlay's own cursor rects render the
  /// crosshair — exactly replicating the working active-display behavior on every display. Frozen
  /// sessions activate the app and don't need this.
  private var pointerTrackingTimer: Timer?
  private var requestedDisplayActivationIDs = Set<CGDirectDisplayID>()
  private var deferredBackdropDisplayIDs = Set<CGDirectDisplayID>()
  private var manualSelectionStartPoint: CGPoint?
  private var manualSelectionCurrentPoint: CGPoint?
  private weak var manualSelectionSourceWindow: AreaSelectionWindow?
  private var manualSelectionLocalMonitor: Any?
  /// Observe-only global counterpart to `manualSelectionLocalMonitor`. The local monitor only
  /// fires while Snapzy is the active app; on a `.nonactivatingPanel` shown via a global
  /// shortcut (e.g. ⌘⇧4 while another app is frontmost) the first drag/up can land before the
  /// app activates, so the local monitor never sees them and the selection silently resets.
  /// A global monitor still receives those events, ensuring the first gesture commits.
  private var manualSelectionGlobalMonitor: Any?
  private var manualSelectionKeyLocalMonitor: Any?
  private var manualSelectionKeyGlobalMonitor: Any?
  /// Re-asserts the crosshair if the app regains focus mid-drag (e.g. after a background capture
  /// tool bounces focus). Installed alongside the drag monitors, torn down with them.
  private var appActivationObserver: Any?
  private var sessionSpaceChangeObserver: Any?
  private var sessionAppActivationObserver: Any?
  private var sessionAppSwitchObserver: Any?
  private var lumaRecapturingTask: Task<Void, Never>?
  private var isMovingManualSelection = false
  private var manualSelectionLastPointerLocation: CGPoint?
  private var previouslyActiveApplication: NSRunningApplication?

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
    let screens = NSScreen.screens
    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "Area selection activating pooled windows",
      context: [
        "screenCount": "\(screens.count)",
        "poolSize": "\(windowPool.count)",
        "mode": "\(selectionMode)",
      ]
    )
    for screen in screens {
      guard let displayID = screen.displayID else {
        DiagnosticLogger.shared.log(
          .warning,
          .capture,
          "Area selection skipped screen with nil displayID",
          context: ["frame": "\(screen.frame)"]
        )
        continue
      }
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
      DiagnosticLogger.shared.log(
        .debug,
        .capture,
        "Area selection window activated",
        context: [
          "displayID": "\(displayID)",
          "frame": "\(screen.frame)",
          "selectionEnabled": "\(allowsSelection)",
          "isPooled": "\(windowPool[displayID] != nil)",
        ]
      )
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
    onTransitionRecapture: AreaSelectionTransitionRecaptureHandler? = nil,
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
      onDisplayActivationRequested: onDisplayActivationRequested,
      onTransitionRecapture: onTransitionRecapture
    )
  }

  private func startSelectionSession(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration? = nil,
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    onDisplayActivationRequested: AreaSelectionDisplayActivationHandler? = nil,
    onTransitionRecapture: AreaSelectionTransitionRecaptureHandler? = nil
  ) {
    QuickAccessManager.shared.suspendForCapture()
    // Always clean up prior session's monitors to prevent orphaned leaks
    removeEscapeMonitors()
    stopPointerTracking()
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
    transitionRecaptureHandler = onTransitionRecapture
    requestedDisplayActivationIDs.removeAll()
    deferredBackdropDisplayIDs.removeAll()
    allowsApplicationWindowSelection = applicationConfiguration != nil
    interactionMode = applicationConfiguration == nil ? .manualRegion : initialInteractionMode
    windowSelectionSnapshot = nil
    selectionSessionID = UUID()
    keyboardOwnerDisplayID = resolvedKeyboardOwnerDisplayID()
    isPresenting = true

    // Observe space changes and activation to keep selection session robust
    sessionSpaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { @MainActor [weak self] _ in
      self?.handleSessionSpaceOrActivationChange()
      self?.recaptureBackdropsForLuma(reason: .spaceChange)
    }

    sessionAppActivationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { @MainActor [weak self] _ in
      self?.handleSessionSpaceOrActivationChange()
      self?.recaptureBackdropsForLuma(reason: .appActivation)
    }

    sessionAppSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { @MainActor [weak self] _ in
      self?.handleSessionSpaceOrActivationChange()
      self?.recaptureBackdropsForLuma(reason: .appActivation)
    }

    // Ensure pool is ready (lazy initialization if not called at app launch)
    if !isPoolReady {
      prepareWindowPool()
    }

    // Activate pooled windows (instant show)
    activatePooledWindows()

    // Bring Snapzy forward so the overlay's transparent crosshair cursor takes effect immediately.
    // The overlay is a non-activating panel, so when the session is triggered from a global
    // shortcut while another app is frontmost, macOS keeps showing the previous app's arrow cursor
    // over our crosshair until the pointer moves and a `cursorUpdate` fires. Activating evaluates
    // the overlay's cursor rects right away.
    //
    // Limit this to frozen-backdrop sessions (screenshot area capture), where a static snapshot
    // sits behind the overlay so nothing live is dimmed. Backdrop-less sessions — recording-area
    // selection and the legacy screenshot API — overlay the actual windows being captured, so
    // activating would deactivate/dim them and leave Snapzy frontmost afterward; those keep the
    // non-activating behavior this window class is built around.
    if !selectionBackdrops.isEmpty {
      previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
      NSApp.activate(ignoringOtherApps: true)

      // When a normal-level window (e.g., Settings) was recently hidden, macOS may
      // not immediately assign key focus to the overlay panel. Schedule a follow-up
      // key assignment after the activation takes effect.
      if let keyboardDisplay = keyboardOwnerDisplayID,
         let keyWindow = windowPool[keyboardDisplay] {
        DispatchQueue.main.async { [weak keyWindow] in
          guard let keyWindow, keyWindow.isVisible else { return }
          keyWindow.makeKey()
          keyWindow.makeFirstResponder(keyWindow.overlayView)
        }
      }
    } else {
      previouslyActiveApplication = nil
      // For non-frozen sessions (recording, OCR, cutout) we cannot activate
      // the app without dimming live windows. Force cursor rect evaluation
      // on pooled windows as a best-effort hint — this prompts macOS to
      // apply the overlay's cursor rects sooner than waiting for the next
      // mouse-move event.
      for (_, window) in windowPool {
        window.invalidateCursorRects(for: window.overlayView)
      }
      // The app stays inactive here, so macOS only routes mouse-moved / cursor-rect handling to the
      // key overlay. Track the pointer and move key ownership to whichever display it is over, so
      // the crosshair follows across every display during the idle (pre-selection) phase.
      startPointerTrackingIfNeeded()
    }

    startWindowSelectionPreparationIfNeeded()

    if selectionBackdrops.isEmpty {
      let targetDisplayID = ScreenUtility.activeDisplayID()
      if let screen = NSScreen.screens.first(where: { $0.displayID == targetDisplayID }) {
        let captureRect = CGDisplayBounds(targetDisplayID)
        let backingScale = screen.backingScaleFactor
        let sessionID = selectionSessionID

        Task { [weak self] in
          let backdrop = await Task.detached { () -> AreaSelectionBackdrop? in
            guard let cgImage = CGWindowListCreateImage(
              captureRect,
              .optionOnScreenOnly,
              kCGNullWindowID,
              .nominalResolution
            ) else { return nil }
            return AreaSelectionBackdrop(
              displayID: targetDisplayID,
              image: cgImage,
              scaleFactor: backingScale,
              isVisible: false
            )
          }.value

          guard let self, self.selectionSessionID == sessionID else { return }
          guard let backdrop else {
            DiagnosticLogger.shared.log(
              .warning,
              .capture,
              "Failed to capture background backdrop for magnifier zoom in backdrop-less session"
            )
            return
          }
          self.applyBackdrop(backdrop, for: targetDisplayID)
        }
      }
    }

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

  func applyBackdrop(_ backdrop: AreaSelectionBackdrop, for displayID: CGDirectDisplayID, animated: Bool = false) {
    let shouldDeferVisualBackdrop = manualSelectionStartPoint != nil
      && selectionBackdrops[displayID] == nil
    liveFallbackDisplayIDs.remove(displayID)
    selectionBackdrops[displayID] = backdrop
    // Adding the first backdrop flips `selectionBackdrops.isEmpty` false, which changes
    // `selectionEnabled(for:)` for EVERY display — including secondaries still awaiting their
    // own backdrop. Reconcile all pooled windows' cached selection-enabled flags so those
    // displays correctly report "disabled" and route the next click through the live-fallback
    // path instead of silently dropping the drag. Runs even if `displayID` has no pooled window.
    reconcileSelectionEnabledAcrossPooledWindows()
    guard let window = windowPool[displayID] else { return }
    if shouldDeferVisualBackdrop {
      // Avoid a visible freeze jump when a secondary display finishes snapshotting mid-drag.
      deferredBackdropDisplayIDs.insert(displayID)
    } else {
      deferredBackdropDisplayIDs.remove(displayID)
      // Animate only when caller opts in and no manual drag is active.
      window.overlayView.applyBackdrop(backdrop, animated: animated && manualSelectionStartPoint == nil)
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

  /// Sync every pooled window's cached `selectionEnabled` flag to the authoritative
  /// `selectionEnabled(for:)` value. The per-view flag is a duplicate of controller state, so it
  /// goes stale whenever a global change (e.g. the first `applyBackdrop` flipping
  /// `selectionBackdrops.isEmpty`) alters the gate for displays other than the one being mutated.
  /// Idempotent and cheap (a bool set per window); only called on rare state transitions, never
  /// per mouse event — so it does not affect the manual-drag latency/frame-rate budget. Windows
  /// mid-drag stay enabled because `selectionEnabled(for:)` honors `liveFallbackDisplayIDs`.
  private func reconcileSelectionEnabledAcrossPooledWindows() {
    for (displayID, window) in windowPool {
      window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
    }
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

  /// Async variant of `withDisplayOverlayHidden` — hides the overlay on main, awaits
  /// the async work closure (which may run off-main), then restores the overlay on main.
  /// Use when the work body performs blocking I/O like `CGDisplayCreateImage`.
  func withDisplayOverlayHiddenAsync<T: Sendable>(
    for displayID: CGDirectDisplayID,
    perform work: @Sendable () async -> T
  ) async -> T {
    guard let window = windowPool[displayID], window.isVisible else {
      return await work()
    }

    // Capture-excluded overlays can stay visible without being baked into the snapshot.
    if window.sharingType == .none {
      return await work()
    }

    window.orderOut(nil)
    let result = await work()
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

  private func handleSessionSpaceOrActivationChange() {
    guard isPresenting else { return }

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Area selection session handling space or activation change",
      context: [
        "isPresenting": "\(isPresenting)",
        "isActive": "\(NSApp.isActive)",
        "keyboardOwnerDisplayID": keyboardOwnerDisplayID.map { "\($0)" } ?? "nil"
      ]
    )

    // Reactivate Snapzy so that cursor rects and key events work correctly
    if !NSApp.isActive {
      NSApp.activate(ignoringOtherApps: true)
    }

    // Restore key focus to the keyboard owner window
    if let keyboardDisplay = keyboardOwnerDisplayID,
       let keyWindow = windowPool[keyboardDisplay] {
      if !keyWindow.isKeyWindow {
        keyWindow.makeKey()
        keyWindow.makeFirstResponder(keyWindow.overlayView)
      }
    }

    // Refresh and invalidate cursors for all windows in the pool, and ensure visibility
    for (_, window) in windowPool {
      window.orderFrontRegardless()
      window.invalidateCursorRects(for: window.overlayView)
      window.overlayView.refreshCursor()
      window.overlayView.needsDisplay = true
    }
  }

  private func recaptureBackdropsForLuma(reason: RecaptureReason = .appActivation) {
    guard isPresenting else { return }

    // For frozen sessions, we never recapture on simple app activations/switches
    // (including the initial activation of Snapzy itself) to avoid double-captures 
    // and losing the focused window's state. We only recapture if the Space changes.
    if transitionRecaptureHandler != nil && reason == .appActivation {
      return
    }

    // Cancel any pending recapture to debounce rapid switches
    lumaRecapturingTask?.cancel()

    lumaRecapturingTask = Task { @MainActor in
      // Wait 300ms for space-sliding / window-order animation transitions to settle
      do {
        try await Task.sleep(nanoseconds: 300_000_000)
      } catch {
        return // Task cancelled
      }

      guard isPresenting else { return }

      // Frozen sessions re-freeze affected displays at full quality (updates both the
      // visible backdrop and the FrozenAreaCaptureSession crop source) via the handler.
      // Gate on the immutable handler — NOT selectionBackdrops visibility, which the
      // invisible luma recapture below would itself overwrite after the first transition.
      // Live / recording / backdrop-less sessions fall through to the cheap luma recapture.
      if let transitionRecaptureHandler {
        DiagnosticLogger.shared.log(
          .info,
          .capture,
          "Frozen session re-freezing displays after transition settle"
        )
        transitionRecaptureHandler()
        return
      }

      DiagnosticLogger.shared.log(
        .info,
        .capture,
        "Recapturing backdrops for live-mode luma calculations after transition settle",
        context: [
          "isPresenting": "\(isPresenting)",
          "isActive": "\(NSApp.isActive)"
        ]
      )

      for screen in NSScreen.screens {
        guard let displayID = screen.displayID else { continue }
        let captureRect = CGDisplayBounds(displayID)
        let backingScale = screen.backingScaleFactor
        let sessionID = self.selectionSessionID
        Task { [weak self] in
          let backdrop = await Task.detached { () -> AreaSelectionBackdrop? in
            guard let cgImage = CGWindowListCreateImage(
              captureRect,
              .optionOnScreenOnly,
              kCGNullWindowID,
              .nominalResolution
            ) else { return nil }
            return AreaSelectionBackdrop(
              displayID: displayID,
              image: cgImage,
              scaleFactor: backingScale,
              isVisible: false
            )
          }.value

          guard let self, self.selectionSessionID == sessionID else { return }
          if let backdrop {
            self.applyBackdrop(backdrop, for: displayID, animated: true)
          }
        }
      }
    }
  }

  private func completeSelection(target: AreaSelectionTarget, from window: AreaSelectionWindow) {
    QuickAccessManager.shared.resumeAfterCapture()
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
    
    previouslyActiveApplication?.activate(options: [])
    previouslyActiveApplication = nil
    
    resetCallbacks()
    dismissesAfterSelection = true
    forceCursorReset()
  }

  private func forceCursorReset() {
    NSCursor.arrow.set()
    
    // Discard cursor rects for all pooled windows before deactivating them
    for (_, window) in windowPool {
      window.discardCursorRects()
      window.invalidateCursorRects(for: window.overlayView)
    }

    // Post a synthetic mouse-moved event to force macOS to re-evaluate the cursor rects.
    // Run after a tiny delay so the window orderOut and activation transitions have fully completed.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      NSCursor.arrow.set()
      let mouseLocation = NSEvent.mouseLocation
      if let syntheticEvent = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: mouseLocation,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 0,
        pressure: 0
      ) {
        NSApp.postEvent(syntheticEvent, atStart: false)
      }
    }
  }

  /// Cancel the current selection
  func cancelSelection() {
    QuickAccessManager.shared.resumeAfterCapture()
    DiagnosticLogger.shared.log(.info, .capture, "Area selection cancelled", context: ["mode": "\(selectionMode)"])
    clearManualSelectionTracking(render: false)
    removeEscapeMonitors()
    cancelWindowSelectionTask()
    deactivatePooledWindows()
    completion?(nil)
    completionWithMode?(nil, selectionMode)
    completionWithResult?(nil)
    
    previouslyActiveApplication?.activate(options: [])
    previouslyActiveApplication = nil
    
    resetCallbacks()
    forceCursorReset()
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

  /// Start the pointer-tracking timer for non-activated live sessions so the crosshair follows the
  /// pointer across all displays before a selection begins. Idempotent — guarded on a nil timer.
  /// Added to `.common` run-loop modes so it keeps firing during window/event tracking. The drag
  /// phase stays authoritative: each tick early-returns while a manual selection is in progress so
  /// `reassertManualSelectionCursor()` owns the cursor.
  private func startPointerTrackingIfNeeded() {
    guard pointerTrackingTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handlePointerTrackingTick()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    pointerTrackingTimer = timer
  }

  /// Move key ownership to the overlay under the pointer when the pointer crosses onto a different
  /// display, so that overlay's cursor rects render the crosshair while the app stays inactive.
  private func handlePointerTrackingTick() {
    guard isPresenting else { return }
    // A manual drag owns the cursor via the drag monitors; don't fight it.
    guard manualSelectionStartPoint == nil else { return }
    let location = NSEvent.mouseLocation
    guard let window = window(containing: location),
          let displayID = window.displayID else { return }
    // Already the key/keyboard owner — nothing to do (also the single-display fast path).
    guard displayID != keyboardOwnerDisplayID else { return }
    promotePointerDisplayToKeyOwner(window, displayID: displayID)
  }

  /// Transfer keyboard + key-window ownership to `window`'s display. Reusing the existing
  /// `receivesKeyboardInput`/`canBecomeKey` machinery keeps a single keyboard owner at a time and,
  /// critically, keeps Escape working: `areaSelectionWindow(_:didReceiveKeyEvent:)` gates key
  /// handling on `keyboardOwnerDisplayID`, so it must track the current key overlay.
  private func promotePointerDisplayToKeyOwner(_ window: AreaSelectionWindow, displayID: CGDirectDisplayID) {
    if let previousID = keyboardOwnerDisplayID, let previousWindow = windowPool[previousID] {
      previousWindow.setReceivesKeyboardInput(false)
      previousWindow.overlayView.hideSizeIndicator()
      previousWindow.overlayView.hideMagnifier()
    }
    keyboardOwnerDisplayID = displayID
    window.setReceivesKeyboardInput(true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(window.overlayView)
    
    // macOS WindowServer is notoriously stubborn about applying cursor rects for newly-key
    // windows of inactive applications if the mouse was already inside the window.
    // By explicitly removing and re-adding the tracking area here, AppKit generates
    // immediate mouseEntered and cursorUpdate events for the new key window.
    window.overlayView.updateTrackingAreas()
    
    // Invalidate cursor rects before the next event
    window.overlayView.refreshCursor()
    
    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "Pointer tracking promoted key overlay",
      context: ["displayID": "\(displayID)"]
    )
  }

  private func stopPointerTracking() {
    pointerTrackingTimer?.invalidate()
    pointerTrackingTimer = nil
  }

  private func resetCallbacks() {
    isPresenting = false
    dismissesAfterSelection = true
    stopPointerTracking()
    lumaRecapturingTask?.cancel()
    lumaRecapturingTask = nil
    if let observer = sessionSpaceChangeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      sessionSpaceChangeObserver = nil
    }
    if let observer = sessionAppActivationObserver {
      NotificationCenter.default.removeObserver(observer)
      sessionAppActivationObserver = nil
    }
    if let observer = sessionAppSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      sessionAppSwitchObserver = nil
    }
    completion = nil
    completionWithMode = nil
    completionWithResult = nil
    selectionBackdrops.removeAll()
    liveFallbackDisplayIDs.removeAll()
    requestedDisplayActivationIDs.removeAll()
    deferredBackdropDisplayIDs.removeAll()
    applicationConfiguration = nil
    displayActivationHandler = nil
    transitionRecaptureHandler = nil
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
    isMovingManualSelection = false
    manualSelectionLastPointerLocation = screenPoint
    installManualSelectionMonitorIfNeeded()
    requestDisplayActivationForManualSelection()
    renderManualSelectionIfNeeded()
  }

  private func updateManualSelection(to screenPoint: CGPoint) {
    guard manualSelectionStartPoint != nil else { return }
    defer { manualSelectionLastPointerLocation = screenPoint }

    if isMovingManualSelection {
      guard let last = manualSelectionLastPointerLocation else { return }
      let dx = screenPoint.x - last.x
      let dy = screenPoint.y - last.y
      guard dx != 0 || dy != 0 else { return }
      manualSelectionStartPoint?.x += dx
      manualSelectionStartPoint?.y += dy
      manualSelectionCurrentPoint?.x += dx
      manualSelectionCurrentPoint?.y += dy
    } else {
      guard screenPoint != manualSelectionCurrentPoint else { return }
      manualSelectionCurrentPoint = screenPoint
    }

    requestDisplayActivationForManualSelection()
    renderManualSelectionIfNeeded()
    reassertManualSelectionCursor()
  }

  /// Keep the crosshair asserted during a drag. The drag is driven by `NSEvent` monitors (not the
  /// overlay view's own `mouseDragged`, which the local monitor consumes), so re-assert here — the
  /// single convergence point for both the local and global drag monitors. `NSCursor.set()` is
  /// process-global, so asserting via the source window's overlay view covers cross-display drags.
  private func reassertManualSelectionCursor() {
    guard manualSelectionStartPoint != nil else { return }
    (manualSelectionSourceWindow ?? activeWindow)?.overlayView.reassertCursorDuringDrag()
  }

  private func handleManualSelectionSpaceEvent(_ event: NSEvent) -> Bool {
    guard event.keyCode == 49 else { return false }
    guard manualSelectionStartPoint != nil else { return false }
    switch event.type {
    case .keyDown:
      if !isMovingManualSelection {
        manualSelectionLastPointerLocation = NSEvent.mouseLocation
        isMovingManualSelection = true
      }
    case .keyUp:
      isMovingManualSelection = false
    default:
      return false
    }
    return true
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
    if appActivationObserver == nil {
      appActivationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.reassertManualSelectionCursor()
        }
      }
    }
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

    if manualSelectionKeyLocalMonitor == nil {
      manualSelectionKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown, .keyUp]
      ) { [weak self] event in
        var handled = false
        MainActor.assumeIsolated {
          handled = self?.handleManualSelectionSpaceEvent(event) ?? false
        }
        return handled ? nil : event
      }
    }
    if manualSelectionKeyGlobalMonitor == nil {
      manualSelectionKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.keyDown, .keyUp]
      ) { [weak self] event in
        MainActor.assumeIsolated {
          _ = self?.handleManualSelectionSpaceEvent(event)
        }
      }
    }

    // Global monitor receives drag/up even while Snapzy is inactive (the first ⌘⇧4 gesture on a
    // nonactivating overlay). The handlers are idempotent — `updateManualSelection` just records
    // the current point and `endManualSelection` early-returns once the selection is torn down —
    // so it is safe for both monitors to fire for the same event when the app is active.
    guard manualSelectionGlobalMonitor == nil else { return }
    manualSelectionGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp]
    ) { [weak self] event in
      let mouseLocation = NSEvent.mouseLocation
      MainActor.assumeIsolated {
        switch event.type {
        case .leftMouseDragged:
          self?.updateManualSelection(to: mouseLocation)
        case .leftMouseUp:
          self?.endManualSelection(at: mouseLocation)
        default:
          break
        }
      }
    }
  }

  private func removeManualSelectionMonitor() {
    if let monitor = manualSelectionLocalMonitor {
      NSEvent.removeMonitor(monitor)
      manualSelectionLocalMonitor = nil
    }
    if let monitor = manualSelectionGlobalMonitor {
      NSEvent.removeMonitor(monitor)
      manualSelectionGlobalMonitor = nil
    }
    if let monitor = manualSelectionKeyLocalMonitor {
      NSEvent.removeMonitor(monitor)
      manualSelectionKeyLocalMonitor = nil
    }
    if let monitor = manualSelectionKeyGlobalMonitor {
      NSEvent.removeMonitor(monitor)
      manualSelectionKeyGlobalMonitor = nil
    }
    if let observer = appActivationObserver {
      NotificationCenter.default.removeObserver(observer)
      appActivationObserver = nil
    }
    isMovingManualSelection = false
    manualSelectionLastPointerLocation = nil
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
    if let observer = sessionSpaceChangeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    if let observer = sessionAppActivationObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = sessionAppSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
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
    if !NSApp.isActive {
      handleSessionSpaceOrActivationChange()
      recaptureBackdropsForLuma()
    }
    requestDisplayActivationIfNeeded(for: window)
  }

  func areaSelectionWindowDidRequestImmediateManualSelection(_ window: AreaSelectionWindow) {
    guard interactionMode == .manualRegion else { return }
    guard let displayID = window.displayID else { return }
    // If the backdrop has already arrived (or live-fallback is already on) the click was
    // processed normally — no need to enable fallback. Otherwise switch to live capture so
    // the pending click can be activated without waiting for the lazy snapshot.
    guard selectionBackdrops[displayID] == nil,
          !liveFallbackDisplayIDs.contains(displayID) else {
      return
    }
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Area selection live fallback enabled by user click",
      context: ["displayID": "\(displayID)"]
    )
    enableLiveFallbackSelection(for: displayID)
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
  /// User pressed inside the overlay before the per-display backdrop snapshot arrived. The
  /// controller should enable live-fallback selection for the window's display so the click
  /// is not dropped if the user releases before the snapshot completes.
  func areaSelectionWindowDidRequestImmediateManualSelection(_ window: AreaSelectionWindow)
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
    self.backgroundColor = NSColor(white: 0, alpha: 0.005)
    self.sharingType = .none
    self.level = .screenSaver
    self.ignoresMouseEvents = false
    self.acceptsMouseMovedEvents = true
    self.isReleasedWhenClosed = false
    self.hasShadow = false
    self.hidesOnDeactivate = false
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    self.animationBehavior = .none  // Disable window animations for instant appearance
    self.becomesKeyOnlyIfNeeded = true
    
    // Lock window movement and resizing
    self.isMovable = false
    self.isMovableByWindowBackground = false
    self.minSize = screen.frame.size
    self.maxSize = screen.frame.size

    // Set up content view
    self.contentView = overlayView
    overlayView.delegate = self
    overlayView.keyEventHandler = { [weak self] event in
      guard let self else { return false }
      return self.selectionDelegate?.areaSelectionWindow(self, didReceiveKeyEvent: event) ?? false
    }

    // Hide the panel from Accessibility so VoiceOver / assistive tech ignore
    // the overlay chrome (kept as hygiene for any future AX-aware capture work).
    self.setAccessibilityElement(false)
    self.setAccessibilityHidden(true)
    self.setAccessibilityRole(.unknown)

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

  override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
    self.minSize = frameRect.size
    self.maxSize = frameRect.size
    super.setFrame(frameRect, display: displayFlag)
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

  func overlayViewDidRequestImmediateManualSelection(_ view: AreaSelectionOverlayView) {
    selectionDelegate?.areaSelectionWindowDidRequestImmediateManualSelection(self)
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
  /// Signals that the user pressed inside the overlay before the per-display backdrop snapshot
  /// was ready. The controller should enable live-fallback selection for the overlay's display
  /// so the click is not silently dropped.
  func overlayViewDidRequestImmediateManualSelection(_ view: AreaSelectionOverlayView)
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
  var dimLayer: CALayer!
  var insideSelectionOverlayLayer: CAShapeLayer!
  private var showSelectionAreaOverlay = true
  private var backdropPixelDataArray: [UInt8]?
  private var backdropWidth = 0
  private var backdropHeight = 0
  private var backdropScale: CGFloat = 1.0
  private var insideOverlayIsDark = true
  /// Throttles the "no luma pixel data" warning to once per selection (see `updateInsideOverlayAppearance`).
  private var didLogMissingLumaData = false

  // MARK: - Magnifying Glass Zoom (Pixel-level zoom)
  private let magnifier = AreaSelectionMagnifier()
  private var currentBackdropImage: CGImage?


  private lazy var reusableDimMaskLayer: CAShapeLayer = {
    let layer = CAShapeLayer()
    layer.fillRule = .evenOdd
    return layer
  }()
  private var reusableCrosshairPath = CGMutablePath()
  private var horizontalCrosshairLayer: CAShapeLayer!
  private var verticalCrosshairLayer: CAShapeLayer!
  private var selectionBorderLayer: CAShapeLayer!
  private var crosshairIndicatorLayer: CAShapeLayer!
  private var sizeIndicatorBackgroundLayer: CALayer!
  private var sizeIndicatorTextLayer: CATextLayer!
  private var lastSizeIndicatorText: String?
  private var lastSizeIndicatorTextSize: CGSize = .zero
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
    configureAccessibilityInvisibility()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    wantsLayer = true
    setupLayers()
    setupTrackingArea()
    configureAccessibilityInvisibility()
  }

  private func configureAccessibilityInvisibility() {
    setAccessibilityElement(false)
    setAccessibilityHidden(true)
    setAccessibilityRole(.unknown)
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

    // Inside selection dark overlay layer (when backdrop overlay is disabled)
    insideSelectionOverlayLayer = CAShapeLayer()
    insideSelectionOverlayLayer.fillColor = NSColor.black.withAlphaComponent(0.12).cgColor
    insideSelectionOverlayLayer.strokeColor = NSColor.black.withAlphaComponent(0.3).cgColor
    insideSelectionOverlayLayer.lineWidth = 4.0
    insideSelectionOverlayLayer.isHidden = true
    insideSelectionOverlayLayer.actions = disabledActions
    rootLayer.addSublayer(insideSelectionOverlayLayer)

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
    configureShadow(
      for: crosshairIndicatorLayer,
      color: .black,
      offset: .zero,
      radius: 2,
      opacity: 0.5
    )
    rootLayer.addSublayer(crosshairIndicatorLayer)

    sizeIndicatorBackgroundLayer = CALayer()
    sizeIndicatorBackgroundLayer.backgroundColor = NSColor.clear.cgColor
    sizeIndicatorBackgroundLayer.cornerRadius = 4
    sizeIndicatorBackgroundLayer.actions = disabledActions
    sizeIndicatorBackgroundLayer.isHidden = true
    rootLayer.addSublayer(sizeIndicatorBackgroundLayer)

    sizeIndicatorTextLayer = CATextLayer()
    configureOverlayTextLayer(sizeIndicatorTextLayer)
    sizeIndicatorTextLayer.font = coordinateIndicatorFont as CTFont
    sizeIndicatorTextLayer.fontSize = coordinateIndicatorFont.pointSize
    sizeIndicatorTextLayer.foregroundColor = NSColor(white: 0.05, alpha: 1.0).cgColor
    configureShadow(
      for: sizeIndicatorTextLayer,
      color: .white,
      offset: CGSize(width: 0.5, height: -0.5),
      radius: 0.1,
      opacity: 1.0
    )
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
    let point = convert(event.locationInWindow, from: nil)
    currentMousePosition = point
    updateCoordinateIndicator(at: point)
    if selectionEnabled, interactionMode == .manualRegion, !isSelecting {
      updateCrosshairLayers()
      updateMagnifier(at: point)
    }
  }

  override func mouseExited(with event: NSEvent) {
    NSCursor.arrow.set()
    hideSizeIndicator()
    hideMagnifier()
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
    initializeCrosshairAtCurrentMousePosition()
    updateCoordinateIndicator(at: currentMousePosition)
  }

  /// Re-assert the crosshair while a manual drag is in progress. On a nonactivating panel the
  /// system can reset the cursor to the default arrow mid-drag (e.g. a background screen-composition
  /// capture); the panel never becomes key, so AppKit's cursor-rect machinery does not self-heal it.
  /// The selection drag monitors call this on every drag update to keep the crosshair sticky.
  func reassertCursorDuringDrag() {
    guard isManualSelectionInProgress else { return }
    activeCursor.set()
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
    crosshairIndicatorLayer.isHidden = true
    updateCoordinateIndicator(at: currentMousePosition)
    showSelectionAreaOverlay = UserDefaults.standard.object(forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay) as? Bool ?? true
    magnifier.reverseZoomDirection = UserDefaults.standard.object(forKey: PreferencesKeys.screenshotReverseMagnifierZoomDirection) as? Bool ?? false
    dimLayer.backgroundColor = showSelectionAreaOverlay ? dimColor.cgColor : nil
    dimLayer.mask = nil
    dimLayer.frame = bounds
    insideSelectionOverlayLayer.isHidden = true
    insideOverlayIsDark = true
    didLogMissingLumaData = false

    CATransaction.commit()
    refreshCursor()

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
      insideSelectionOverlayLayer.isHidden = true
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

  private func cacheBackdropPixels(from cgImage: CGImage, scale: CGFloat) {
    let width = cgImage.width
    let height = cgImage.height
    self.backdropWidth = width
    self.backdropHeight = height
    self.backdropScale = scale

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
      self.backdropPixelDataArray = nil
      DiagnosticLogger.shared.log(
        .error,
        .capture,
        "Failed to create CGContext for backdrop pixel caching",
        context: ["width": "\(width)", "height": "\(height)"]
      )
      return
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    if let dataPtr = context.data {
      let totalBytes = width * height * 4
      let bufferPointer = UnsafeBufferPointer(start: dataPtr.assumingMemoryBound(to: UInt8.self), count: totalBytes)
      self.backdropPixelDataArray = Array(bufferPointer)
    } else {
      self.backdropPixelDataArray = nil
    }

    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "cacheBackdropPixels completed",
      context: [
        "width": "\(width)",
        "height": "\(height)",
        "scale": "\(scale)",
        "cachedBytes": "\(self.backdropPixelDataArray?.count ?? 0)"
      ]
    )
  }

  private func calculateAverageLuminance(for rect: CGRect) -> Double? {
    guard let pixelData = backdropPixelDataArray,
          backdropWidth > 0,
          backdropHeight > 0,
          !rect.isEmpty else {
      return nil
    }

    // Map the selection rect (view points) into backdrop pixels. Derive the scale from the ACTUAL
    // cached image dimensions vs the view bounds rather than trusting `backdropScale`: the live luma
    // backdrop is captured at `.nominalResolution` (point-sized), so a stored `backingScaleFactor`
    // (2× on Retina) overshoots and clamps the sample grid to the screen edge — which made small /
    // centered selections mis-detect the background. Deriving from real dims is correct for both
    // nominal (ratio ≈ 1) and best-resolution (ratio ≈ backingScale) images.
    let scaleX = bounds.width > 0 ? CGFloat(backdropWidth) / bounds.width : backdropScale
    let scaleY = bounds.height > 0 ? CGFloat(backdropHeight) / bounds.height : backdropScale
    let pixelRect = CGRect(
      x: rect.origin.x * scaleX,
      y: rect.origin.y * scaleY,
      width: rect.width * scaleX,
      height: rect.height * scaleY
    )

    let gridCount = 5
    var totalLuma = 0.0
    var sampleCount = 0

    for row in 0..<gridCount {
      for col in 0..<gridCount {
        let pctX = Double(col + 1) / Double(gridCount + 1)
        let pctY = Double(row + 1) / Double(gridCount + 1)

        let sampleX = Int(pixelRect.origin.x + pixelRect.width * CGFloat(pctX))
        let sampleYInCocoa = Int(pixelRect.origin.y + pixelRect.height * CGFloat(pctY))

        let x = max(0, min(backdropWidth - 1, sampleX))
        // Invert y because Cocoa origin is bottom-left, while CGImage origin is top-left
        let y = max(0, min(backdropHeight - 1, backdropHeight - 1 - sampleYInCocoa))

        let pixelOffset = (y * backdropWidth + x) * 4
        if pixelOffset + 2 < pixelData.count {
          let r = Double(pixelData[pixelOffset]) / 255.0
          let g = Double(pixelData[pixelOffset + 1]) / 255.0
          let b = Double(pixelData[pixelOffset + 2]) / 255.0
          // BT.601 luminance formula
          let luma = 0.299 * r + 0.587 * g + 0.114 * b
          totalLuma += luma
          sampleCount += 1
        }
      }
    }

    return sampleCount > 0 ? (totalLuma / Double(sampleCount)) : nil
  }

  private func updateInsideOverlayAppearance(for localRect: CGRect) {
    if let avgLuma = calculateAverageLuminance(for: localRect) {
      didLogMissingLumaData = false
      let wasDark = insideOverlayIsDark
      if insideOverlayIsDark {
        if avgLuma < 0.4 {
          insideOverlayIsDark = false
        }
      } else {
        if avgLuma > 0.6 {
          insideOverlayIsDark = true
        }
      }

      // Log only on an actual light/dark flip. This runs per drag frame (60+ fps), so logging
      // every frame would add string-building + I/O to the hot path and risk dropped frames.
      if wasDark != insideOverlayIsDark {
        DiagnosticLogger.shared.log(
          .debug,
          .capture,
          "updateInsideOverlayAppearance flipped",
          context: [
            "avgLuma": String(format: "%.3f", avgLuma),
            "isDark": "\(insideOverlayIsDark)",
          ]
        )
      }
    } else if !didLogMissingLumaData {
      // Log the missing-data case at most once per selection: while the async luma backdrop is still
      // being captured the user can already drag, and logging every frame would spam warnings.
      didLogMissingLumaData = true
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "updateInsideOverlayAppearance failed to calculate average luma (no pixel data cached)",
        context: [
          "hasPixelData": "\(backdropPixelDataArray != nil)",
          "width": "\(backdropWidth)",
          "height": "\(backdropHeight)",
        ]
      )
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if insideOverlayIsDark {
      insideSelectionOverlayLayer.fillColor = NSColor.black.withAlphaComponent(0.12).cgColor
      insideSelectionOverlayLayer.strokeColor = NSColor.black.withAlphaComponent(0.3).cgColor
    } else {
      insideSelectionOverlayLayer.fillColor = NSColor.white.withAlphaComponent(0.15).cgColor
      insideSelectionOverlayLayer.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
    }
    CATransaction.commit()
  }

  func applyBackdrop(_ backdrop: AreaSelectionBackdrop, animated: Bool = false) {
    let shouldAnimate = animated
      && BackdropTransitionEffect.shouldCrossfade(
           isReapplication: currentBackdropImage != nil,
           isVisible: backdrop.isVisible)

    // Frame, scale, and visibility are never animated.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.frame = bounds
    snapshotLayer.contentsScale = backdrop.scaleFactor
    snapshotLayer.isHidden = !backdrop.isVisible
    CATransaction.commit()

    // Contents swap: crossfade on re-apply when opted-in, hard swap otherwise.
    CATransaction.begin()
    if shouldAnimate {
      BackdropTransitionEffect.addCrossfade(to: snapshotLayer)
    } else {
      CATransaction.setDisableActions(true)
    }
    snapshotLayer.contents = backdrop.image
    CATransaction.commit()

    self.currentBackdropImage = backdrop.image
    cacheBackdropPixels(from: backdrop.image, scale: backdrop.scaleFactor)
    if magnifier.zoom > 1.0 {
      updateMagnifier(at: currentMousePosition)
    }
    if selectionEnabled {
      updateCoordinateIndicator(at: currentMousePosition)
    }
  }

  func clearBackdrop() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.contents = nil
    snapshotLayer.contentsScale = 1.0
    snapshotLayer.isHidden = true
    magnifier.removeLayers()
    CATransaction.commit()

    backdropPixelDataArray = nil
    backdropWidth = 0
    backdropHeight = 0
    backdropScale = 1.0
    currentBackdropImage = nil
    magnifier.zoom = 1.0
  }

  // MARK: - Magnifying Glass Zoom Implementation

  private func updateMagnifier(at point: CGPoint) {
    guard isMouseOver else {
      magnifier.removeLayers()
      return
    }
    magnifier.update(
      at: point,
      bounds: bounds,
      backdropImage: currentBackdropImage,
      pixelData: backdropPixelDataArray,
      backdropWidth: backdropWidth,
      backdropHeight: backdropHeight,
      backdropScale: backdropScale,
      contentsScale: screenScaleFactor,
      in: layer ?? CALayer()
    )
  }

  override func scrollWheel(with event: NSEvent) {
    if event.modifierFlags.contains(.command) {
      let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
      if delta != 0 {
        if magnifier.handleScroll(delta: delta, hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas) {
          updateMagnifier(at: currentMousePosition)
        }
      }
    } else {
      super.scrollWheel(with: event)
    }
  }


#if DEBUG

  var testSnapshotLayer: CALayer { snapshotLayer }
  var testBackdropPixelDataArray: [UInt8]? { backdropPixelDataArray }
  var testMagnifierZoom: CGFloat {
    get { magnifier.zoom }
    set { magnifier.zoom = newValue }
  }
  func testUpdateMagnifier(at point: CGPoint) {
    updateMagnifier(at: point)
  }
  var testMagnifierContainerLayer: CALayer? {
    magnifier.containerLayer
  }
  var testMagnifierImageLayer: CALayer? {
    magnifier.imageLayer
  }
  var testReverseMagnifierZoomDirection: Bool {
    get { magnifier.reverseZoomDirection }
    set { magnifier.reverseZoomDirection = newValue }
  }
  func testScrollWheel(deltaY: CGFloat, modifierFlags: NSEvent.ModifierFlags, hasPreciseScrollingDeltas: Bool = false) {
    if modifierFlags.contains(.command) {
      if deltaY != 0 {
        if magnifier.handleScroll(delta: deltaY, hasPreciseScrollingDeltas: hasPreciseScrollingDeltas) {
          updateMagnifier(at: currentMousePosition)
        }
      }
    }
  }
  var testSizeIndicatorTextLayer: CATextLayer { sizeIndicatorTextLayer }
  var testSizeIndicatorBackgroundLayer: CALayer { sizeIndicatorBackgroundLayer }
#endif



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
    insideSelectionOverlayLayer.frame = bounds
    hideSizeIndicator()
    CATransaction.commit()
    updateModeHint()
  }

  // MARK: - CALayer Updates (60fps performance)

  private func updateCrosshairLayers() {
    guard selectionEnabled, interactionMode == .manualRegion else {
      crosshairIndicatorLayer.isHidden = true
      hideSizeIndicator()
      return
    }

    crosshairIndicatorLayer.isHidden = true
    updateCoordinateIndicator(at: currentMousePosition)
  }

  /// Updates and returns the reusable crosshair indicator path centered at the given point
  private func createCrosshairIndicatorPath(at point: CGPoint) -> CGPath {
    let size = crosshairIndicatorSize
    reusableCrosshairPath = CGMutablePath()

    // Vertical line
    reusableCrosshairPath.move(to: CGPoint(x: point.x, y: point.y - size))
    reusableCrosshairPath.addLine(to: CGPoint(x: point.x, y: point.y + size))

    // Horizontal line
    reusableCrosshairPath.move(to: CGPoint(x: point.x - size, y: point.y))
    reusableCrosshairPath.addLine(to: CGPoint(x: point.x + size, y: point.y))

    return reusableCrosshairPath
  }

  private func updateDimLayerMask(for selectionRect: CGRect) {
    // Reuse mask layer to avoid per-frame CAShapeLayer allocation
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addRect(selectionRect)
    reusableDimMaskLayer.path = path
    if dimLayer.mask !== reusableDimMaskLayer {
      dimLayer.mask = reusableDimMaskLayer
    }
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

  private let coordinateIndicatorFont = NSFont.systemFont(ofSize: 10, weight: .medium)

  private var coordinateTextAttributes: [NSAttributedString.Key: Any] {
    [
      .font: coordinateIndicatorFont,
      .foregroundColor: NSColor(white: 0.15, alpha: 1.0),
    ]
  }

  private func multiLineTextSize(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGSize {
    let lines = text.components(separatedBy: "\n")
    let maxWidth = lines.map { $0.size(withAttributes: attributes).width }.max() ?? 0
    let lineHeight = "0".size(withAttributes: attributes).height
    let totalHeight = lineHeight * CGFloat(lines.count) + 2.0
    return CGSize(width: maxWidth, height: totalHeight)
  }

  private func configureShadow(
    for layer: CALayer,
    color: NSColor,
    offset: CGSize,
    radius: CGFloat,
    opacity: Float
  ) {
    layer.shadowColor = color.cgColor
    layer.shadowOffset = offset
    layer.shadowRadius = radius
    layer.shadowOpacity = opacity
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

  func hideSizeIndicator() {
    sizeIndicatorBackgroundLayer.isHidden = true
    sizeIndicatorTextLayer.isHidden = true
    lastSizeIndicatorText = nil
  }

  func hideMagnifier() {
    magnifier.removeLayers()
  }

  #if DEBUG
  var testMouseLocationOverride: CGPoint?
  #endif

  private var isMouseOver: Bool {
    #if DEBUG
    if NSClassFromString("XCTestCase") != nil, self.window == nil {
      return true
    }
    let mouseLocation = testMouseLocationOverride ?? NSEvent.mouseLocation
    #else
    let mouseLocation = NSEvent.mouseLocation
    #endif
    guard let window = self.window,
          window.isVisible,
          window.frame.contains(mouseLocation) else {
      return false
    }
    return true
  }

  private func updateSizeIndicator(for rect: CGRect, measuredSize: CGSize? = nil) {
    let displayedSize = measuredSize ?? rect.size
    let sizeText = "\(Int(displayedSize.width))\n\(Int(displayedSize.height))"
    let attributes = coordinateTextAttributes
    let textSize: CGSize
    if sizeText == lastSizeIndicatorText {
      textSize = lastSizeIndicatorTextSize
    } else {
      textSize = multiLineTextSize(sizeText, attributes: attributes)
      lastSizeIndicatorText = sizeText
      lastSizeIndicatorTextSize = textSize
    }

    let point = currentMousePosition
    let offset: CGFloat = 12
    var textRect = CGRect(
      x: point.x + offset,
      y: point.y - textSize.height - 4,
      width: textSize.width,
      height: textSize.height
    )

    if textRect.maxX > bounds.maxX {
      textRect.origin.x = point.x - textSize.width - offset
    }
    if textRect.minY < bounds.minY {
      textRect.origin.y = point.y + offset
    }

    updateTextLayerScales()
    sizeIndicatorBackgroundLayer.frame = textRect.insetBy(dx: -4, dy: -2)
    sizeIndicatorBackgroundLayer.isHidden = false

    sizeIndicatorTextLayer.string = sizeText
    sizeIndicatorTextLayer.frame = textRect
    sizeIndicatorTextLayer.isHidden = false
  }

  private func updateCoordinateIndicator(at point: CGPoint) {
    guard isMouseOver, interactionMode == .manualRegion, !isSelecting else {
      hideSizeIndicator()
      return
    }

    let localX = Int(point.x)
    let localY = Int(bounds.height - point.y)
    let text = "\(localX)\n\(localY)"

    let attributes = coordinateTextAttributes
    let textSize: CGSize
    if text == lastSizeIndicatorText {
      textSize = lastSizeIndicatorTextSize
    } else {
      textSize = multiLineTextSize(text, attributes: attributes)
      lastSizeIndicatorText = text
      lastSizeIndicatorTextSize = textSize
    }

    let offset: CGFloat = 12
    var textRect = CGRect(
      x: point.x + offset,
      y: point.y - textSize.height - 4,
      width: textSize.width,
      height: textSize.height
    )

    if textRect.maxX > bounds.maxX {
      textRect.origin.x = point.x - textSize.width - offset
    }
    if textRect.minY < bounds.minY {
      textRect.origin.y = point.y + offset
    }

    updateTextLayerScales()
    sizeIndicatorBackgroundLayer.frame = textRect.insetBy(dx: -4, dy: -2)
    sizeIndicatorBackgroundLayer.isHidden = false

    sizeIndicatorTextLayer.string = text
    sizeIndicatorTextLayer.frame = textRect
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

    if magnifier.zoom > 1.0 {
      updateMagnifier(at: currentMousePosition)
    }

    guard let screenRect, !screenRect.isEmpty else {

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
      insideSelectionOverlayLayer.isHidden = true
      crosshairIndicatorLayer.isHidden = true
      if let localCurrentPoint, bounds.contains(localCurrentPoint), selectionEnabled {
        updateCoordinateIndicator(at: localCurrentPoint)
      } else {
        hideSizeIndicator()
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
    crosshairIndicatorLayer.isHidden = true

    if localRect.isEmpty {
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
      insideSelectionOverlayLayer.isHidden = true
      hideSizeIndicator()
    } else {
      selectionBorderLayer.isHidden = false
      selectionBorderLayer.path = CGPath(rect: localRect, transform: nil)
      if showSelectionAreaOverlay {
        updateDimLayerMask(for: localRect)
        insideSelectionOverlayLayer.isHidden = true
      } else {
        dimLayer.mask = nil
        insideSelectionOverlayLayer.path = CGPath(rect: localRect, transform: nil)
        updateInsideOverlayAppearance(for: localRect)
        insideSelectionOverlayLayer.isHidden = false
      }
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
      if interactionMode == .applicationWindow {
        updateApplicationSelectionLayers()
      }
      return
    }
    let screenPoint = NSEvent.mouseLocation
    hoveredWindowCandidate = windowSelectionSnapshot?.hitTest(at: screenPoint)
    if interactionMode == .applicationWindow {
      updateApplicationSelectionLayers()
    }
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
        insideSelectionOverlayLayer.isHidden = true
      } else {
        selectionBorderLayer.isHidden = false
        selectionBorderLayer.path = CGPath(rect: localRect, transform: nil)
        if showSelectionAreaOverlay {
          updateDimLayerMask(for: localRect)
          insideSelectionOverlayLayer.isHidden = true
        } else {
          dimLayer.mask = nil
          insideSelectionOverlayLayer.path = CGPath(rect: localRect, transform: nil)
          updateInsideOverlayAppearance(for: localRect)
          insideSelectionOverlayLayer.isHidden = false
        }
      }
    } else {
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
      insideSelectionOverlayLayer.isHidden = true
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
    if let areaWindow = self.window as? AreaSelectionWindow {
      DiagnosticLogger.shared.log(
        .debug,
        .capture,
        "Area selection mouseDown received",
        context: [
          "displayID": "\(areaWindow.displayID.map(String.init(describing:)) ?? "nil")",
          "selectionEnabled": "\(selectionEnabled)",
          "point": "\(point)",
          "interactionMode": "\(interactionMode)",
        ]
      )
    }
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else {
      if interactionMode == .manualRegion {
        pendingSelectionStartPoint = point
        // Backdrop snapshot is still being prepared for this display. Ask the controller to
        // enable live-fallback selection so the click isn't silently dropped if the user
        // releases before the snapshot arrives. The lazy snapshot continues in the background
        // and will replace the live view via applyBackdrop() once ready.
        delegate?.overlayViewDidRequestImmediateManualSelection(self)
      }
      return
    }
    activeCursor.set()
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
    activeCursor.set()
    switch interactionMode {
    case .manualRegion:
      guard isSelecting else { return }
      delegate?.overlayView(self, manualSelectionChangedTo: point)
      updateMagnifier(at: point)
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
    activeCursor.set()
    updateCoordinateIndicator(at: point)
    guard selectionEnabled else { return }
    switch interactionMode {
    case .manualRegion:
      if !isSelecting {
        updateCrosshairLayers()
        updateMagnifier(at: point)
      }
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }


  override func rightMouseDown(with event: NSEvent) {
    delegate?.overlayViewDidCancel(self)
  }

  private var activeCursor: NSCursor {
    switch interactionMode {
    case .manualRegion:
      return showSelectionAreaOverlay ? NSCursor.vectorScreenshotCrosshairLight : NSCursor.vectorScreenshotCrosshairHighContrast
    case .applicationWindow:
      guard selectionEnabled else { return .arrow }
      return NSCursor.applicationWindowCursor
    }
  }

  var isManualSelectionInProgress: Bool {
    interactionMode == .manualRegion && isSelecting
  }
}

// MARK: - Recreated macOS Crosshair Cursors
extension NSCursor {
  static var vectorScreenshotCrosshairHighContrast: NSCursor = {
    let size = NSSize(width: 32, height: 32)
    let image = NSImage(size: size)
    image.isTemplate = false
    
    image.lockFocus()
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()
    
    let verticalPath = NSBezierPath()
    // Bottom segment (y: 5 to 16)
    verticalPath.move(to: NSPoint(x: 15.5, y: 5))
    verticalPath.line(to: NSPoint(x: 15.5, y: 16))
    // Top segment (y: 17 to 28)
    verticalPath.move(to: NSPoint(x: 15.5, y: 17))
    verticalPath.line(to: NSPoint(x: 15.5, y: 28))
    
    let horizontalPath = NSBezierPath()
    // Left segment (x: 4 to 15)
    horizontalPath.move(to: NSPoint(x: 4, y: 16.5))
    horizontalPath.line(to: NSPoint(x: 15, y: 16.5))
    // Right segment (x: 16 to 27)
    horizontalPath.move(to: NSPoint(x: 16, y: 16.5))
    horizontalPath.line(to: NSPoint(x: 27, y: 16.5))
    
    let circleRect = NSRect(x: 9.5, y: 10.5, width: 12.0, height: 12.0)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    
    // Circle fill (no shadow) - black with alpha 0.15 matching native A=38
    NSColor.black.withAlphaComponent(0.15).setFill()
    circlePath.fill()
    
    // Configure white shadow for high contrast on dark backgrounds
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.white.withAlphaComponent(0.65)
    shadow.shadowOffset = .zero
    shadow.shadowBlurRadius = 1.5
    
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    
    // Draw dark core lines (width 1.0) with shadow - white 0.20, alpha 0.85 matching native (51,51,51,217)
    let lineColor = NSColor(white: 0.20, alpha: 0.85)
    lineColor.setStroke()
    verticalPath.lineWidth = 1.0
    verticalPath.stroke()
    horizontalPath.lineWidth = 1.0
    horizontalPath.stroke()
    
    // Circle dark stroke - black with alpha 0.32 matching native A=81
    NSColor.black.withAlphaComponent(0.32).setStroke()
    circlePath.lineWidth = 1.0
    circlePath.stroke()
    
    NSGraphicsContext.current?.restoreGraphicsState()
    
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 15, y: 15))
  }()

  static var vectorScreenshotCrosshairLight: NSCursor = {
    let size = NSSize(width: 32, height: 32)
    let image = NSImage(size: size)
    image.isTemplate = false
    
    image.lockFocus()
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()
    
    let verticalPath = NSBezierPath()
    // Bottom segment (y: 5 to 16)
    verticalPath.move(to: NSPoint(x: 15.5, y: 5))
    verticalPath.line(to: NSPoint(x: 15.5, y: 16))
    // Top segment (y: 17 to 28)
    verticalPath.move(to: NSPoint(x: 15.5, y: 17))
    verticalPath.line(to: NSPoint(x: 15.5, y: 28))
    
    let horizontalPath = NSBezierPath()
    // Left segment (x: 4 to 15)
    horizontalPath.move(to: NSPoint(x: 4, y: 16.5))
    horizontalPath.line(to: NSPoint(x: 15, y: 16.5))
    // Right segment (x: 16 to 27)
    horizontalPath.move(to: NSPoint(x: 16, y: 16.5))
    horizontalPath.line(to: NSPoint(x: 27, y: 16.5))
    
    let circleRect = NSRect(x: 9.5, y: 10.5, width: 12.0, height: 12.0)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    
    let lightColor = NSColor.white
    
    // Circle fill (no shadow)
    lightColor.withAlphaComponent(0.15).setFill()
    circlePath.fill()
    
    // Configure black shadow for white lines
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -1.0)
    shadow.shadowBlurRadius = 1.0
    
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    
    // Draw clean single light-colored line with shadow
    lightColor.withAlphaComponent(0.85).setStroke()
    verticalPath.lineWidth = 1.0
    verticalPath.stroke()
    horizontalPath.lineWidth = 1.0
    horizontalPath.stroke()
    
    // Circle stroke - white with alpha 0.30 matching native A=81 proportion
    lightColor.withAlphaComponent(0.30).setStroke()
    circlePath.lineWidth = 1.0
    circlePath.stroke()
    
    NSGraphicsContext.current?.restoreGraphicsState()
    
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 15, y: 15))
  }()

  static var applicationWindowCursor: NSCursor = {
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
}
