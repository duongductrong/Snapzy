//
//  KeystrokeOverlayWindow.swift
//  Snapzy
//
//  Transparent overlay window that displays a keystroke badge
//  at the bottom-center of the recording area.
//  Captured by ScreenCaptureKit via exceptingWindows so the
//  keystrokes appear in the recorded video.
//

import AppKit
import QuartzCore

@MainActor
final class KeystrokeOverlayWindow: NSWindow {

  private var badgeView: KeystrokeBadgeView?
  private var fadeOutWorkItem: DispatchWorkItem?

  init(recordingRect: CGRect) {
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

    let badge = KeystrokeBadgeView()
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.alphaValue = 0
    contentView.addSubview(badge)

    // Position at bottom-center, 40px from bottom
    NSLayoutConstraint.activate([
      badge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
    ])

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

    // Schedule fade-out after linger
    let workItem = DispatchWorkItem { [weak self] in
      self?.fadeOutBadge()
    }
    fadeOutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
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

  private static let horizontalPadding: CGFloat = 14
  private static let verticalPadding: CGFloat = 8
  private static let cornerRadius: CGFloat = 8
  private static let fontSize: CGFloat = 16

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
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
    bgLayer.cornerRadius = Self.cornerRadius
    layer?.addSublayer(bgLayer)

    // Text layer
    textLayer.font = NSFont.systemFont(ofSize: Self.fontSize, weight: .medium) as CTFont
    textLayer.fontSize = Self.fontSize
    textLayer.foregroundColor = NSColor.white.cgColor
    textLayer.alignmentMode = .center
    textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    textLayer.truncationMode = .none
    layer?.addSublayer(textLayer)
  }

  func updateText(_ text: String) {
    textLayer.string = text

    // Measure text size
    let font = NSFont.systemFont(ofSize: Self.fontSize, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let textSize = (text as NSString).size(withAttributes: attrs)

    let badgeWidth = textSize.width + Self.horizontalPadding * 2
    let badgeHeight = textSize.height + Self.verticalPadding * 2

    // Update own frame (centered via constraints, only size matters)
    let newSize = CGSize(width: badgeWidth, height: badgeHeight)

    // Remove existing width/height constraints
    constraints.filter { $0.firstAttribute == .width || $0.firstAttribute == .height }
      .forEach { removeConstraint($0) }

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: newSize.width),
      heightAnchor.constraint(equalToConstant: newSize.height),
    ])

    // Position layers
    let bounds = CGRect(origin: .zero, size: newSize)
    bgLayer.frame = bounds
    bgLayer.path = CGPath(
      roundedRect: bounds,
      cornerWidth: Self.cornerRadius,
      cornerHeight: Self.cornerRadius,
      transform: nil
    )

    textLayer.frame = CGRect(
      x: Self.horizontalPadding,
      y: Self.verticalPadding - 1,
      width: textSize.width,
      height: textSize.height
    )
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
