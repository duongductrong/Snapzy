//
//  MouseClickHighlightWindow.swift
//  Snapzy
//
//  Transparent overlay window that draws ripple wave effects at click positions
//  and a persistent follow-circle while the mouse is held down.
//  Captured by ScreenCaptureKit via exceptingWindows so the effect
//  appears in the recorded video.
//

import AppKit
import QuartzCore

@MainActor
final class MouseClickHighlightWindow: NSWindow {

  /// Persistent circle that follows the cursor while mouse is held
  private var holdCircleView: HoldCircleView?
  private let config: MouseHighlightConfiguration

  init(recordingRect: CGRect, configuration: MouseHighlightConfiguration = MouseHighlightConfiguration()) {
    self.config = configuration
    super.init(
      contentRect: recordingRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
  }

  // MARK: - Configuration

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isReleasedWhenClosed = false
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    ignoresMouseEvents = true
  }

  // MARK: - Public

  var overlayWindowID: CGWindowID {
    CGWindowID(windowNumber)
  }

  func updateRecordingRect(_ rect: CGRect) {
    setFrame(rect, display: true)
  }

  /// On mouse-down: spawn ripple waves and show hold circle
  func showClickEffect(at screenPoint: NSPoint) {
    guard let contentView else { return }

    let viewPoint = viewPosition(from: screenPoint)

    // Spawn expanding ripple rings
    let count = config.rippleCount
    let delayStep = config.animationDuration > 0 ? min(0.12, config.animationDuration / Double(max(count, 1)) * 0.5) : 0.12
    for i in 0..<count {
      let delay = CFTimeInterval(i) * delayStep
      let ripple = RippleRingView(center: viewPoint, configuration: config)
      contentView.addSubview(ripple)
      ripple.animateExpand(delay: delay) { [weak ripple] in
        ripple?.removeFromSuperview()
      }
    }

    // Show persistent hold circle
    holdCircleView?.removeFromSuperview()
    let hold = HoldCircleView(center: viewPoint, configuration: config)
    contentView.addSubview(hold)
    hold.animateIn()
    holdCircleView = hold
  }

  /// While mouse is held and dragged, move the hold circle to follow cursor
  func moveClickEffect(to screenPoint: NSPoint) {
    guard let hold = holdCircleView else { return }
    let viewPoint = viewPosition(from: screenPoint)
    hold.updateCenter(viewPoint)
  }

  /// On mouse-up: fade out and remove the hold circle
  func dismissClickEffect() {
    guard let hold = holdCircleView else { return }
    holdCircleView = nil
    hold.animateOut { [weak hold] in
      hold?.removeFromSuperview()
    }
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  // MARK: - Helpers

  private func viewPosition(from screenPoint: NSPoint) -> NSPoint {
    let windowPoint = convertPoint(fromScreen: screenPoint)
    return NSPoint(x: windowPoint.x, y: windowPoint.y)
  }
}

// MARK: - Ripple Ring View

/// A single hollow circular ring that expands outward and fades.
private final class RippleRingView: NSView {

  private let ringLayer = CAShapeLayer()
  private let maxDiameter: CGFloat
  private let ringWidth: CGFloat
  private let duration: CFTimeInterval
  private let strokeColor: CGColor

  init(center: NSPoint, configuration: MouseHighlightConfiguration) {
    self.maxDiameter = configuration.highlightSize
    self.ringWidth = configuration.ringWidth
    self.duration = configuration.animationDuration
    self.strokeColor = configuration.highlightColor
      .withAlphaComponent(configuration.highlightOpacity).cgColor

    let size = maxDiameter
    let frame = CGRect(
      x: center.x - size / 2,
      y: center.y - size / 2,
      width: size,
      height: size
    )
    super.init(frame: frame)

    wantsLayer = true
    layer?.masksToBounds = false
    setupRingLayer()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  private func setupRingLayer() {
    let bounds = CGRect(origin: .zero, size: CGSize(width: maxDiameter, height: maxDiameter))
    let inset = ringWidth / 2
    let path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)

    ringLayer.path = path
    ringLayer.fillColor = nil
    ringLayer.strokeColor = strokeColor
    ringLayer.lineWidth = ringWidth
    ringLayer.frame = bounds

    // Start small and invisible
    ringLayer.opacity = 0
    ringLayer.transform = CATransform3DMakeScale(0.15, 0.15, 1)

    layer?.addSublayer(ringLayer)
  }

  func animateExpand(delay: CFTimeInterval, completion: @escaping () -> Void) {
    CATransaction.begin()
    CATransaction.setCompletionBlock(completion)

    // Scale: small → full
    let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
    scaleAnim.fromValue = 0.15
    scaleAnim.toValue = 1.0
    scaleAnim.duration = duration
    scaleAnim.beginTime = CACurrentMediaTime() + delay
    scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    scaleAnim.fillMode = .both
    scaleAnim.isRemovedOnCompletion = false

    // Opacity: appear then fade
    let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
    opacityAnim.values = [0.0, 0.8, 0.0]
    opacityAnim.keyTimes = [0, 0.25, 1.0]
    opacityAnim.duration = duration
    opacityAnim.beginTime = CACurrentMediaTime() + delay
    opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    opacityAnim.fillMode = .both
    opacityAnim.isRemovedOnCompletion = false

    ringLayer.add(scaleAnim, forKey: "rippleScale")
    ringLayer.add(opacityAnim, forKey: "rippleFade")

    CATransaction.commit()
  }
}

// MARK: - Hold Circle View

/// A persistent hollow circle that follows the cursor while the mouse is held down.
private final class HoldCircleView: NSView {

  private let circleDiameter: CGFloat
  private let ringLayer = CAShapeLayer()

  init(center: NSPoint, configuration: MouseHighlightConfiguration) {
    self.circleDiameter = configuration.holdCircleSize
    let ringWidth = configuration.ringWidth

    let size = circleDiameter
    let frame = CGRect(
      x: center.x - size / 2,
      y: center.y - size / 2,
      width: size,
      height: size
    )
    super.init(frame: frame)

    wantsLayer = true
    layer?.masksToBounds = false
    setupRingLayer(ringWidth: ringWidth, color: configuration.highlightColor.withAlphaComponent(configuration.highlightOpacity))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  private func setupRingLayer(ringWidth: CGFloat, color: NSColor) {
    let bounds = CGRect(origin: .zero, size: CGSize(width: circleDiameter, height: circleDiameter))
    let inset = ringWidth / 2
    let path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)

    ringLayer.path = path
    ringLayer.fillColor = nil
    ringLayer.strokeColor = color.cgColor
    ringLayer.lineWidth = ringWidth
    ringLayer.frame = bounds

    ringLayer.opacity = 0
    ringLayer.transform = CATransform3DMakeScale(0.5, 0.5, 1)

    layer?.addSublayer(ringLayer)
  }

  func updateCenter(_ point: NSPoint) {
    // Disable implicit animations during rapid drag updates
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let size = circleDiameter
    frame = CGRect(
      x: point.x - size / 2,
      y: point.y - size / 2,
      width: size,
      height: size
    )

    CATransaction.commit()
  }

  func animateIn() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
    scaleAnim.fromValue = 0.5
    scaleAnim.toValue = 1.0
    scaleAnim.duration = 0.15
    scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    scaleAnim.fillMode = .forwards
    scaleAnim.isRemovedOnCompletion = false

    let opacityAnim = CABasicAnimation(keyPath: "opacity")
    opacityAnim.fromValue = 0.0
    opacityAnim.toValue = 1.0
    opacityAnim.duration = 0.15
    opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    opacityAnim.fillMode = .forwards
    opacityAnim.isRemovedOnCompletion = false

    ringLayer.add(scaleAnim, forKey: "holdScaleIn")
    ringLayer.add(opacityAnim, forKey: "holdFadeIn")

    CATransaction.commit()
  }

  func animateOut(completion: @escaping () -> Void) {
    CATransaction.begin()
    CATransaction.setCompletionBlock(completion)

    let opacityAnim = CABasicAnimation(keyPath: "opacity")
    opacityAnim.fromValue = 1.0
    opacityAnim.toValue = 0.0
    opacityAnim.duration = 0.3
    opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    opacityAnim.fillMode = .forwards
    opacityAnim.isRemovedOnCompletion = false

    ringLayer.add(opacityAnim, forKey: "holdFadeOut")

    CATransaction.commit()
  }
}
