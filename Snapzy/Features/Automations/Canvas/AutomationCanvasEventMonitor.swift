//
//  AutomationCanvasEventMonitor.swift
//  Snapzy
//
//  SwiftUI on macOS 13 has no scroll-wheel or trackpad-pinch callbacks, so the
//  canvas watches those events with a local monitor scoped to its own frame.
//  Keys (⌫, Tab, ⌘D) are only taken when no text field is being edited.
//

import AppKit
import SwiftUI

struct AutomationCanvasEventMonitor: NSViewRepresentable {
  /// Trackpad two-finger scroll: pan by the delta (points).
  var onPan: (CGSize) -> Void
  /// Pinch, ⌘-scroll or a mouse wheel: zoom by the factor around the point.
  var onZoom: (CGFloat, CGPoint) -> Void
  /// A key the canvas may handle. Return true when handled.
  var onKey: (NSEvent) -> Bool

  func makeNSView(context: Context) -> MonitorView {
    let view = MonitorView()
    view.handlers = self
    return view
  }

  func updateNSView(_ nsView: MonitorView, context: Context) {
    nsView.handlers = self
  }

  static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
    nsView.stopMonitoring()
  }

  final class MonitorView: NSView {
    var handlers: AutomationCanvasEventMonitor?
    private var monitor: Any?

    override var isFlipped: Bool { true }

    // Never takes clicks: the SwiftUI canvas above handles them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown]) { [weak self] event in
        guard let self else { return event }
        return self.handle(event) ? nil : event
      }
    }

    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
      guard let window, event.window === window, let handlers else { return false }
      switch event.type {
      case .keyDown:
        // Typing in the name field or the inspector keeps its keys.
        // So do focused controls and lists (an Ask step's choices, a picker).
        let responder = window.firstResponder
        if responder is NSText || responder is NSControl || responder is NSTableView { return false }
        if window.attachedSheet != nil { return false }
        return handlers.onKey(event)
      case .scrollWheel:
        let location = convert(event.locationInWindow, from: nil)
        // Only scrolls over the canvas itself; the inspector beside it scrolls on its own.
        guard bounds.contains(location) else { return false }
        if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
          // Mouse wheel and ⌘-scroll zoom; precise deltas are points, wheel deltas are lines.
          let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
          guard delta != 0 else { return true }
          handlers.onZoom(exp(delta), location)
        } else {
          handlers.onPan(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        }
        return true
      case .magnify:
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return false }
        handlers.onZoom(1 + event.magnification, location)
        return true
      default:
        return false
      }
    }
  }
}
