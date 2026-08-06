import Cocoa
import QuartzCore

final class AreaSelectionMagnifier {
  // Configurable bounds/sizes. The preview square and the info panel below it share one width.
  private let magnifierSize: CGFloat = 160.0
  private let panelGap: CGFloat = 8.0
  private let magnifierGap: CGFloat = 20.0
  private let minMagnifierZoom: CGFloat = 1.0
  private let maxMagnifierZoom: CGFloat = 20.0
  /// Zoom level used when the "show magnifier by default" preference is on and a new
  /// selection session starts — high enough to be immediately useful for pixel-level work.
  static let defaultActiveZoom: CGFloat = 7.0
  /// Below this zoom level, the grid is suppressed. Checked against `zoom` itself (not the
  /// on-screen pixel span) so the threshold feels the same to the user regardless of the
  /// backdrop's resolution — the same ⌘+scroll amount always crosses it.
  private let gridVisibilityZoomThreshold: CGFloat = 6.0

  // Info panel row layout. `panelHeight` is derived from these plus the current font metrics
  // (see below) rather than hand-tuned, so resizing any row's content can't silently make it
  // overlap its neighbor.
  private let panelHorizontalPadding: CGFloat = 10.0
  private let panelVerticalPadding: CGFloat = 8.0
  private let panelRowGap: CGFloat = 4.0
  private let swatchSize: CGFloat = 18.0
  private let swatchTextGap: CGFloat = 7.0
  private let keyCapSize: CGFloat = 16.0
  private let keyCapTextGap: CGFloat = 6.0

  /// Cached font metrics: fonts here are fixed for the object's lifetime, so measuring them
  /// via `NSString.size(withAttributes:)` on every access (as computed properties previously
  /// did) was pure waste — `update(at:...)` reads several of these per call, and a single
  /// ⌘+scroll tick calls `update` once, so this matters under rapid scrolling. `lazy` computes
  /// each exactly once.
  private lazy var hexLineHeight: CGFloat = "0".size(withAttributes: [.font: overlayFont]).height
  private lazy var hintLineHeight: CGFloat = "0".size(withAttributes: [.font: hintFont]).height
  private lazy var keyCapTextHeight: CGFloat = "C".size(withAttributes: [.font: keyCapFont]).height
  private lazy var hintPrefixWidth: CGFloat = {
    let text = copyHintPrefixText
    return text.isEmpty ? 0 : text.size(withAttributes: [.font: hintFont]).width
  }()

  private var colorRowHeight: CGFloat { max(hexLineHeight, swatchSize) }
  private var hintRowHeight: CGFloat { max(keyCapSize, hintLineHeight) }

  /// Whether the color-picker panel (swatch, hex value, copy hint) shows below the preview —
  /// the "Show color picker panel" preference. When off, the magnifier is just the pixel
  /// grid/crosshair preview, matching its footprint before this panel existed.
  var showsColorPanel = true

  private var panelHeight: CGFloat {
    guard showsColorPanel else { return 0 }
    return panelVerticalPadding * 2
      + colorRowHeight + panelRowGap
      + hintRowHeight
  }

  /// Full container height (preview square, plus gap + info panel when `showsColorPanel`).
  /// Internal rather than private so tests can derive expected layout positions from it
  /// instead of hardcoding a value that silently drifts whenever a row size here changes.
  var totalHeight: CGFloat {
    showsColorPanel ? magnifierSize + panelGap + panelHeight : magnifierSize
  }

  // The layers managed by this magnifier
  private(set) var containerLayer: CALayer?
  /// Sits behind `imageLayer`, slightly larger — a dark ring visible against light content,
  /// since `imageLayer`'s own light border can blend into a light backdrop underneath it.
  private(set) var imageOuterBorderLayer: CALayer?
  private(set) var imageLayer: CALayer?
  private(set) var gridLayer: CAShapeLayer?
  private(set) var crosshairLayer: CAShapeLayer?
  private(set) var centerPixelLayer: CAShapeLayer?
  private(set) var panelLayer: CALayer?
  private(set) var colorSwatchLayer: CALayer?
  private(set) var colorTextLayer: CATextLayer?
  private(set) var hintPrefixTextLayer: CATextLayer?
  private(set) var hintKeyCapBackgroundLayer: CALayer?
  private(set) var hintKeyCapTextLayer: CATextLayer?
  private(set) var hintTextLayer: CATextLayer?

  var zoom: CGFloat = 1.0 // Starts at 1.0 (deactivated)
  var reverseZoomDirection = false

  /// Resets zoom for a new selection session. `showByDefault` mirrors the
  /// "show magnifier by default" preference: on, the magnifier starts already active at
  /// `defaultActiveZoom`; off, it starts deactivated (1.0) as before, requiring ⌘+scroll.
  func resetZoom(showByDefault: Bool) {
    zoom = showByDefault ? Self.defaultActiveZoom : minMagnifierZoom
  }

  /// Hex value of the pixel under the cursor as of the last `update(at:...)` call.
  private(set) var lastHexColor: String?

  // Disables default layer animations
  private let disabledActions: [String: CAAction] = [
    kCAOnOrderIn: NSNull(),
    kCAOnOrderOut: NSNull(),
    "sublayers": NSNull(),
    "contents": NSNull(),
    "bounds": NSNull(),
    "position": NSNull(),
    "hidden": NSNull(),
    "contentsRect": NSNull(),
  ]

  private var overlayFont: NSFont {
    NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
  }

  private var hintFont: NSFont {
    NSFont.systemFont(ofSize: 12, weight: .medium)
  }

  private var keyCapFont: NSFont {
    NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
  }

  private var copyHintPrefixText: String {
    L10n.ScreenCapture.magnifierCopyColorHintPrefix
  }

  private var copyHintText: String {
    L10n.ScreenCapture.magnifierCopyColorHintSuffix
  }

  func setupLayersIfNeeded(in rootLayer: CALayer, contentsScale: CGFloat) {
    guard containerLayer == nil else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Container layer: purely a grouping layer, positioned as one unit
    let container = CALayer()
    container.frame = CGRect(x: 0, y: 0, width: magnifierSize, height: totalHeight)
    container.actions = disabledActions
    container.isHidden = true
    rootLayer.addSublayer(container)
    self.containerLayer = container

    let imageOriginY = showsColorPanel ? panelHeight + panelGap : 0

    // Outer border: a dark ring behind the preview, slightly larger than it. `imageLayer`'s
    // own border is light (to read against dark content); on light content that light border
    // all but disappears, so this dark ring guarantees a visible edge either way.
    let outerBorderWidth: CGFloat = 2.0
    let imageOuterBorder = CALayer()
    imageOuterBorder.frame = CGRect(
      x: -outerBorderWidth, y: imageOriginY - outerBorderWidth,
      width: magnifierSize + outerBorderWidth * 2, height: magnifierSize + outerBorderWidth * 2
    )
    imageOuterBorder.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
    imageOuterBorder.cornerRadius = 12 + outerBorderWidth
    imageOuterBorder.actions = disabledActions
    container.addSublayer(imageOuterBorder)
    self.imageOuterBorderLayer = imageOuterBorder

    // Image layer: displays nearest-neighbor pixelated zoom, occupies the top square
    let imgLayer = CALayer()
    imgLayer.frame = CGRect(x: 0, y: imageOriginY, width: magnifierSize, height: magnifierSize)
    imgLayer.cornerRadius = 12
    imgLayer.masksToBounds = true
    imgLayer.magnificationFilter = .nearest
    imgLayer.contentsGravity = .resize
    imgLayer.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
    imgLayer.borderWidth = 1.5
    imgLayer.shadowColor = NSColor.black.cgColor
    imgLayer.shadowOffset = CGSize(width: 0, height: -4)
    imgLayer.shadowRadius = 8
    imgLayer.shadowOpacity = 0.4
    imgLayer.actions = disabledActions
    container.addSublayer(imgLayer)
    self.imageLayer = imgLayer

    // Pixel grid: faint lines delineating source-pixel boundaries at high zoom
    let grid = CAShapeLayer()
    grid.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
    grid.fillColor = nil
    grid.lineWidth = 0.5
    grid.actions = disabledActions
    grid.isHidden = true
    imgLayer.addSublayer(grid)
    self.gridLayer = grid

    // Crosshair: guide lines spanning the preview, gapped around the target pixel
    let crosshair = CAShapeLayer()
    crosshair.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
    crosshair.fillColor = nil
    crosshair.lineWidth = 1.0
    crosshair.shadowColor = NSColor.black.cgColor
    crosshair.shadowOpacity = 0.5
    crosshair.shadowRadius = 1.0
    crosshair.shadowOffset = .zero
    crosshair.actions = disabledActions
    imgLayer.addSublayer(crosshair)
    self.crosshairLayer = crosshair

    // Center pixel indicator layer: thin border highlighting the exact target pixel
    let centerIndicator = CAShapeLayer()
    centerIndicator.strokeColor = NSColor.systemRed.cgColor
    centerIndicator.fillColor = nil
    centerIndicator.lineWidth = 1.0
    centerIndicator.actions = disabledActions
    imgLayer.addSublayer(centerIndicator)
    self.centerPixelLayer = centerIndicator

    // Info panel: sits below the magnified preview, shows coordinates, color, and copy hint
    let panel = CALayer()
    panel.frame = CGRect(x: 0, y: 0, width: magnifierSize, height: panelHeight)
    panel.cornerRadius = 12
    panel.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
    panel.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    panel.borderWidth = 1.0
    panel.actions = disabledActions
    panel.isHidden = true
    container.addSublayer(panel)
    self.panelLayer = panel

    let swatch = CALayer()
    swatch.cornerRadius = 4
    swatch.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
    swatch.borderWidth = 1.0
    swatch.actions = disabledActions
    panel.addSublayer(swatch)
    self.colorSwatchLayer = swatch

    let colorText = CATextLayer()
    configureTextLayer(colorText, font: overlayFont, color: .white, contentsScale: contentsScale)
    panel.addSublayer(colorText)
    self.colorTextLayer = colorText

    // Copy hint row: "[prefix] [C] [suffix]", e.g. "按 [C] 复制色值" / "Press [C] to Copy".
    // The "C" reads as a pressable key (solid badge) rather than blending into the sentence.
    let hintPrefixText = CATextLayer()
    configureTextLayer(hintPrefixText, font: hintFont, color: NSColor.white.withAlphaComponent(0.95), contentsScale: contentsScale)
    hintPrefixText.string = copyHintPrefixText
    panel.addSublayer(hintPrefixText)
    self.hintPrefixTextLayer = hintPrefixText

    let keyCapBackground = CALayer()
    keyCapBackground.backgroundColor = NSColor.white.cgColor
    keyCapBackground.cornerRadius = 4
    keyCapBackground.actions = disabledActions
    panel.addSublayer(keyCapBackground)
    self.hintKeyCapBackgroundLayer = keyCapBackground

    let keyCapText = CATextLayer()
    configureTextLayer(keyCapText, font: keyCapFont, color: .black, contentsScale: contentsScale)
    keyCapText.string = "C"
    keyCapText.alignmentMode = .center
    panel.addSublayer(keyCapText)
    self.hintKeyCapTextLayer = keyCapText

    let hintText = CATextLayer()
    configureTextLayer(hintText, font: hintFont, color: NSColor.white.withAlphaComponent(0.95), contentsScale: contentsScale)
    hintText.string = copyHintText
    panel.addSublayer(hintText)
    self.hintTextLayer = hintText

    CATransaction.commit()
  }

  private func configureTextLayer(_ layer: CATextLayer, font: NSFont, color: NSColor, contentsScale: CGFloat) {
    layer.actions = disabledActions
    layer.font = font as CTFont
    layer.fontSize = font.pointSize
    layer.foregroundColor = color.cgColor
    layer.alignmentMode = .left
    layer.contentsScale = contentsScale
    layer.truncationMode = .none
    layer.isWrapped = false
  }

  func removeLayers() {
    copiedFeedbackWorkItem?.cancel()
    copiedFeedbackWorkItem = nil

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    containerLayer?.removeFromSuperlayer()
    containerLayer = nil
    imageOuterBorderLayer = nil
    imageLayer = nil
    gridLayer = nil
    crosshairLayer = nil
    centerPixelLayer = nil
    panelLayer = nil
    colorSwatchLayer = nil
    colorTextLayer = nil
    hintPrefixTextLayer = nil
    hintKeyCapBackgroundLayer = nil
    hintKeyCapTextLayer = nil
    hintTextLayer = nil
    CATransaction.commit()

    lastHexColor = nil
  }

  func handleScroll(delta: CGFloat, hasPreciseScrollingDeltas: Bool) -> Bool {
    let multiplier: CGFloat = hasPreciseScrollingDeltas ? 0.2 : 1.0
    var directionSign: CGFloat = delta > 0 ? 1.0 : -1.0
    if reverseZoomDirection {
      directionSign = -directionSign
    }
    let zoomChange = directionSign * multiplier
    let oldZoom = zoom
    zoom = max(minMagnifierZoom, min(maxMagnifierZoom, zoom + zoomChange))
    return zoom != oldZoom
  }

  private var pixelReadContext: CGContext?

  func update(
    at point: CGPoint,
    bounds: CGRect,
    backdropImage: CGImage?,
    contentsScale: CGFloat,
    in rootLayer: CALayer
  ) {
    guard zoom > 1.0, let backdropImage = backdropImage else {
      removeLayers()
      return
    }

    setupLayersIfNeeded(in: rootLayer, contentsScale: contentsScale)

    guard let container = containerLayer,
          let imgLayer = imageLayer,
          let grid = gridLayer,
          let crosshair = crosshairLayer,
          let centerIndicator = centerPixelLayer,
          let panel = panelLayer,
          let swatch = colorSwatchLayer,
          let colorText = colorTextLayer,
          let hintPrefixText = hintPrefixTextLayer,
          let keyCapBackground = hintKeyCapBackgroundLayer,
          let keyCapText = hintKeyCapTextLayer,
          let hintText = hintTextLayer else {
      return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Compute magnifier window frame based on mouse position
    var originX = point.x + magnifierGap
    var originY = point.y + magnifierGap

    // Check boundary & flip dynamically
    if originX + magnifierSize > bounds.maxX {
      originX = point.x - magnifierGap - magnifierSize
    }
    if originY + totalHeight > bounds.maxY {
      originY = point.y - magnifierGap - totalHeight
    }

    // Absolute screen clamping
    originX = max(bounds.minX, min(bounds.maxX - magnifierSize, originX))
    originY = max(bounds.minY, min(bounds.maxY - totalHeight, originY))

    container.frame = CGRect(x: originX, y: originY, width: magnifierSize, height: totalHeight)
    container.isHidden = false
    panel.isHidden = !showsColorPanel

    // Set cropped and scaled image contents via contentsRect (nearest-neighbor)
    imgLayer.contents = backdropImage
    let norm_w = magnifierSize / (zoom * bounds.width)
    let norm_h = magnifierSize / (zoom * bounds.height)
    let norm_x = (point.x / bounds.width) - norm_w / 2.0
    let norm_y = (point.y / bounds.height) - norm_h / 2.0
    imgLayer.contentsRect = CGRect(x: norm_x, y: norm_y, width: norm_w, height: norm_h)

    // On-screen size of a single source pixel, accounting for the backdrop's own resolution
    // (which is typically higher than view points on Retina) so the highlighted pixel, grid,
    // and crosshair line up with what is actually rendered rather than the raw zoom factor.
    let pixelSpanX = backdropImage.width > 0
      ? zoom * bounds.width / CGFloat(backdropImage.width)
      : zoom
    let pixelSpanY = backdropImage.height > 0
      ? zoom * bounds.height / CGFloat(backdropImage.height)
      : zoom

    // Central pixel highlight rect
    let cx = magnifierSize / 2.0
    let cy = magnifierSize / 2.0
    let px = cx - pixelSpanX / 2.0
    let py = cy - pixelSpanY / 2.0
    let pixelRect = CGRect(x: px, y: py, width: pixelSpanX, height: pixelSpanY)
    centerIndicator.path = CGPath(rect: pixelRect, transform: nil)

    crosshair.path = crosshairPath(pixelRect: pixelRect, size: magnifierSize)

    if zoom >= gridVisibilityZoomThreshold {
      grid.path = gridPath(
        originX: px, originY: py,
        stepX: pixelSpanX, stepY: pixelSpanY,
        size: magnifierSize
      )
      grid.isHidden = false
    } else {
      grid.isHidden = true
    }

    // Read pixel color under cursor directly from the backdrop image (1×1 crop + draw, exact)
    let hex = hexColor(at: point, bounds: bounds, image: backdropImage)
    lastHexColor = hex

    let hexDisplay = hex ?? "--------"
    colorText.string = hexDisplay
    swatch.backgroundColor = (hex.flatMap(NSColor.init(magnifierHex:)) ?? NSColor.black).cgColor

    if showsColorPanel {
      layoutPanel(
        swatch: swatch,
        colorText: colorText,
        hintPrefixText: hintPrefixText,
        keyCapBackground: keyCapBackground,
        keyCapText: keyCapText,
        hintText: hintText
      )
    }

    CATransaction.commit()
  }

  private func layoutPanel(
    swatch: CALayer,
    colorText: CATextLayer,
    hintPrefixText: CATextLayer,
    keyCapBackground: CALayer,
    keyCapText: CATextLayer,
    hintText: CATextLayer
  ) {
    let prefixTrailingGap: CGFloat = hintPrefixWidth > 0 ? keyCapTextGap : 0

    // Bottom row: "[prefix] [C] [suffix]", e.g. "按 [C] 复制色值" / "[C] キーでコピー"
    let hintRowY = panelVerticalPadding
    hintPrefixText.frame = CGRect(
      x: panelHorizontalPadding, y: hintRowY + (hintRowHeight - hintLineHeight) / 2.0,
      width: hintPrefixWidth, height: hintLineHeight
    )
    let keyCapX = panelHorizontalPadding + hintPrefixWidth + prefixTrailingGap
    keyCapBackground.frame = CGRect(
      x: keyCapX, y: hintRowY + (hintRowHeight - keyCapSize) / 2.0,
      width: keyCapSize, height: keyCapSize
    )
    keyCapText.frame = CGRect(
      x: keyCapBackground.frame.minX,
      y: keyCapBackground.frame.minY + (keyCapSize - keyCapTextHeight) / 2.0 - 0.5,
      width: keyCapSize, height: keyCapTextHeight
    )
    let suffixX = keyCapBackground.frame.maxX + keyCapTextGap
    hintText.frame = CGRect(
      x: suffixX, y: hintRowY + (hintRowHeight - hintLineHeight) / 2.0,
      width: max(0, magnifierSize - panelHorizontalPadding - suffixX), height: hintLineHeight
    )

    // Top row: color swatch + hex value
    let colorRowY = hintRowY + hintRowHeight + panelRowGap
    swatch.frame = CGRect(
      x: panelHorizontalPadding, y: colorRowY + (hexLineHeight - swatchSize) / 2.0,
      width: swatchSize, height: swatchSize
    )
    colorText.frame = CGRect(
      x: panelHorizontalPadding + swatchSize + swatchTextGap, y: colorRowY,
      width: magnifierSize - panelHorizontalPadding * 2 - swatchSize - swatchTextGap, height: hexLineHeight
    )
  }

  /// Builds a path outlining every source-pixel boundary visible within the preview, anchored
  /// so lines fall exactly on the same grid as the highlighted target pixel.
  private func gridPath(originX: CGFloat, originY: CGFloat, stepX: CGFloat, stepY: CGFloat, size: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard stepX > 0, stepY > 0 else { return path }

    let minColumn = Int(floor((0 - originX) / stepX)) - 1
    let maxColumn = Int(ceil((size - originX) / stepX)) + 1
    for n in minColumn...maxColumn {
      let x = originX + CGFloat(n) * stepX
      guard x >= 0, x <= size else { continue }
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size))
    }

    let minRow = Int(floor((0 - originY) / stepY)) - 1
    let maxRow = Int(ceil((size - originY) / stepY)) + 1
    for n in minRow...maxRow {
      let y = originY + CGFloat(n) * stepY
      guard y >= 0, y <= size else { continue }
      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: size, y: y))
    }

    return path
  }

  /// Builds a crosshair spanning the full preview, with a gap left open around `pixelRect` so
  /// the lines point at the exact target pixel without obscuring it.
  private func crosshairPath(pixelRect: CGRect, size: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let midX = pixelRect.midX
    let midY = pixelRect.midY

    if pixelRect.minX > 0 {
      path.move(to: CGPoint(x: 0, y: midY))
      path.addLine(to: CGPoint(x: pixelRect.minX, y: midY))
    }
    if pixelRect.maxX < size {
      path.move(to: CGPoint(x: pixelRect.maxX, y: midY))
      path.addLine(to: CGPoint(x: size, y: midY))
    }
    if pixelRect.minY > 0 {
      path.move(to: CGPoint(x: midX, y: 0))
      path.addLine(to: CGPoint(x: midX, y: pixelRect.minY))
    }
    if pixelRect.maxY < size {
      path.move(to: CGPoint(x: midX, y: pixelRect.maxY))
      path.addLine(to: CGPoint(x: midX, y: size))
    }

    return path
  }

  private var copiedFeedbackWorkItem: DispatchWorkItem?

  /// Copies the currently sampled pixel's hex value to the clipboard, flashing a brief
  /// confirmation in place of the copy hint. Returns false if the magnifier isn't active.
  @discardableResult
  func copyColorToClipboard() -> Bool {
    guard showsColorPanel, zoom > 1.0, let hex = lastHexColor,
          let hintPrefixText = hintPrefixTextLayer,
          let keyCapBackground = hintKeyCapBackgroundLayer,
          let keyCapText = hintKeyCapTextLayer,
          let hintText = hintTextLayer else { return false }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(hex, forType: .string)

    copiedFeedbackWorkItem?.cancel()

    // Swap the "[prefix] [C] [suffix]" row for a single full-width "Copied" message —
    // restored (with the row's normal layout) by the work item below.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    hintPrefixText.isHidden = true
    keyCapBackground.isHidden = true
    keyCapText.isHidden = true
    hintText.string = L10n.ScreenCapture.magnifierColorCopiedFeedback
    hintText.frame = CGRect(
      x: panelHorizontalPadding, y: hintText.frame.minY,
      width: magnifierSize - panelHorizontalPadding * 2, height: hintText.frame.height
    )
    CATransaction.commit()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self,
            let swatch = self.colorSwatchLayer,
            let colorText = self.colorTextLayer,
            let hintPrefixText = self.hintPrefixTextLayer,
            let keyCapBackground = self.hintKeyCapBackgroundLayer,
            let keyCapText = self.hintKeyCapTextLayer,
            let hintText = self.hintTextLayer else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      hintPrefixText.isHidden = false
      keyCapBackground.isHidden = false
      keyCapText.isHidden = false
      hintText.string = self.copyHintText
      self.layoutPanel(
        swatch: swatch,
        colorText: colorText,
        hintPrefixText: hintPrefixText,
        keyCapBackground: keyCapBackground,
        keyCapText: keyCapText,
        hintText: hintText
      )
      CATransaction.commit()
    }
    copiedFeedbackWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)

    return true
  }

  /// Reads the exact pixel color under `point` by cropping a single pixel out of `image`
  /// and drawing it into a reusable 1×1 context. Returns nil on any failure.
  private func hexColor(at point: CGPoint, bounds: CGRect, image: CGImage) -> String? {
    guard bounds.width > 0, bounds.height > 0, image.width > 0, image.height > 0 else {
      return nil
    }

    let scaleX = CGFloat(image.width) / bounds.width
    let scaleY = CGFloat(image.height) / bounds.height
    let x = max(0, min(image.width - 1, Int(point.x * scaleX)))
    // Invert y because Cocoa origin is bottom-left, while CGImage origin is top-left
    let y = max(0, min(image.height - 1, image.height - 1 - Int(point.y * scaleY)))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context: CGContext
    if let cached = pixelReadContext {
      context = cached
    } else {
      guard let created = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      ) else {
        return nil
      }
      pixelReadContext = created
      context = created
    }

    guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
      return nil
    }
    context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    guard let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
  }
}

private extension NSColor {
  convenience init?(magnifierHex hex: String) {
    var sanitized = hex
    if sanitized.hasPrefix("#") {
      sanitized.removeFirst()
    }
    guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
    let r = CGFloat((value >> 16) & 0xFF) / 255.0
    let g = CGFloat((value >> 8) & 0xFF) / 255.0
    let b = CGFloat(value & 0xFF) / 255.0
    self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
  }
}
