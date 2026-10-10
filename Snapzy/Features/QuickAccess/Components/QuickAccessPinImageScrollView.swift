//
//  QuickAccessPinImageScrollView.swift
//  Snapzy
//
//  AppKit-backed zoom and pan viewport for pinned screenshots.
//

import AppKit
import SwiftUI

struct QuickAccessPinImageViewport: NSViewRepresentable {
  @ObservedObject var state: QuickAccessPinWindowState

  func makeNSView(context _: Context) -> QuickAccessPinImageScrollView {
    let scrollView = QuickAccessPinImageScrollView()
    scrollView.isLockedProvider = { [weak state] in
      state?.isLocked ?? true
    }
    scrollView.onViewportChange = { [weak state] magnification, panOffset in
      state?.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.stateResizeRequest = { [weak state] size, fraction in state?.onWindowResize?(size, fraction) }
    scrollView.update(
      image: state.image,
      viewportSize: state.displaySize,
      imageSize: state.baseSize,
      zoomMode: state.zoomMode,
      magnification: state.zoomFactor,
      panOffset: state.panOffset
    )
    return scrollView
  }

  func updateNSView(_ scrollView: QuickAccessPinImageScrollView, context _: Context) {
    scrollView.stateResizeRequest = { [weak state] size, fraction in state?.onWindowResize?(size, fraction) }
    scrollView.update(
      image: state.image,
      viewportSize: state.displaySize,
      imageSize: state.baseSize,
      zoomMode: state.zoomMode,
      magnification: state.zoomFactor,
      panOffset: state.panOffset
    )
  }
}

@MainActor
final class QuickAccessPinImageScrollView: NSScrollView {
  typealias ViewportChangeHandler = (_ magnification: CGFloat, _ panOffset: CGPoint) -> Void

  enum ScrollAction: Equatable {
    case magnify
    case pan
    case reject(String)
  }

  var onViewportChange: ViewportChangeHandler?
  var isLockedProvider: () -> Bool = { false } {
    didSet {
      imageView.isLockedProvider = isLockedProvider
    }
  }

  private let imageView = QuickAccessPinImageDocumentView()
  private var configuredImage: NSImage?
  private var configuredViewportSize: CGSize = .zero
  private var configuredImageSize: CGSize = .zero
  private var zoomMode: QuickAccessPinZoomMode = .defaultMode
  private var requestedMagnification: CGFloat = 1
  private var requestedPanOffset: CGPoint = .zero
  private var stateApplicationDepth = 0
  private var pendingFocalAnchor: CGPoint?
  private var boundsObserver: NSObjectProtocol?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  deinit {
    if let boundsObserver {
      NotificationCenter.default.removeObserver(boundsObserver)
    }
  }

  override var mouseDownCanMoveWindow: Bool {
    true
  }

  override func layout() {
    stateApplicationDepth += 1
    defer { stateApplicationDepth -= 1 }
    super.layout()
    let viewportSize = contentSize
    guard viewportSize.width > 0, viewportSize.height > 0,
          viewportSize != configuredViewportSize
    else { return }
    configuredViewportSize = viewportSize
    resizeDocumentForViewport()
    applyViewport(magnification: requestedMagnification, panOffset: requestedPanOffset)
  }

  func update(
    image: NSImage,
    viewportSize: CGSize,
    imageSize: CGSize,
    zoomMode: QuickAccessPinZoomMode,
    magnification: CGFloat,
    panOffset: CGPoint
  ) {
    requestedMagnification = magnification
    requestedPanOffset = panOffset
    performStateApplication {
      let imageChanged = configuredImage !== image
      let viewportChanged = configuredViewportSize != viewportSize || configuredImageSize != imageSize || self.zoomMode != zoomMode
      configuredImage = image
      self.zoomMode = zoomMode
      configuredImageSize = imageSize
      imageView.image = image
      imageView.onMagnify = { [weak self] event in self?.handleMagnify(event) }

      if imageChanged || viewportChanged {
        configuredViewportSize = viewportSize
        resizeDocumentForViewport()
      }

      applyViewport(magnification: magnification, panOffset: panOffset)
    }
  }

  private func handleMagnify(_ event: NSEvent) {
    let windowPoint = event.locationInWindow
    let viewportPoint = convert(windowPoint, from: nil)
    let contentPoint = contentView.convert(windowPoint, from: nil)
    guard !isLockedProvider() else { return }
    let delta = event.magnification
    guard delta.isFinite else { return }
    applyMagnificationDelta(delta, centeredAtContentPoint: contentPoint, windowPoint: viewportPoint)
  }

  override func magnify(with event: NSEvent) {
    handleMagnify(event)
  }

  override func scrollWheel(with event: NSEvent) {
    switch scrollAction(for: event) {
    case .reject(_):
      return
    case .magnify:
      let localPoint = convert(event.locationInWindow, from: nil)
      let contentPoint = contentView.convert(event.locationInWindow, from: nil)
      applyMagnificationDelta(-event.scrollingDeltaY * 0.01, centeredAtContentPoint: contentPoint, windowPoint: localPoint)
    case .pan:
      applyScrollPan(for: event) { super.scrollWheel(with: event) }
    }
  }

  func scrollAction(for event: NSEvent) -> ScrollAction {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !isLockedProvider() else { return .reject("locked") }
    if modifiers == .command {
      guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), abs(event.scrollingDeltaY) > 0 else {
        return .reject("horizontalOrZeroDelta")
      }
      return .magnify
    }
    guard modifiers.isEmpty else { return .reject("modifiers") }
    if zoomMode == .windowFollowsImage {
      guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), abs(event.scrollingDeltaY) > 0 else {
        return .reject("horizontalOrZeroDelta")
      }
      return .magnify
    }
    guard event.hasPreciseScrollingDeltas else { return .reject("nonPrecise") }
    guard contentOverflowsViewport else { return .reject("noOverflow") }
    return .pan
  }

  func applyScrollPan(for _: NSEvent, performPan: () -> Void) {
    performPan()
    publishViewportChange()
  }

  var currentPanOffset: CGPoint {
    guard let documentView, magnification > 0 else { return .zero }
    return QuickAccessPinImageGeometry.panOffset(
      documentSize: documentView.bounds.size,
      visibleRect: documentView.visibleRect,
      magnification: magnification
    )
  }

  private var contentOverflowsViewport: Bool {
    let scaledSize = CGSize(
      width: imageView.bounds.width * magnification,
      height: imageView.bounds.height * magnification
    )
    return scaledSize.width > contentSize.width + 0.001
      || scaledSize.height > contentSize.height + 0.001
  }

  private var isApplyingState: Bool {
    stateApplicationDepth > 0
  }

  private func configure() {
    let centeringClipView = QuickAccessPinCenteringClipView()
    centeringClipView.drawsBackground = false
    contentView = centeringClipView
    drawsBackground = true
    backgroundColor = NSColor.black.withAlphaComponent(0.03)
    borderType = .noBorder
    hasHorizontalScroller = false
    hasVerticalScroller = false
    autohidesScrollers = true
    horizontalScrollElasticity = .none
    verticalScrollElasticity = .none
    allowsMagnification = false
    minMagnification = QuickAccessPinWindowState.minimumZoomFactor
    maxMagnification = QuickAccessPinWindowState.maximumZoomFactor
    contentView.postsBoundsChangedNotifications = true
    documentView = imageView
    imageView.isLockedProvider = isLockedProvider

    boundsObserver = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification,
      object: contentView,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.isApplyingState else { return }
        self.publishViewportChange()
      }
    }
  }

  private func resizeDocumentForViewport() {
    guard let image = configuredImage else {
      imageView.frame = .zero
      return
    }
    let viewportSize = configuredViewportSize == .zero ? contentSize : configuredViewportSize
    let fittedSize: CGSize
    if zoomMode == .windowFollowsImage {
      fittedSize = QuickAccessPinImageGeometry.fittedContentSize(imageSize: image.size, viewportSize: configuredImageSize)
    } else {
      let scale = min(1, viewportSize.width / max(image.size.width, 1))
      fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
    imageView.frame = NSRect(origin: .zero, size: fittedSize)
    imageView.needsDisplay = true
  }

  private func applyViewport(magnification requestedMagnification: CGFloat, panOffset: CGPoint) {
    guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
    let clampedMagnification = min(
      max(requestedMagnification, minMagnification),
      maxMagnification
    )
    let clampedPan = QuickAccessPinImageGeometry.clampedPanOffset(
      panOffset,
      viewportSize: configuredViewportSize,
      contentSize: CGSize(
        width: imageView.bounds.width * clampedMagnification,
        height: imageView.bounds.height * clampedMagnification
      )
    )

    let zoomChanged = abs(magnification - clampedMagnification) > 0.000_1
    let panChanged = !pointsAreEqual(currentPanOffset, clampedPan)
    guard zoomChanged || panChanged else { return }

    performStateApplication {
      if zoomChanged {
        let anchor: CGPoint
        if let focal = pendingFocalAnchor {
          anchor = focal
          pendingFocalAnchor = nil
        } else {
          let visibleRect = documentView?.visibleRect ?? imageView.bounds
          anchor = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        }
        setMagnification(clampedMagnification, centeredAt: anchor)
      }

      let visibleSize = CGSize(
        width: contentSize.width / clampedMagnification,
        height: contentSize.height / clampedMagnification
      )
      let origin = QuickAccessPinImageGeometry.visibleRectOrigin(
        panOffset: clampedPan,
        documentSize: imageView.bounds.size,
        visibleSize: visibleSize,
        magnification: clampedMagnification
      )
      contentView.setBoundsOrigin(origin)
      reflectScrolledClipView(contentView)
    }
  }

  private func performStateApplication(_ body: () -> Void) {
    stateApplicationDepth += 1
    defer { stateApplicationDepth -= 1 }
    body()
  }

  func applyMagnificationDelta(_ delta: CGFloat, centeredAtContentPoint point: CGPoint, windowPoint: CGPoint) {
    let target = min(max(magnification * (1 + delta), minMagnification), maxMagnification)
    let before = magnification
    guard target != before else { return }

    pendingFocalAnchor = point
    performStateApplication {
      setMagnification(target, centeredAt: point)
    }
    publishViewportChange()
    if zoomMode == .windowFollowsImage {
      if window == nil {
        stateResizeRequest?(displaySizeForZoom(target), liveAnchorFraction(windowPoint: windowPoint))
      } else {
        performWindowResizingZoom(target: target, contentPoint: point, windowPoint: windowPoint)
      }
    }
  }

  private func performWindowResizingZoom(target: CGFloat, contentPoint: CGPoint, windowPoint: CGPoint) {
    guard let window else { return }
    let cursorBase = convert(windowPoint, to: nil)
    let cursorScreen = window.convertToScreen(NSRect(origin: cursorBase, size: .zero)).origin
    let documentAnchor = imageView.convert(cursorBase, from: nil)

    stateResizeRequest?(displaySizeForZoom(target), liveAnchorFraction(windowPoint: windowPoint))
    window.contentView?.layoutSubtreeIfNeeded()
    reanchor(imagePoint: documentAnchor, atScreenPoint: cursorScreen)
  }

  private func reanchor(imagePoint: CGPoint, atScreenPoint cursorScreen: CGPoint) {
    guard let window else { return }
    let cursorBase = window.convertFromScreen(NSRect(origin: cursorScreen, size: .zero)).origin
    let currentImagePoint = imageView.convert(cursorBase, from: nil)
    let delta = NSPoint(
      x: currentImagePoint.x - imagePoint.x,
      y: currentImagePoint.y - imagePoint.y
    )
    guard abs(delta.x) > 0.001 || abs(delta.y) > 0.001 else { return }
    let origin = contentView.bounds.origin
    performStateApplication {
      contentView.setBoundsOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
      reflectScrolledClipView(contentView)
    }
    publishViewportChange()
  }

  var stateResizeRequest: ((CGSize, CGPoint) -> Void)?

  private func displaySizeForZoom(_ target: CGFloat) -> CGSize {
    QuickAccessPinWindowState.windowFollowsImageDisplaySize(
      baseSize: configuredImageSize,
      zoomFactor: target
    )
  }

  private func liveAnchorFraction(windowPoint: CGPoint) -> CGPoint {
    guard let window else {
      return CGPoint(x: bounds.width > 0 ? windowPoint.x / bounds.width : 0.5, y: bounds.height > 0 ? windowPoint.y / bounds.height : 0.5)
    }
    let pointInWindow = convert(windowPoint, to: nil)
    let frame = window.frame
    return CGPoint(
      x: frame.width > 0 ? pointInWindow.x / frame.width : 0.5,
      y: frame.height > 0 ? pointInWindow.y / frame.height : 0.5
    )
  }

  private func publishViewportChange() {
    requestedMagnification = magnification
    requestedPanOffset = currentPanOffset
    onViewportChange?(requestedMagnification, requestedPanOffset)
  }

  private func pointsAreEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
    abs(lhs.x - rhs.x) < 0.000_1 && abs(lhs.y - rhs.y) < 0.000_1
  }

}

private final class QuickAccessPinCenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var constrainedBounds = super.constrainBoundsRect(proposedBounds)
    guard let documentView else { return constrainedBounds }

    if documentView.frame.width < proposedBounds.width {
      constrainedBounds.origin.x = (documentView.frame.width - proposedBounds.width) / 2
    }
    if documentView.frame.height < proposedBounds.height {
      constrainedBounds.origin.y = (documentView.frame.height - proposedBounds.height) / 2
    }
    return constrainedBounds
  }
}

final class QuickAccessPinImageDocumentView: NSView {
  var isLockedProvider: () -> Bool = { false }
  var onMagnify: ((NSEvent) -> Void)?

  var image: NSImage? {
    didSet {
      needsDisplay = true
    }
  }

  override var isFlipped: Bool {
    true
  }

  override var mouseDownCanMoveWindow: Bool {
    true
  }

  override var needsPanelToBecomeKey: Bool {
    !isLockedProvider()
  }

  override var acceptsFirstResponder: Bool {
    needsPanelToBecomeKey
  }

  override func magnify(with event: NSEvent) {
    onMagnify?(event)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let image else { return }
    image.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: image.size),
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.high]
    )
  }
}
