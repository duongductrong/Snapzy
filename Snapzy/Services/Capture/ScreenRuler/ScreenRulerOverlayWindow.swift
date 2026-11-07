//
//  ScreenRulerOverlayWindow.swift
//  Snapzy
//
//  Per-display Screen Ruler overlay: shows the frozen snapshot of its display, measures the
//  space around the pointer, and keeps the boxes and spans the user pinned.
//

import AppKit
import Carbon.HIToolbox
import SnapzyMeasureCore

@MainActor
protocol ScreenRulerOverlayViewDelegate: AnyObject {
  func screenRulerOverlayViewDidReceivePointer(_ view: ScreenRulerOverlayView)
  func screenRulerOverlayViewDidCancel(_ view: ScreenRulerOverlayView)
}

final class ScreenRulerOverlayWindow: NSPanel {
  let overlayView: ScreenRulerOverlayView
  let displayID: CGDirectDisplayID

  init(screen: NSScreen, snapshot: FrozenDisplaySnapshot) {
    displayID = snapshot.displayID
    let bounds = CGRect(origin: .zero, size: screen.frame.size)
    overlayView = ScreenRulerOverlayView(frame: bounds, snapshot: snapshot)

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .screenSaver
    isOpaque = true
    backgroundColor = .black
    hasShadow = false
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    animationBehavior = .none
    becomesKeyOnlyIfNeeded = false
    CaptureChromeWindowRegistry.configure(self, role: .captureOverlay)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isMovable = false
    isMovableByWindowBackground = false

    // The frozen screen sits in the container's layer; the overlay view draws on top of it,
    // so pointer moves redraw only the measurements, never the full-size snapshot.
    let container = NSView(frame: bounds)
    container.wantsLayer = true
    container.layer?.contents = snapshot.image
    container.layer?.contentsGravity = .resize
    container.layer?.magnificationFilter = .nearest
    overlayView.autoresizingMask = [.width, .height]
    container.addSubview(overlayView)
    contentView = container
    setFrame(screen.frame, display: false)
  }

  /// Non-activating: key input arrives without activating Snapzy.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class ScreenRulerOverlayView: NSView {
  /// Pointer travel (in points) before a press turns into a box drag, so click jitter
  /// still pins a span.
  private static let dragThreshold: CGFloat = 4

  weak var delegate: ScreenRulerOverlayViewDelegate?

  let snapshot: FrozenDisplaySnapshot
  /// Pixels for edge scans; nil while it is being built or after the pointer left the display.
  var raster: ScreenRulerRaster? {
    didSet { remeasure() }
  }
  var axis: ScreenRulerAxis = .both {
    didSet { remeasure() }
  }
  var unit: ScreenRulerUnit = .points {
    didSet { needsDisplay = true }
  }
  var tolerance = ScreenRulerEdgeScanner.defaultTolerance {
    didSet { remeasure() }
  }
  var hint: String? {
    didSet { needsDisplay = true }
  }
  /// Short-lived message shown in place of the hint, e.g. after a copy.
  private var feedback: String?
  private var feedbackGeneration = 0

  /// Warps the real pointer; replaced in tests.
  var warpPointer: (CGPoint) -> Void = { point in LivePassthroughCursorRestorer().restore(to: point) }
  /// Whether ⌘ is held; replaced in tests.
  var commandKeyIsDown: () -> Bool = { NSEvent.modifierFlags.contains(.command) }

  private(set) var pins: [ScreenRulerMeasurement] = []
  private(set) var live: ScreenRulerMeasurement?
  private(set) var pointerPixel: ColorPickerPixel?
  private(set) var dragBox: ScreenRulerPixelRect?
  private var pressPixel: ColorPickerPixel?

  var pixelWidth: Int { snapshot.image.width }
  var pixelHeight: Int { snapshot.image.height }
  /// Snapshot pixels per point on each axis, matching how the backdrop is stretched.
  var scaleX: CGFloat { bounds.width > 0 ? CGFloat(pixelWidth) / bounds.width : snapshot.pixelScaleFactor }
  var scaleY: CGFloat { bounds.height > 0 ? CGFloat(pixelHeight) / bounds.height : snapshot.pixelScaleFactor }

  init(frame frameRect: NSRect, snapshot: FrozenDisplaySnapshot) {
    self.snapshot = snapshot
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.isOpaque = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
    )
  }

  // MARK: - Events

  override func mouseEntered(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    pointerLeft()
  }

  override func mouseDown(with event: NSEvent) {
    press(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    drag(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    release()
  }

  override func rightMouseDown(with event: NSEvent) {
    delegate?.screenRulerOverlayViewDidCancel(self)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      delegate?.screenRulerOverlayViewDidCancel(self)
      return
    }
    super.keyDown(with: event)
  }

  // MARK: - Interaction

  func pointerMoved(to point: CGPoint) {
    delegate?.screenRulerOverlayViewDidReceivePointer(self)
    pointerPixel = pixel(at: point)
    remeasure()
  }

  func pointerLeft() {
    pointerPixel = nil
    live = nil
    needsDisplay = true
  }

  func press(at point: CGPoint) {
    // After an arrow-key nudge the press measures from the nudged pixel.
    if pointerPixel == nil {
      pointerMoved(to: point)
    }
    pressPixel = pointerPixel
    dragBox = nil
  }

  func drag(to point: CGPoint) {
    pointerMoved(to: point)
    guard let pressPixel, let pointerPixel else { return }
    let travel = max(
      CGFloat(abs(pointerPixel.x - pressPixel.x)) / scaleX,
      CGFloat(abs(pointerPixel.y - pressPixel.y)) / scaleY
    )
    if dragBox != nil || travel >= Self.dragThreshold {
      dragBox = ScreenRulerPixelRect(corner: pressPixel, pointerPixel)
      needsDisplay = true
    }
  }

  /// A drag pins the box, snapped to its content unless ⌘ is held; a click pins what the
  /// pointer measures.
  func release() {
    defer {
      pressPixel = nil
      dragBox = nil
      needsDisplay = true
    }
    if let dragBox {
      if let raster, !commandKeyIsDown() {
        pinSnapped(dragBox, raster: raster)
      } else {
        pins.append(.box(dragBox))
      }
    } else if let live {
      pins.append(live)
    }
  }

  /// Boxes this large (in snapshot pixels) snap off the main thread: an empty full-screen box
  /// on a 5K display takes up to ~1 s to scan. The raw box shows until the snap lands.
  static let backgroundSnapArea = 1_000_000

  private func pinSnapped(_ box: ScreenRulerPixelRect, raster: ScreenRulerRaster) {
    let tolerance = tolerance
    guard box.width * box.height > Self.backgroundSnapArea else {
      pins.append(.box(ScreenRulerEdgeScanner.snap(box, in: raster, tolerance: tolerance)))
      return
    }
    let placeholder = ScreenRulerMeasurement.box(box)
    pins.append(placeholder)
    Task { @MainActor [weak self] in
      let snapped = await Task.detached(priority: .userInitiated) {
        ScreenRulerEdgeScanner.snap(box, in: raster, tolerance: tolerance)
      }.value
      // Replace the placeholder unless it was removed in the meantime.
      guard let self, let index = self.pins.lastIndex(of: placeholder) else { return }
      self.pins[index] = .box(snapped)
      self.needsDisplay = true
    }
  }

  func removeLastPin() {
    guard !pins.isEmpty else { return }
    pins.removeLast()
    needsDisplay = true
  }

  /// Shows `message` where the hint is for a moment. Toasts would sit under the overlay.
  func showFeedback(_ message: String, duration: TimeInterval = 1.5) {
    feedbackGeneration += 1
    let generation = feedbackGeneration
    feedback = message
    needsDisplay = true
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
      guard let self, self.feedbackGeneration == generation else { return }
      self.feedback = nil
      self.needsDisplay = true
    }
  }

  /// The live measurement, else the most recent pin.
  var currentMeasurement: ScreenRulerMeasurement? {
    live ?? pins.last
  }

  /// Moves the measured pixel by whole snapshot pixels and keeps the real pointer on it.
  func nudge(dx: Int, dy: Int) {
    let start = pointerPixel ?? pixel(at: currentPointerLocation())
    let target = ColorPickerPixelSampler.clamp(
      ColorPickerPixel(x: start.x + dx, y: start.y + dy),
      imageWidth: pixelWidth,
      imageHeight: pixelHeight
    )
    pointerPixel = target
    remeasure()
    let center = ColorPickerPixelSampler.point(
      forCenterOf: target,
      bounds: bounds,
      imageWidth: pixelWidth,
      imageHeight: pixelHeight
    )
    if let window {
      let screenPoint = window.convertPoint(toScreen: convert(center, to: nil))
      // Quartz global coordinates are top-left based on the primary display.
      let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
      warpPointer(CGPoint(x: screenPoint.x, y: primaryMaxY - screenPoint.y))
    }
  }

  /// `screenPoint` is in AppKit global coordinates.
  func trackPointer(atScreenPoint screenPoint: CGPoint) {
    guard let window else { return }
    pointerMoved(to: convert(window.convertPoint(fromScreen: screenPoint), from: nil))
  }

  // MARK: - Drawing

  func drawing(forExport: Bool) -> ScreenRulerDrawing {
    var drawing = ScreenRulerDrawing(size: bounds.size, scaleX: scaleX, scaleY: scaleY, unit: unit)
    drawing.pins = pins
    if forExport {
      // A file with no pins keeps what the pointer was measuring.
      drawing.live = pins.isEmpty ? live : nil
    } else {
      drawing.live = live
      drawing.dragBox = dragBox
      drawing.pointer = pointerPixel
      drawing.hint = feedback ?? hint
    }
    return drawing
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    context.translateBy(x: 0, y: bounds.height)
    context.scaleBy(x: 1, y: -1)
    ScreenRulerRenderer.draw(drawing(forExport: false), in: context)
    context.restoreGState()
  }

  private func remeasure() {
    if let raster, let pointerPixel {
      live = .span(ScreenRulerEdgeScanner.span(in: raster, from: pointerPixel, axis: axis, tolerance: tolerance))
    } else {
      live = nil
    }
    needsDisplay = true
  }

  private func pixel(at point: CGPoint) -> ColorPickerPixel {
    ColorPickerPixelSampler.pixel(at: point, bounds: bounds, imageWidth: pixelWidth, imageHeight: pixelHeight)
  }

  private func currentPointerLocation() -> CGPoint {
    guard let window else { return CGPoint(x: bounds.midX, y: bounds.midY) }
    return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
  }
}
