//
//  QuickAccessPinWindowManager.swift
//  Snapzy
//
//  Manages independent always-on-top pinned screenshot windows.
//

import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class QuickAccessPinWindowManager {
  static let shared = QuickAccessPinWindowManager()

  private var controllers: [UUID: QuickAccessPinWindowController] = [:]

  private init() {}

  /// - Parameter entranceFrom: The region the pinned image should grow out of — the Quick Access
  ///   card it was pinned from, when the gesture came from a card. Falls back to the captured
  ///   region, and to a plain fade when neither is known.
  @discardableResult
  func show(
    item: QuickAccessItem,
    entranceFrom: NSRect? = nil,
    onUserClose: @escaping (UUID) -> Void
  ) -> Bool {
    guard !item.isVideo else { return false }

    if let controller = controllers[item.id] {
      controller.update(item: item)
      controller.orderFront()
      return true
    }

    let controller = QuickAccessPinWindowController(item: item, entranceFrom: entranceFrom)
    controller.onUserClose = { [weak self] id in
      self?.controllers[id] = nil
      onUserClose(id)
    }
    controllers[item.id] = controller
    controller.show()
    return true
  }

  func update(item: QuickAccessItem, imageOverride: NSImage? = nil) {
    controllers[item.id]?.update(item: item, imageOverride: imageOverride)
  }

  func setPinZoomMode(_ mode: QuickAccessPinZoomMode) {
    for controller in controllers.values { controller.setZoomMode(mode) }
  }

  func close(id: UUID) {
    controllers.removeValue(forKey: id)?.close()
  }

  func closeAll() {
    for controller in controllers.values {
      controller.close()
    }
    controllers.removeAll()
  }

  func suspendAllMouseMonitors() {
    for controller in controllers.values {
      controller.suspendMouseMonitors()
    }
  }

  func resumeAllMouseMonitors() {
    for controller in controllers.values {
      controller.resumeMouseMonitors()
    }
  }
}

@MainActor
private final class QuickAccessPinWindowController {
  /// Replaced rather than stacked, in case a pin is re-shown while its first entrance is running.
  private static let entranceMotionKey = "quickAccess.pin.entrance"

  /// One entrance, precomputed: see `makeEntrance()`.
  private struct Entrance {
    let flightFrame: NSRect
    let restingFrame: NSRect
    let containerFrame: NSRect
    let transform: CATransform3D
  }

  var onUserClose: ((UUID) -> Void)?

  private let id: UUID
  private let state: QuickAccessPinWindowState
  private let window: QuickAccessPinWindow
  /// Fills the window, so the frame change AppKit performs on every `setFrame` lands here instead of
  /// on the view that holds the laid-out content.
  private let contentHost = NSView(frame: .zero)
  /// Host for the SwiftUI content, sized by the sizing policy once at the resting frame and moved by
  /// nothing else but this controller. The entrance scales this view's layer, so the content is never
  /// re-flowed mid-flight.
  private let contentContainer = NSView(frame: .zero)
  /// The entrance currently in flight, cleared when the pin lands. Its frames are the only truth
  /// about where the window is allowed to be while the spring runs.
  private var activeEntrance: Entrance?
  /// The region the entrance flies out of. The card the gesture came from wins over the captured
  /// region: a pin whose resting size matches its capture has nowhere to travel, while the card sits
  /// in a corner and always gives the flight somewhere to come from.
  private let entranceOrigin: CGRect?

  init(item: QuickAccessItem, entranceFrom: NSRect? = nil) {
    id = item.id

    let image = Self.loadImage(for: item)
    let origin = CaptureOriginStore.shared.origin(for: item.url)
    entranceOrigin = entranceFrom ?? origin
    // The display the capture came from, not the one the pointer happens to be on: after a
    // capture on monitor 2 the pointer usually drifts back to monitor 1.
    let screen = origin.flatMap(ScreenUtility.screen(containing:)) ?? ScreenUtility.activeScreen()
    let mode = QuickAccessPinZoomModeStore.shared.mode
    let baseSize = QuickAccessPinWindowSizing.size(for: image.size, visibleSize: screen.visibleFrame.size, mode: mode)
    state = QuickAccessPinWindowState(
      id: item.id,
      url: item.url,
      image: image,
      thumbnail: item.thumbnail,
      baseSize: baseSize,
      zoomMode: mode
    )

    let restingSize = state.displaySize
    let restingFrame = origin.map {
      QuickAccessPinWindowSizing.frame(
        size: restingSize,
        centeredAt: CGPoint(x: $0.midX, y: $0.midY)
      )
    } ?? QuickAccessPinWindowSizing.centeredFrame(size: restingSize, on: screen)
    let frame = QuickAccessPinWindowSizing.constrainedFrame(restingFrame, on: screen)
    window = QuickAccessPinWindow(contentRect: frame, state: state)
    state.onWindowResize = { [weak self] size, anchorFraction in
      self?.resize(to: size, preservingAnchorFraction: anchorFraction, animated: false)
    }
    installContent()
    window.onEscapeRequested = { [weak self] in
      self?.handleUserClose()
    }
  }

  func show() {
    guard let entrance = makeEntrance() else {
      window.alphaValue = 0
      orderFront()
      fadeIn()
      return
    }
    playEntrance(entrance)
  }

  func orderFront() {
    window.orderFrontRegardless()
    window.updateMousePassthrough()
  }

  /// Everything the flight needs, decided before the window is shown: the wide frame it travels
  /// inside, where the content sits in it, and the transform that puts the content on its source
  /// region. `nil` when there is nothing to fly from, or the path cannot be shown.
  private func makeEntrance() -> Entrance? {
    guard !SnapzyMotionPreferences.shared.reduceMotion, let entranceOrigin,
          let layer = contentContainer.layer
    else { return nil }

    let restingFrame = window.frame
    let screen = ScreenUtility.screen(containing: restingFrame) ?? window.screen ?? ScreenUtility.activeScreen()
    guard let flightFrame = QuickAccessPinWindowSizing.flightRect(
      resting: restingFrame,
      start: entranceOrigin,
      shadowMargin: QuickAccessPinWindowSizing.entranceShadowMargin,
      screenFrame: screen.frame
    ) else { return nil }

    let containerFrame = restingFrame.offsetBy(
      dx: -flightFrame.minX,
      dy: -flightFrame.minY
    )
    let startInFlight = entranceOrigin.offsetBy(
      dx: -flightFrame.minX,
      dy: -flightFrame.minY
    )
    let transform = QuickAccessPinWindowSizing.entranceTransform(
      targetRect: startInFlight,
      layerRect: containerFrame,
      anchorPoint: layer.anchorPoint,
      geometryFlipped: layer.isGeometryFlipped
    )
    guard transform.m11 != 1 || transform.m22 != 1 || transform.m41 != 0 || transform.m42 != 0 else {
      return nil
    }

    return Entrance(
      flightFrame: flightFrame,
      restingFrame: restingFrame,
      containerFrame: containerFrame,
      transform: transform
    )
  }

  /// The content is laid out once, at its resting size, and the compositor scales it along the path;
  /// the window only shrinks back to the resting frame when the spring has settled, which moves the
  /// content by nothing at all.
  private func playEntrance(_ entrance: Entrance) {
    activeEntrance = entrance
    window.setFrame(entrance.flightFrame, display: false)
    contentContainer.frame = entrance.containerFrame
    window.isEntranceInFlight = true
    window.alphaValue = 0
    window.orderFrontRegardless()

    guard let layer = contentContainer.layer else {
      finishEntrance()
      fadeIn()
      return
    }

    layer.removeAnimation(forKey: Self.entranceMotionKey)
    let spring = CASpringAnimation(keyPath: "transform")
    spring.mass = 1
    spring.stiffness = 340
    spring.damping = 32
    spring.fromValue = NSValue(caTransform3D: entrance.transform)
    spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    spring.duration = spring.settlingDuration

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.finishEntrance() }
    }
    layer.add(spring, forKey: Self.entranceMotionKey)
    CATransaction.commit()

    fadeIn()
  }

  /// Land the pin: back to the resting frame with the content filling it. Anything that measures the
  /// window — a resize, a zoom-mode change — has to do this first, because mid-flight the window is
  /// a wide transparent frame rather than the pin.
  func finishEntrance() {
    guard let entrance = activeEntrance else { return }
    activeEntrance = nil
    window.isEntranceInFlight = false
    window.setFrame(entrance.restingFrame, display: true)
    contentContainer.frame = NSRect(origin: .zero, size: entrance.restingFrame.size)
    window.updateMousePassthrough()
  }

  func update(item: QuickAccessItem, imageOverride: NSImage? = nil) {
    let image = imageOverride ?? Self.loadImage(for: item)
    let screen = window.screen ?? ScreenUtility.activeScreen()
    let baseSize = QuickAccessPinWindowSizing.size(for: image.size, visibleSize: screen.visibleFrame.size, mode: state.zoomMode)
    let newSize = state.update(
      url: item.url,
      image: image,
      thumbnail: item.thumbnail,
      baseSize: baseSize
    )
    resize(to: newSize, animated: false)
  }

  func close() {
    window.close()
  }

  func suspendMouseMonitors() {
    window.suspendMouseMonitors()
  }

  func resumeMouseMonitors() {
    window.resumeMouseMonitors()
    // The monitors were down while another surface owned the pointer, so `isMouseInside` still
    // describes where the cursor was when they went away. Without this the hover-revealed chrome
    // stays lit over a pin the pointer has long since left.
    window.updateMousePassthrough()
  }

  private func installContent() {
    let restingBounds = NSRect(origin: .zero, size: state.displaySize)
    contentHost.frame = restingBounds
    contentHost.wantsLayer = true
    // Layer-backed so the entrance can scale this view's own layer instead of resizing the window.
    contentContainer.frame = restingBounds
    contentContainer.wantsLayer = true
    // The window resizes its content view on every frame change; the container has to keep its
    // resting size through the flight, so only this controller moves it.
    contentContainer.autoresizingMask = []
    let hosting = hostingView(size: state.displaySize)
    hosting.autoresizingMask = [.width, .height]
    contentContainer.addSubview(hosting)
    contentHost.addSubview(contentContainer)
    window.contentView = contentHost
  }

  /// Alpha runs alongside the flight instead of inside it: the fade is short, so the window is
  /// opaque for most of the travel and the motion reads as one object moving rather than appearing.
  private func fadeIn() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = SnapzyMotionPreferences.shared.reduceMotion ? 0.18 : 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().alphaValue = 1
    }
  }

  private func hostingView(size: CGSize) -> NSHostingView<QuickAccessPinWindowView> {
    let view = QuickAccessPinWindowView(
      state: state,
      onClose: { [weak self] in
        self?.handleUserClose()
      },
      onLockChanged: { [weak self] in
        self?.window.updateMousePassthrough()
      }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: size)
    return hostingView
  }

  private func handleUserClose() {
    QuickAccessManager.shared.setWindowOpen(id: id, isOpen: false)
    self.close()
    self.onUserClose?(self.id)
  }

  private func resize(to size: CGSize, animated: Bool) {
    finishEntrance()
    let currentFrame = window.frame
    let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
    let proposedFrame = NSRect(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
    let screen = window.screen ?? ScreenUtility.activeScreen()
    let targetFrame = QuickAccessPinWindowSizing.constrainedFrame(proposedFrame, on: screen)
    window.setFrame(targetFrame, display: true, animate: animated)
    contentContainer.frame = NSRect(origin: .zero, size: targetFrame.size)
    window.updateMousePassthrough()
  }

  func setZoomMode(_ mode: QuickAccessPinZoomMode) {
    finishEntrance()
    let screen = window.screen ?? ScreenUtility.activeScreen()
    let size = QuickAccessPinWindowSizing.size(for: state.image.size, visibleSize: screen.visibleFrame.size, mode: mode)
    guard state.setZoomMode(mode, baseSize: size) else { return }
    let frame = QuickAccessPinWindowSizing.resizedFrame(
      window.frame,
      to: size,
      within: screen.visibleFrame
    )
    window.setFrame(frame, display: true, animate: false)
    contentContainer.frame = NSRect(origin: .zero, size: size)
    window.updateMousePassthrough()
  }

  private func resize(to size: CGSize, preservingAnchorFraction fraction: CGPoint, animated: Bool) {
    finishEntrance()
    let oldFrame = window.frame
    let frame = QuickAccessPinWindowSizing.resizedFrame(
      oldFrame,
      to: size,
      preservingAnchorFraction: fraction
    )
    window.setFrame(frame, display: true, animate: animated)
    contentContainer.frame = NSRect(origin: .zero, size: size)
    window.updateMousePassthrough()
  }

  private static func loadImage(for item: QuickAccessItem) -> NSImage {
    let access = SandboxFileAccessManager.shared.beginAccessingURL(item.url)
    defer { access.stop() }
    return NSImage(contentsOf: item.url) ?? item.thumbnail
  }
}
