//
//  ColorPickerLoupe.swift
//  Snapzy
//
//  The Pick Color loupe: a circle centered on the sampled pixel that stands in for the
//  cursor, magnifying a pixel-aligned grid whose center cell is exactly the pixel copied.
//  Its ring takes the sampled color, and a label below shows the hex and RGB values.
//

import AppKit
import QuartzCore

/// Nonisolated on purpose: overlay views hold the loupe, and AppKit can free a view while draining an
/// autorelease pool after a Swift job. A main-actor (isolated) deinit run there aborts on
/// macOS 13–15 (back-deployed `swift_task_deinitOnExecutor`, "pointer being freed was not allocated").
nonisolated final class ColorPickerLoupe {
  /// On-screen size of one source pixel, in points. Whole points keep the grid crisp.
  static let cellSizes: [CGFloat] = [6, 8, 10, 12, 14, 16, 20, 24, 30]
  static let diameters: [CGFloat] = [110, 140, 180, 220, 260]
  static let defaultCellSizeIndex = 3
  static let defaultDiameterIndex = 1

  private static let ringWidth: CGFloat = 6
  private static let labelGap: CGFloat = 10
  private static let gridVisibilityCellSize: CGFloat = 8

  var cellSizeIndex: Int {
    didSet { cellSizeIndex = Self.clampedIndex(cellSizeIndex, count: Self.cellSizes.count) }
  }

  var diameterIndex: Int {
    didSet {
      diameterIndex = Self.clampedIndex(diameterIndex, count: Self.diameters.count)
      if diameterIndex != oldValue { removeLayers() }
    }
  }

  var cellSize: CGFloat { Self.cellSizes[cellSizeIndex] }
  var diameter: CGFloat { Self.diameters[diameterIndex] }

  /// Source pixels from the center to the loupe edge, rounded up so the circle is always full.
  var radiusInPixels: Int { Int(ceil(diameter / 2 / cellSize)) }

  private let hintText: String
  private(set) var containerLayer: CALayer?
  private var pixelLayer: CALayer?
  private var gridLayer: CAShapeLayer?
  private var ringLayer: CAShapeLayer?
  private var centerOuterLayer: CAShapeLayer?
  private var centerInnerLayer: CAShapeLayer?
  private(set) var labelLayer: CALayer?
  private(set) var hexTextLayer: CATextLayer?
  private var detailTextLayer: CATextLayer?
  private var hintTextLayer: CATextLayer?
  private var renderedGridKey: (cellSize: CGFloat, side: Int)?
  private var renderedColor: ColorPickerColor?
  private var labelRowSizes: [CGSize]?

  private let disabledActions: [String: CAAction] = [
    "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
    "hidden": NSNull(), "path": NSNull(), "strokeColor": NSNull(), "string": NSNull(),
    kCAOnOrderIn: NSNull(), kCAOnOrderOut: NSNull(), "sublayers": NSNull(),
  ]

  init(cellSizeIndex: Int, diameterIndex: Int, hintText: String) {
    self.cellSizeIndex = Self.clampedIndex(cellSizeIndex, count: Self.cellSizes.count)
    self.diameterIndex = Self.clampedIndex(diameterIndex, count: Self.diameters.count)
    self.hintText = hintText
  }

  /// Draws the loupe centered on `center` (the sampled pixel's center, in `rootLayer`
  /// coordinates). `neighborhood` must be `(2 * radiusInPixels + 1)²` pixels.
  func update(
    center: CGPoint,
    neighborhood: CGImage,
    color: ColorPickerColor,
    bounds: CGRect,
    contentsScale: CGFloat,
    in rootLayer: CALayer
  ) {
    setupLayersIfNeeded(in: rootLayer, contentsScale: contentsScale)
    guard let containerLayer, let pixelLayer, let gridLayer, let ringLayer,
          let centerOuterLayer, let centerInnerLayer, let labelLayer,
          let hexTextLayer, let detailTextLayer, let hintTextLayer else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let side = neighborhood.width
    let gridSize = CGFloat(side) * cellSize
    let circleRect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
    containerLayer.isHidden = false
    containerLayer.frame = CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )

    // The center cell's middle sits exactly on the loupe's center.
    pixelLayer.contents = neighborhood
    pixelLayer.frame = CGRect(
      x: (diameter - gridSize) / 2,
      y: (diameter - gridSize) / 2,
      width: gridSize,
      height: gridSize
    )

    if cellSize >= Self.gridVisibilityCellSize {
      if renderedGridKey?.cellSize != cellSize || renderedGridKey?.side != side {
        gridLayer.path = Self.gridPath(side: side, cellSize: cellSize)
        renderedGridKey = (cellSize, side)
      }
      gridLayer.frame = pixelLayer.frame
      gridLayer.isHidden = false
    } else {
      gridLayer.isHidden = true
    }

    let cellRect = CGRect(
      x: (diameter - cellSize) / 2,
      y: (diameter - cellSize) / 2,
      width: cellSize,
      height: cellSize
    )
    centerOuterLayer.path = CGPath(rect: cellRect.insetBy(dx: -1, dy: -1), transform: nil)
    centerInnerLayer.path = CGPath(rect: cellRect, transform: nil)
    centerOuterLayer.strokeColor = (color.isLight ? NSColor.black : NSColor.white).cgColor
    centerInnerLayer.strokeColor = (color.isLight ? NSColor.white : NSColor.black).withAlphaComponent(0.6).cgColor

    ringLayer.path = CGPath(
      ellipseIn: circleRect.insetBy(dx: Self.ringWidth / 2, dy: Self.ringWidth / 2),
      transform: nil
    )
    ringLayer.strokeColor = color.cgColor

    // Updates arrive per pointer move and per streamed frame; re-rasterize text only on change.
    if renderedColor != color {
      hexTextLayer.string = color.hex
      detailTextLayer.string = "RGB \(color.rgbDescription)"
      renderedColor = color
      labelRowSizes = nil
    }
    layoutLabel(
      labelLayer: labelLayer,
      hexText: hexTextLayer,
      detailText: detailTextLayer,
      hintText: hintTextLayer,
      center: center,
      bounds: bounds
    )

    CATransaction.commit()
  }

  func hide() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    containerLayer?.isHidden = true
    labelLayer?.isHidden = true
    CATransaction.commit()
  }

  func removeLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    containerLayer?.removeFromSuperlayer()
    labelLayer?.removeFromSuperlayer()
    CATransaction.commit()
    containerLayer = nil
    pixelLayer = nil
    gridLayer = nil
    ringLayer = nil
    centerOuterLayer = nil
    centerInnerLayer = nil
    labelLayer = nil
    hexTextLayer = nil
    detailTextLayer = nil
    hintTextLayer = nil
    renderedGridKey = nil
    renderedColor = nil
    labelRowSizes = nil
  }

  // MARK: - Layers

  private func setupLayersIfNeeded(in rootLayer: CALayer, contentsScale: CGFloat) {
    guard containerLayer == nil else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let container = CALayer()
    container.actions = disabledActions
    container.shadowColor = NSColor.black.cgColor
    container.shadowOpacity = 0.35
    container.shadowRadius = 8
    container.shadowOffset = CGSize(width: 0, height: -2)
    container.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter), transform: nil)

    // Clips the magnified pixels to the circle; the shadow stays on the unclipped container.
    let clip = CALayer()
    clip.actions = disabledActions
    clip.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
    clip.cornerRadius = diameter / 2
    clip.masksToBounds = true
    clip.backgroundColor = NSColor.black.cgColor
    container.addSublayer(clip)

    let pixels = CALayer()
    pixels.actions = disabledActions
    pixels.magnificationFilter = .nearest
    pixels.minificationFilter = .nearest
    clip.addSublayer(pixels)

    let grid = CAShapeLayer()
    grid.actions = disabledActions
    grid.fillColor = nil
    grid.strokeColor = NSColor.black.withAlphaComponent(0.22).cgColor
    grid.lineWidth = 1 / max(contentsScale, 1)
    clip.addSublayer(grid)

    let centerOuter = CAShapeLayer()
    centerOuter.actions = disabledActions
    centerOuter.fillColor = nil
    centerOuter.lineWidth = 1.5
    clip.addSublayer(centerOuter)

    let centerInner = CAShapeLayer()
    centerInner.actions = disabledActions
    centerInner.fillColor = nil
    centerInner.lineWidth = 1
    clip.addSublayer(centerInner)

    let ring = CAShapeLayer()
    ring.actions = disabledActions
    ring.fillColor = nil
    ring.lineWidth = Self.ringWidth
    container.addSublayer(ring)

    // Hairlines on both sides of the ring keep it visible on any background and any color.
    let outerEdge = CAShapeLayer()
    outerEdge.actions = disabledActions
    outerEdge.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter).insetBy(dx: 0.5, dy: 0.5), transform: nil)
    outerEdge.fillColor = nil
    outerEdge.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
    outerEdge.lineWidth = 1
    container.addSublayer(outerEdge)

    let innerEdge = CAShapeLayer()
    innerEdge.actions = disabledActions
    let innerInset = Self.ringWidth + 0.5
    innerEdge.path = CGPath(
      ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter).insetBy(dx: innerInset, dy: innerInset),
      transform: nil
    )
    innerEdge.fillColor = nil
    innerEdge.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
    innerEdge.lineWidth = 1
    container.addSublayer(innerEdge)

    // The label is a sibling so it never inherits the circular shadow path.
    let label = CALayer()
    label.actions = disabledActions
    label.backgroundColor = NSColor(white: 0.1, alpha: 0.94).cgColor
    label.cornerRadius = 8
    label.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
    label.borderWidth = 1

    let hex = makeTextLayer(font: .monospacedSystemFont(ofSize: 14, weight: .semibold), color: .white, contentsScale: contentsScale)
    let detail = makeTextLayer(font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: NSColor.white.withAlphaComponent(0.75), contentsScale: contentsScale)
    let hint = makeTextLayer(font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.55), contentsScale: contentsScale)
    hint.string = hintText
    label.addSublayer(hex)
    label.addSublayer(detail)
    label.addSublayer(hint)

    rootLayer.addSublayer(container)
    rootLayer.addSublayer(label)
    CATransaction.commit()

    containerLayer = container
    pixelLayer = pixels
    gridLayer = grid
    ringLayer = ring
    centerOuterLayer = centerOuter
    centerInnerLayer = centerInner
    labelLayer = label
    hexTextLayer = hex
    detailTextLayer = detail
    hintTextLayer = hint
  }

  private func makeTextLayer(font: NSFont, color: NSColor, contentsScale: CGFloat) -> CATextLayer {
    let layer = CATextLayer()
    layer.actions = disabledActions
    layer.font = font
    layer.fontSize = font.pointSize
    layer.foregroundColor = color.cgColor
    layer.alignmentMode = .center
    layer.contentsScale = contentsScale
    layer.truncationMode = .end
    layer.isWrapped = false
    return layer
  }

  private func layoutLabel(
    labelLayer: CALayer,
    hexText: CATextLayer,
    detailText: CATextLayer,
    hintText: CATextLayer,
    center: CGPoint,
    bounds: CGRect
  ) {
    let horizontalPadding: CGFloat = 12
    let verticalPadding: CGFloat = 7
    let rowGap: CGFloat = 2
    let rows: [(CATextLayer, NSFont)] = [hexText, detailText, hintText].compactMap { layer in
      guard let font = layer.font as? NSFont else { return nil }
      return (layer, font)
    }
    let sizes = labelRowSizes ?? rows.map { layer, font -> CGSize in
      let string = layer.string as? String ?? ""
      let size = (string as NSString).size(withAttributes: [.font: font])
      return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
    labelRowSizes = sizes
    let width = min(
      max(sizes.map(\.width).max() ?? 0, 96) + horizontalPadding * 2,
      max(bounds.width - 8, 96)
    )
    let height = sizes.map(\.height).reduce(0, +) + rowGap * CGFloat(max(sizes.count - 1, 0)) + verticalPadding * 2

    // Below the loupe by default; above it when the display edge would cut it off.
    var origin = CGPoint(x: center.x - width / 2, y: center.y - diameter / 2 - Self.labelGap - height)
    if origin.y < bounds.minY + 4 {
      origin.y = center.y + diameter / 2 + Self.labelGap
    }
    origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - width - 4)
    labelLayer.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
    labelLayer.isHidden = false

    var y = height - verticalPadding
    for ((layer, _), size) in zip(rows, sizes) {
      y -= size.height
      layer.frame = CGRect(x: horizontalPadding, y: y, width: width - horizontalPadding * 2, height: size.height)
      y -= rowGap
    }
  }

  private static func gridPath(side: Int, cellSize: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let length = CGFloat(side) * cellSize
    for index in 1..<max(side, 1) {
      let offset = CGFloat(index) * cellSize
      path.move(to: CGPoint(x: offset, y: 0))
      path.addLine(to: CGPoint(x: offset, y: length))
      path.move(to: CGPoint(x: 0, y: offset))
      path.addLine(to: CGPoint(x: length, y: offset))
    }
    return path
  }

  private static func clampedIndex(_ index: Int, count: Int) -> Int {
    min(max(index, 0), count - 1)
  }
}
