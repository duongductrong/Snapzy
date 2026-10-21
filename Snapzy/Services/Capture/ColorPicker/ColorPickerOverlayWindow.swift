//
//  ColorPickerOverlayWindow.swift
//  Snapzy
//
//  Per-display Pick Color overlay: a see-through panel that keeps the live screen visible,
//  takes the clicks, and draws the `ColorPickerLoupe` where the cursor would be.
//

import AppKit
import Carbon.HIToolbox

@MainActor
protocol ColorPickerOverlayViewDelegate: AnyObject {
  func colorPickerOverlayView(_ view: ColorPickerOverlayView, didPick color: ColorPickerColor)
  func colorPickerOverlayViewDidCancel(_ view: ColorPickerOverlayView)
  func colorPickerOverlayViewDidReceivePointer(_ view: ColorPickerOverlayView)
}

final class ColorPickerOverlayWindow: NSPanel {
  let overlayView: ColorPickerOverlayView
  let displayID: CGDirectDisplayID?

  init(screen: NSScreen) {
    displayID = screen.displayID
    overlayView = ColorPickerOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .screenSaver
    isOpaque = false
    // Nearly clear: the live screen shows through, but the panel still takes the clicks.
    backgroundColor = NSColor(white: 0, alpha: 0.005)
    hasShadow = false
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    animationBehavior = .none
    becomesKeyOnlyIfNeeded = false
    // Snapzy's own chrome never lands in a capture or a recording.
    sharingType = .none
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isMovable = false
    isMovableByWindowBackground = false
    contentView = overlayView
    setFrame(screen.frame, display: false)
  }

  /// Non-activating: the panel takes key input without activating Snapzy, so the app being
  /// picked from keeps its active look (and its active colors).
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class ColorPickerOverlayView: NSView {
  /// Trackpad scroll distance per zoom/size step; a mouse wheel steps once per notch.
  private static let preciseScrollStep: CGFloat = 12

  weak var delegate: ColorPickerOverlayViewDelegate?

  /// Live pixels for this display. Nil while the display isn't streamed (the pointer is on
  /// another display, or capture is still starting).
  var pixelSource: ColorPickerPixelSource? {
    didSet {
      oldValue?.onUpdate = nil
      pixelSource?.onUpdate = { [weak self] in self?.sourceDidUpdate() }
      sourceDidUpdate()
    }
  }

  /// Warps the real pointer; replaced in tests.
  var warpPointer: (CGPoint) -> Void = { point in LivePassthroughCursorRestorer().restore(to: point) }

  private let loupe: ColorPickerLoupe
  private let reversesScrollDirection: Bool
  private var pointerLocation: CGPoint?
  private(set) var currentPixel: ColorPickerPixel?
  private(set) var currentColor: ColorPickerColor?
  private var scrollAccumulator: CGFloat = 0

  override init(frame frameRect: NSRect) {
    let defaults = UserDefaults.standard
    loupe = ColorPickerLoupe(
      cellSizeIndex: defaults.object(forKey: PreferencesKeys.colorPickerLoupeCellSizeIndex) as? Int
        ?? ColorPickerLoupe.defaultCellSizeIndex,
      diameterIndex: defaults.object(forKey: PreferencesKeys.colorPickerLoupeDiameterIndex) as? Int
        ?? ColorPickerLoupe.defaultDiameterIndex,
      hintText: L10n.ScreenCapture.colorPickerHint
    )
    reversesScrollDirection = defaults
      .object(forKey: PreferencesKeys.screenshotReverseMagnifierZoomDirection) as? Bool ?? false
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }

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

  override func mouseEntered(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    hideLoupe()
  }

  override func mouseDown(with event: NSEvent) {
    // Pick what the loupe shows: after an arrow-key nudge that is the nudged pixel, not
    // whatever point the click lands on.
    if currentPixel == nil {
      pointerMoved(to: convert(event.locationInWindow, from: nil))
    }
    guard let currentColor else { return }
    delegate?.colorPickerOverlayView(self, didPick: currentColor)
  }

  override func rightMouseDown(with event: NSEvent) {
    delegate?.colorPickerOverlayViewDidCancel(self)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      delegate?.colorPickerOverlayViewDidCancel(self)
      return
    }
    super.keyDown(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    applyScroll(
      delta: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
      resizesLoupe: event.modifierFlags.contains(.option)
    )
  }

  // MARK: - Interaction

  /// Scroll zooms; ⌥+scroll resizes the loupe. Both are remembered for the next session.
  func applyScroll(delta: CGFloat, hasPreciseScrollingDeltas: Bool, resizesLoupe: Bool) {
    guard delta != 0 else { return }
    let step: Int
    if hasPreciseScrollingDeltas {
      scrollAccumulator += delta
      guard abs(scrollAccumulator) >= Self.preciseScrollStep else { return }
      step = scrollAccumulator > 0 ? 1 : -1
      scrollAccumulator = 0
    } else {
      step = delta > 0 ? 1 : -1
    }
    let signedStep = reversesScrollDirection ? -step : step

    if resizesLoupe {
      loupe.diameterIndex += signedStep
      UserDefaults.standard.set(loupe.diameterIndex, forKey: PreferencesKeys.colorPickerLoupeDiameterIndex)
    } else {
      loupe.cellSizeIndex += signedStep
      UserDefaults.standard.set(loupe.cellSizeIndex, forKey: PreferencesKeys.colorPickerLoupeCellSizeIndex)
    }
    render()
  }

  /// Moves the sampled pixel by whole display pixels (physical pixels on Retina), keeping
  /// the real pointer on it so the next mouse move continues from there.
  func nudge(dx: Int, dy: Int) {
    guard let size = pixelSource?.pixelSize else { return }
    let start = currentPixel ?? pixel(at: pointerLocation ?? currentPointerLocation(), size: size)
    let target = ColorPickerPixelSampler.clamp(
      ColorPickerPixel(x: start.x + dx, y: start.y + dy),
      imageWidth: size.width,
      imageHeight: size.height
    )
    let center = ColorPickerPixelSampler.point(
      forCenterOf: target,
      bounds: bounds,
      imageWidth: size.width,
      imageHeight: size.height
    )
    pointerLocation = center
    select(target)
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

  func hideLoupe() {
    pointerLocation = nil
    currentPixel = nil
    currentColor = nil
    loupe.hide()
  }

  // MARK: - Rendering

  private func pointerMoved(to point: CGPoint) {
    pointerLocation = point
    delegate?.colorPickerOverlayViewDidReceivePointer(self)
    guard let size = pixelSource?.pixelSize else { return }
    select(pixel(at: point, size: size))
  }

  /// New frame (or a newly attached source): resample the same pixel so the loupe follows
  /// whatever is playing under it.
  private func sourceDidUpdate() {
    guard let size = pixelSource?.pixelSize else {
      currentPixel = nil
      currentColor = nil
      loupe.hide()
      return
    }
    if let currentPixel {
      select(currentPixel)
    } else if let pointerLocation {
      select(pixel(at: pointerLocation, size: size))
    }
  }

  private func select(_ pixel: ColorPickerPixel) {
    currentPixel = pixel
    currentColor = pixelSource?.color(of: pixel)
    render()
  }

  private func render() {
    guard let layer, let pixelSource, let size = pixelSource.pixelSize,
          let currentPixel, let currentColor,
          let neighborhood = pixelSource.neighborhood(of: currentPixel, radius: loupe.radiusInPixels) else { return }
    loupe.update(
      center: ColorPickerPixelSampler.point(
        forCenterOf: currentPixel,
        bounds: bounds,
        imageWidth: size.width,
        imageHeight: size.height
      ),
      neighborhood: neighborhood,
      color: currentColor,
      bounds: bounds,
      contentsScale: window?.backingScaleFactor ?? 2.0,
      in: layer
    )
  }

  private func pixel(at point: CGPoint, size: (width: Int, height: Int)) -> ColorPickerPixel {
    ColorPickerPixelSampler.pixel(at: point, bounds: bounds, imageWidth: size.width, imageHeight: size.height)
  }

  private func currentPointerLocation() -> CGPoint {
    guard let window else { return CGPoint(x: bounds.midX, y: bounds.midY) }
    return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
  }
}

#if DEBUG
extension ColorPickerOverlayView {
  var testLoupe: ColorPickerLoupe { loupe }

  func testPointerMoved(to point: CGPoint) {
    pointerMoved(to: point)
  }
}
#endif
