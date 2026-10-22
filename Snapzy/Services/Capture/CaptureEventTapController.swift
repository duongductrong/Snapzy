//
//  CaptureEventTapController.swift
//  Snapzy
//
//  Global CGEventTap that drives the live-capture overlay. The tap consumes
//  every event in its mask, freezing interaction with the content beneath:
//  hover UI (tooltips, hover cards) visible when capture activates is never
//  dismissed by mouse-moved/exited events, so it persists and can be captured.
//  See plans/260723-2112-live-capture-passthrough (Phase 01; semantics
//  corrected after user validation against CleanShot X, 260723).
//

import AppKit
import Foundation

/// Mouse button/drag activity observed by the capture event tap.
enum CaptureButtonEvent: Equatable, Sendable {
  case leftMouseDown
  case leftMouseUp
  case leftMouseDragged
  case rightMouseDown
  case rightMouseUp
  case rightMouseDragged

  init?(eventType: CGEventType) {
    switch eventType {
    case .leftMouseDown: self = .leftMouseDown
    case .leftMouseUp: self = .leftMouseUp
    case .leftMouseDragged: self = .leftMouseDragged
    case .rightMouseDown: self = .rightMouseDown
    case .rightMouseUp: self = .rightMouseUp
    case .rightMouseDragged: self = .rightMouseDragged
    default: return nil
    }
  }
}

protocol CaptureEventTapDelegate: AnyObject {
  /// Observation before consume — the event drives crosshair/magnifier/coordinate
  /// updates, then the tap consumes it so the app beneath never reacts to (or
  /// dismisses its hover UI because of) the pointer moving.
  func eventTapDidObserveMouseMoved(at screenPoint: CGPoint)
  /// Consumed events — underlying apps never see these.
  func eventTapDidReceiveButton(_ kind: CaptureButtonEvent, at screenPoint: CGPoint)
  /// Key down/up. Returns `true` to consume the event, `false` to pass it through
  /// to the app beneath.
  func eventTapShouldConsumeKeyEvent(_ event: CGEvent) -> Bool
  /// Observation before consume — the wheel drives the magnifier zoom, then the
  /// tap consumes the event so the content beneath does not shift mid-selection.
  func eventTapDidReceiveScroll(deltaY: CGFloat, hasPreciseScrollingDeltas: Bool, isCommandDown: Bool)
}

/// System-touching seams behind injectable closures so the controller's state
/// machine can be unit-tested without a real event tap.
struct CaptureEventTapDependencies {
  /// Opaque handle for a created event tap (a retained `CFMachPort` in production).
  typealias TapHandle = AnyObject

  var isAccessibilityTrusted: () -> Bool
  var createTap: (_ callback: CGEventTapCallBack, _ userInfo: UnsafeMutableRawPointer?) -> TapHandle?
  var createRunLoopSource: (_ tap: TapHandle) -> CFRunLoopSource?
  var setTapEnabled: (_ tap: TapHandle, _ enabled: Bool) -> Void
  /// Unregisters the tap from the window server. Disabling a tap and dropping
  /// its run-loop source does not remove it: the `CFMachPort` and its source
  /// retain each other until the port is invalidated, so every session would
  /// otherwise leave a disabled tap registered for the life of the process.
  var invalidateTap: (_ tap: TapHandle) -> Void
}

extension CaptureEventTapDependencies {
  static func live(eventMask: CGEventMask) -> CaptureEventTapDependencies {
    CaptureEventTapDependencies(
      isAccessibilityTrusted: { AXIsProcessTrusted() },
      createTap: { callback, userInfo in
        CGEvent.tapCreate(
          tap: .cgSessionEventTap,
          place: .headInsertEventTap,
          options: .defaultTap,
          eventsOfInterest: eventMask,
          callback: callback,
          userInfo: userInfo
        )
      },
      createRunLoopSource: { tap in
        CFMachPortCreateRunLoopSource(nil, unsafeDowncast(tap, to: CFMachPort.self), 0)
      },
      setTapEnabled: { tap, enabled in
        CGEvent.tapEnable(tap: unsafeDowncast(tap, to: CFMachPort.self), enable: enabled)
      },
      invalidateTap: { tap in
        CFMachPortInvalidate(unsafeDowncast(tap, to: CFMachPort.self))
      }
    )
  }
}

/// Owns the session event tap for a live capture session.
///
/// Threading: all public methods must be called from the main thread. The tap's
/// run-loop source is installed on the main run loop, so the tap callback (and
/// therefore every delegate call) already fires on the main queue — no
/// per-event dispatch is needed and the callback stays allocation-free (release
/// builds; DEBUG signpost instrumentation boxes an interval token per event).
final class CaptureEventTapController {
  /// Scroll-wheel events are consumed while the capture overlay is active so
  /// the content beneath does not shift mid-selection (decision recorded in
  /// plan.md). Flip to `false` to let scroll pass through to apps beneath.
  static let consumesScrollWheelEvents = true

  /// Events the tap observes: pure hover motion plus everything the capture
  /// state machine needs to drive selection, cancellation, and confirmation.
  static let eventMask: CGEventMask = {
    var mask: CGEventMask = 0
    let eventTypes: [CGEventType] = [
      .mouseMoved,
      .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .keyDown, .keyUp,
      .scrollWheel,
    ]
    for eventType in eventTypes {
      mask |= CGEventMask(1) << CGEventMask(eventType.rawValue)
    }
    return mask
  }()

  weak var delegate: CaptureEventTapDelegate?

  private let dependencies: CaptureEventTapDependencies
  private var tap: CaptureEventTapDependencies.TapHandle?
  private var runLoopSource: CFRunLoopSource?

  private(set) var isRunning = false

  /// `true` when the process holds Accessibility trust and a session tap can
  /// be created at all. When `false`, callers should fall back to the legacy
  /// panel-input capture mode.
  var isAvailable: Bool {
    dependencies.isAccessibilityTrusted()
  }

  init(dependencies: CaptureEventTapDependencies = .live(eventMask: CaptureEventTapController.eventMask)) {
    self.dependencies = dependencies
  }

  deinit {
    stop()
  }

  // MARK: - Permission

  /// Prompt the user for Accessibility permission if not already granted.
  /// Returns `true` if permission is already granted at call time.
  ///
  /// Deliberately checks real TCC trust (not the injected checker) so the
  /// system prompt reflects reality — mirrors `SmartElementQueryService`.
  @discardableResult
  func ensureAccessibilityPermission() -> Bool {
    if AXIsProcessTrusted() { return true }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    DiagnosticLogger.shared.log(
      .warning,
      .capture,
      "Capture event tap: accessibility prompt shown"
    )
    return false
  }

  // MARK: - Lifecycle

  /// Create and install the event tap. Safe to call repeatedly — a running
  /// tap is left untouched. Returns `false` when Accessibility permission is
  /// missing or tap creation failed (caller should use the legacy path).
  @discardableResult
  func start() -> Bool {
    guard !isRunning else { return true }
    guard isAvailable else {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Capture event tap unavailable: accessibility permission not granted"
      )
      return false
    }

    let userInfo = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = dependencies.createTap(Self.tapCallback, userInfo) else {
      DiagnosticLogger.shared.log(
        .error,
        .capture,
        "Failed to create capture event tap"
      )
      return false
    }
    guard let runLoopSource = dependencies.createRunLoopSource(tap) else {
      dependencies.invalidateTap(tap)
      DiagnosticLogger.shared.log(
        .error,
        .capture,
        "Failed to create run-loop source for capture event tap"
      )
      return false
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    dependencies.setTapEnabled(tap, true)

    self.tap = tap
    self.runLoopSource = runLoopSource
    isRunning = true
    return true
  }

  /// Disable and tear down the event tap, restoring normal event delivery.
  /// Safe to call repeatedly and from any exit path (commit, cancel, Esc).
  func stop() {
    guard isRunning else { return }
    if let tap {
      dependencies.setTapEnabled(tap, false)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFRunLoopSourceInvalidate(runLoopSource)
    }
    if let tap {
      dependencies.invalidateTap(tap)
    }
    tap = nil
    runLoopSource = nil
    isRunning = false
  }

  // MARK: - Tap Callback

  /// C-convention trampoline; must not capture context. The controller is
  /// passed unretained — the tap is always torn down before the controller
  /// is deallocated (`stop()` from `deinit`).
  private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<CaptureEventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleTapEvent(type: type, event: event)
  }

  /// Tap callback body. Runs on the main run loop; must stay allocation-free
  /// and O(1) — heavy work belongs in the delegate, batched per display frame.
  /// Returns the event to pass it through, or `nil` to consume it.
  /// Internal so tests can exercise routing without a real tap.
  func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let signpost = PerfSignpost.CapturePassthrough.beginInterval("tapEvent")
    defer { PerfSignpost.CapturePassthrough.endInterval(signpost) }
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // The system disabled the tap (timeout or user input); re-enable it so
      // the capture session keeps receiving events.
      PerfSignpost.CapturePassthrough.event("tapDisabled")
      if let tap {
        dependencies.setTapEnabled(tap, true)
      }
      return Unmanaged.passUnretained(event)

    case .mouseMoved:
      // Observe-then-consume: the delegate drives crosshair/magnifier/coordinate
      // updates from the move, but the event never reaches the app beneath —
      // freezing interaction keeps already-visible hover UI (tooltips, hover
      // cards) alive so it can be captured, instead of letting the move
      // trigger mouse-exited dismissal (matches CleanShot X behavior).
      delegate?.eventTapDidObserveMouseMoved(at: event.location)
      return nil

    case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
         .rightMouseDown, .rightMouseUp, .rightMouseDragged:
      if let kind = CaptureButtonEvent(eventType: type) {
        delegate?.eventTapDidReceiveButton(kind, at: event.location)
      }
      return nil

    case .keyDown, .keyUp:
      // The overlay never takes key status in a passthrough session (keying it
      // deactivates the window beneath, which dismisses Qt tooltips — #635), so
      // keystrokes reach the session only through here. The delegate decides
      // which ones the app beneath must not see.
      guard delegate?.eventTapShouldConsumeKeyEvent(event) == true else {
        return Unmanaged.passUnretained(event)
      }
      return nil

    case .scrollWheel:
      guard Self.consumesScrollWheelEvents else {
        return Unmanaged.passUnretained(event)
      }
      // Observe-then-consume (same contract as mouseMoved): the delegate drives
      // the magnifier zoom from the wheel, but the event never reaches the app
      // beneath — its content must not shift mid-selection.
      delegate?.eventTapDidReceiveScroll(
        deltaY: Self.scrollDeltaY(from: event),
        hasPreciseScrollingDeltas: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
        isCommandDown: event.flags.contains(.maskCommand)
      )
      return nil

    default:
      return Unmanaged.passUnretained(event)
    }
  }

  /// Wheel delta in the same units the legacy `NSEvent` path reports: precise
  /// (continuous) devices yield point deltas like `NSEvent.scrollingDeltaY`,
  /// otherwise whole-wheel notches like `NSEvent.deltaY` — so the magnifier's
  /// zoom step matches the window-event path on both device kinds.
  private static func scrollDeltaY(from event: CGEvent) -> CGFloat {
    if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
      return CGFloat(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
    }
    return CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
  }
}
