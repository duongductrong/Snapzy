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
  private var selectionMode: SelectionMode = .screenshot
  private var activeWindow: AreaSelectionWindow?
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
      self?.refreshWindowPool()
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

      if let window = windowPool[displayID] {
        // Sync frame to current screen position before showing
        if window.frame != screen.frame {
          window.setFrame(screen.frame, display: true)
          window.overlayView.updateBounds(screen.frame)
          print("[Snapzy:AreaSelection] activatePooledWindows() — resynced stale frame for display \(displayID)")
        }
        // Reset and show existing pooled window without stealing focus
        window.overlayView.resetSelection()
        window.selectionDelegate = self
        window.orderFrontRegardless()
      } else {
        // Fallback: create window if not pooled
        let window = AreaSelectionWindow(screen: screen, pooled: false)
        window.selectionDelegate = self
        windowPool[displayID] = window
        window.orderFrontRegardless()
      }
    }
  }

  /// Deactivate all windows (hide, don't close)
  private func deactivatePooledWindows() {
    for (_, window) in windowPool {
      window.orderOut(nil)
      window.overlayView.resetSelection()
    }
    activeWindow = nil
  }

  // MARK: - Public API

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
    // Always clean up prior session's monitors to prevent orphaned leaks
    removeEscapeMonitors()
    print("[Snapzy:AreaSelection] startSelection(mode: \(mode)) — monitors cleaned, starting")

    self.selectionMode = mode
    self.completionWithMode = completion

    // Ensure pool is ready (lazy initialization if not called at app launch)
    if !isPoolReady {
      prepareWindowPool()
    }

    // Activate pooled windows (instant show)
    activatePooledWindows()

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
    print("[Snapzy:AreaSelection] cancelSelection() called")
    removeEscapeMonitors()
    deactivatePooledWindows()
    completion?(nil)
    completion = nil
    completionWithMode?(nil, selectionMode)
    completionWithMode = nil
  }

  /// Complete selection with the given rect
  func completeSelection(rect: CGRect, from window: AreaSelectionWindow) {
    print("[Snapzy:AreaSelection] completeSelection(rect: \(rect))")
    removeEscapeMonitors()
    deactivatePooledWindows()
    completion?(rect)
    completion = nil
    completionWithMode?(rect, selectionMode)
    completionWithMode = nil
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

/// Full-screen overlay panel for area selection
/// Uses NSPanel with .nonactivatingPanel to prevent background windows from deactivating/blurring
/// Supports pooled mode for instant activation
final class AreaSelectionWindow: NSPanel {

  weak var selectionDelegate: AreaSelectionWindowDelegate?

  let overlayView: AreaSelectionOverlayView
  private let targetScreen: NSScreen

  /// Initialize window for a screen
  /// - Parameters:
  ///   - screen: The screen this window covers
  ///   - pooled: If true, window starts hidden for pool pre-allocation
  init(screen: NSScreen, pooled: Bool = false) {
    self.targetScreen = screen
    self.overlayView = AreaSelectionOverlayView(frame: screen.frame)

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

    // Set up content view
    self.contentView = overlayView
    overlayView.delegate = self

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

  // Non-activating: prevent stealing focus from other apps
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
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
  }
}

// MARK: - AreaSelectionOverlayViewDelegate Protocol

protocol AreaSelectionOverlayViewDelegate: AnyObject {
  func overlayView(_ view: AreaSelectionOverlayView, didSelectRect rect: CGRect)
  func overlayViewDidCancel(_ view: AreaSelectionOverlayView)
}

// MARK: - AreaSelectionOverlayView

/// The view that handles drawing and mouse interaction
/// Uses CALayer-based rendering for 60fps crosshair movement (Phase 2 optimization)
final class AreaSelectionOverlayView: NSView {

  weak var delegate: AreaSelectionOverlayViewDelegate?

  // MARK: - Selection State

  private var isSelecting = false
  private var selectionStartPoint: CGPoint?
  private var selectionEndPoint: CGPoint?
  private var currentMousePosition: CGPoint = .zero

  // MARK: - CALayer-based Rendering (Phase 2 Optimization)

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

  /// Disabled animations for instant layer updates
  private var disabledActions: [String: CAAction] {
    return [
      "position": NSNull(),
      "bounds": NSNull(),
      "path": NSNull(),
      "hidden": NSNull(),
      "opacity": NSNull(),
      "backgroundColor": NSNull(),
      "frame": NSNull()
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
    NSCursor.crosshair.push()
  }

  override func mouseEntered(with event: NSEvent) {
    NSCursor.crosshair.push()
  }

  override func mouseExited(with event: NSEvent) {
    NSCursor.pop()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    setupTrackingArea()
  }

  // MARK: - Public Methods

  /// Reset selection state for window pool reuse
  func resetSelection() {
    isSelecting = false
    selectionStartPoint = nil
    selectionEndPoint = nil

    // Initialize crosshair at current mouse position immediately
    initializeCrosshairAtCurrentMousePosition()

    // Rebuild tracking areas for current bounds (prevents stale hit-testing)
    updateTrackingAreas()

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Keep crosshair layers hidden (using indicator instead)
    horizontalCrosshairLayer.isHidden = true
    verticalCrosshairLayer.isHidden = true
    selectionBorderLayer.isHidden = true
    crosshairIndicatorLayer.isHidden = false
    dimLayer.mask = nil
    dimLayer.frame = bounds

    CATransaction.commit()

    // Update crosshair position immediately
    updateCrosshairLayers()

    needsDisplay = true
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
    dimLayer.frame = bounds
    CATransaction.commit()

    // Rebuild tracking areas for new bounds
    updateTrackingAreas()
  }

  // MARK: - First Mouse

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  // MARK: - Layout

  override func layout() {
    super.layout()

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dimLayer.frame = bounds
    CATransaction.commit()
  }

  // MARK: - Drawing (Only for size indicator text)

  override func draw(_ dirtyRect: NSRect) {
    // Only draw size indicator - layers handle dim, crosshair, selection
    if isSelecting, let rect = calculateSelectionRect() {
      drawSizeIndicator(for: rect)
    }
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

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    selectionStartPoint = point
    selectionEndPoint = point
    isSelecting = true
    updateSelectionLayers()
  }

  override func mouseDragged(with event: NSEvent) {
    guard isSelecting else { return }
    selectionEndPoint = convert(event.locationInWindow, from: nil)
    updateSelectionLayers()
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
      resetSelection()
    }
  }

  override func mouseMoved(with event: NSEvent) {
    currentMousePosition = convert(event.locationInWindow, from: nil)
    if !isSelecting {
      updateCrosshairLayers()
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    delegate?.overlayViewDidCancel(self)
  }
}
