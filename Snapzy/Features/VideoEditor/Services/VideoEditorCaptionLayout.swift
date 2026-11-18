//
//  VideoEditorCaptionLayout.swift
//  Snapzy
//
//  One CoreText layout for a caption, shared by the preview and the export: same line
//  breaks, same font, same box. The text is always laid out for a video 1080 units
//  tall and then scaled (`unit`), because CoreText's system font changes glyph widths
//  with point size: laying out at each size would give the preview a different box.
//

import CoreGraphics
import CoreText
import Foundation

nonisolated struct VideoEditorCaptionLayout: Equatable {
  /// Lines and metrics below are in reference units (video 1080 tall).
  let lines: [String]
  let fontSize: CGFloat
  let isBold: Bool
  let lineHeight: CGFloat
  let ascent: CGFloat
  /// Inner padding of the background pill.
  let padding: CGSize
  /// Box size in reference units.
  let referenceSize: CGSize
  /// Video units per reference unit.
  let unit: CGFloat

  /// Size of the whole caption box (pill), in the video rect's units.
  var size: CGSize { CGSize(width: referenceSize.width * unit, height: referenceSize.height * unit) }

  static let referenceHeight: CGFloat = 1080

  /// Widest share of the video width a caption may take.
  static let maxWidthFraction: CGFloat = 0.92

  static func make(text: String, settings: VideoEditorCaptionSettings, videoSize: CGSize) -> VideoEditorCaptionLayout? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, videoSize.width > 1, videoSize.height > 1 else { return nil }
    let lines = trimmed.split(whereSeparator: \.isNewline).flatMap {
      VideoEditorCaptionLineBreaker.lines(String($0), maxCharsPerLine: settings.maxCharsPerLine)
    }
    guard !lines.isEmpty else { return nil }

    let unit = videoSize.height / referenceHeight
    let referenceWidth = videoSize.width / unit
    var fontSize = max(settings.fontSize * referenceHeight, 4)
    let maxTextWidth = referenceWidth * maxWidthFraction - 2 * horizontalPadding(fontSize: fontSize)
    let widest = lines.map { width(of: $0, fontSize: fontSize, bold: settings.isBold) }.max() ?? 0
    if widest > maxTextWidth, widest > 0 {
      // Long words or narrow videos: shrink to fit rather than overflow the frame.
      fontSize = max(fontSize * maxTextWidth / widest, 4)
    }

    let font = makeFont(size: fontSize, bold: settings.isBold)
    let ascent = CTFontGetAscent(font)
    let lineHeight = ceil(ascent + CTFontGetDescent(font) + CTFontGetLeading(font))
    let padding = CGSize(width: horizontalPadding(fontSize: fontSize), height: fontSize * 0.3)
    let textWidth = lines.map { width(of: $0, fontSize: fontSize, bold: settings.isBold) }.max() ?? 0
    let size = CGSize(
      width: ceil(textWidth + 2 * padding.width),
      height: ceil(lineHeight * CGFloat(lines.count) + 2 * padding.height)
    )
    return VideoEditorCaptionLayout(
      lines: lines, fontSize: fontSize, isBold: settings.isBold, lineHeight: lineHeight,
      ascent: ascent, padding: padding, referenceSize: size, unit: unit
    )
  }

  /// Box origin inside `videoRect` (top-left coordinates), centered horizontally.
  func frame(in videoRect: CGRect, settings: VideoEditorCaptionSettings) -> CGRect {
    let margin = settings.margin * videoRect.height
    let y = settings.position == .top
      ? videoRect.minY + margin
      : videoRect.maxY - margin - size.height
    return CGRect(x: videoRect.midX - size.width / 2, y: y, width: size.width, height: size.height)
  }

  static func makeFont(size: CGFloat, bold: Bool) -> CTFont {
    CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
      ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
  }

  static func width(of line: String, fontSize: CGFloat, bold: Bool) -> CGFloat {
    let ctLine = CTLineCreateWithAttributedString(attributed(line, font: makeFont(size: fontSize, bold: bold), color: nil, outline: false))
    return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
  }

  static func attributed(_ text: String, font: CTFont, color: CGColor?, outline: Bool) -> NSAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font]
    if let color { attributes[.init(kCTForegroundColorAttributeName as String)] = color }
    if outline {
      attributes[.init(kCTStrokeColorAttributeName as String)] = CGColor(gray: 0, alpha: 0.9)
      attributes[.init(kCTStrokeWidthAttributeName as String)] = -4.0 as CGFloat
    }
    return NSAttributedString(string: text, attributes: attributes)
  }

  private static func horizontalPadding(fontSize: CGFloat) -> CGFloat {
    fontSize * 0.55
  }
}

/// Draws a caption layout into a bitmap (export: Core Image; preview: SwiftUI Image).
nonisolated enum VideoEditorCaptionRenderer {
  /// The caption box as an image `scale` times the layout size (pixels per layout unit).
  static func image(_ layout: VideoEditorCaptionLayout, settings: VideoEditorCaptionSettings, scale: CGFloat = 1) -> CGImage? {
    let width = Int(ceil(layout.size.width * scale))
    let height = Int(ceil(layout.size.height * scale))
    guard width > 0, height > 0,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }
    // Draw in reference units; the context maps them to pixels.
    context.scaleBy(x: scale * layout.unit, y: scale * layout.unit)
    context.setShouldSmoothFonts(false)

    let box = CGRect(origin: .zero, size: layout.referenceSize)
    if settings.backgroundOpacity > 0 {
      let radius = min(layout.fontSize * 0.35, box.height / 2)
      context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
      context.setFillColor(CGColor(gray: 0, alpha: min(max(settings.backgroundOpacity, 0), 1)))
      context.fillPath()
    }

    let font = VideoEditorCaptionLayout.makeFont(size: layout.fontSize, bold: layout.isBold)
    let outline = settings.backgroundOpacity < 0.2
    for (index, line) in layout.lines.enumerated() {
      let ctLine = CTLineCreateWithAttributedString(
        VideoEditorCaptionLayout.attributed(line, font: font, color: settings.textCGColor, outline: outline)
      )
      let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
      // CoreGraphics is bottom-up: line 0 sits at the top of the box.
      let baseline = layout.referenceSize.height - layout.padding.height - layout.ascent - CGFloat(index) * layout.lineHeight
      context.textPosition = CGPoint(x: (layout.referenceSize.width - lineWidth) / 2, y: baseline)
      CTLineDraw(ctLine, context)
    }
    return context.makeImage()
  }
}
