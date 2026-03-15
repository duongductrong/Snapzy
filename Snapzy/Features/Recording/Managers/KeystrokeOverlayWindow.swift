//
//  KeystrokeOverlayWindow.swift
//  Snapzy
//
//  Transparent overlay window that displays a keystroke badge
//  within the recording area, positioned according to user settings.
//  Captured by ScreenCaptureKit via exceptingWindows so the
//  keystrokes appear in the recorded video.
//

import AppKit
import QuartzCore

@MainActor
final class KeystrokeOverlayWindow: NSWindow {

  private var badgeView: KeystrokeBadgeView?
  private var fadeOutWorkItem: DispatchWorkItem?
  private let config: KeystrokeOverlayConfiguration

  init(recordingRect: CGRect, configuration: KeystrokeOverlayConfiguration = KeystrokeOverlayConfiguration()) {
    self.config = configuration
    super.init(
      contentRect: recordingRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    setupBadgeView(recordingRect: recordingRect)
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

  private func setupBadgeView(recordingRect: CGRect) {
    guard let contentView else { return }

    let badge = KeystrokeBadgeView(fontSize: config.fontSize)
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.alphaValue = 0
    contentView.addSubview(badge)

    // Position based on configuration
    let offset = config.edgeOffset
    var constraints: [NSLayoutConstraint] = []

    switch config.position {
    case .bottomCenter:
      constraints = [
        badge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -offset),
      ]
    case .bottomLeft:
      constraints = [
        badge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: offset),
        badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -offset),
      ]
    case .bottomRight:
      constraints = [
        badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -offset),
        badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -offset),
      ]
    case .topCenter:
      constraints = [
        badge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: offset),
      ]
    case .topLeft:
      constraints = [
        badge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: offset),
        badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: offset),
      ]
    case .topRight:
      constraints = [
        badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -offset),
        badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: offset),
      ]
    }

    NSLayoutConstraint.activate(constraints)
    badgeView = badge
  }

  // MARK: - Public

  var overlayWindowID: CGWindowID {
    CGWindowID(windowNumber)
  }

  func updateRecordingRect(_ rect: CGRect) {
    setFrame(rect, display: true)
  }

  /// Display a keystroke string in the badge with animation
  func showKeystroke(_ text: String) {
    guard let badge = badgeView else { return }

    // Cancel pending fade-out
    fadeOutWorkItem?.cancel()

    badge.updateText(text)

    if badge.alphaValue < 1 {
      // Fade in
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        badge.animator().alphaValue = 1
      }
      // Scale in
      badge.layer?.removeAnimation(forKey: "scaleIn")
      let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
      scaleAnim.fromValue = 0.9
      scaleAnim.toValue = 1.0
      scaleAnim.duration = 0.15
      scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
      scaleAnim.fillMode = .forwards
      scaleAnim.isRemovedOnCompletion = true
      badge.layer?.add(scaleAnim, forKey: "scaleIn")
    } else {
      // Already visible — pulse to indicate repeat
      badge.layer?.removeAnimation(forKey: "pulse")
      let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
      pulse.values = [1.0, 1.06, 1.0]
      pulse.keyTimes = [0, 0.4, 1.0]
      pulse.duration = 0.12
      pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      badge.layer?.add(pulse, forKey: "pulse")
    }

    // Schedule fade-out after configurable linger duration
    let workItem = DispatchWorkItem { [weak self] in
      self?.fadeOutBadge()
    }
    fadeOutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + config.displayDuration, execute: workItem)
  }

  private func fadeOutBadge() {
    guard let badge = badgeView else { return }

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.4
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      badge.animator().alphaValue = 0
    }
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// MARK: - Keystroke Badge View

/// A rounded-rect pill that displays keystroke text
private final class KeystrokeBadgeView: NSView {

  private let textLayer = CATextLayer()
  private let bgLayer = CAShapeLayer()

  private let badgeFontSize: CGFloat
  private let horizontalPadding: CGFloat = 14
  private let verticalPadding: CGFloat = 8
  private let badgeCornerRadius: CGFloat = 8

  /// Cached font to avoid repeated allocation
  private let cachedFont: NSFont

  /// Stored size constraints to avoid filtering all constraints on update
  private var widthConstraint: NSLayoutConstraint?
  private var heightConstraint: NSLayoutConstraint?

  init(fontSize: CGFloat = 16) {
    self.badgeFontSize = fontSize
    self.cachedFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    setupLayers()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  private func setupLayers() {
    // Background layer
    bgLayer.fillColor = NSColor(white: 0.12, alpha: 0.85).cgColor
    bgLayer.cornerRadius = badgeCornerRadius
    layer?.addSublayer(bgLayer)

    // Text layer
    textLayer.font = cachedFont as CTFont
    textLayer.fontSize = badgeFontSize
    textLayer.foregroundColor = NSColor.white.cgColor
    textLayer.alignmentMode = .center
    textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    textLayer.truncationMode = .none
    layer?.addSublayer(textLayer)
  }

  func updateText(_ text: String) {
    // Disable implicit layer animations during resize
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    textLayer.string = text

    // Measure text size using cached font
    let attrs: [NSAttributedString.Key: Any] = [.font: cachedFont]
    let textSize = (text as NSString).size(withAttributes: attrs)

    let badgeWidth = textSize.width + horizontalPadding * 2
    let badgeHeight = textSize.height + verticalPadding * 2

    // Update stored constraints (or create if first time)
    if let wc = widthConstraint, let hc = heightConstraint {
      wc.constant = badgeWidth
      hc.constant = badgeHeight
    } else {
      let wc = widthAnchor.constraint(equalToConstant: badgeWidth)
      let hc = heightAnchor.constraint(equalToConstant: badgeHeight)
      NSLayoutConstraint.activate([wc, hc])
      widthConstraint = wc
      heightConstraint = hc
    }

    // Position layers
    let bounds = CGRect(origin: .zero, size: CGSize(width: badgeWidth, height: badgeHeight))
    bgLayer.frame = bounds
    bgLayer.path = CGPath(
      roundedRect: bounds,
      cornerWidth: badgeCornerRadius,
      cornerHeight: badgeCornerRadius,
      transform: nil
    )

    textLayer.frame = CGRect(
      x: horizontalPadding,
      y: verticalPadding - 1,
      width: textSize.width,
      height: textSize.height
    )

    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    // AppKit layer-backed views default to anchorPoint (0, 0).
    // Set to center so scale/pulse animations originate from the badge center.
    // position must be in the superlayer's coordinate space (frame, not bounds).
    guard let layer else { return }
    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    layer.position = CGPoint(x: frame.midX, y: frame.midY)
  }

  override var isFlipped: Bool { true }
}
