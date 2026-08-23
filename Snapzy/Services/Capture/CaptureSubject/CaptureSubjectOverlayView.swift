//
//  CaptureSubjectOverlayView.swift
//  Snapzy
//
//  PixelSnap-style area overlay: drag a search rect, lock a snapped preview,
//  and click the camera button to capture.
//

import AppKit
import Carbon.HIToolbox
import QuartzCore

@MainActor
protocol CaptureSubjectOverlayViewDelegate: AnyObject {
  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseMovedAt point: CGPoint)
  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseDownAt point: CGPoint)
  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseDraggedAt point: CGPoint)
  func captureSubjectOverlayView(_ view: CaptureSubjectOverlayView, mouseUpAt point: CGPoint)
  func captureSubjectOverlayViewDidCancel(_ view: CaptureSubjectOverlayView)
  func captureSubjectOverlayViewDidRequestCapture(_ view: CaptureSubjectOverlayView)
}

final class CaptureSubjectOverlayView: NSView {
  weak var delegate: CaptureSubjectOverlayViewDelegate?
  private(set) var currentPreview: CaptureSubjectSnappedPreview?
  private(set) var currentDragRect: CGRect?
  private(set) var isCameraHovered = false
  private(set) var borderLayer: CAShapeLayer!
  private(set) var innerBorderLayer: CAShapeLayer!
  private var previewImageLayer: CALayer!
  private var cameraBackgroundLayer: CALayer!
  private var cameraIconLayer: CALayer!
  private var widthBadgeLayer: CALayer!
  private var widthTextLayer: CATextLayer!
  private var heightBadgeLayer: CALayer!
  private var heightTextLayer: CATextLayer!
  private var cameraImage: CGImage?
  private var pointerLocation: CGPoint?

  private static let cameraButtonSize: CGFloat = 36

  private var disabledActions: [String: CAAction] {
    [
      "bounds": NSNull(),
      "contents": NSNull(),
      "frame": NSNull(),
      "hidden": NSNull(),
      "path": NSNull(),
      "position": NSNull(),
    ]
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  override var acceptsFirstResponder: Bool { true }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(bounds, cursor: NSCursor.vectorScreenshotCrosshairHighContrast)
    if let local = localCameraRect {
      addCursorRect(local, cursor: .pointingHand)
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
        owner: self,
        userInfo: nil
      )
    )
  }

  override func cursorUpdate(with event: NSEvent) { applyCursor(for: event) }
  override func mouseEntered(with event: NSEvent) { applyCursor(for: event) }
  override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rebuildChrome()
    CATransaction.commit()
  }

  override func mouseMoved(with event: NSEvent) {
    applyCursor(for: event)
    let point = screenPoint(for: event)
    updateHover(at: convert(event.locationInWindow, from: nil))
    delegate?.captureSubjectOverlayView(self, mouseMovedAt: point)
  }

  override func mouseDown(with event: NSEvent) {
    let local = convert(event.locationInWindow, from: nil)
    updateHover(at: local)
    if isCameraHovered {
      delegate?.captureSubjectOverlayViewDidRequestCapture(self)
      return
    }
    applyCursor(for: event)
    delegate?.captureSubjectOverlayView(self, mouseDownAt: screenPoint(for: event))
  }

  override func mouseDragged(with event: NSEvent) {
    applyCursor(for: event)
    delegate?.captureSubjectOverlayView(self, mouseDraggedAt: screenPoint(for: event))
  }

  override func mouseUp(with event: NSEvent) {
    delegate?.captureSubjectOverlayView(self, mouseUpAt: screenPoint(for: event))
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      delegate?.captureSubjectOverlayViewDidCancel(self)
      return
    }
    super.keyDown(with: event)
  }

  override func cancelOperation(_ sender: Any?) {
    delegate?.captureSubjectOverlayViewDidCancel(self)
  }

  func updatePreview(_ preview: CaptureSubjectSnappedPreview?) {
    currentPreview = preview
    if preview != nil { currentDragRect = nil }
    if preview == nil {
      isCameraHovered = false
      pointerLocation = nil
    }
    window?.invalidateCursorRects(for: self)
    rebuildTransaction()
  }

  func updateDragRect(_ screenRect: CGRect?) {
    currentDragRect = screenRect
    rebuildTransaction()
  }

  func updateBounds(_ screenFrame: CGRect) {
    frame = CGRect(origin: .zero, size: screenFrame.size)
    updateTrackingAreas()
    needsLayout = true
  }

  func setPointer(_ screenPoint: CGPoint?) {
    pointerLocation = screenPoint.flatMap { localPoint(for: $0) }
    updateHover(at: pointerLocation)
  }

  var currentPreviewRect: CGRect? { currentPreview?.rect }

  var localCameraRect: CGRect? {
    guard let preview = localPreviewRect else { return nil }
    return CGRect(
      x: preview.midX - Self.cameraButtonSize / 2,
      y: preview.midY - Self.cameraButtonSize / 2,
      width: Self.cameraButtonSize,
      height: Self.cameraButtonSize
    )
  }

  private func configure() {
    wantsLayer = true
    setAccessibilityElement(false)
    setAccessibilityHidden(true)
    setAccessibilityRole(.unknown)
    cameraImage = Self.makeCameraImage()
    setupLayers()
    updateTrackingAreas()
  }

  private func setupLayers() {
    guard let rootLayer = layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    previewImageLayer = CALayer()
    previewImageLayer.contentsGravity = .resize
    previewImageLayer.actions = disabledActions
    previewImageLayer.isHidden = true
    previewImageLayer.shadowColor = NSColor.black.cgColor
    previewImageLayer.shadowOpacity = 0.18
    previewImageLayer.shadowRadius = 6
    previewImageLayer.shadowOffset = CGSize(width: 0, height: -1)
    rootLayer.addSublayer(previewImageLayer)

    borderLayer = CAShapeLayer()
    borderLayer.fillColor = nil
    borderLayer.strokeColor = Self.snapBorderColor.cgColor
    borderLayer.lineWidth = 2
    borderLayer.actions = disabledActions
    borderLayer.isHidden = true
    rootLayer.addSublayer(borderLayer)

    innerBorderLayer = CAShapeLayer()
    innerBorderLayer.fillColor = nil
    innerBorderLayer.strokeColor = Self.snapInnerBorderColor.cgColor
    innerBorderLayer.lineWidth = 1
    innerBorderLayer.actions = disabledActions
    innerBorderLayer.isHidden = true
    rootLayer.addSublayer(innerBorderLayer)

    widthBadgeLayer = makeBadgeLayer()
    rootLayer.addSublayer(widthBadgeLayer)
    widthTextLayer = makeTextLayer()
    rootLayer.addSublayer(widthTextLayer)
    heightBadgeLayer = makeBadgeLayer()
    rootLayer.addSublayer(heightBadgeLayer)
    heightTextLayer = makeTextLayer()
    rootLayer.addSublayer(heightTextLayer)

    cameraBackgroundLayer = CALayer()
    cameraBackgroundLayer.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
    cameraBackgroundLayer.borderColor = NSColor.white.withAlphaComponent(0.92).cgColor
    cameraBackgroundLayer.borderWidth = 1
    cameraBackgroundLayer.cornerRadius = 18
    cameraBackgroundLayer.actions = disabledActions
    cameraBackgroundLayer.isHidden = true
    rootLayer.addSublayer(cameraBackgroundLayer)

    cameraIconLayer = CALayer()
    cameraIconLayer.contentsGravity = .resizeAspect
    cameraIconLayer.contents = cameraImage
    cameraIconLayer.actions = disabledActions
    cameraIconLayer.isHidden = true
    rootLayer.addSublayer(cameraIconLayer)

    CATransaction.commit()
  }

  private func rebuildTransaction() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rebuildChrome()
    CATransaction.commit()
  }

  private func rebuildChrome() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    widthTextLayer.contentsScale = scale
    heightTextLayer.contentsScale = scale

    let activeRect: CGRect?
    let isLocked = currentPreview != nil
    if let preview = currentPreview {
      activeRect = localRect(for: preview.rect)
      borderLayer.lineWidth = 2.5
      borderLayer.lineDashPattern = nil
    } else if let drag = currentDragRect {
      activeRect = localRect(for: drag)
      borderLayer.lineWidth = 2
      borderLayer.lineDashPattern = [6, 4]
    } else {
      activeRect = nil
    }

    guard let localRect = activeRect else {
      borderLayer.path = nil
      borderLayer.isHidden = true
      innerBorderLayer.path = nil
      innerBorderLayer.isHidden = true
      hidePreviewImage()
      hideCamera()
      hideDimensions()
      return
    }

    borderLayer.strokeColor = Self.snapBorderColor.cgColor
    borderLayer.path = CGPath(rect: localRect, transform: nil)
    borderLayer.isHidden = false

    let inset = max(1, borderLayer.lineWidth)
    let innerRect = localRect.insetBy(dx: inset, dy: inset)
    if innerRect.width > 1, innerRect.height > 1 {
      innerBorderLayer.path = CGPath(rect: innerRect, transform: nil)
      innerBorderLayer.isHidden = false
    } else {
      innerBorderLayer.path = nil
      innerBorderLayer.isHidden = true
    }

    if isLocked, let image = currentPreview?.image {
      previewImageLayer.frame = localRect
      previewImageLayer.contents = image
      previewImageLayer.isHidden = false
    } else {
      hidePreviewImage()
    }

    updateDimensionBadges(for: localRect)
    updateCamera(in: localRect, visible: isLocked)
    updateAccessibility(isLocked: isLocked)
  }

  private func updateDimensionBadges(for localRect: CGRect) {
    let text: String
    if let preview = currentPreview {
      text = preview.dimensionText
    } else if let drag = currentDragRect {
      text = "\(max(1, Int(drag.width.rounded()))) × \(max(1, Int(drag.height.rounded())))"
    } else {
      hideDimensions()
      return
    }

    let parts = text.split(separator: "×").map { $0.trimmingCharacters(in: .whitespaces) }
    let widthText = parts.first.map { String($0) } ?? text
    let heightText = parts.count > 1 ? String(parts[1]) : text

    placeBadge(
      background: widthBadgeLayer,
      textLayer: widthTextLayer,
      text: widthText,
      at: CGPoint(x: localRect.midX, y: localRect.minY - 8),
      above: false
    )
    placeBadge(
      background: heightBadgeLayer,
      textLayer: heightTextLayer,
      text: heightText,
      at: CGPoint(x: localRect.maxX + 8, y: localRect.midY),
      above: true
    )
  }

  private func placeBadge(
    background: CALayer,
    textLayer: CATextLayer,
    text: String,
    at point: CGPoint,
    above: Bool
  ) {
    let attributes = Self.badgeTextAttributes
    let size = (text as NSString).size(withAttributes: attributes)
    let paddingX: CGFloat = 6
    let paddingY: CGFloat = 3
    let badgeSize = CGSize(width: size.width + paddingX * 2, height: size.height + paddingY * 2)
    var origin = above
      ? CGPoint(x: point.x, y: point.y - badgeSize.height / 2)
      : CGPoint(x: point.x - badgeSize.width / 2, y: point.y - badgeSize.height)
    origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - badgeSize.width - 4)
    origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - badgeSize.height - 4)
    let frame = CGRect(origin: origin, size: badgeSize)
    background.frame = frame
    background.isHidden = false
    textLayer.string = text
    textLayer.frame = frame.insetBy(dx: paddingX, dy: paddingY)
    textLayer.isHidden = false
  }

  private func updateCamera(in localRect: CGRect, visible: Bool) {
    guard visible, let cameraRect = localCameraRect else {
      hideCamera()
      return
    }
    cameraBackgroundLayer.frame = cameraRect
    cameraBackgroundLayer.backgroundColor = isCameraHovered
      ? NSColor.white.withAlphaComponent(0.92).cgColor
      : NSColor.black.withAlphaComponent(0.62).cgColor
    cameraBackgroundLayer.borderColor = isCameraHovered
      ? NSColor.black.withAlphaComponent(0.18).cgColor
      : NSColor.white.withAlphaComponent(0.92).cgColor
    cameraBackgroundLayer.isHidden = false
    cameraIconLayer.frame = cameraRect.insetBy(dx: 10, dy: 10)
    cameraIconLayer.contents = isCameraHovered ? Self.makeCameraImage(color: .black) : cameraImage
    cameraIconLayer.isHidden = false
  }

  private func updateHover(at localPoint: CGPoint?) {
    let hovered = localPoint.flatMap { point in
      localCameraRect?.insetBy(dx: -4, dy: -4).contains(point)
    } ?? false
    guard hovered != isCameraHovered else { return }
    isCameraHovered = hovered
    rebuildTransaction()
  }

  private func updateAccessibility(isLocked: Bool) {
    if isLocked {
      setAccessibilityElement(true)
      setAccessibilityHidden(false)
      setAccessibilityRole(.button)
      setAccessibilityLabel(L10n.ScreenCapture.captureSubjectPreview)
    } else {
      setAccessibilityElement(false)
      setAccessibilityHidden(true)
      setAccessibilityRole(.unknown)
      setAccessibilityLabel(nil)
    }
  }

  private func hidePreviewImage() {
    previewImageLayer.contents = nil
    previewImageLayer.isHidden = true
  }

  private func hideCamera() {
    cameraBackgroundLayer.isHidden = true
    cameraIconLayer.isHidden = true
  }

  private func hideDimensions() {
    widthBadgeLayer.isHidden = true
    widthTextLayer.isHidden = true
    heightBadgeLayer.isHidden = true
    heightTextLayer.isHidden = true
  }

  private var localPreviewRect: CGRect? {
    guard let currentPreview else { return nil }
    return localRect(for: currentPreview.rect)
  }

  private func localRect(for screenRect: CGRect) -> CGRect? {
    guard let window else { return nil }
    let rect = screenRect
      .offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
      .intersection(bounds)
      .integral
    guard !rect.isNull, !rect.isEmpty else { return nil }
    return rect
  }

  private func localPoint(for screenPoint: CGPoint) -> CGPoint? {
    guard let window else { return nil }
    return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
  }

  private func cursor(for event: NSEvent) -> NSCursor {
    let point = convert(event.locationInWindow, from: nil)
    if let localCameraRect, localCameraRect.insetBy(dx: -4, dy: -4).contains(point) {
      return .pointingHand
    }
    return NSCursor.vectorScreenshotCrosshairHighContrast
  }

  private func applyCursor(for event: NSEvent) {
    guard window?.isVisible == true else { return }
    cursor(for: event).set()
  }

  private func screenPoint(for event: NSEvent) -> CGPoint {
    guard let window else {
      return convert(event.locationInWindow, to: nil)
    }
    return window.convertPoint(toScreen: event.locationInWindow)
  }

  private static let snapBorderColor = NSColor(srgbRed: 0.18, green: 0.86, blue: 0.96, alpha: 1)
  private static let snapInnerBorderColor = NSColor.white.withAlphaComponent(0.88)

  private func makeBadgeLayer() -> CALayer {
    let layer = CALayer()
    layer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    layer.cornerRadius = 4
    layer.actions = disabledActions
    layer.isHidden = true
    return layer
  }

  private func makeTextLayer() -> CATextLayer {
    let layer = CATextLayer()
    layer.font = NSFont.systemFont(ofSize: 10, weight: .medium)
    layer.fontSize = 10
    layer.foregroundColor = NSColor.white.cgColor
    layer.alignmentMode = .center
    layer.actions = disabledActions
    layer.isHidden = true
    layer.contentsGravity = .resizeAspect
    return layer
  }

  private static var badgeTextAttributes: [NSAttributedString.Key: Any] {
    [
      .font: NSFont.systemFont(ofSize: 10, weight: .medium),
      .foregroundColor: NSColor.white,
    ]
  }

  private static func makeCameraImage(color: NSColor = .white) -> CGImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard
      let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    else { return nil }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }
}
