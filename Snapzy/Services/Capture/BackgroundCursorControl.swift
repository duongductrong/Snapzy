//
//  BackgroundCursorControl.swift
//  Snapzy
//
//  Grants this background, never-activating process permission to control the
//  system cursor's visibility. `CGDisplayHideCursor` only takes effect for the
//  FOREGROUND application (Apple: "your application must be in the foreground"),
//  but the live-capture passthrough overlay needs to hide the system arrow while
//  Snapzy stays a background `LSUIElement` that never activates (activating would
//  dismiss the hover UI the feature exists to preserve). Setting the private
//  CoreGraphics Services connection property `SetsCursorInBackground` on this
//  process's main WindowServer connection lifts that restriction, so the existing
//  per-display `CGDisplayHideCursor`/`CGDisplayShowCursor` balance
//  (`LivePassthroughCursorHider`) actually applies and only the drawn crosshair
//  proxy remains — matching the legacy window-event path's appearance.
//
//  The private symbols are resolved lazily via `dlsym` (never linked directly), so
//  a future OS that dropped them degrades to the old foreground-only behavior
//  instead of failing to launch. Safe for the sandboxed, notarized, non-App-Store
//  build: it sets a property on the connection this process already owns — no new
//  entitlement, mach-lookup, or hardened-runtime exception. See
//  plans/260723-2112-live-capture-passthrough and `LivePassthroughCursorHider`.
//
//  Residual limitation: while the pointer is over the Dock the WindowServer keeps
//  the Dock in cursor control, which blocks `SetsCursorInBackground` — the arrow
//  can momentarily reappear there. Everywhere else only the crosshair shows.
//

import Foundation

/// Enables background cursor-visibility control for this process by setting the
/// private CGS `SetsCursorInBackground` connection property. The attempt is made
/// at most once per instance (`enableOnce`); the system-touching call sits behind
/// an injected `setEnabled` closure so the once-only logic is unit-testable while
/// `liveSetEnabled` (the real `dlsym` seam) stays untested — mirroring
/// `CaptureEventTapDependencies.live`.
final class BackgroundCursorControl {
  private let setEnabled: () -> Bool
  private var configured = false
  private var lastResult = false

  init(setEnabled: @escaping () -> Bool = BackgroundCursorControl.liveSetEnabled) {
    self.setEnabled = setEnabled
  }

  /// Attempt to grant background cursor control, at most once per instance.
  /// Returns whether the property is (now, or was already) set. Idempotent: a
  /// failed first attempt is not retried — the caller keeps the foreground-only
  /// baseline for the rest of the run.
  @discardableResult
  func enableOnce() -> Bool {
    guard !configured else { return lastResult }
    configured = true
    lastResult = setEnabled()
    return lastResult
  }

  // MARK: - Live seam

  private typealias CGSMainConnectionIDFn = @convention(c) () -> Int32
  // CGSSetConnectionProperty(cid, targetCID, key, value) -> CGError (0 == success).
  private typealias CGSSetConnectionPropertyFn =
    @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

  /// Real implementation: resolve `CGSMainConnectionID` + `CGSSetConnectionProperty`
  /// from the already-loaded CoreGraphics/SkyLight symbols and set the property to
  /// true on this process's main connection (which acts as both `cid` and target).
  /// Returns `false` (and logs) if the symbols are unavailable or the call reports
  /// an error, so the caller falls back cleanly to foreground-only behavior.
  nonisolated static func liveSetEnabled() -> Bool {
    // `dlopen(nil, …)` returns the global symbol table (main program plus every
    // loaded library, including CoreGraphics via AppKit); it is a pseudo-handle
    // that must not be `dlclose`'d.
    guard
      let handle = dlopen(nil, RTLD_LAZY),
      let mainConnectionSym = dlsym(handle, "CGSMainConnectionID"),
      let setPropertySym = dlsym(handle, "CGSSetConnectionProperty")
    else {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "BackgroundCursorControl: CGS symbols unavailable; cursor hide stays foreground-only"
      )
      return false
    }

    let mainConnectionID = unsafeBitCast(mainConnectionSym, to: CGSMainConnectionIDFn.self)
    let setConnectionProperty = unsafeBitCast(setPropertySym, to: CGSSetConnectionPropertyFn.self)

    let connectionID = mainConnectionID()
    let key = "SetsCursorInBackground" as CFString
    let status = setConnectionProperty(connectionID, connectionID, key, kCFBooleanTrue!)

    guard status == 0 else {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "BackgroundCursorControl: CGSSetConnectionProperty failed",
        context: ["status": "\(status)"]
      )
      return false
    }

    DiagnosticLogger.shared.log(.info, .capture, "BackgroundCursorControl enabled")
    return true
  }
}
