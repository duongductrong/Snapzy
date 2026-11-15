//
//  AnnotateTranslatedTextBlock.swift
//  Snapzy
//
//  Payload, layout and drawing for Auto Translate overlays: a cover that hides the
//  source text and the translation drawn on top, fitted to the source block.
//

import AppKit
import CoreGraphics

/// How the source text under a translation is hidden.
nonisolated enum TranslationCoverStyle: String, CaseIterable, Equatable, Codable {
  /// Flat fill sampled from the background around the text.
  case solid
  /// Blurred source plus a tint, for photos and gradients where a flat fill shows.
  case frosted
  /// No cover; the translation is drawn over the source as-is.
  case none
}

nonisolated enum TranslationTextAlignment: String, Equatable, Codable {
  case leading
  case center
  case trailing

  var nsTextAlignment: NSTextAlignment {
    switch self {
    case .leading: .left
    case .center: .center
    case .trailing: .right
    }
  }
}

/// Auto Translate result for one source block. Colors live in `AnnotationProperties`
/// (`strokeColor` = text, `fillColor` = cover), like other annotations.
nonisolated struct TranslatedTextBlock: Equatable {
  var sourceText: String
  var translatedText: String
  var sourceLanguage: String?
  var targetLanguage: String
  var cover: TranslationCoverStyle
  var alignment: TranslationTextAlignment
  var isBold: Bool
  /// The user changed the font size; resizing keeps it instead of re-fitting.
  var isFontSizeManual: Bool
  /// Size the fitter aims for before shrinking; scales with the box when resized.
  var baseFontSize: CGFloat
  /// One Auto Translate run; running again replaces the previous group.
  var groupID: UUID
}

extension AnnotationType {
  var isTranslation: Bool {
    if case .translation = self { return true }
    return false
  }
}

nonisolated enum AnnotateTranslationTextLayout {
  static let minimumFontSize: CGFloat = 4
  static let maximumFontSize: CGFloat = 200
  /// Vision line boxes span ascender to descender: about 1.2 × the point size.
  static let rowHeightToFontSize: CGFloat = 1 / 1.2
  /// The fitter never shrinks below this share of the source size.
  static let minimumFitScale: CGFloat = 0.6
  /// Height growth allowed when even the smallest fitted size overflows.
  static let maximumHeightGrowth: CGFloat = 0.5

  static func font(size: CGFloat, fontName: String, isBold: Bool) -> NSFont {
    let clamped = min(max(size, minimumFontSize), maximumFontSize)
    var font = NSFont(name: fontName, size: clamped) ?? NSFont.systemFont(ofSize: clamped)
    if isBold {
      font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }
    return font
  }

  static func padding(for bounds: CGRect) -> CGFloat {
    min(max(bounds.height * 0.06, 0.5), 4)
  }

  static func attributes(
    font: NSFont,
    color: NSColor,
    alignment: TranslationTextAlignment
  ) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment.nsTextAlignment
    paragraph.lineBreakMode = .byWordWrapping
    return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
  }

  static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    let rect = (text as NSString).boundingRect(
      with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font]
    )
    return ceil(rect.height)
  }

  /// Largest size in `[minimumFitScale × base, base]` whose wrapped text fits `bounds`.
  /// When nothing fits, returns the smallest size and the height it needs (capped).
  static func fit(
    text: String,
    in bounds: CGRect,
    baseFontSize: CGFloat,
    fontName: String,
    isBold: Bool,
    allowsGrowth: Bool = true
  ) -> (fontSize: CGFloat, bounds: CGRect) {
    let base = min(max(baseFontSize, minimumFontSize), maximumFontSize)
    let padding = padding(for: bounds)
    let width = max(bounds.width - padding * 2, 1)
    let height = max(bounds.height - padding * 2, 1)

    func fits(_ size: CGFloat) -> Bool {
      textHeight(text, font: font(size: size, fontName: fontName, isBold: isBold), width: width) <= height + 0.5
    }

    if fits(base) {
      return (base, bounds)
    }

    var low = max(base * minimumFitScale, minimumFontSize)
    var high = base
    if !fits(low) {
      guard allowsGrowth else { return (low, bounds) }
      let needed = textHeight(text, font: font(size: low, fontName: fontName, isBold: isBold), width: width) + padding * 2
      let grownHeight = min(needed, bounds.height * (1 + maximumHeightGrowth))
      // Annotate space is bottom-left: grow downward on screen by lowering minY.
      let grown = CGRect(x: bounds.minX, y: bounds.maxY - grownHeight, width: bounds.width, height: grownHeight)
      return (low, grown)
    }

    for _ in 0..<12 where high - low > 0.25 {
      let mid = (low + high) / 2
      if fits(mid) {
        low = mid
      } else {
        high = mid
      }
    }
    return (low, bounds)
  }

  /// Draws the translation into a non-flipped context (annotate space). The caller draws
  /// the cover first.
  static func drawText(
    _ block: TranslatedTextBlock,
    in bounds: CGRect,
    fontSize: CGFloat,
    fontName: String,
    color: NSColor,
    context: CGContext
  ) {
    let rect = bounds.standardized
    guard rect.width > 0, rect.height > 0, !block.translatedText.isEmpty else { return }

    let font = font(size: fontSize, fontName: fontName, isBold: block.isBold)
    let padding = padding(for: rect)
    let width = max(rect.width - padding * 2, 1)
    let textHeight = min(textHeight(block.translatedText, font: font, width: width), rect.height)
    let textRect = CGRect(
      x: rect.minX + padding,
      y: rect.minY + max((rect.height - textHeight) / 2, 0),
      width: width,
      height: textHeight
    )

    // Text drawing goes through the current AppKit context; reuse it when it already
    // wraps `context` (canvas and exporter set it up), otherwise wrap it.
    let needsWrapper = NSGraphicsContext.current?.cgContext !== context
    if needsWrapper {
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    }
    context.saveGState()
    context.clip(to: rect)
    (block.translatedText as NSString).draw(
      with: textRect,
      options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
      attributes: attributes(font: font, color: color, alignment: block.alignment)
    )
    context.restoreGState()
    if needsWrapper {
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  static func coverPath(in bounds: CGRect) -> CGPath {
    let rect = bounds.standardized
    let radius = min(rect.height * 0.12, 4)
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }
}
