//
//  InlineAreaMagnifierHostView.swift
//  Snapzy
//
//  Hosts the shared `AreaSelectionMagnifier` inside the SwiftUI-based inline area annotate
//  flow, so screenshot-and-annotate (⌘⇧7) renders the exact same magnifier/color-picker as
//  plain area screenshot (⌘⇧4) instead of a second reimplementation.
//

import AppKit

/// Pure-display host: never participates in hit-testing, so the selection drag gesture
/// underneath (driven by SwiftUI) is unaffected. Scroll-wheel zoom and the "C" copy shortcut
/// are driven externally via `InlineAreaAnnotateSession`'s own event monitors — mirroring how
/// `AreaSelectionOverlayView` handles them for plain screenshot capture — rather than through
/// this view's own event handlers, since a hit-testable view would block the gesture.
final class InlineAreaMagnifierHostView: NSView {
  let magnifier = AreaSelectionMagnifier()
  var backdropImage: CGImage?

  /// The display's known viewport size, pushed in explicitly from SwiftUI
  /// (`InlineAreaMagnifierOverlay`) rather than read off `self.bounds`. AppKit only applies the
  /// frame from the `.frame(width:height:)` SwiftUI modifier once its own layout pass runs,
  /// which is not guaranteed to have happened yet the first time `update(at:)` fires — an early
  /// call would otherwise see `bounds == .zero` and every position/clamping computation in
  /// `AreaSelectionMagnifier.update(bounds:)` (including a `bounds.width`/`bounds.height`
  /// division) would degenerate to the origin, pinning the magnifier to the bottom-left corner
  /// until a later update finally observed a correct frame. This property is always correct
  /// because we set it ourselves, synchronously, before it's ever read.
  var displayBounds: CGRect = .zero

  private var lastPoint: CGPoint?

  /// This flow has nothing equivalent to plain area screenshot's `updateCoordinateIndicator`
  /// bubble, so while the magnifier is inactive (its own panel isn't showing coordinates —
  /// see `AreaSelectionMagnifier.showsCoordinatesInPanel`), this stands in as the sole source
  /// of cursor position; it hides once the magnifier activates and its panel takes over. Style
  /// shared with that indicator via `CoordinateBubbleStyle`.
  private(set) var coordinateBubbleBackgroundLayer: CALayer?
  private(set) var coordinateBubbleTextLayer: CATextLayer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /// `point` is in this view's local (AppKit, bottom-left origin) coordinate space.
  func update(at point: CGPoint) {
    lastPoint = point
    render()
  }

  func hide() {
    lastPoint = nil
    magnifier.removeLayers()
    coordinateBubbleBackgroundLayer?.isHidden = true
    coordinateBubbleTextLayer?.isHidden = true
  }

  @discardableResult
  func applyScroll(delta: CGFloat, hasPreciseScrollingDeltas: Bool) -> Bool {
    guard magnifier.handleScroll(delta: delta, hasPreciseScrollingDeltas: hasPreciseScrollingDeltas) else {
      return false
    }
    render()
    return true
  }

  private func render() {
    guard let layer, let point = lastPoint else { return }
    magnifier.update(
      at: point,
      bounds: displayBounds,
      backdropImage: backdropImage,
      contentsScale: window?.backingScaleFactor ?? 2.0,
      in: layer
    )
    updateCoordinateBubble(at: point, in: layer)
  }

  private func updateCoordinateBubble(at point: CGPoint, in layer: CALayer) {
    guard magnifier.zoom <= 1.0 else {
      coordinateBubbleBackgroundLayer?.isHidden = true
      coordinateBubbleTextLayer?.isHidden = true
      return
    }

    let background = coordinateBubbleBackgroundLayer ?? {
      let newLayer = CALayer()
      newLayer.backgroundColor = CoordinateBubbleStyle.backgroundColor.cgColor
      newLayer.cornerRadius = CoordinateBubbleStyle.cornerRadius
      newLayer.actions = [
        kCAOnOrderIn: NSNull(), kCAOnOrderOut: NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(),
      ]
      layer.addSublayer(newLayer)
      coordinateBubbleBackgroundLayer = newLayer
      return newLayer
    }()
    let text = coordinateBubbleTextLayer ?? {
      let newLayer = CATextLayer()
      newLayer.actions = background.actions
      newLayer.font = CoordinateBubbleStyle.font as CTFont
      newLayer.fontSize = CoordinateBubbleStyle.font.pointSize
      newLayer.foregroundColor = CoordinateBubbleStyle.textColor.cgColor
      newLayer.shadowColor = CoordinateBubbleStyle.shadowColor.cgColor
      newLayer.shadowOffset = CoordinateBubbleStyle.shadowOffset
      newLayer.shadowRadius = CoordinateBubbleStyle.shadowRadius
      newLayer.shadowOpacity = CoordinateBubbleStyle.shadowOpacity
      newLayer.alignmentMode = .left
      newLayer.contentsScale = window?.backingScaleFactor ?? 2.0
      newLayer.truncationMode = .none
      newLayer.isWrapped = false
      layer.addSublayer(newLayer)
      coordinateBubbleTextLayer = newLayer
      return newLayer
    }()

    let localX = Int(point.x)
    let localY = Int(displayBounds.height - point.y)
    let string = "\(localX)\n\(localY)"
    let textSize = multiLineTextSize(string, font: CoordinateBubbleStyle.font)
    let offset: CGFloat = 12.0
    let hInset = CoordinateBubbleStyle.horizontalInset
    let vInset = CoordinateBubbleStyle.verticalInset

    var textOrigin = CGPoint(x: point.x + offset + hInset, y: point.y - textSize.height - vInset - offset / 2)
    if textOrigin.x + textSize.width + hInset > displayBounds.maxX {
      textOrigin.x = point.x - textSize.width - hInset - offset
    }
    if textOrigin.y - vInset < displayBounds.minY {
      textOrigin.y = point.y + offset + vInset
    }
    let textRect = CGRect(origin: textOrigin, size: textSize)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    background.frame = textRect.insetBy(dx: -hInset, dy: -vInset)
    background.isHidden = false
    text.string = string
    text.frame = textRect
    text.isHidden = false
    CATransaction.commit()
  }

  /// `NSString.size(withAttributes:)` ignores embedded newlines (measures as a single line) —
  /// this measures the two-line "x\ny" coordinate string properly. Mirrors
  /// `AreaSelectionOverlayView.multiLineTextSize`.
  private func multiLineTextSize(_ text: String, font: NSFont) -> CGSize {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let lines = text.components(separatedBy: "\n")
    let maxWidth = lines.map { $0.size(withAttributes: attributes).width }.max() ?? 0
    let lineHeight = "0".size(withAttributes: attributes).height
    let totalHeight = lineHeight * CGFloat(lines.count) + 2.0
    return CGSize(width: maxWidth, height: totalHeight)
  }
}
