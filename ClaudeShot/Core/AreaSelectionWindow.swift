//
//  AreaSelectionWindow.swift
//  ClaudeShot
//
//  Overlay window for area selection with mouse
//

import AppKit
import Foundation

/// Callback type for when area selection is completed
typealias AreaSelectionCompletion = (CGRect?) -> Void

/// Mode for area selection
enum SelectionMode {
  case screenshot
  case recording
}

/// Callback type with mode
typealias AreaSelectionCompletionWithMode = (CGRect?, SelectionMode) -> Void

/// Controller for managing area selection overlay across all screens
@MainActor
final class AreaSelectionController: NSObject {

  private var overlayWindows: [AreaSelectionWindow] = []
  private var completion: AreaSelectionCompletion?
  private var completionWithMode: AreaSelectionCompletionWithMode?
  private var selectionMode: SelectionMode = .screenshot
  private var activeWindow: AreaSelectionWindow?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?

  /// Start area selection mode (legacy - for screenshots)
  /// - Parameter completion: Called with the selected rect, or nil if cancelled
  func startSelection(completion: @escaping AreaSelectionCompletion) {
    startSelection(mode: .screenshot) { rect, _ in
      completion(rect)
    }
  }

  /// Start area selection with mode
  /// - Parameters:
  ///   - mode: The selection mode (screenshot or recording)
  ///   - completion: Called with the selected rect and mode, or nil if cancelled
  func startSelection(mode: SelectionMode, completion: @escaping AreaSelectionCompletionWithMode) {
    self.selectionMode = mode
    self.completionWithMode = completion

    // Create overlay window for each screen
    for screen in NSScreen.screens {
      let window = AreaSelectionWindow(screen: screen)
      window.selectionDelegate = self
      overlayWindows.append(window)
      window.orderFrontRegardless()
    }

    // Set up escape key monitoring (local for when app is active)
    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {  // Escape key
        self?.cancelSelection()
        return nil
      }
      return event
    }

    // Global monitor for when app may not be fully active
    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {  // Escape key
        DispatchQueue.main.async {
          self?.cancelSelection()
        }
      }
    }
  }

  /// Cancel the current selection
  func cancelSelection() {
    closeAllWindows()
    completion?(nil)
    completion = nil
    completionWithMode?(nil, selectionMode)
    completionWithMode = nil
  }

  /// Complete selection with the given rect
  func completeSelection(rect: CGRect, from window: AreaSelectionWindow) {
    closeAllWindows()
    completion?(rect)
    completion = nil
    completionWithMode?(rect, selectionMode)
    completionWithMode = nil
  }

  private func closeAllWindows() {
    // Remove escape key monitors
    if let monitor = localEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      localEscapeMonitor = nil
    }
    if let monitor = globalEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      globalEscapeMonitor = nil
    }

    for window in overlayWindows {
      window.close()
    }
    overlayWindows.removeAll()
    activeWindow = nil
  }
}

// MARK: - AreaSelectionWindowDelegate

extension AreaSelectionController: AreaSelectionWindowDelegate {
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectRect rect: CGRect) {
    completeSelection(rect: rect, from: window)
  }

  func areaSelectionWindowDidCancel(_ window: AreaSelectionWindow) {
    cancelSelection()
  }

  func areaSelectionWindowDidBecomeActive(_ window: AreaSelectionWindow) {
    activeWindow = window
  }
}

// MARK: - AreaSelectionWindowDelegate Protocol

protocol AreaSelectionWindowDelegate: AnyObject {
  func areaSelectionWindow(_ window: AreaSelectionWindow, didSelectRect rect: CGRect)
  func areaSelectionWindowDidCancel(_ window: AreaSelectionWindow)
  func areaSelectionWindowDidBecomeActive(_ window: AreaSelectionWindow)
}

// MARK: - AreaSelectionWindow

/// Full-screen overlay window for area selection
final class AreaSelectionWindow: NSWindow {

  weak var selectionDelegate: AreaSelectionWindowDelegate?

  private let overlayView: AreaSelectionOverlayView
  private let targetScreen: NSScreen

  init(screen: NSScreen) {
    self.targetScreen = screen
    self.overlayView = AreaSelectionOverlayView(frame: screen.frame)

    super.init(
      contentRect: screen.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    // Configure window
    self.isOpaque = false
    self.backgroundColor = .clear
    self.level = .screenSaver  // Higher level to ensure immediate focus
    self.ignoresMouseEvents = false
    self.acceptsMouseMovedEvents = true
    self.isReleasedWhenClosed = false
    self.hasShadow = false
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    // Set up content view
    self.contentView = overlayView
    overlayView.delegate = self

    // Force window to be key and main immediately
    self.makeKeyAndOrderFront(nil)
    self.makeMain()

    // Ensure first responder is set to overlay view for immediate mouse handling
    self.makeFirstResponder(overlayView)
  }

  // Required initializers
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

// MARK: - AreaSelectionOverlayViewDelegate

extension AreaSelectionWindow: AreaSelectionOverlayViewDelegate {
  func overlayView(_ view: AreaSelectionOverlayView, didSelectRect rect: CGRect) {
    // Convert from view coordinates to screen coordinates
    let screenRect = convertToScreenCoordinates(rect)
    selectionDelegate?.areaSelectionWindow(self, didSelectRect: screenRect)
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
    // No Y-flip needed - ScreenCaptureKit uses bottom-left origin like macOS
  }
}

// MARK: - AreaSelectionOverlayViewDelegate Protocol

protocol AreaSelectionOverlayViewDelegate: AnyObject {
  func overlayView(_ view: AreaSelectionOverlayView, didSelectRect rect: CGRect)
  func overlayViewDidCancel(_ view: AreaSelectionOverlayView)
}

// MARK: - AreaSelectionOverlayView

/// The actual view that handles drawing and mouse interaction
final class AreaSelectionOverlayView: NSView {

  weak var delegate: AreaSelectionOverlayViewDelegate?

  // Selection state - initialize with nil to detect first interaction
  private var isSelecting = false
  private var selectionStartPoint: CGPoint?
  private var selectionEndPoint: CGPoint?
  private var currentMousePosition: CGPoint = .zero

  // Appearance
  private let dimColor = NSColor.black.withAlphaComponent(0.4)
  private let selectionBorderColor = NSColor.white
  private let selectionBorderWidth: CGFloat = 2.0
  private let crosshairColor = NSColor.white.withAlphaComponent(0.6)

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupTrackingArea()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupTrackingArea()
  }

  private func setupTrackingArea() {
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseMoved, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    setupTrackingArea()
  }

  // Accept first mouse click without requiring window activation
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw dim overlay
    dimColor.setFill()
    bounds.fill()

    if isSelecting {
      drawSelection()
    } else {
      drawCrosshair()
    }
  }

  private func drawSelection() {
    guard let selectionRect = calculateSelectionRect() else { return }

    // Clear the selection area (make it bright/visible)
    NSColor.clear.setFill()
    selectionRect.fill(using: .copy)

    // Draw selection border
    let borderPath = NSBezierPath(rect: selectionRect)
    borderPath.lineWidth = selectionBorderWidth
    selectionBorderColor.setStroke()
    borderPath.stroke()

    // Draw size indicator
    drawSizeIndicator(for: selectionRect)
  }

  private func drawSizeIndicator(for rect: CGRect) {
    let sizeText = "\(Int(rect.width)) x \(Int(rect.height))"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white,
      .backgroundColor: NSColor.black.withAlphaComponent(0.7),
    ]

    let textSize = sizeText.size(withAttributes: attributes)
    var textRect = CGRect(
      x: rect.maxX - textSize.width - 8,
      y: rect.minY - textSize.height - 8,
      width: textSize.width + 8,
      height: textSize.height + 4
    )

    // Ensure text stays within bounds
    if textRect.minY < 0 {
      textRect.origin.y = rect.maxY + 4
    }
    if textRect.maxX > bounds.maxX {
      textRect.origin.x = rect.minX
    }

    // Draw background
    NSColor.black.withAlphaComponent(0.7).setFill()
    let bgPath = NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4)
    bgPath.fill()

    // Draw text
    let textPoint = CGPoint(x: textRect.minX + 4, y: textRect.minY + 2)
    sizeText.draw(at: textPoint, withAttributes: attributes)
  }

  private func drawCrosshair() {
    let crosshairPath = NSBezierPath()

    // Vertical line
    crosshairPath.move(to: CGPoint(x: currentMousePosition.x, y: 0))
    crosshairPath.line(to: CGPoint(x: currentMousePosition.x, y: bounds.height))

    // Horizontal line
    crosshairPath.move(to: CGPoint(x: 0, y: currentMousePosition.y))
    crosshairPath.line(to: CGPoint(x: bounds.width, y: currentMousePosition.y))

    crosshairPath.lineWidth = 1.0
    crosshairColor.setStroke()
    crosshairPath.stroke()
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

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    selectionStartPoint = point
    selectionEndPoint = point
    isSelecting = true
    // Force immediate display update on first interaction
    display()
  }

  override func mouseDragged(with event: NSEvent) {
    guard isSelecting else { return }
    selectionEndPoint = convert(event.locationInWindow, from: nil)
    // Use display() for immediate redraw during drag
    display()
  }

  override func mouseUp(with event: NSEvent) {
    guard isSelecting else { return }
    selectionEndPoint = convert(event.locationInWindow, from: nil)
    isSelecting = false

    if let selectionRect = calculateSelectionRect(),
      selectionRect.width > 5 && selectionRect.height > 5
    {
      delegate?.overlayView(self, didSelectRect: selectionRect)
    } else {
      // Reset selection state if too small
      selectionStartPoint = nil
      selectionEndPoint = nil
      needsDisplay = true
    }
  }

  override func mouseMoved(with event: NSEvent) {
    currentMousePosition = convert(event.locationInWindow, from: nil)
    if !isSelecting {
      needsDisplay = true
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    delegate?.overlayViewDidCancel(self)
  }
}
