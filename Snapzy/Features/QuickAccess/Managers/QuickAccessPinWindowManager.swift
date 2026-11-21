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
  /// Both directions of the flight share one key, so a pin re-shown while its first flight is still
  /// running replaces the animation instead of stacking on it.
  private static let flightMotionKey = "quickAccess.pin.flight"

  /// One flight, precomputed: see `makeFlight()`.
  private struct Flight {
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
  /// Host for the SwiftUI content, sized by the sizing policy once at its resting frame and moved by
  /// nothing else but this controller. The flight scales this view's layer, so the content is never
  /// re-flowed mid-travel.
  private let contentContainer = NSView(frame: .zero)
  /// The flight currently in progress, cleared when it completes. Its frames are the only truth about
  /// where the window is allowed to be while a spring runs.
  private var activeFlight: Flight?
  /// Where the flight is going: a leaving pin closes its window instead of landing in place.
  private var isLeaving = false
  /// Backup completion, in case the spring's completion block never reaches the main thread.
  private var flightLanding: Timer?
  /// A flight outlives the manager's reference to this controller — closing a pin drops it from the
  /// dictionary immediately — so the flight holds the controller itself until it completes.
  private var flightLease: QuickAccessPinWindowController?
  /// The region the flight grows out of and returns to. The card the gesture came from wins over the
  /// captured region: a pin whose resting size matches its capture has nowhere to travel, while the
  /// card sits in a corner and always gives the flight somewhere to come from.
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
    guard let flight = makeFlight() else {
      window.alphaValue = 0
      orderFront()
      fadeIn()
      return
    }
    runFlight(flight, leaving: false)
  }

  func orderFront() {
    window.orderFrontRegardless()
    window.updateMousePassthrough()
  }

  /// Everything a flight needs, decided from where the window sits right now: the wide frame it
  /// travels inside, where the content sits in it, and the transform that puts the content on its
  /// source region. `nil` when there is nothing to fly to or from, or the path cannot be shown.
  private func makeFlight() -> Flight? {
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

    return Flight(
      flightFrame: flightFrame,
      restingFrame: restingFrame,
      containerFrame: containerFrame,
      transform: transform
    )
  }

  /// The content is laid out once, at its resting size, and the compositor scales it along the path;
  /// the window only changes frame at the ends of the travel, which moves the content by nothing at
  /// all. Entering, the pin starts scaled onto its source region and relaxes to identity; leaving runs
  /// the same spring backwards and closes when it settles. One path, one mechanism, both directions.
  private func runFlight(_ flight: Flight, leaving: Bool) {
    isLeaving = leaving
    activeFlight = flight
    // The manager drops a closing pin from its dictionary right away, so a flight has to keep its own
    // controller alive or the window it is still drawing would be deallocated.
    flightLease = self
    window.setFrame(flight.flightFrame, display: false)
    contentContainer.frame = flight.containerFrame
    window.isInFlight = true
    // Applied now rather than on the next pointer move: until then the wide transparent flight window
    // would take the clicks and scrolls aimed at the card it is flying out of.
    window.updateMousePassthrough()
    // The flight window is far larger than the pin, and its native shadow is drawn from the window
    // frame — which would put a soft rectangle around the whole path. The content carries its own
    // shadow inside the margin, so the window goes without one until the flight is over.
    window.hasShadow = false
    window.alphaValue = leaving ? 1 : 0
    window.orderFrontRegardless()

    guard let layer = contentContainer.layer else {
      completeFlight()
      if !leaving { fadeIn() }
      return
    }

    layer.removeAnimation(forKey: Self.flightMotionKey)
    let spring = CASpringAnimation(keyPath: "transform")
    spring.mass = 1
    // The repo's motion vocabulary: springs open at 340/32 and close at the shorter, harder 420/42.
    spring.stiffness = leaving ? 420 : 340
    spring.damping = leaving ? 42 : 32
    let destination = leaving ? flight.transform : CATransform3DIdentity
    spring.fromValue = NSValue(caTransform3D: leaving ? CATransform3DIdentity : flight.transform)
    spring.toValue = NSValue(caTransform3D: destination)
    spring.duration = spring.settlingDuration

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.completeFlight() }
    }
    // A settled spring is taken off the layer, which hands the drawing back to the layer's own
    // transform. Leaving that at identity made an exit spend its last frames redrawing the pin full
    // size again before the window closed.
    layer.transform = destination
    layer.add(spring, forKey: Self.flightMotionKey)
    CATransaction.commit()
    scheduleLanding(after: spring.settlingDuration)

    if leaving {
      // A pin that fades the whole way dissolves instead of leaving, so opacity only drops once the
      // travel is nearly done and the picture is small inside the region it disappears into.
      let hold = max(0, spring.settlingDuration - 0.14)
      DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
        MainActor.assumeIsolated {
          guard self?.isLeaving == true else { return }
          self?.fadeOut()
        }
      }
    } else {
      fadeIn()
    }
  }

  /// A timer registered in the common run-loop modes still fires while a menu is tracking, so a pin
  /// gestured from the Quick Access menu cannot be left stranded in its flight frame if the
  /// compositor's completion block is dropped.
  private func scheduleLanding(after seconds: TimeInterval) {
    let timer = Timer(timeInterval: seconds + 0.35, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.completeFlight() }
    }
    RunLoop.main.add(timer, forMode: .common)
    flightLanding = timer
  }

  /// Resolve a flight: a leaving pin closes, an arriving one lands back at its resting frame with the
  /// content filling it. Anything that measures the window — a resize, a zoom-mode change — has to do
  /// this first, because mid-flight the window is a wide transparent frame rather than the pin.
  func completeFlight() {
    guard let flight = activeFlight else { return }
    let wasLeaving = isLeaving
    activeFlight = nil
    isLeaving = false
    flightLanding?.invalidate()
    flightLanding = nil
    contentContainer.layer?.removeAnimation(forKey: Self.flightMotionKey)
    window.isInFlight = false
    if wasLeaving {
      window.close()
    } else {
      window.hasShadow = true
      window.setFrame(flight.restingFrame, display: true)
      contentContainer.frame = NSRect(origin: .zero, size: flight.restingFrame.size)
      window.updateMousePassthrough()
    }
    flightLease = nil
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

  /// Dismiss the pin along the path it came from. A close that arrives mid-entrance lands the pin
  /// first, so the exit always starts from the resting frame rather than from somewhere inside the
  /// travel.
  func close() {
    // A second close while a pin is already on its way out would land it and send it off again, which
    // is exactly the flicker a mashed Esc or a double click on the close button would show.
    guard !isLeaving else { return }
    completeFlight()
    flightLease = self
    guard let flight = makeFlight() else {
      fadeOutAndClose()
      return
    }
    runFlight(flight, leaving: true)
  }

  /// The fallback for a pin with nowhere to fly back to, which includes Reduce Motion: fade in place
  /// on the real frame, then close.
  private func fadeOutAndClose() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = SnapzyMotionPreferences.shared.reduceMotion ? 0.18 : 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      guard let self else { return }
      self.window.close()
      self.flightLease = nil
    })
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
    // Layer-backed so a flight can scale this view's own layer instead of resizing the window.
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

  /// The tail of a leaving flight, started once the pin has nearly reached the region it vanishes
  /// into. Fading the whole way would read as a dissolve instead of the pin going home.
  private func fadeOut() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      window.animator().alphaValue = 0
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
    // This controller owns every frame the pin takes, so the host has no size to report to the
    // window. Left on, its constraint pass re-measures the root on every update and, while a flight
    // moves the container inside a larger window, keeps invalidating its own transform until AppKit
    // throws for exceeding the window's Update Constraints pass limit.
    hostingView.sizingOptions = []
    hostingView.frame = NSRect(origin: .zero, size: size)
    return hostingView
  }

  private func handleUserClose() {
    QuickAccessManager.shared.setWindowOpen(id: id, isOpen: false)
    self.close()
    self.onUserClose?(self.id)
  }

  private func resize(to size: CGSize, animated: Bool) {
    completeFlight()
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
    completeFlight()
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
    completeFlight()
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
