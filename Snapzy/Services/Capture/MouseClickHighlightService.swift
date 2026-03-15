//
//  MouseClickHighlightService.swift
//  Snapzy
//
//  Detects global mouse clicks and drag movement, forwarding events
//  to the click highlight overlay so they appear in screen recordings.
//

import AppKit
import Foundation

@MainActor
final class MouseClickHighlightService {

  private var globalDownMonitor: Any?
  private var localDownMonitor: Any?
  private var globalUpMonitor: Any?
  private var localUpMonitor: Any?
  private var globalDragMonitor: Any?
  private var localDragMonitor: Any?
  private var recordingRect: CGRect = .zero
  private var isRunning = false
  private var isMouseDown = false
  private var lastDragTime: CFTimeInterval = 0

  /// Minimum interval between drag callbacks (~120 Hz cap)
  private static let dragThrottleInterval: CFTimeInterval = 0.008

  /// Called on mouse-down with screen-space position
  var onMouseDown: ((NSPoint) -> Void)?

  /// Called on mouse-up
  var onMouseUp: (() -> Void)?

  /// Called while mouse is held and dragged, with updated screen-space position
  var onMouseDragged: ((NSPoint) -> Void)?

  func start(recordingRect: CGRect) {
    guard !isRunning else { return }
    isRunning = true
    self.recordingRect = recordingRect

    // Mouse-down monitors
    globalDownMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handleMouseDown(event)
      }
    }

    localDownMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handleMouseDown(event)
      }
      return event
    }

    // Mouse-up monitors
    globalUpMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseUp, .rightMouseUp]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleMouseUp()
      }
    }

    localUpMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseUp, .rightMouseUp]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handleMouseUp()
      }
      return event
    }

    // Mouse-dragged monitors (cursor movement while held)
    globalDragMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDragged, .rightMouseDragged]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleMouseDragged()
      }
    }

    localDragMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDragged, .rightMouseDragged]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handleMouseDragged()
      }
      return event
    }
  }

  func stop() {
    isRunning = false
    isMouseDown = false

    let monitors = [globalDownMonitor, localDownMonitor,
                    globalUpMonitor, localUpMonitor,
                    globalDragMonitor, localDragMonitor]
    for monitor in monitors {
      if let m = monitor { NSEvent.removeMonitor(m) }
    }
    globalDownMonitor = nil
    localDownMonitor = nil
    globalUpMonitor = nil
    localUpMonitor = nil
    globalDragMonitor = nil
    localDragMonitor = nil

    onMouseDown = nil
    onMouseUp = nil
    onMouseDragged = nil
  }

  func updateRecordingRect(_ rect: CGRect) {
    recordingRect = rect
  }

  private func handleMouseDown(_ event: NSEvent) {
    let location = NSEvent.mouseLocation
    guard recordingRect.contains(location) else { return }
    isMouseDown = true
    onMouseDown?(location)
  }

  private func handleMouseUp() {
    guard isMouseDown else { return }
    isMouseDown = false
    onMouseUp?()
  }

  private func handleMouseDragged() {
    guard isMouseDown else { return }

    // Throttle drag callbacks to avoid flooding the main thread
    let now = CACurrentMediaTime()
    guard now - lastDragTime >= Self.dragThrottleInterval else { return }
    lastDragTime = now

    let location = NSEvent.mouseLocation
    onMouseDragged?(location)
  }
}
