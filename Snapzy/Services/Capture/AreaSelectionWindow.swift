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
  /// Read-only to other overlays (e.g. `RecordingCoordinator` uses it to decide whether a
  /// presenting session is recording-owned before reacting to its app-toggle shortcut).
  private(set) var selectionMode: SelectionMode = .screenshot
  private var selectionBackdrops: [CGDirectDisplayID: AreaSelectionBackdrop] = [:]
  private var liveFallbackDisplayIDs = Set<CGDirectDisplayID>()
  private var interactionMode: AreaSelectionInteractionMode = .manualRegion
  private var allowsApplicationWindowSelection = false
  private var applicationConfiguration: AreaSelectionApplicationConfiguration?
  private var displayActivationHandler: AreaSelectionDisplayActivationHandler?
  private var transitionRecaptureHandler: AreaSelectionTransitionRecaptureHandler?
  private var windowSelectionSnapshot: WindowSelectionSnapshot?
  private var windowSelectionTask: Task<Void, Never>?
  private var retainedPopoverVisibilityRefreshTask: Task<Void, Never>?
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
  /// crosshair — exactly replicating the working active-display behavior on every display without
  /// making Snapzy the foreground application.
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
  /// Bounded per-session watchdog that re-verifies pooled windows are actually presenting
  /// (see `scheduleSessionPresentationWatchdog`). `orderFrontRegardless()` is best-effort —
  /// WindowServer can silently refuse it or leave a stale frame/space/occlusion state that
  /// still reports `isVisible == true` while compositing nothing. In live-passthrough
  /// sessions the event tap keeps selection fully functional, so such a session looks
  /// alive but paints nothing (no crosshair, no selection rect). The one-shot `isVisible`
  /// assertion this replaces could neither detect nor heal those states.
  private var sessionPresentationWatchdogTimer: Timer?
  private var sessionPresentationWatchdogTicks = 0
  /// Displays the watchdog most recently flagged anomalous; used to log when a heal actually
  /// recovers presentation (the evidence loop for the intermittent invisible-session bug).
  private var sessionPresentationAnomalousDisplays = Set<CGDirectDisplayID>()
  private var isMovingManualSelection = false
  private var manualSelectionLastPointerLocation: CGPoint?

  /// Live-passthrough input source (plans/260723-2112-live-capture-passthrough): in live
  /// (backdrop-less) screenshot sessions the selection gesture is driven by this session
  /// event tap instead of the overlay's own event stream. The tap consumes all mouse
  /// events, so interaction with the apps beneath is frozen and already-visible hover
  /// UI (tooltips, hover cards) persists for capture instead of being dismissed by
  /// pointer movement. Falls back to window-event input when Accessibility trust is missing.
  private let livePassthroughEventTap = CaptureEventTapController()
  private var isLivePassthroughInputActive = false
  private var hasRevealedLivePassthroughDim = false
  /// Grants this background process permission to hide the system cursor (see
  /// `BackgroundCursorControl`); without it `CGDisplayHideCursor` is a no-op off the
  /// foreground app. Enabled once per session, just before the first hide below.
  private let backgroundCursorControl = BackgroundCursorControl()
  /// Per-display cursor hide/show balance. With `backgroundCursorControl` enabled the
  /// hides actually take effect from this background agent, so only the drawn crosshair
  /// proxy remains (the arrow may momentarily reappear over the Dock — see
  /// `BackgroundCursorControl`).
  private var livePassthroughCursorHider = LivePassthroughCursorHider()
  /// Restores the real cursor position on teardown without the 0.25s post-warp
  /// hardware-event suppression (see `LivePassthroughCursorRestorer`).
  private let livePassthroughCursorRestorer = LivePassthroughCursorRestorer()
  /// Hover coalescing state: latest observed point, one scheduled UI update per run-loop
  /// pass, and the last point/display that actually triggered a hit-test.
  private var pendingLivePassthroughHoverPoint: CGPoint?
  private var isLivePassthroughHoverUpdateScheduled = false
  private var lastProcessedLivePassthroughHoverPoint: CGPoint?
  private var lastProcessedLivePassthroughDisplayID: CGDirectDisplayID?
  /// Last raw pointer location (global Quartz, top-left origin) the capture event tap
  /// reported this session. On teardown the cursor is warped here before it is revealed:
  /// while the consuming tap runs, the WindowServer's tracked cursor position goes stale, so
  /// `CGDisplayShowCursor` alone would reveal the arrow at the pre-session spot (a visible
  /// "jump"). Nil until the first observed event; cleared on teardown.
  private var lastLivePassthroughPointerLocation: CGPoint?

  /// Whether the overlay should be dismissed immediately after a selection is made.
  /// When `false`, the caller is responsible for calling `cancelSelection()` to dismiss.
  /// Prefer the `dismissesAfterSelection` start parameter over `setDismissesAfterSelection`:
  /// the parameter is applied AFTER session-start teardown, so it cannot be wiped by the
  /// replacement-cancel of a previous session (and cannot leak into the next session).
  private(set) var dismissesAfterSelection = true

  func setDismissesAfterSelection(_ value: Bool) {
    dismissesAfterSelection = value
  }

  // MARK: - Initialization

  override private init() {
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
    let currentDisplayIDs = Set(NSScreen.screens.compactMap(\.displayID))
    let pooledDisplayIDs = Set(windowPool.keys)

    // Remove windows for disconnected displays
    for displayID in pooledDisplayIDs.subtracting(currentDisplayIDs) {
      windowPool[displayID]?.close()
      windowPool.removeValue(forKey: displayID)
    }

    // Add windows for new displays. When a session is presenting, the new panel must be
    // configured and shown immediately — a hidden pooled window is a click fall-through hole
    // on its display (clicks reach the apps underneath while the session looks alive).
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID,
            windowPool[displayID] == nil else { continue }
      let window = AreaSelectionWindow(screen: screen, pooled: true)
      window.selectionDelegate = self
      windowPool[displayID] = window
      if isPresenting {
        configureSessionWindow(window, for: screen, displayID: displayID)
      }
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

      let window: AreaSelectionWindow
      let isPooled: Bool
      if let pooled = windowPool[displayID] {
        window = pooled
        isPooled = true
      } else {
        // Fallback: create window if not pooled
        window = AreaSelectionWindow(screen: screen, pooled: false)
        windowPool[displayID] = window
        isPooled = false
      }
      configureSessionWindow(window, for: screen, displayID: displayID)
      DiagnosticLogger.shared.log(
        .debug,
        .capture,
        "Area selection window activated",
        context: [
          "displayID": "\(displayID)",
          "frame": "\(screen.frame)",
          "selectionEnabled": "\(selectionEnabled(for: displayID))",
          "isPooled": "\(isPooled)",
        ]
      )
    }
  }

  /// Configure a window for the current session state and present it without stealing focus.
  /// Shared by `activatePooledWindows` (session start) and `refreshWindowPool` (mid-session
  /// display attach) so any window shown during a session gets identical selection state.
  private func configureSessionWindow(
    _ window: AreaSelectionWindow,
    for screen: NSScreen,
    displayID: CGDirectDisplayID
  ) {
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
    window.updateSelectionMode(selectionMode)
    // Set the passthrough flag BEFORE any overlay configuration that funnels into
    // `applyActiveCursor()` (`setInteractionMode`, `setSelectionEnabled`, `resetSelection`,
    // and the final `refreshCursor()`). With the flag in place those calls skip
    // `NSCursor.set()` for passthrough sessions; without it the crosshair would be set
    // on the real cursor at session start and could leak past teardown (e.g. onto the
    // Quick Access card) now that background cursor changes stick.
    window.setLivePassthroughInputEnabled(isLivePassthroughInputActive)
    if let backdrop = selectionBackdrops[displayID] {
      window.overlayView.applyBackdrop(backdrop)
    } else {
      window.overlayView.clearBackdrop()
    }
    window.selectionDelegate = self
    window.orderFrontRegardless()
    window.overlayView.setAllowsApplicationWindowSelection(allowsApplicationWindowSelection)
    window.overlayView.setWindowSelectionSnapshot(windowSelectionSnapshot)
    window.overlayView.setRetainedMenuBarPopoverCaptures(
      applicationConfiguration?.immediateMenuBarPopoverCaptures ?? []
    )
    window.overlayView.setInteractionMode(interactionMode, resetSelection: false)
    window.overlayView.setSelectionEnabled(selectionEnabled(for: displayID))
    window.overlayView.resetSelection()
    // A window attached mid-session (display hot-plug) must match the current dim
    // state, not the hidden initial state — and its display joins the cursor
    // hide/show balance (the hider guards against double-hiding covered displays).
    window.overlayView.setLivePassthroughDimHidden(!livePassthroughShowsDim)
    if isLivePassthroughInputActive {
      livePassthroughCursorHider.hide(displayIDs: [displayID])
    }
    window.setReceivesKeyboardInput(displayID == keyboardOwnerDisplayID)
    window.activateKeyboardInputIfNeeded()
    window.overlayView.refreshCursor()
  }

  /// Reset window interaction state without hiding.
  private func resetPooledWindows() {
    for (_, window) in windowPool {
      window.setReceivesKeyboardInput(false)
      // Clear the passthrough flag only AFTER `resetSelection()`: its `refreshCursor()`
      // funnels into `applyActiveCursor()`, which must still see the passthrough guard
      // so it skips `NSCursor.set()`. Clearing the flag first would set the crosshair on
      // the real cursor mid-teardown and leak it past the session (e.g. onto the Quick
      // Access card).
      window.overlayView.resetSelection()
      window.overlayView.clearBackdrop()
      window.setLivePassthroughInputEnabled(false)
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
    startSelectionSession(mode: .screenshot, backdrops: [:], completion: completion)
  }

  /// Start area selection with mode
  /// - Parameters:
  ///   - mode: The selection mode (screenshot or recording)
  ///   - completion: Called with the selected rect and mode, or nil if cancelled
  func startSelection(mode: SelectionMode, completion: @escaping AreaSelectionCompletionWithMode) {
    startSelectionSession(mode: mode, backdrops: [:], completionWithMode: completion)
  }

  func startSelection(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    dismissesAfterSelection: Bool = true,
    completion: @escaping AreaSelectionResultCompletion
  ) {
    startSelection(
      mode: mode,
      backdrops: backdrops,
      applicationConfiguration: nil,
      initialInteractionMode: initialInteractionMode,
      dismissesAfterSelection: dismissesAfterSelection,
      completion: completion
    )
  }

  func startSelection(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration?,
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    dismissesAfterSelection: Bool = true,
    onDisplayActivationRequested: AreaSelectionDisplayActivationHandler? = nil,
    onTransitionRecapture: AreaSelectionTransitionRecaptureHandler? = nil,
    completion: @escaping AreaSelectionResultCompletion
  ) {
    startSelectionSession(
      mode: mode,
      backdrops: backdrops,
      applicationConfiguration: applicationConfiguration,
      initialInteractionMode: initialInteractionMode,
      dismissesAfterSelection: dismissesAfterSelection,
      completionWithResult: completion,
      onDisplayActivationRequested: onDisplayActivationRequested,
      onTransitionRecapture: onTransitionRecapture
    )
  }

  private func startSelectionSession(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    applicationConfiguration: AreaSelectionApplicationConfiguration? = nil,
    initialInteractionMode: AreaSelectionInteractionMode = .manualRegion,
    dismissesAfterSelection: Bool = true,
    completion: AreaSelectionCompletion? = nil,
    completionWithMode: AreaSelectionCompletionWithMode? = nil,
    completionWithResult: AreaSelectionResultCompletion? = nil,
    onDisplayActivationRequested: AreaSelectionDisplayActivationHandler? = nil,
    onTransitionRecapture: AreaSelectionTransitionRecaptureHandler? = nil
  ) {
    // Atomic replacement: a presenting session must be torn down through the normal cancel
    // path — never silently dropped. This runs BEFORE the new completion is stored (below), so
    // `cancelSelection` invokes the PREVIOUS session's completion with nil and each feature's
    // own cancel cleanup runs: selection-active flags reset, hidden windows restore, frozen
    // sessions invalidate. Without this, a replaced session stranded its caller's state (e.g.
    // CaptureViewModel.isAreaSelectionActive stuck true, blocking every later capture) and
    // leaked the previous session's observers and Quick Access suspension.
    if isPresenting {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Area selection replacing a presenting session; cancelling it first",
        context: [
          "previousMode": "\(selectionMode)",
          "newMode": "\(mode)",
        ]
      )
      cancelSelection()
    }
    QuickAccessManager.shared.suspendForCapture()
    // Always clean up prior session's monitors to prevent orphaned leaks
    removeEscapeMonitors()
    stopPointerTracking()
    clearManualSelectionTracking(render: false)
    cancelWindowSelectionTask()
    cancelRetainedPopoverVisibilityRefresh()
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
    self.completion = completion
    self.completionWithMode = completionWithMode
    self.completionWithResult = completionWithResult
    displayActivationHandler = onDisplayActivationRequested
    transitionRecaptureHandler = onTransitionRecapture
    requestedDisplayActivationIDs.removeAll()
    deferredBackdropDisplayIDs.removeAll()
    // Per-session recovery memory for the presentation watchdog (kept across mid-session
    // watchdog re-arms; see `cancelSessionPresentationWatchdog`).
    sessionPresentationAnomalousDisplays.removeAll()
    allowsApplicationWindowSelection = applicationConfiguration != nil
    interactionMode = applicationConfiguration == nil ? .manualRegion : initialInteractionMode
    windowSelectionSnapshot = applicationConfiguration.map { configuration in
      WindowSelectionSnapshot(
        orderedCandidates: configuration.immediateMenuBarPopoverCaptures.map { capture in
          WindowSelectionCandidate(
            target: capture.target,
            ownerName: "",
            windowLayer: 1
          )
        }
      )
    }
    selectionSessionID = UUID()
    keyboardOwnerDisplayID = resolvedKeyboardOwnerDisplayID()
    isPresenting = true
    // Applied after the replacement teardown above (which resets it to true), so the caller's
    // policy survives a session start and never leaks across sessions.
    self.dismissesAfterSelection = dismissesAfterSelection

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

    // Start the event tap before windows are configured so each panel picks up the
    // correct input mode (tap-driven passthrough vs. legacy window events).
    startLivePassthroughInputIfNeeded()

    // Activate pooled windows (instant show)
    activatePooledWindows()
    scheduleRetainedMenuBarPopoverVisibilityRefresh()

    // Keep live overlay sessions non-activating so foreground-window capture still observes the app
    // that was frontmost when the capture started. Cursor rect refresh plus pointer tracking gives
    // backdrop-less sessions crosshair ownership without making Snapzy the active app. Frozen
    // sessions already render over a captured backdrop and do not need this key-window churn.
    for (_, window) in windowPool {
      window.invalidateCursorRects(for: window.overlayView)
    }
    if selectionBackdrops.isEmpty, !isLivePassthroughInputActive {
      // Passthrough sessions get pointer-follows from tap moves and need no key-window
      // churn (Esc/arrows arrive via the tap regardless of which window is key), so the
      // 60 Hz key-follows-pointer timer stays off there. It still runs for the legacy
      // window-event fallback.
      startPointerTrackingIfNeeded()
    }

    // Mirror the legacy appearance: window-selection mode always shows the dim (with a
    // cutout on the hovered window); manual region shows it from session start when the
    // selection-area-overlay preference is on, otherwise the first drag reveals it.
    updateLivePassthroughDimVisibility()

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

          guard let self, selectionSessionID == sessionID else { return }
          guard let backdrop else {
            DiagnosticLogger.shared.log(
              .warning,
              .capture,
              "Failed to capture background backdrop for magnifier zoom in backdrop-less session"
            )
            return
          }
          applyBackdrop(backdrop, for: targetDisplayID)
        }
      }
    }

    if keyboardOwnerDisplayID == nil || isLivePassthroughInputActive {
      // Set up session key monitoring when the overlay cannot own keyboard input directly —
      // and in passthrough sessions as a fallback: the tap is the primary Esc path and
      // consumes the event, so these monitors only ever fire if the tap is starved
      // (Secure Event Input) or disabled.
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

    scheduleSessionPresentationWatchdog()
  }

  /// Bounded presentation watchdog: checks once on the next run-loop turn, then every 0.5s
  /// for the first ~3s of the session. `orderFrontRegardless()` is best-effort: WindowServer
  /// can silently refuse it (fullscreen-space transitions, transient ordering loss), leave a
  /// stale frame after a display reconfiguration, mark the window occluded, or drop the
  /// panel's all-spaces membership — states that can still report `isVisible == true` while
  /// compositing nothing. A session whose panels never present looks alive to the user while
  /// (in live-passthrough) the event tap keeps selection fully functional — invisible but
  /// pixel-correct captures. Each check verifies the full presentation state via
  /// `AreaSelectionPresentationLogic` — including the WindowServer's own on-screen window
  /// list, the ground truth the AppKit-side properties can all miss — heals what it can
  /// (frame resync + membership/order re-assert), and logs the exact failure plus the
  /// overlay's layer diagnostics so field reports can be diagnosed from the diagnostic log
  /// bundle.
  private func scheduleSessionPresentationWatchdog() {
    cancelSessionPresentationWatchdog()
    let sessionID = selectionSessionID
    sessionPresentationWatchdogTicks = 0
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        self?.runSessionPresentationCheck(sessionID: sessionID)
      }
    }
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleSessionPresentationWatchdogTick(sessionID: sessionID)
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    sessionPresentationWatchdogTimer = timer
  }

  private func cancelSessionPresentationWatchdog() {
    sessionPresentationWatchdogTimer?.invalidate()
    sessionPresentationWatchdogTimer = nil
    sessionPresentationWatchdogTicks = 0
    // Note: `sessionPresentationAnomalousDisplays` is intentionally NOT cleared here — the
    // watchdog re-arms on every mid-session space/activation change, and clearing would lose
    // the memory needed to log a post-switch recovery (the 2-desktop field scenario). The
    // set is reset at session start instead.
  }

  private func handleSessionPresentationWatchdogTick(sessionID: UUID) {
    guard isPresenting, selectionSessionID == sessionID else {
      cancelSessionPresentationWatchdog()
      return
    }
    sessionPresentationWatchdogTicks += 1
    runSessionPresentationCheck(sessionID: sessionID)
    if sessionPresentationWatchdogTicks >= 6 {
      cancelSessionPresentationWatchdog()
    }
  }

  /// Verify every pooled window's presentation state; heal and log anomalies. Safe to call
  /// repeatedly — a clean window is a no-op.
  private func runSessionPresentationCheck(sessionID: UUID) {
    guard isPresenting, selectionSessionID == sessionID else { return }
    let onScreenWindowNumbers = windowServerOnScreenWindowNumbers()
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID,
            let window = windowPool[displayID] else { continue }
      // A window number <= 0 means the panel has no WindowServer window yet (never ordered
      // in) — the query can't classify it, so report unknown rather than a false anomaly.
      let onScreenPerWindowServer: Bool? = {
        guard let onScreenWindowNumbers, window.windowNumber > 0 else { return nil }
        return onScreenWindowNumbers.contains(window.windowNumber)
      }()
      let state = AreaSelectionPresentationState(
        isVisible: window.isVisible,
        isOnActiveSpace: window.isOnActiveSpace,
        occlusionVisible: window.occlusionState.contains(.visible),
        alphaValue: window.alphaValue,
        windowFrame: window.frame,
        screenFrame: screen.frame,
        onScreenPerWindowServer: onScreenPerWindowServer
      )
      let issues = AreaSelectionPresentationLogic.issues(for: state)
      if issues.isEmpty {
        // Evidence loop: a previously flagged display that now presents cleanly tells us the
        // heal worked (and how many ticks it took).
        if sessionPresentationAnomalousDisplays.remove(displayID) != nil {
          DiagnosticLogger.shared.log(
            .info,
            .capture,
            "Area selection window presentation recovered after re-assert",
            context: [
              "displayID": "\(displayID)",
              "watchdogTick": "\(sessionPresentationWatchdogTicks)",
              "windowNumber": "\(window.windowNumber)",
            ]
          )
        }
        continue
      }
      sessionPresentationAnomalousDisplays.insert(displayID)
      var context: [String: String] = [
        "issues": issues.map(\.rawValue).joined(separator: ","),
        "displayID": "\(displayID)",
        "isVisible": "\(window.isVisible)",
        "isOnActiveSpace": "\(window.isOnActiveSpace)",
        "occlusionState": "\(window.occlusionState.rawValue)",
        "alphaValue": "\(window.alphaValue)",
        "appIsActive": "\(NSApp.isActive)",
        "screenFrame": "\(screen.frame)",
        "windowFrame": "\(window.frame)",
        "windowNumber": "\(window.windowNumber)",
        "onScreenPerWindowServer": onScreenPerWindowServer.map { "\($0)" } ?? "unknown",
        "watchdogTick": "\(sessionPresentationWatchdogTicks)",
      ]
      context.merge(window.overlayView.presentationDiagnostics()) { _, new in new }
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Area selection window presentation anomaly; re-asserting",
        context: context
      )
      if issues.contains(.frameMismatch) {
        window.setFrame(screen.frame, display: true)
        window.overlayView.updateBounds(screen.frame)
      }
      window.reassertPresentation()
      window.activateKeyboardInputIfNeeded()
      window.overlayView.refreshCursor()
    }
  }

  /// WindowServer ground truth: the window numbers the compositor currently presents
  /// (CGWindowList `.optionOnScreenOnly`). AppKit window properties are app-side bookkeeping
  /// and can report a healthy state for a window the compositor never presents on the active
  /// space — the invisible-session failure this watchdog exists for. Returns nil when the
  /// query itself fails; callers must treat that as "unknown", never as an anomaly.
  private func windowServerOnScreenWindowNumbers() -> Set<Int>? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
      as? [[String: Any]] else { return nil }
    return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
  }

  /// Menu extras may close after Snapzy's nonactivating selection panels are already visible.
  /// Check only the initially retained IDs for a short, bounded period, then stop as soon as
  /// they have all disappeared. This stays off the pointer/hover path and avoids double-rendering
  /// panels that remain alive (for example, application-defined status-item popovers).
  private func scheduleRetainedMenuBarPopoverVisibilityRefresh() {
    guard let captures = applicationConfiguration?.immediateMenuBarPopoverCaptures, !captures.isEmpty else {
      return
    }
    cancelRetainedPopoverVisibilityRefresh()
    let sessionID = selectionSessionID
    let targets = captures.map(\.target)
    var remainingVisibleWindowIDs = Set(targets.map(\.windowID))
    retainedPopoverVisibilityRefreshTask = Task { [weak self] in
      for attempt in 0 ..< 10 {
        guard let self, isPresenting, selectionSessionID == sessionID else { return }
        let sampledVisibleWindowIDs = await Task.detached(priority: .utility) {
          WindowSelectionQueryService.visibleWindowIDs(for: targets)
        }.value
        guard isPresenting, selectionSessionID == sessionID else { return }
        // Once a source has disappeared, keep its retained image visible for this session even
        // if a later WindowServer sample transiently reports that ID again.
        remainingVisibleWindowIDs.formIntersection(sampledVisibleWindowIDs)
        for (_, window) in windowPool {
          window.overlayView.setRetainedMenuBarPopoverWindowIDsStillOnScreen(remainingVisibleWindowIDs)
        }
        guard !remainingVisibleWindowIDs.isEmpty, attempt < 9 else { return }
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          return
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
    if event.keyCode == 53 { // Escape key
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
          !windowPool.values.contains(where: \.overlayView.isManualSelectionInProgress) else {
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
    updateLivePassthroughDimVisibility()
  }

  private func startWindowSelectionPreparationIfNeeded() {
    guard let applicationConfiguration else { return }
    let immediateSnapshot = windowSelectionSnapshot
    let sessionID = selectionSessionID
    windowSelectionTask = Task { [weak self] in
      let snapshot = await WindowSelectionQueryService.prepareSnapshot(
        prefetchedContentTask: applicationConfiguration.prefetchedContentTask,
        excludeOwnApplication: applicationConfiguration.excludeOwnApplication
      )
      await MainActor.run {
        guard let self, self.selectionSessionID == sessionID else { return }
        self.windowSelectionSnapshot = immediateSnapshot?.merging(snapshot) ?? snapshot
        for (_, window) in self.windowPool {
          window.overlayView.setWindowSelectionSnapshot(self.windowSelectionSnapshot)
        }
      }
    }
  }

  private func cancelWindowSelectionTask() {
    windowSelectionTask?.cancel()
    windowSelectionTask = nil
  }

  private func cancelRetainedPopoverVisibilityRefresh() {
    retainedPopoverVisibilityRefreshTask?.cancel()
    retainedPopoverVisibilityRefreshTask = nil
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
        "keyboardOwnerDisplayID": keyboardOwnerDisplayID.map { "\($0)" } ?? "nil",
      ]
    )

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

    // Space switches are the prime suspect for a panel's lost all-spaces membership or
    // compositing (the overlay shows on one desktop Space but not another). Re-arm the
    // bounded watchdog so the seconds after each switch get the same WindowServer
    // ground-truth verification and membership re-assert heal as session start.
    scheduleSessionPresentationWatchdog()
  }

  private func recaptureBackdropsForLuma(reason: RecaptureReason = .appActivation) {
    guard isPresenting else { return }

    // For frozen sessions, we never recapture on simple app activations/switches
    // (including the initial activation of Snapzy itself) to avoid double-captures
    // and losing the focused window's state. We only recapture if the Space changes.
    if transitionRecaptureHandler != nil, reason == .appActivation {
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
          "isActive": "\(NSApp.isActive)",
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

          guard let self, selectionSessionID == sessionID else { return }
          if let backdrop {
            applyBackdrop(backdrop, for: displayID, animated: true)
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
    // Snapshot and clear the callbacks BEFORE invoking them: a completion may synchronously
    // call back into the controller (live area mode calls `cancelSelection()` to dismiss after
    // its mouse-up snapshots) — without this, that re-entrant call would fire the same
    // completion a second time with nil.
    let completion = completion
    let completionWithMode = completionWithMode
    let completionWithResult = completionWithResult
    self.completion = nil
    self.completionWithMode = nil
    self.completionWithResult = nil
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
    // Snapshot and clear before invoking — see `completeSelection` (re-entrancy safety).
    let completion = completion
    let completionWithMode = completionWithMode
    let completionWithResult = completionWithResult
    self.completion = nil
    self.completionWithMode = nil
    self.completionWithResult = nil
    completion?(nil)
    completionWithMode?(nil, selectionMode)
    completionWithResult?(nil)

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
  /// Added to `.common` run-loop modes so it keeps firing during window/event tracking. Once a
  /// manual selection starts, each tick re-asserts the crosshair through
  /// `reassertManualSelectionCursor()` instead — covering the stationary-hold gap between
  /// mouseDown and the first drag event that the drag monitors cannot reach.
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
    // A manual drag owns the cursor, but the drag monitors only re-assert it on pointer
    // movement — and the WindowServer can reset the crosshair to the arrow right after
    // mouseDown (the activation handoff the click itself triggered, a backdrop recapture
    // blocking the run loop). With the button held and the pointer stationary, no drag event
    // ever fires, so the arrow would stick until the user moves. Re-assert on every tick for
    // the whole drag instead. Key ownership below must still not move mid-drag — the source
    // window owns the gesture — so the early return stays.
    if manualSelectionStartPoint != nil {
      reassertManualSelectionCursor()
      return
    }
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

  // MARK: - Live Passthrough Input

  /// Live (backdrop-less) screenshot sessions can run tap-driven with input consumed by
  /// the session event tap, which consumes every mouse event — freezing interaction with the
  /// apps beneath so already-visible hover UI (tooltips, hover cards) is never dismissed and
  /// can be captured. Frozen and
  /// recording sessions keep window-event input, and the `screenshotLivePassthrough`
  /// preference (default on) forces the legacy path when the user opts out.
  private func shouldUseLivePassthroughInput(
    mode: SelectionMode,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop]
  ) -> Bool {
    let passthroughEnabled = UserDefaults.standard
      .object(forKey: PreferencesKeys.screenshotLivePassthrough) as? Bool ?? true
    return mode == .screenshot && backdrops.isEmpty && passthroughEnabled
  }

  /// The system Accessibility prompt is shown at most once per app run, so users who
  /// decline are never nagged on every capture — the session simply falls back.
  private static var hasPromptedLivePassthroughAccessibility = false

  /// Start the capture event tap for a live session. Without Accessibility trust (or if tap
  /// creation fails) the session falls back to legacy window-event input — nothing regresses.
  private func startLivePassthroughInputIfNeeded() {
    guard shouldUseLivePassthroughInput(mode: selectionMode, backdrops: selectionBackdrops) else { return }
    guard livePassthroughEventTap.isAvailable else {
      if !Self.hasPromptedLivePassthroughAccessibility {
        Self.hasPromptedLivePassthroughAccessibility = true
        livePassthroughEventTap.ensureAccessibilityPermission()
      }
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Live passthrough input unavailable (accessibility not granted); using window-event input"
      )
      return
    }
    livePassthroughEventTap.delegate = self
    guard livePassthroughEventTap.start() else { return }
    isLivePassthroughInputActive = true
    hasRevealedLivePassthroughDim = false
    lastLivePassthroughPointerLocation = nil
    // Hide the system cursor for the session so only the drawn crosshair proxy shows
    // (see `updateCursorProxy`). `CGDisplayHideCursor` only applies to the foreground
    // app, and this agent must never activate mid-capture — so first grant this
    // background process cursor control via `SetsCursorInBackground` (idempotent, once
    // per run); the hides below then take effect. If that grant is unavailable the hide
    // silently no-ops and we fall back to the old arrow-visible baseline. `NSCursor.hide()`
    // cannot substitute: it carries the same foreground requirement and only applies over
    // our own windows, which hit-transparent panels never are. The per-display balance is
    // honored on teardown (`stopLivePassthroughInput`) so the cursor can never be left
    // hidden where a hide took effect. (The arrow may momentarily reappear over the Dock —
    // see `BackgroundCursorControl`.)
    backgroundCursorControl.enableOnce()
    livePassthroughCursorHider.hide(displayIDs: Set(NSScreen.screens.compactMap(\.displayID)))
    DiagnosticLogger.shared.log(.info, .capture, "Live passthrough input active")
  }

  /// Stop the event tap and restore the cursor (where the hide took effect). Called
  /// from the single teardown funnel (`resetCallbacks`), which every exit path
  /// (commit, cancel, Esc, right-click, session replacement) runs through. Idempotent.
  private func stopLivePassthroughInput() {
    guard isLivePassthroughInputActive else { return }
    livePassthroughEventTap.stop()
    // Before revealing the real cursor, put it where the pointer actually is. While the
    // consuming tap ran, the WindowServer's tracked cursor position went stale, so
    // `CGDisplayShowCursor` alone reveals the arrow at the pre-session spot — a visible
    // "jump". `restore(to:)` warps to the last location the tap observed with the
    // post-warp hardware-event suppression window neutralized, so the cursor neither
    // freezes nor jumps as the user keeps moving. Skipped when the pointer never moved
    // this session (nothing to correct).
    if let location = lastLivePassthroughPointerLocation {
      livePassthroughCursorRestorer.restore(to: location)
    }
    isLivePassthroughInputActive = false
    hasRevealedLivePassthroughDim = false
    pendingLivePassthroughHoverPoint = nil
    lastProcessedLivePassthroughHoverPoint = nil
    lastProcessedLivePassthroughDisplayID = nil
    lastLivePassthroughPointerLocation = nil
    livePassthroughCursorHider.showAll()
  }

  /// Show the dim layer on the first consumed drag and keep it for the remainder of the
  /// session. With the selection-area-overlay preference on the dim is already visible from
  /// session start, so this only matters for the preference-off case (where the dim layer is
  /// colorless and revealing it is a visual no-op).
  private func revealLivePassthroughDimIfNeeded() {
    guard isLivePassthroughInputActive, !hasRevealedLivePassthroughDim else { return }
    hasRevealedLivePassthroughDim = true
    updateLivePassthroughDimVisibility()
  }

  private var livePassthroughShowsDim: Bool {
    LivePassthroughInputLogic.showsDim(
      interactionMode: interactionMode,
      hasRevealedDim: hasRevealedLivePassthroughDim,
      isDragging: manualSelectionStartPoint != nil,
      showsDimFromStart: UserDefaults.standard
        .object(forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay) as? Bool ?? true
    )
  }

  private func updateLivePassthroughDimVisibility() {
    guard isLivePassthroughInputActive else { return }
    let showDim = livePassthroughShowsDim
    for (_, window) in windowPool {
      window.overlayView.setLivePassthroughDimHidden(!showDim)
    }
  }

  /// Route an observed-then-consumed hover position into the overlay under the pointer.
  /// Coalesced: only the latest point is kept and at most one UI update is enqueued per
  /// run-loop pass — CALayer commits already batch per pass, so this just prevents
  /// redundant hit-tests/layout when a high-frequency mouse floods the tap.
  private func handleLivePassthroughHover(at screenPoint: CGPoint) {
    guard isPresenting, isLivePassthroughInputActive else { return }
    pendingLivePassthroughHoverPoint = screenPoint
    guard !isLivePassthroughHoverUpdateScheduled else { return }
    isLivePassthroughHoverUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.isLivePassthroughHoverUpdateScheduled = false
        guard let point = self.pendingLivePassthroughHoverPoint else { return }
        self.pendingLivePassthroughHoverPoint = nil
        self.processLivePassthroughHover(at: point)
      }
    }
  }

  private func processLivePassthroughHover(at screenPoint: CGPoint) {
    guard isPresenting, isLivePassthroughInputActive else { return }
    let pointerWindow = window(containing: screenPoint)
    let pointerDisplayID = pointerWindow?.displayID
    let displayChanged = pointerDisplayID != lastProcessedLivePassthroughDisplayID
    guard LivePassthroughInputLogic.shouldProcessHover(
      newPoint: screenPoint,
      lastProcessedPoint: lastProcessedLivePassthroughHoverPoint,
      containingDisplayChanged: displayChanged
    ) else { return }
    lastProcessedLivePassthroughHoverPoint = screenPoint
    lastProcessedLivePassthroughDisplayID = pointerDisplayID
    let signpost = PerfSignpost.CapturePassthrough.beginInterval("hoverUpdate")
    defer { PerfSignpost.CapturePassthrough.endInterval(signpost) }
    // Displays the pointer is not on get the old tracking-area `mouseExited` cleanup.
    for (_, pooledWindow) in windowPool {
      if pooledWindow == pointerWindow {
        pooledWindow.overlayView.handleLivePassthroughMouseMoved(atScreenPoint: screenPoint)
      } else {
        pooledWindow.overlayView.hideSizeIndicator()
        pooledWindow.overlayView.hideMagnifier()
        pooledWindow.overlayView.hideCursorProxy()
      }
    }
  }

  /// Route a consumed button event into the existing selection state machine.
  private func handleLivePassthroughButton(_ kind: CaptureButtonEvent, at screenPoint: CGPoint) {
    guard isPresenting, isLivePassthroughInputActive else { return }
    switch kind {
    case .leftMouseDown:
      guard let window = window(containing: screenPoint) else {
        // The tap already consumed this click — with no pooled window under the point it
        // vanishes instead of reaching the app beneath. Should not happen (every screen
        // gets a panel at session start); log it so field reports can be diagnosed.
        DiagnosticLogger.shared.log(
          .warning,
          .capture,
          "Live passthrough consumed leftMouseDown with no pooled window under the point",
          context: ["screenPoint": "\(screenPoint)"]
        )
        return
      }
      window.overlayView.handleLivePassthroughMouseDown(atScreenPoint: screenPoint)
    case .leftMouseDragged:
      revealLivePassthroughDimIfNeeded()
      switch interactionMode {
      case .manualRegion:
        // Same path the global drag monitors use: global coordinates, works across displays.
        updateManualSelection(to: screenPoint)
      case .applicationWindow:
        window(containing: screenPoint)?.overlayView.handleLivePassthroughMouseDragged(atScreenPoint: screenPoint)
      }
    case .leftMouseUp:
      switch interactionMode {
      case .manualRegion:
        endManualSelection(at: screenPoint)
      case .applicationWindow:
        window(containing: screenPoint)?.overlayView.handleLivePassthroughMouseUp(atScreenPoint: screenPoint)
      }
    case .rightMouseDown:
      cancelSelection()
    case .rightMouseUp, .rightMouseDragged:
      break
    }
  }

  /// Route a consumed key. Esc cancels via the same teardown funnel as right-click.
  /// Arrows/Return stay no-ops: the legacy overlay has no nudge/confirm key handling
  /// to mirror (verified — only the Annotate canvas nudges, not area selection), and
  /// the fallback escape monitors cover a starved tap. All other keys pass through
  /// the tap untouched (Space-drag move, application-mode toggle).
  private func handleLivePassthroughKey(_ key: CaptureKeyEvent) {
    guard isPresenting, isLivePassthroughInputActive else { return }
    switch key {
    case .escape:
      cancelSelection()
    case .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .return:
      break
    }
  }

  /// CGEvent locations arrive in global Quartz coordinates (top-left origin); the selection
  /// machinery works in AppKit global coordinates (bottom-left) — flip once at the boundary.
  private func appKitScreenPoint(fromQuartzGlobalPoint point: CGPoint) -> CGPoint {
    let mainScreenHeight = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })?.frame.height
      ?? CGDisplayBounds(CGMainDisplayID()).height
    return LivePassthroughInputLogic.appKitScreenPoint(
      fromQuartzGlobalPoint: point,
      mainScreenHeight: mainScreenHeight
    )
  }

  private func resetCallbacks() {
    isPresenting = false
    dismissesAfterSelection = true
    stopPointerTracking()
    stopLivePassthroughInput()
    cancelSessionPresentationWatchdog()
    lumaRecapturingTask?.cancel()
    lumaRecapturingTask = nil
    cancelRetainedPopoverVisibilityRefresh()
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
  /// single convergence point for the local/global drag monitors and the pointer-tracking tick,
  /// which covers stationary holds between mouseDown and the first drag event. `NSCursor.set()` is
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
      restoreLivePassthroughHoverAfterAbortedSelection(at: screenPoint)
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

  /// A tap (mouseDown+Up with no drag) aborts the selection: the per-window
  /// `resetSelection()` above cleared the drawn crosshair and coordinate indicator.
  /// Re-run the hover pipeline at the tap point so both reappear exactly as after any
  /// hover move — cursor proxy on the pointer display only, indicators hidden on the
  /// other displays. The coalescing gate is reset first so the stationary tap point
  /// (already the last processed hover point) is not dropped as a sub-pixel move.
  /// No-op outside live-passthrough sessions, where window events keep hover alive.
  private func restoreLivePassthroughHoverAfterAbortedSelection(at screenPoint: CGPoint) {
    guard isPresenting, isLivePassthroughInputActive else { return }
    lastProcessedLivePassthroughHoverPoint = nil
    processLivePassthroughHover(at: screenPoint)
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

  func areaSelectionWindowDidCancel(_: AreaSelectionWindow) {
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

  func areaSelectionWindow(_: AreaSelectionWindow, manualSelectionChangedTo screenPoint: CGPoint) {
    updateManualSelection(to: screenPoint)
  }

  func areaSelectionWindow(_: AreaSelectionWindow, manualSelectionEndedAt screenPoint: CGPoint) {
    endManualSelection(at: screenPoint)
  }
}

// MARK: - CaptureEventTapDelegate

extension AreaSelectionController: CaptureEventTapDelegate {
  /// The tap's run-loop source is installed on the main run loop, so these callbacks
  /// already fire on the main thread — `assumeIsolated` is safe and avoids per-event
  /// dispatch. `screenPoint` arrives in global Quartz coordinates and is flipped to
  /// AppKit coordinates once, here at the boundary.
  nonisolated func eventTapDidObserveMouseMoved(at screenPoint: CGPoint) {
    MainActor.assumeIsolated {
      lastLivePassthroughPointerLocation = screenPoint
      handleLivePassthroughHover(at: appKitScreenPoint(fromQuartzGlobalPoint: screenPoint))
    }
  }

  nonisolated func eventTapDidReceiveButton(_ kind: CaptureButtonEvent, at screenPoint: CGPoint) {
    MainActor.assumeIsolated {
      lastLivePassthroughPointerLocation = screenPoint
      handleLivePassthroughButton(kind, at: appKitScreenPoint(fromQuartzGlobalPoint: screenPoint))
    }
  }

  nonisolated func eventTapDidReceiveKey(_ key: CaptureKeyEvent) {
    MainActor.assumeIsolated {
      handleLivePassthroughKey(key)
    }
  }

  nonisolated func eventTapDidReceiveScroll(deltaY: CGFloat, hasPreciseScrollingDeltas: Bool, isCommandDown: Bool) {
    MainActor.assumeIsolated {
      guard isPresenting, isLivePassthroughInputActive,
            let quartzPoint = lastLivePassthroughPointerLocation else { return }
      let screenPoint = appKitScreenPoint(fromQuartzGlobalPoint: quartzPoint)
      window(containing: screenPoint)?.overlayView.handleLivePassthroughScroll(
        deltaY: deltaY,
        hasPreciseScrollingDeltas: hasPreciseScrollingDeltas,
        isCommandDown: isCommandDown
      )
    }
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
    targetScreen = screen
    overlayView = AreaSelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    // Configure as non-activating panel to prevent background windows from blurring
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = NSColor(white: 0, alpha: 0.005)
    sharingType = .none
    level = .screenSaver
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    isReleasedWhenClosed = false
    hasShadow = false
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    animationBehavior = .none // Disable window animations for instant appearance
    becomesKeyOnlyIfNeeded = true

    // Lock window movement and resizing
    isMovable = false
    isMovableByWindowBackground = false
    minSize = screen.frame.size
    maxSize = screen.frame.size

    // Set up content view
    contentView = overlayView
    overlayView.delegate = self
    overlayView.keyEventHandler = { [weak self] event in
      guard let self else { return false }
      return selectionDelegate?.areaSelectionWindow(self, didReceiveKeyEvent: event) ?? false
    }

    // Hide the panel from Accessibility so VoiceOver / assistive tech ignore
    // the overlay chrome (kept as hygiene for any future AX-aware capture work).
    setAccessibilityElement(false)
    setAccessibilityHidden(true)
    setAccessibilityRole(.unknown)

    if pooled {
      // Pooled windows start hidden
      orderOut(nil)
    } else {
      // Non-pooled windows show immediately without stealing focus
      orderFrontRegardless()
    }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateSelectionMode(_ mode: SelectionMode) {
    overlayView.selectionMode = mode
  }

  /// Switch between window-event input (default) and live-passthrough input.
  /// Passthrough makes the panel hit-transparent (clear background — fully transparent
  /// pixels are not hit-testable). This is REQUIRED for hover persistence: any hittable
  /// window under the pointer steals pointer ownership from the app beneath, which
  /// synthesizes tracking-exit and dismisses its visible hover UI. Interaction freeze
  /// comes from the event tap consuming every mouse event before delivery; if the tap
  /// is ever disabled by the system, events hit this panel whose handlers are inert in
  /// passthrough mode — the apps beneath never see them either way. The system cursor
  /// is hidden (`CGDisplayHideCursor`, unlocked from this background agent by
  /// `BackgroundCursorControl`) and the crosshair is rendered by the drawn proxy layer,
  /// never by cursor rects — cursor rects would require this panel to be hittable.
  func setLivePassthroughInputEnabled(_ enabled: Bool) {
    ignoresMouseEvents = enabled
    acceptsMouseMovedEvents = !enabled
    backgroundColor = enabled ? .clear : NSColor(white: 0, alpha: 0.005)
    overlayView.setLivePassthroughInputEnabled(enabled)
  }

  override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
    minSize = frameRect.size
    maxSize = frameRect.size
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

  /// Force the WindowServer to re-evaluate this panel's space membership and ordering. Plain
  /// `orderFrontRegardless()` only re-orders within the spaces the window is already a
  /// member of, so it cannot repair a broken `.canJoinAllSpaces` membership — the
  /// invisible-on-the-active-Space field failure where every AppKit property looks healthy.
  /// Cycling off-screen with a real collection-behavior change makes the WindowServer
  /// re-join every space; the `needsDisplay` nudge recommits the layer tree afterwards.
  func reassertPresentation() {
    let behavior = collectionBehavior
    orderOut(nil)
    collectionBehavior = []
    collectionBehavior = behavior
    orderFrontRegardless()
    overlayView.needsDisplay = true
  }

  var displayID: CGDirectDisplayID? {
    targetScreen.displayID
  }

  // Non-activating: prevent stealing focus from other apps
  override var canBecomeKey: Bool {
    receivesKeyboardInput
  }

  override var canBecomeMain: Bool {
    false
  }
}

// MARK: - AreaSelectionOverlayViewDelegate

extension AreaSelectionWindow: AreaSelectionOverlayViewDelegate {
  func overlayView(_: AreaSelectionOverlayView, didSelectRect rect: CGRect) {
    // Convert from view coordinates to screen coordinates
    let screenRect = convertToScreenCoordinates(rect)
    selectionDelegate?.areaSelectionWindow(self, didSelectRect: screenRect)
  }

  func overlayView(_: AreaSelectionOverlayView, didSelectWindow target: WindowCaptureTarget) {
    selectionDelegate?.areaSelectionWindow(self, didSelectWindow: target)
  }

  func overlayViewDidCancel(_: AreaSelectionOverlayView) {
    selectionDelegate?.areaSelectionWindowDidCancel(self)
  }

  func overlayViewDidRequestDisplayActivation(_: AreaSelectionOverlayView) {
    selectionDelegate?.areaSelectionWindowDidRequestDisplayActivation(self)
  }

  func overlayViewDidRequestImmediateManualSelection(_: AreaSelectionOverlayView) {
    selectionDelegate?.areaSelectionWindowDidRequestImmediateManualSelection(self)
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionBeganAt point: CGPoint) {
    selectionDelegate?.areaSelectionWindow(self, manualSelectionBeganAt: convertToScreenPoint(point))
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionChangedTo point: CGPoint) {
    selectionDelegate?.areaSelectionWindow(self, manualSelectionChangedTo: convertToScreenPoint(point))
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionEndedAt point: CGPoint) {
    selectionDelegate?.areaSelectionWindow(self, manualSelectionEndedAt: convertToScreenPoint(point))
  }

  private func convertToScreenCoordinates(_ rect: CGRect) -> CGRect {
    // The rect is in window coordinates (bottom-left origin)
    // Convert to global screen coordinates (also bottom-left origin)
    let windowFrame = frame

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
  /// True while a non-empty selection rect is on screen (drag in progress with visible area).
  /// The coordinate label stays visible until this flips true, then the dimensions label
  /// owns the size indicator layers — mirroring native macOS / CleanShot X behavior.
  private var hasVisibleSelectionRect = false
  private var pendingSelectionStartPoint: CGPoint?
  /// "Show window under cursor automatically" preference (see `PreferencesCaptureSettingsView`):
  /// while on, hovering in manual-region mode previews whatever window is under the cursor —
  /// the ⇧A toggle to `.applicationWindow` mode is no longer needed to see it.
  private var autoDetectWindowUnderCursor = false
  /// Set on mouseDown in manual-region mode when the press landed on a hovered window and
  /// auto-detection is on — the gesture hasn't yet been classified as a click (select the
  /// window) or a drag (fall through to manual region selection). Cleared by whichever happens.
  private var pendingWindowDetectionStartPoint: CGPoint?
  private let windowDetectionDragThreshold: CGFloat = 4.0
  private var currentMousePosition: CGPoint = .zero
  private var windowSelectionSnapshot: WindowSelectionSnapshot?
  private var hoveredWindowCandidate: WindowSelectionCandidate?
  private var retainedMenuBarPopoverCaptures: [CGWindowID: ImmediateMenuBarPopoverCapture] = [:]
  private var retainedMenuBarPopoverWindowIDsStillOnScreen = Set<CGWindowID>()

  // MARK: - CALayer-based Rendering (Phase 2 Optimization)

  private var snapshotLayer: CALayer!
  private var retainedMenuBarPopoverLayers: [CGWindowID: CALayer] = [:]
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
  /// Drawn replacement for the system cursor in live-passthrough sessions (the legacy
  /// cursor image is drawn at the pointer — pixel-parity with the window-event path's
  /// `NSCursor`; the system cursor itself stays where it is, since no public API can
  /// hide it from a background agent — see `LivePassthroughCursorHider`).
  private var cursorProxyLayer: CALayer!
  private var sizeIndicatorBackgroundLayer: CALayer!
  private var sizeIndicatorTextLayer: CATextLayer!
  private var lastSizeIndicatorText: String?
  private var lastSizeIndicatorTextSize: CGSize = .zero
  private var modeHintBackgroundLayer: CALayer!
  private var modeHintTextLayer: CATextLayer!

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
  /// Live-passthrough sessions drive the selection gesture from the capture event tap;
  /// the view's own mouse handlers stay inert (the panel gets no events anyway). The dim
  /// layer starts hidden here; the controller drives its visibility afterwards via
  /// `setLivePassthroughDimHidden(_:)`.
  private var isLivePassthroughInput = false
  /// Set once the event tap has delivered a real pointer position. While a passthrough
  /// session runs, the tap consumes every mouse move, so `NSEvent.mouseLocation` stays
  /// frozen at the session-start position — code that needs the pointer must read the
  /// tap-tracked `currentMousePosition` instead of the stale system location.
  private var hasLivePassthroughPointerPosition = false

  /// Disabled animations for instant layer updates
  private var disabledActions: [String: CAAction] {
    [
      "position": NSNull(),
      "bounds": NSNull(),
      "path": NSNull(),
      "hidden": NSNull(),
      "opacity": NSNull(),
      "backgroundColor": NSNull(),
      "frame": NSNull(),
      "contents": NSNull(),
      "contentsScale": NSNull(),
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

    // Local retained popover images sit above any full-display backdrop but below the dim
    // layer, so the existing application-window cutout makes them look like live content.
    // They remain absent while the matching WindowServer window is still on screen.

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

    // Drawn cursor proxy (live passthrough only; see `updateCursorProxy`). Starts hidden;
    // positioned at the pointer on every hover/drag update.
    cursorProxyLayer = CALayer()
    cursorProxyLayer.actions = disabledActions
    cursorProxyLayer.isHidden = true
    rootLayer.addSublayer(cursorProxyLayer)

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

  override func cursorUpdate(with _: NSEvent) {
    guard !isLivePassthroughInput else { return }
    applyActiveCursor()
  }

  override func mouseEntered(with event: NSEvent) {
    guard !isLivePassthroughInput else { return }
    delegate?.overlayViewDidRequestDisplayActivation(self)
    applyActiveCursor()
    let point = convert(event.locationInWindow, from: nil)
    currentMousePosition = point
    updateCoordinateIndicator(at: point)
    if selectionEnabled, interactionMode == .manualRegion, !isSelecting {
      updateCrosshairLayers()
      updateMagnifier(at: point)
    }
  }

  override func mouseExited(with _: NSEvent) {
    guard !isLivePassthroughInput else { return }
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
    applyActiveCursor()
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
    applyActiveCursor()
  }

  /// Effect seam for the real-cursor set in `applyActiveCursor()` — production applies
  /// the cursor to the system, tests record it. Mirrors the injectable-effect pattern
  /// of `LivePassthroughCursorHider` / `BackgroundCursorControl`.
  var cursorSetEffect: (NSCursor) -> Void = { $0.set() }

  /// Apply the mode's cursor image to the *real* system cursor — but never during live
  /// passthrough. There the real cursor is hidden and the crosshair is drawn by
  /// `cursorProxyLayer`, so setting the real cursor is pointless; and now that
  /// `BackgroundCursorControl` makes background cursor changes stick, doing so would leak
  /// the crosshair image onto the system cursor after the session ends (e.g. onto the Quick
  /// Access card). The window-event fallback path still sets the cursor normally.
  ///
  /// Also never while the overlay is off screen: its `.activeAlways` + `.mouseMoved`
  /// tracking area keeps delivering `mouseMoved`/`cursorUpdate` to this view after the
  /// session ends and the window is ordered out (`isVisible == false`), and the passthrough
  /// flag is already cleared by `resetPooledWindows()` at that point — so without this
  /// guard every stray event re-applies the crosshair and leaks it onto whatever the
  /// pointer hovers next (observed over the Quick Access card).
  private func applyActiveCursor() {
    guard !isLivePassthroughInput else { return }
    guard window?.isVisible ?? true else { return }
    cursorSetEffect(activeCursor)
  }

  // MARK: - Public Methods

  /// Reset selection state for window pool reuse
  func resetSelection() {
    isSelecting = false
    hasVisibleSelectionRect = false
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
    cursorProxyLayer.isHidden = true
    updateCoordinateIndicator(at: currentMousePosition)
    showSelectionAreaOverlay = UserDefaults.standard
      .object(forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay) as? Bool ?? true
    magnifier.reverseZoomDirection = UserDefaults.standard
      .object(forKey: PreferencesKeys.screenshotReverseMagnifierZoomDirection) as? Bool ?? false
    autoDetectWindowUnderCursor = UserDefaults.standard
      .object(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor) as? Bool ?? false
    pendingWindowDetectionStartPoint = nil
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

  /// Switch between window-event input (default) and live-passthrough input.
  /// In passthrough mode the dim layer starts hidden — the controller drives its
  /// visibility afterwards via `setLivePassthroughDimHidden(_:)`.
  func setLivePassthroughInputEnabled(_ enabled: Bool) {
    isLivePassthroughInput = enabled
    dimLayer.isHidden = enabled
    if !enabled {
      hasLivePassthroughPointerPosition = false
      hideCursorProxy()
    }
  }

  /// Set dim layer visibility in a live-passthrough session. Driven by the controller's
  /// `updateLivePassthroughDimVisibility()` — in manual mode visible from session start when
  /// the selection-area-overlay preference is on (otherwise revealed by the first drag),
  /// always visible in window-selection mode (mirroring the legacy window-event appearance).
  /// No-op outside passthrough mode.
  func setLivePassthroughDimHidden(_ hidden: Bool) {
    guard isLivePassthroughInput else { return }
    dimLayer.isHidden = hidden
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

  /// Max long-edge of the cached backdrop bitmap. The cache only feeds the 5×5 average-luminance
  /// sample grid, so a tiny image is plenty; this avoids a ~59 MB main-thread raster + copy on
  /// 5K Retina displays.
  private static let backdropPixelCacheMaxLongEdge: CGFloat = 512

  private func cacheBackdropPixels(from cgImage: CGImage, scale: CGFloat) {
    let startedAt = Date()
    let sourceWidth = cgImage.width
    let sourceHeight = cgImage.height
    guard sourceWidth > 0, sourceHeight > 0 else {
      backdropWidth = 0
      backdropHeight = 0
      backdropScale = scale
      backdropPixelDataArray = nil
      return
    }

    let downscale = min(1, Self.backdropPixelCacheMaxLongEdge / CGFloat(max(sourceWidth, sourceHeight)))
    let width = max(1, Int((CGFloat(sourceWidth) * downscale).rounded()))
    let height = max(1, Int((CGFloat(sourceHeight) * downscale).rounded()))
    backdropWidth = width
    backdropHeight = height
    backdropScale = scale

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
      backdropPixelDataArray = nil
      DiagnosticLogger.shared.log(
        .error,
        .capture,
        "Failed to create CGContext for backdrop pixel caching",
        context: ["width": "\(width)", "height": "\(height)"]
      )
      return
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    if let dataPtr = context.data {
      let totalBytes = width * height * 4
      let bufferPointer = UnsafeBufferPointer(start: dataPtr.assumingMemoryBound(to: UInt8.self), count: totalBytes)
      backdropPixelDataArray = Array(bufferPointer)
    } else {
      backdropPixelDataArray = nil
    }

    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "cacheBackdropPixels completed",
      context: [
        "width": "\(width)",
        "height": "\(height)",
        "sourceWidth": "\(sourceWidth)",
        "sourceHeight": "\(sourceHeight)",
        "scale": "\(scale)",
        "cachedBytes": "\(backdropPixelDataArray?.count ?? 0)",
        "duration_ms": "\(Date().timeIntervalSince(startedAt) * 1000)",
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

    for row in 0 ..< gridCount {
      for col in 0 ..< gridCount {
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
        isVisible: backdrop.isVisible
      )

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

    currentBackdropImage = backdrop.image
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
      contentsScale: screenScaleFactor,
      in: layer ?? CALayer()
    )
  }

  override func scrollWheel(with event: NSEvent) {
    if event.modifierFlags.contains(.command) {
      let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
      if delta != 0 {
        applyMagnifierScroll(delta: delta, hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas)
      }
    } else {
      super.scrollWheel(with: event)
    }
  }

  /// Shared magnifier-zoom step for both input paths (window scroll events and
  /// the live-passthrough event tap). Redraws at the tracked pointer position
  /// when the zoom actually changed.
  func applyMagnifierScroll(delta: CGFloat, hasPreciseScrollingDeltas: Bool) {
    if magnifier.handleScroll(delta: delta, hasPreciseScrollingDeltas: hasPreciseScrollingDeltas) {
      updateMagnifier(at: currentMousePosition)
    }
  }

  /// Live-passthrough input: the event tap consumes scroll-wheel events before
  /// they can become `NSEvent`s, so the controller forwards them here. Applies
  /// the same ⌘ gate as `scrollWheel(with:)`.
  func handleLivePassthroughScroll(deltaY: CGFloat, hasPreciseScrollingDeltas: Bool, isCommandDown: Bool) {
    guard isCommandDown, deltaY != 0 else { return }
    applyMagnifierScroll(delta: deltaY, hasPreciseScrollingDeltas: hasPreciseScrollingDeltas)
  }

  #if DEBUG

    var testSnapshotLayer: CALayer {
      snapshotLayer
    }

    var testBackdropPixelDataArray: [UInt8]? {
      backdropPixelDataArray
    }

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

    func testScrollWheel(
      deltaY: CGFloat,
      modifierFlags: NSEvent.ModifierFlags,
      hasPreciseScrollingDeltas: Bool = false
    ) {
      if modifierFlags.contains(.command) {
        if deltaY != 0 {
          applyMagnifierScroll(delta: deltaY, hasPreciseScrollingDeltas: hasPreciseScrollingDeltas)
        }
      }
    }

    var testSizeIndicatorTextLayer: CATextLayer {
      sizeIndicatorTextLayer
    }

    var testSizeIndicatorBackgroundLayer: CALayer {
      sizeIndicatorBackgroundLayer
    }

    var testCurrentMousePosition: CGPoint {
      currentMousePosition
    }

    var testCursorProxyLayer: CALayer {
      cursorProxyLayer
    }
  #endif

  /// Initialize crosshair at current mouse position (called on activation)
  private func initializeCrosshairAtCurrentMousePosition() {
    // Live passthrough: the event tap consumes every mouse move, so `NSEvent.mouseLocation`
    // is frozen at the session-start position. Once the tap has delivered a real position
    // keep it — re-reading the stale system location would snap the crosshair and the
    // coordinate indicator back to where the session started (observed after a tap).
    guard !(isLivePassthroughInput && hasLivePassthroughPointerPosition) else { return }
    // Get the current mouse location in screen coordinates
    let mouseLocationInScreen = NSEvent.mouseLocation

    // Convert to window coordinates, then to view coordinates
    if let window {
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

  /// Current mouse location converted to view coordinates, falling back to the last
  /// tracked position when the view has no window (e.g. unit tests).
  private func currentLocalMousePoint() -> CGPoint {
    // Live passthrough: `NSEvent.mouseLocation` is stale (see
    // `initializeCrosshairAtCurrentMousePosition`); the tap-tracked position is fresh.
    if isLivePassthroughInput, hasLivePassthroughPointerPosition {
      return currentMousePosition
    }
    if let window {
      return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }
    return currentMousePosition
  }

  /// Re-evaluates the coordinate indicator after a non-mouse event (layout pass, bounds
  /// change, selection re-render). `updateCoordinateIndicator(at:)` applies its own guards
  /// (mouse-over, interaction mode, visible selection rect), so this only restores the label
  /// where it belongs on screen and keeps it hidden everywhere else — including during a
  /// drag, where the dimensions label owns the size indicator layers.
  private func refreshCoordinateIndicatorAfterPassiveUpdate() {
    updateCoordinateIndicator(at: currentLocalMousePoint())
  }

  /// Update bounds when screen configuration changes
  func updateBounds(_ newFrame: CGRect) {
    frame = CGRect(origin: .zero, size: newFrame.size)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.frame = bounds
    updateRetainedMenuBarPopoverLayers()
    dimLayer.frame = bounds
    refreshCoordinateIndicatorAfterPassiveUpdate()
    CATransaction.commit()

    // Rebuild tracking areas for new bounds
    updateTrackingAreas()
    updateModeHint()
  }

  /// Diagnostic snapshot of the layer tree for the presentation watchdog's anomaly logs —
  /// answers "would anything paint?" without exposing the private layers. The keys are
  /// merged into the watchdog's log context so a field report shows the exact rendering
  /// state at the moment the window failed to present.
  func presentationDiagnostics() -> [String: String] {
    [
      "overlayBounds": "\(bounds)",
      "overlayLayerAttached": "\(layer != nil)",
      "overlaySublayerCount": "\(layer?.sublayers?.count ?? 0)",
      "snapshotLayerHidden": "\(snapshotLayer?.isHidden ?? true)",
      "snapshotLayerHasContents": "\(snapshotLayer?.contents != nil)",
      "dimLayerHidden": "\(dimLayer?.isHidden ?? true)",
      "dimLayerFrame": "\(dimLayer?.frame ?? .zero)",
      "cursorProxyHidden": "\(cursorProxyLayer?.isHidden ?? true)",
      "selectionBorderHidden": "\(selectionBorderLayer?.isHidden ?? true)",
      "backdropImagePresent": "\(currentBackdropImage != nil)",
      "isLivePassthroughInput": "\(isLivePassthroughInput)",
      "showSelectionAreaOverlay": "\(showSelectionAreaOverlay)",
    ]
  }

  // MARK: - First Mouse

  override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
    true
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
    updateRetainedMenuBarPopoverLayers()
    dimLayer.frame = bounds
    insideSelectionOverlayLayer.frame = bounds
    refreshCoordinateIndicatorAfterPassiveUpdate()
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

  /// Hide the drawn cursor proxy (pointer left this display, session ended, or
  /// passthrough disabled). No-op when already hidden.
  func hideCursorProxy() {
    cursorProxyLayer.isHidden = true
  }

  /// Drawn replacement for the system cursor in live-passthrough sessions. The system
  /// cursor is hidden for the session (`BackgroundCursorControl` +
  /// `LivePassthroughCursorHider`), so this proxy renders the visible cursor: the exact
  /// legacy cursor image (`activeCursor` — crosshair in manual mode, camera in window
  /// mode, arrow fallback) is drawn at the pointer with the same hotspot, giving
  /// pixel-parity with the window-event path. The position follows `currentMousePosition`,
  /// which hover and drag renders keep fresh.
  private func updateCursorProxy() {
    guard isLivePassthroughInput, isMouseOver else {
      cursorProxyLayer.isHidden = true
      return
    }
    let cursor = activeCursor
    let image = cursor.image
    let hotSpot = cursor.hotSpot
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    cursorProxyLayer.contents = image
    cursorProxyLayer.frame = CGRect(
      x: currentMousePosition.x - hotSpot.x,
      y: currentMousePosition.y - (image.size.height - hotSpot.y),
      width: image.size.width,
      height: image.size.height
    )
    cursorProxyLayer.isHidden = false
    CATransaction.commit()
  }

  #if DEBUG
    var testMouseLocationOverride: CGPoint?
  #endif

  private var isMouseOver: Bool {
    #if DEBUG
      if NSClassFromString("XCTestCase") != nil, self.window == nil {
        return true
      }
    #endif
    // Live passthrough: `NSEvent.mouseLocation` is frozen at the session-start position
    // (the tap consumes every move), so hit-test the tap-tracked pointer position
    // instead — otherwise the coordinate indicator and cursor proxy follow the stale
    // point, and vanish entirely once the pointer is on another display.
    if isLivePassthroughInput, hasLivePassthroughPointerPosition {
      guard let window, window.isVisible else { return false }
      let pointerOnScreen = window.convertPoint(toScreen: convert(currentMousePosition, to: nil))
      return window.frame.contains(pointerOnScreen)
    }
    #if DEBUG
      let mouseLocation = testMouseLocationOverride ?? NSEvent.mouseLocation
    #else
      let mouseLocation = NSEvent.mouseLocation
    #endif
    guard let window,
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
    guard isMouseOver, interactionMode == .manualRegion, !hasVisibleSelectionRect else {
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

    let shortcut: CaptureOverlayShortcut? = switch selectionMode {
    case .screenshot, .scrollingCapture:
      CaptureOverlayShortcutSettings.applicationCaptureShortcut
    case .recording:
      CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
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
    if let currentScreenPoint, let window {
      let pointInWindow = window.convertPoint(fromScreen: currentScreenPoint)
      localCurrentPoint = convert(pointInWindow, from: nil)
      currentMousePosition = localCurrentPoint ?? currentMousePosition
    } else {
      localCurrentPoint = nil
    }

    if magnifier.zoom > 1.0 {
      updateMagnifier(at: currentMousePosition)
    }

    // Keep the drawn cursor proxy glued to the pointer during drags (passthrough only;
    // no-op otherwise). Hover updates position it via `handlePrimaryMouseMoved`.
    updateCursorProxy()

    guard let screenRect, !screenRect.isEmpty else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      hasVisibleSelectionRect = false
      selectionBorderLayer.isHidden = true
      dimLayer.mask = nil
      insideSelectionOverlayLayer.isHidden = true
      crosshairIndicatorLayer.isHidden = true
      if selectionEnabled {
        // No drag point: fall back to the fresh mouse location so the coordinate
        // indicator survives re-renders triggered before the first mouse move
        // (e.g. an async backdrop landing right after the session starts, or the
        // mouseDown that begins a selection before the first drag movement).
        updateCoordinateIndicator(at: localCurrentPoint ?? currentLocalMousePoint())
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
    hasVisibleSelectionRect = !localRect.isEmpty
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

  func setRetainedMenuBarPopoverCaptures(_ captures: [ImmediateMenuBarPopoverCapture]) {
    retainedMenuBarPopoverCaptures = Dictionary(
      uniqueKeysWithValues: captures.map { ($0.target.windowID, $0) }
    )
    // Hide every retained crop until the controller has performed its post-activation
    // WindowServer liveness check.
    retainedMenuBarPopoverWindowIDsStillOnScreen = Set(retainedMenuBarPopoverCaptures.keys)
    updateRetainedMenuBarPopoverLayers()
  }

  func setRetainedMenuBarPopoverWindowIDsStillOnScreen(_ windowIDs: Set<CGWindowID>) {
    retainedMenuBarPopoverWindowIDsStillOnScreen = windowIDs
    updateRetainedMenuBarPopoverLayers()
  }

  private func updateRetainedMenuBarPopoverLayers() {
    guard let rootLayer = layer, let window, let displayID = window.screen?.displayID else { return }

    let capturesForDisplay = retainedMenuBarPopoverCaptures.values.filter {
      $0.target.displayID == displayID
    }
    let captureIDs = Set(capturesForDisplay.map(\.target.windowID))
    for windowID in retainedMenuBarPopoverLayers.keys.filter({ !captureIDs.contains($0) }) {
      retainedMenuBarPopoverLayers[windowID]?.removeFromSuperlayer()
      retainedMenuBarPopoverLayers[windowID] = nil
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for capture in capturesForDisplay {
      let popoverLayer: CALayer
      if let existing = retainedMenuBarPopoverLayers[capture.target.windowID] {
        popoverLayer = existing
      } else {
        let created = CALayer()
        created.contentsGravity = .resize
        created.actions = disabledActions
        rootLayer.insertSublayer(created, above: snapshotLayer)
        retainedMenuBarPopoverLayers[capture.target.windowID] = created
        popoverLayer = created
      }
      popoverLayer.frame = convertToLocalRect(capture.target.frame).intersection(bounds)
      popoverLayer.contents = capture.image
      popoverLayer.contentsScale = capture.scaleFactor
      popoverLayer.isHidden = !WindowCaptureSelectionPolicy.shouldShowRetainedMenuBarPopover(
        isWindowStillOnScreen: retainedMenuBarPopoverWindowIDsStillOnScreen.contains(capture.target.windowID)
      )
    }
    CATransaction.commit()
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
    if let window {
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
    guard let window else { return screenRect }
    return CGRect(
      x: screenRect.origin.x - window.frame.origin.x,
      y: screenRect.origin.y - window.frame.origin.y,
      width: screenRect.width,
      height: screenRect.height
    )
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    guard !isLivePassthroughInput else { return }
    handlePrimaryMouseDown(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isLivePassthroughInput else { return }
    handlePrimaryMouseDragged(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    guard !isLivePassthroughInput else { return }
    handlePrimaryMouseUp(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseMoved(with event: NSEvent) {
    guard !isLivePassthroughInput else { return }
    handlePrimaryMouseMoved(at: convert(event.locationInWindow, from: nil))
  }

  override func rightMouseDown(with _: NSEvent) {
    guard !isLivePassthroughInput else { return }
    delegate?.overlayViewDidCancel(self)
  }

  // MARK: - Live Passthrough Input

  /// Feed a pointer event from the capture event tap (live-passthrough sessions only).
  /// `screenPoint` is in AppKit global coordinates; the shared point-based handlers keep
  /// tap-driven input on the exact same code path as the window-event fallback.
  func handleLivePassthroughMouseDown(atScreenPoint screenPoint: CGPoint) {
    guard isLivePassthroughInput, let localPoint = localPoint(fromScreenPoint: screenPoint) else { return }
    hasLivePassthroughPointerPosition = true
    handlePrimaryMouseDown(at: localPoint)
  }

  func handleLivePassthroughMouseDragged(atScreenPoint screenPoint: CGPoint) {
    guard isLivePassthroughInput, let localPoint = localPoint(fromScreenPoint: screenPoint) else { return }
    hasLivePassthroughPointerPosition = true
    handlePrimaryMouseDragged(at: localPoint)
  }

  func handleLivePassthroughMouseUp(atScreenPoint screenPoint: CGPoint) {
    guard isLivePassthroughInput, let localPoint = localPoint(fromScreenPoint: screenPoint) else { return }
    hasLivePassthroughPointerPosition = true
    handlePrimaryMouseUp(at: localPoint)
  }

  func handleLivePassthroughMouseMoved(atScreenPoint screenPoint: CGPoint) {
    guard isLivePassthroughInput, let localPoint = localPoint(fromScreenPoint: screenPoint) else { return }
    hasLivePassthroughPointerPosition = true
    handlePrimaryMouseMoved(at: localPoint)
  }

  private func localPoint(fromScreenPoint screenPoint: CGPoint) -> CGPoint? {
    guard let window else { return nil }
    return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
  }

  // MARK: - Shared Mouse Handling

  private func handlePrimaryMouseDown(at point: CGPoint) {
    currentMousePosition = point
    if let areaWindow = window as? AreaSelectionWindow {
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
    applyActiveCursor()
    switch interactionMode {
    case .manualRegion:
      if isAutoWindowDetectionActive, hoveredWindowCandidate != nil {
        // Don't commit to a manual drag yet — the gesture might turn out to be a click on the
        // hovered window instead. `handlePrimaryMouseDragged` resolves it once it clears the
        // drag threshold; `handlePrimaryMouseUp` resolves it if it never does.
        pendingWindowDetectionStartPoint = point
      } else {
        isSelecting = true
        delegate?.overlayView(self, manualSelectionBeganAt: point)
      }
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  private func handlePrimaryMouseDragged(at point: CGPoint) {
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else {
      if pendingSelectionStartPoint != nil {
        currentMousePosition = point
      }
      return
    }
    applyActiveCursor()
    switch interactionMode {
    case .manualRegion:
      if let pendingStart = pendingWindowDetectionStartPoint {
        let distance = hypot(point.x - pendingStart.x, point.y - pendingStart.y)
        guard distance >= windowDetectionDragThreshold else {
          // Still within the click/drag ambiguity window — keep tracking whatever window is
          // under the cursor so the highlight follows the (still not-yet-a-drag) pointer.
          updateWindowHover(at: point)
          updateApplicationSelectionLayers()
          return
        }
        // Crossed the threshold: this is a drag, not a click. Replay it as a manual selection
        // starting from the original mouseDown point so the drawn rect matches what the user
        // actually dragged.
        pendingWindowDetectionStartPoint = nil
        isSelecting = true
        delegate?.overlayView(self, manualSelectionBeganAt: pendingStart)
        delegate?.overlayView(self, manualSelectionChangedTo: point)
        updateMagnifier(at: point)
        return
      }
      guard isSelecting else { return }
      delegate?.overlayView(self, manualSelectionChangedTo: point)
      updateMagnifier(at: point)
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  private func handlePrimaryMouseUp(at point: CGPoint) {
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    guard selectionEnabled else {
      pendingSelectionStartPoint = nil
      return
    }

    switch interactionMode {
    case .manualRegion:
      if pendingWindowDetectionStartPoint != nil {
        // Released before crossing the drag threshold: treat it as a click on the hovered
        // window rather than an (empty, sub-threshold) manual region.
        pendingWindowDetectionStartPoint = nil
        updateWindowHover(at: point)
        if let hoveredWindowCandidate {
          delegate?.overlayView(self, didSelectWindow: hoveredWindowCandidate.target)
        }
        return
      }
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

  private func handlePrimaryMouseMoved(at point: CGPoint) {
    currentMousePosition = point
    delegate?.overlayViewDidRequestDisplayActivation(self)
    applyActiveCursor()
    updateCoordinateIndicator(at: point)
    updateCursorProxy()
    guard selectionEnabled else { return }
    switch interactionMode {
    case .manualRegion:
      if !isSelecting {
        updateMagnifier(at: point)
        if isAutoWindowDetectionActive {
          updateWindowHover(at: point)
          if hoveredWindowCandidate != nil {
            updateApplicationSelectionLayers()
          } else {
            updateCrosshairLayers()
          }
        } else {
          updateCrosshairLayers()
        }
      }
    case .applicationWindow:
      updateWindowHover(at: point)
    }
  }

  private var activeCursor: NSCursor {
    switch interactionMode {
    case .manualRegion:
      return showSelectionAreaOverlay ? NSCursor.vectorScreenshotCrosshairLight : NSCursor
        .vectorScreenshotCrosshairHighContrast
    case .applicationWindow:
      guard selectionEnabled else { return .arrow }
      return NSCursor.applicationWindowCursor
    }
  }

  /// Whether hovering in `.manualRegion` mode should preview the window under the cursor —
  /// the preference is meaningless unless this session actually has window-selection data to
  /// hit-test against (`allowsApplicationWindowSelection`, set from `applicationConfiguration`).
  private var isAutoWindowDetectionActive: Bool {
    autoDetectWindowUnderCursor && allowsApplicationWindowSelection
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
