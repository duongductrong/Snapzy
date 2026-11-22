//
//  SnapzyOnboardingWindowController.swift
//  Snapzy
//
//  Window controller hosting the borderless Dark Liquid Glass onboarding window.
//

import AppKit
import SwiftUI

@MainActor
final class SnapzyOnboardingWindowController: NSObject, NSWindowDelegate {
  static let shared = SnapzyOnboardingWindowController()

  private var window: NSWindow?
  private var finaleOverlay: OnboardingFinaleOverlayController?
  var onClose: (() -> Void)?

  private var isPresenting = false
  private var isEnforcing = false

  var isVisible: Bool { window?.isVisible ?? false }

  func show() {
    NSApp.setActivationPolicy(.regular)
    activate()

    let window = window ?? makeWindow()
    self.window = window

    let isFirstPresentation = !window.isVisible
    if isFirstPresentation {
      window.setFrame(Self.preferredFrame(), display: false)
      window.alphaValue = SnapzyMotionPreferences.shared.reduceMotion ? 1 : 0
    }

    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()

    fitWithinScreen(window)

    if isFirstPresentation {
      presentAnimated(window)
    }

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard let window = self.window else { return }
      window.makeKeyAndOrderFront(nil)
      self.activate()
    }
  }

  func close(launchIconWindowFrame: CGRect? = nil) {
    guard let window else { return }
    if let launchIconWindowFrame {
      dismissWithFinale(window, iconWindowFrame: launchIconWindowFrame)
    } else {
      dismissAnimated(window)
    }
  }

  // MARK: - Geometry & Clamping

  private static func visibleFrame(of screen: NSScreen?) -> NSRect {
    (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
  }

  private static func sizeLimits(on screen: NSScreen?) -> (min: NSSize, max: NSSize) {
    let visible = visibleFrame(of: screen)
    let inset = SnapzyOnboardingMetrics.screenMargin * 2
    let ceiling = NSSize(
      width: min(SnapzyOnboardingMetrics.maxSize.width, max(visible.width - inset, 1)),
      height: min(SnapzyOnboardingMetrics.maxSize.height, max(visible.height - inset, 1))
    )
    let floor = NSSize(
      width: min(SnapzyOnboardingMetrics.minSize.width, ceiling.width),
      height: min(SnapzyOnboardingMetrics.minSize.height, ceiling.height)
    )
    return (floor, ceiling)
  }

  private static func preferredFrame(on screen: NSScreen? = nil) -> NSRect {
    let visible = visibleFrame(of: screen)
    let limits = sizeLimits(on: screen)

    let size = NSSize(
      width: min(max(visible.width * SnapzyOnboardingMetrics.screenFill, limits.min.width), limits.max.width),
      height: min(max(visible.height * SnapzyOnboardingMetrics.screenFill, limits.min.height), limits.max.height)
    )

    return NSRect(
      x: (visible.midX - size.width / 2).rounded(),
      y: (visible.midY - size.height / 2).rounded(),
      width: size.width.rounded(),
      height: size.height.rounded()
    )
  }

  private func clamped(_ size: NSSize, on screen: NSScreen?) -> NSSize {
    let limits = Self.sizeLimits(on: screen)
    return NSSize(
      width: min(max(size.width, limits.min.width), limits.max.width),
      height: min(max(size.height, limits.min.height), limits.max.height)
    )
  }

  private func fitWithinScreen(_ window: NSWindow) {
    let size = clamped(window.frame.size, on: window.screen)
    guard size != window.frame.size else { return }
    let visible = Self.visibleFrame(of: window.screen)
    window.setFrame(
      NSRect(
        x: (visible.midX - size.width / 2).rounded(),
        y: (visible.midY - size.height / 2).rounded(),
        width: size.width,
        height: size.height
      ),
      display: true
    )
  }

  private func enforceSizeLimits(on window: NSWindow) {
    let size = clamped(window.frame.size, on: window.screen)
    guard size != window.frame.size else { return }

    var frame = window.frame
    frame.origin.y += frame.height - size.height
    frame.size = size
    window.setFrame(Self.nudgedOnScreen(frame, on: window.screen), display: true)
  }

  private static func nudgedOnScreen(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
    let visible = visibleFrame(of: screen)
    var frame = frame
    frame.origin.x = min(max(frame.minX, visible.minX), max(visible.maxX - frame.width, visible.minX))
    frame.origin.y = min(max(frame.minY, visible.minY), max(visible.maxY - frame.height, visible.minY))
    return frame
  }

  // MARK: - Presentation & Animation

  private func presentAnimated(_ window: NSWindow) {
    guard !SnapzyMotionPreferences.shared.reduceMotion else {
      window.alphaValue = 1
      return
    }

    let target = window.frame
    let start = clamped(
      NSSize(width: target.width * 0.98, height: target.height * 0.98),
      on: window.screen
    )
    isPresenting = true
    window.setFrame(
      NSRect(
        x: (target.midX - start.width / 2).rounded(),
        y: (target.midY - start.height / 2).rounded(),
        width: start.width,
        height: start.height
      ),
      display: false
    )

    NSAnimationContext.runAnimationGroup { context in
      context.duration = SnapzyMotionSpec.settle.duration
      context.timingFunction = SnapzyMotionSpec.glide.timingFunction
      window.animator().alphaValue = 1
      window.animator().setFrame(target, display: true)
    } completionHandler: { [weak self] in
      window.alphaValue = 1
      window.setFrame(target, display: false)
      MainActor.assumeIsolated { self?.isPresenting = false }
    }
  }

  private func dismissWithFinale(_ window: NSWindow, iconWindowFrame: CGRect) {
    let windowFrame = window.frame
    let startScreenCenter = CGPoint(
      x: windowFrame.minX + iconWindowFrame.midX,
      y: windowFrame.maxY - iconWindowFrame.midY
    )

    let statusFrame = AppStatusBarController.shared.statusItemScreenFrame
    let targetScreen = Self.screenContaining(frame: statusFrame)
      ?? window.screen
      ?? NSScreen.main
      ?? NSScreen.screens.first

    if let targetScreen {
      let screenFrame = targetScreen.frame
      let menuBarHeight = max(24, screenFrame.maxY - targetScreen.visibleFrame.maxY)
      let targetMenuBarCenter = statusFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
        ?? CGPoint(x: screenFrame.maxX - 240, y: screenFrame.maxY - menuBarHeight * 0.5)

      let overlay = OnboardingFinaleOverlayController(
        screen: targetScreen,
        startScreenCenter: startScreenCenter,
        targetMenuBarCenter: targetMenuBarCenter,
        menuBarHeight: menuBarHeight,
        reduceMotion: SnapzyMotionPreferences.shared.reduceMotion
      ) { [weak self] in
        self?.finaleOverlay = nil
      }
      self.finaleOverlay = overlay
      overlay.present()
    }

    // Dissolve the onboarding window cleanly right as the desktop overlay picks up the icon
    guard !SnapzyMotionPreferences.shared.reduceMotion else {
      window.close()
      return
    }

    let endSize = NSSize(width: windowFrame.width * 0.975, height: windowFrame.height * 0.975)
    let endFrame = NSRect(
      x: (windowFrame.midX - endSize.width * 0.5).rounded(),
      y: (windowFrame.midY - endSize.height * 0.5).rounded(),
      width: endSize.width.rounded(),
      height: endSize.height.rounded()
    )

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.28
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
      window.animator().alphaValue = 0
      window.animator().setFrame(endFrame, display: true)
    } completionHandler: { [weak self] in
      window.close()
      window.alphaValue = 1
      MainActor.assumeIsolated {
        self?.window = nil
        NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: window)
      }
    }
  }

  private static func screenContaining(frame: CGRect?) -> NSScreen? {
    guard let frame else { return nil }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    return NSScreen.screens.first { $0.frame.contains(center) }
  }

  private func dismissAnimated(_ window: NSWindow) {
    guard !SnapzyMotionPreferences.shared.reduceMotion else {
      window.close()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = SnapzyMotionSpec.contentOut.duration + 0.06
      context.timingFunction = SnapzyMotionSpec.contentOut.timingFunction
      window.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      window.close()
      window.alphaValue = 1
      MainActor.assumeIsolated {
        self?.window = nil
        NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: window)
      }
    }
  }

  // MARK: - Window Construction

  private func activate() {
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeWindow() -> NSWindow {
    let created = SnapzyOnboardingPanel(
      contentRect: Self.preferredFrame(),
      styleMask: [.borderless, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    created.title = L10n.Splash.welcomeTitle
    created.delegate = self
    created.isReleasedWhenClosed = false
    created.level = .normal
    created.collectionBehavior = [.fullScreenAuxiliary]
    fitWithinScreen(created)

    created.isOpaque = false
    created.backgroundColor = .clear
    created.hasShadow = true
    created.isMovableByWindowBackground = true
    created.appearance = NSAppearance(named: .darkAqua)

    let hosting = NSHostingView(
      rootView: SnapzyOnboardingView(onDismiss: { [weak self] launchIconWindowFrame in
        self?.close(launchIconWindowFrame: launchIconWindowFrame)
      })
      .environmentObject(OnboardingLocalizationController())
    )
    hosting.sizingOptions = [.minSize, .maxSize]

    hosting.wantsLayer = true
    hosting.layer?.cornerRadius = SnapzyOnboardingMetrics.windowRadius
    hosting.layer?.cornerCurve = .continuous
    hosting.layer?.masksToBounds = true
    hosting.layer?.drawsAsynchronously = true

    created.contentView = hosting
    return created
  }

  // MARK: - NSWindowDelegate

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    clamped(frameSize, on: sender.screen)
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    enforceSizeLimits(on: window)
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
          !isPresenting, !isEnforcing, !window.inLiveResize else { return }
    isEnforcing = true
    Task { @MainActor [weak self] in
      self?.enforceSizeLimits(on: window)
      self?.isEnforcing = false
    }
  }

  func windowDidChangeScreen(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    fitWithinScreen(window)
  }

  func windowWillClose(_ notification: Notification) {
    MainActor.assumeIsolated {
      self.window = nil
      let closingWindow = notification.object as? NSWindow
      NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: closingWindow)
      self.onClose?()
    }
  }
}

private final class SnapzyOnboardingPanel: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

// MARK: - Celebratory Desktop Finale (Menu Bar Ascent & Liquid Glass Arrival Pill)

@MainActor
private final class OnboardingFinaleOverlayController {
  private var panel: NSPanel?
  private let screen: NSScreen
  private let startScreenCenter: CGPoint
  private let targetMenuBarCenter: CGPoint
  private let menuBarHeight: CGFloat
  private let reduceMotion: Bool
  private let onFinish: () -> Void

  init(
    screen: NSScreen,
    startScreenCenter: CGPoint,
    targetMenuBarCenter: CGPoint,
    menuBarHeight: CGFloat,
    reduceMotion: Bool,
    onFinish: @escaping () -> Void
  ) {
    self.screen = screen
    self.startScreenCenter = startScreenCenter
    self.targetMenuBarCenter = targetMenuBarCenter
    self.menuBarHeight = menuBarHeight
    self.reduceMotion = reduceMotion
    self.onFinish = onFinish
  }

  func present() {
    let screenFrame = screen.frame
    let startLocal = CGPoint(
      x: startScreenCenter.x - screenFrame.minX,
      y: screenFrame.maxY - startScreenCenter.y
    )
    let targetLocal = CGPoint(
      x: targetMenuBarCenter.x - screenFrame.minX,
      y: screenFrame.maxY - targetMenuBarCenter.y
    )

    let overlayPanel = OnboardingFinalePanel(
      contentRect: screenFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    overlayPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    overlayPanel.isOpaque = false
    overlayPanel.backgroundColor = .clear
    overlayPanel.hasShadow = false
    overlayPanel.ignoresMouseEvents = true
    overlayPanel.isReleasedWhenClosed = false
    overlayPanel.appearance = NSAppearance(named: .darkAqua)

    let hosting = NSHostingView(
      rootView: OnboardingFinaleOverlayView(
        screenSize: screenFrame.size,
        startPoint: startLocal,
        targetPoint: targetLocal,
        menuBarHeight: menuBarHeight,
        reduceMotion: reduceMotion
      ) { [weak self] in
        self?.teardown()
      }
    )
    hosting.wantsLayer = true
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
    hosting.layer?.drawsAsynchronously = true
    overlayPanel.contentView = hosting

    overlayPanel.orderFrontRegardless()
    self.panel = overlayPanel
  }

  private func teardown() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    onFinish()
  }
}

private final class OnboardingFinalePanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private struct OnboardingFinaleOverlayView: View {
  let screenSize: CGSize
  let startPoint: CGPoint
  let targetPoint: CGPoint
  let menuBarHeight: CGFloat
  let reduceMotion: Bool
  let onComplete: () -> Void

  @State private var flightProgress: CGFloat = 0
  @State private var iconOpacity: Double = 1
  @State private var ripplePrimary: CGFloat = 0
  @State private var rippleEcho: CGFloat = 0
  @State private var pillVisible = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.clear

      // Single crisp optical precision ripple on menu bar dock (zero neon glow, zero confetti)
      if !reduceMotion {
        dockRippleRing(progress: ripplePrimary, maxDiameter: 54, lineWidth: 1.25, peakOpacity: 0.72)
          .position(targetPoint)

        dockRippleRing(progress: rippleEcho, maxDiameter: 36, lineWidth: 0.9, peakOpacity: 0.44)
          .position(targetPoint)

        // Ascending Snapzy icon gliding across the real macOS desktop into the menu bar
        Color.clear
          .modifier(FinaleIconFlightModifier(
            progress: flightProgress,
            startPoint: startPoint,
            targetPoint: targetPoint
          ))
          .opacity(iconOpacity)
      }

      // Native macOS Dark Liquid Glass Arrival Pill anchored directly beneath Snapzy's menu bar icon
      menuBarArrivalPill
        .position(
          x: min(max(targetPoint.x, 176), screenSize.width - 176),
          y: menuBarHeight + 31
        )
        .opacity(pillVisible ? 1 : 0)
        .scaleEffect(reduceMotion ? 1.0 : (pillVisible ? 1.0 : 0.94))
        .offset(y: reduceMotion ? 0 : (pillVisible ? 0 : -10))
        .animation(
          reduceMotion
            ? .easeInOut(duration: 0.22)
            : .spring(response: 0.42, dampingFraction: 0.82),
          value: pillVisible
        )
    }
    .frame(width: screenSize.width, height: screenSize.height)
    .environment(\.colorScheme, .dark)
    .task {
      await runChoreography()
    }
  }

  private func dockRippleRing(
    progress: CGFloat,
    maxDiameter: CGFloat,
    lineWidth: CGFloat,
    peakOpacity: Double
  ) -> some View {
    let clamped = max(0, min(1, progress))
    let diameter = 14 + (maxDiameter - 14) * clamped
    let opacity = clamped > 0.001 ? peakOpacity * Double(pow(1 - clamped, 1.5)) : 0
    return Circle()
      .strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(opacity),
            Color(red: 0.36, green: 0.56, blue: 1.0).opacity(opacity * 0.85),
          ],
          startPoint: .top,
          endPoint: .bottom
        ),
        lineWidth: lineWidth
      )
      .frame(width: diameter, height: diameter)
  }

  private var menuBarArrivalPill: some View {
    let shape = Capsule(style: .continuous)
    return HStack(spacing: 10) {
      Image(nsImage: SnapzyOnboardingIconCache.appIcon)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 22, height: 22)
        // radius-lint:allow — clips the 22pt app icon bitmap to match macOS icon curvature
        .clipShape(Radius.rect(Radius.controlXS))

      HStack(spacing: 6) {
        Text("Snapzy")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(Color.white)

        Text("·")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.36))

        Text(L10n.Onboarding.completionAreaCaptureTitle)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.76))
      }

      SnapzyKeycapChip(label: "⇧⌘4", emphasis: true)
    }
    .padding(.leading, 10)
    .padding(.trailing, 12)
    .frame(height: 40)
    .background {
      ZStack {
        shape.fill(.ultraThinMaterial)
        shape.fill(Color.black.opacity(0.36))
      }
    }
    .overlay {
      shape.strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(0.24),
            Color.white.opacity(0.07),
          ],
          startPoint: .top,
          endPoint: .bottom
        ),
        lineWidth: 0.5
      )
    }
    .shadow(color: Color.black.opacity(0.34), radius: 18, y: 8)
    .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)
    .fixedSize()
  }

  @MainActor
  private func runChoreography() async {
    if reduceMotion {
      pillVisible = true
      try? await Task.sleep(for: .milliseconds(2100))
      pillVisible = false
      try? await Task.sleep(for: .milliseconds(260))
      onComplete()
      return
    }

    // Beat 1: Silky 120fps arc ascent from the onboarding window directly into the live menu bar icon
    withAnimation(.timingCurve(0.22, 0.0, 0.10, 1.0, duration: 0.70)) {
      flightProgress = 1.0
    }

    // Beat 2 (680ms — synced with Beat 2 crystalline G5-D6 chime at 900ms total):
    // Dock into the real menu bar icon with a crisp single optical ripple
    try? await Task.sleep(for: .milliseconds(670))
    withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.58)) {
      ripplePrimary = 1.0
    }
    withAnimation(.easeOut(duration: 0.12)) {
      iconOpacity = 0
    }

    try? await Task.sleep(for: .milliseconds(65))
    withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.52)) {
      rippleEcho = 1.0
    }

    // Beat 3: Native Dark Liquid Glass arrival pill drops right beneath the live menu bar icon
    pillVisible = true

    try? await Task.sleep(for: .milliseconds(2500))
    pillVisible = false

    try? await Task.sleep(for: .milliseconds(420))
    onComplete()
  }
}

/// Pure GPU 120fps curved ascent of the 60.5pt Snapzy app icon straight into the 16pt menu bar mark.
private struct FinaleIconFlightModifier: ViewModifier, Animatable {
  var progress: CGFloat
  let startPoint: CGPoint
  let targetPoint: CGPoint

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let t = max(0, min(1, progress))
    let arc = sin(t * .pi)

    // Graceful buoyant flight arc toward the menu bar icon (zero abrupt corner turns)
    let x = startPoint.x + (targetPoint.x - startPoint.x) * t + 34 * arc
    let y = startPoint.y + (targetPoint.y - startPoint.y) * t - 26 * arc

    let startSize: CGFloat = 60.5
    let endSize: CGFloat = 18.0
    let currentSize = startSize + (endSize - startSize) * t

    let startRadius: CGFloat = Radius.card * 1.08
    let endRadius: CGFloat = 5.5
    let currentRadius = startRadius + (endRadius - startRadius) * t
    let shape = RoundedRectangle(cornerRadius: currentRadius, style: .continuous) // radius-lint:allow — continuous flight interpolation between Radius.card and menu bar icon

    // Cross-blend cleanly from the blue app icon into the crisp white template menu bar mark
    let markBlend = min(1.0, max(0.0, Double((t - 0.68) / 0.28)))
    let iconAlpha = 1.0 - markBlend

    ZStack {
      if iconAlpha > 0.005 {
        Image(nsImage: SnapzyOnboardingIconCache.appIcon)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(width: currentSize, height: currentSize)
          .clipShape(shape)
          // Constant radius + alpha-only modulation keeps 120fps free of per-frame blur rebuilds
          .shadow(
            color: Color.black.opacity(0.30 * (1.0 - Double(t) * 0.75)),
            radius: 14,
            y: 7
          )
          .opacity(iconAlpha)
      }

      if markBlend > 0.005 {
        Image("WelcomeMark")
          .renderingMode(.template)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .foregroundStyle(Color.white)
          .frame(width: 15, height: 15)
          .opacity(markBlend)
      }
    }
    .position(x: x, y: y)
  }
}
