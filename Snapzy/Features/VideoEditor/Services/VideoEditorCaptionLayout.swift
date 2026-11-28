//
//  VideoEditorCaptionLayout.swift
//  Snapzy
//
//  Shared CoreText layout and crisp bitmap renderer supporting the macOS system font,
//  installed device font families, and user-imported `.ttf`/`.otf`/`.ttc` files via
//  `VideoEditorFontResolver`.
//

import AppKit
import CoreGraphics
import CoreText
import Foundation

nonisolated struct VideoEditorCaptionLayout: Equatable, Sendable {
  struct WordSpan: Equatable, Sendable {
    let globalIndex: Int
    let utf16Location: Int
    let utf16Length: Int
    let text: String
  }

  struct LineSpec: Equatable, Sendable {
    let text: String
    let isHero: Bool
    let fontSize: CGFloat
    let customFontId: String
    let weight: Int
    let isItalic: Bool
    let trackingPoints: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let lineHeight: CGFloat
  }

  let lines: [String]
  let lineSpecs: [LineSpec]
  let lineWordSpans: [[WordSpan]]
  let flatWords: [String]
  let fontSize: CGFloat
  let isBold: Bool
  let fontFamily: VideoEditorCaptionSettings.FontFamily
  let trackingPoints: CGFloat
  let lineHeight: CGFloat
  let ascent: CGFloat
  let descent: CGFloat
  let padding: CGSize
  let outerOutset: CGFloat
  let referenceSize: CGSize
  let unit: CGFloat

  var size: CGSize {
    CGSize(width: referenceSize.width * unit, height: referenceSize.height * unit)
  }

  var bitmapSize: CGSize {
    CGSize(
      width: (referenceSize.width + 2 * outerOutset) * unit,
      height: (referenceSize.height + 2 * outerOutset) * unit
    )
  }

  static let referenceHeight: CGFloat = 1080
  static let maxWidthFraction: CGFloat = 0.90

  static func make(
    text: String,
    settings: VideoEditorCaptionSettings,
    videoSize: CGSize
  ) -> VideoEditorCaptionLayout? {
    let rawTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawTrimmed.isEmpty, videoSize.width > 1, videoSize.height > 1 else { return nil }

    let clampedWidthFraction = min(0.96, max(0.18, settings.maxWidthFraction))
    let unit = videoSize.height / referenceHeight
    let referenceWidth = videoSize.width / unit
    var heroFontSize = max(settings.fontSize * referenceHeight, 4)
    let horizPad = horizontalPadding(fontSize: heroFontSize, surface: settings.surfaceStyle)
    let leadingExtraPre = leadingAccessoryAdvance(fontSize: heroFontSize, surface: settings.surfaceStyle)
    let maxTextWidth = max(40, referenceWidth * clampedWidthFraction - leadingExtraPre - 2 * horizPad)

    let heroWeight = settings.resolvedWeight
    let heroItalic = settings.resolvedItalic

    let prepared = prepareLines(
      rawText: rawTrimmed,
      settings: settings,
      maxTextWidth: maxTextWidth,
      heroFontSize: heroFontSize,
      heroWeight: heroWeight,
      heroItalic: heroItalic,
      clampedWidthFraction: clampedWidthFraction
    )
    guard !prepared.isEmpty else { return nil }

    let initialMaxWidth = prepared.map { item -> CGFloat in
      let lineSize = item.isHero ? heroFontSize : heroFontSize * 0.56
      let wght = item.isHero ? heroWeight : 500
      let ital = item.isHero ? heroItalic : false
      let trk = item.isHero ? (lineSize * settings.tracking.emFactor) : (lineSize * -0.016)
      return width(
        of: item.text,
        fontSize: lineSize,
        customFontId: settings.customFontId,
        weight: wght,
        italic: ital,
        tracking: trk
      )
    }.max() ?? 0

    if initialMaxWidth > maxTextWidth, initialMaxWidth > 0 {
      heroFontSize = max(heroFontSize * maxTextWidth / initialMaxWidth, 4)
    }

    var specs: [LineSpec] = []
    var measuredMaxWidth: CGFloat = 0
    for item in prepared {
      let lineSize = item.isHero ? heroFontSize : max(4, heroFontSize * 0.56)
      let wght = item.isHero ? heroWeight : 500
      let ital = item.isHero ? heroItalic : false
      let trk = item.isHero ? (lineSize * settings.tracking.emFactor) : (lineSize * -0.016)
      let resolved = VideoEditorFontResolver.resolveFont(
        familyId: settings.customFontId,
        size: lineSize,
        weight: wght,
        italic: ital
      )
      let asc = CTFontGetAscent(resolved.font)
      let desc = CTFontGetDescent(resolved.font)
      let lh = ceil((asc + desc) * (item.isHero ? 1.05 : 1.03))
      specs.append(LineSpec(
        text: item.text,
        isHero: item.isHero,
        fontSize: lineSize,
        customFontId: settings.customFontId,
        weight: wght,
        isItalic: ital,
        trackingPoints: trk,
        ascent: asc,
        descent: desc,
        lineHeight: lh
      ))
      let w = width(
        of: item.text,
        fontSize: lineSize,
        customFontId: settings.customFontId,
        weight: wght,
        italic: ital,
        tracking: trk
      )
      measuredMaxWidth = max(measuredMaxWidth, w)
    }

    let leadingExtra = leadingAccessoryAdvance(fontSize: heroFontSize, surface: settings.surfaceStyle)
    let padding = CGSize(
      width: horizontalPadding(fontSize: heroFontSize, surface: settings.surfaceStyle),
      height: verticalPadding(fontSize: heroFontSize, surface: settings.surfaceStyle)
    )
    let totalLinesHeight = specs.map(\.lineHeight).reduce(0, +)
    let boxSize = CGSize(
      width: ceil(measuredMaxWidth + leadingExtra + 2 * padding.width),
      height: ceil(totalLinesHeight + 2 * padding.height)
    )

    let lines = specs.map(\.text)
    var globalWordIndex = 0
    var flatWords: [String] = []
    var allSpans: [[WordSpan]] = []
    for line in lines {
      let nsLine = line as NSString
      var spans: [WordSpan] = []
      var searchStart = 0
      while searchStart < nsLine.length {
        while searchStart < nsLine.length,
              CharacterSet.whitespacesAndNewlines
              .contains(UnicodeScalar(nsLine.character(at: searchStart)) ?? UnicodeScalar(32)) {
          searchStart += 1
        }
        guard searchStart < nsLine.length else { break }
        var wordEnd = searchStart
        while wordEnd < nsLine.length,
              !CharacterSet.whitespacesAndNewlines
              .contains(UnicodeScalar(nsLine.character(at: wordEnd)) ?? UnicodeScalar(32)) {
          wordEnd += 1
        }
        let length = wordEnd - searchStart
        let token = nsLine.substring(with: NSRange(location: searchStart, length: length))
        spans.append(WordSpan(
          globalIndex: globalWordIndex,
          utf16Location: searchStart,
          utf16Length: length,
          text: token
        ))
        flatWords.append(token)
        globalWordIndex += 1
        searchStart = wordEnd
      }
      allSpans.append(spans)
    }

    let glowOutset = settings.glowIntensity > 0.01
      ? ceil(heroFontSize * (0.48 + 0.34 * settings.glowIntensity))
      : 0
    let wordMotionOutset = settings.wordMode != .fullLine
      ? ceil(max(12, heroFontSize * 0.36))
      : 0
    let baseOutset: CGFloat = switch settings.surfaceStyle {
    case .classicPill:
      0
    case .glowBloom:
      ceil(max(16, heroFontSize * 0.48))
    case .rangeHighlight:
      ceil(max(14, heroFontSize * 0.42))
    case .selectionFrame:
      ceil(max(12, heroFontSize * 0.34))
    case .solarPill, .studioGlass, .cinemaClean, .editorialPaper, .monoTag, .accentRule:
      ceil(max(12, heroFontSize * 0.34))
    }
    let outset = max(baseOutset, max(glowOutset, wordMotionOutset))

    let heroResolved = VideoEditorFontResolver.resolveFont(
      familyId: settings.customFontId,
      size: heroFontSize,
      weight: heroWeight,
      italic: heroItalic
    )
    let heroAsc = CTFontGetAscent(heroResolved.font)
    let heroDesc = CTFontGetDescent(heroResolved.font)

    return VideoEditorCaptionLayout(
      lines: lines,
      lineSpecs: specs,
      lineWordSpans: allSpans,
      flatWords: flatWords,
      fontSize: heroFontSize,
      isBold: settings.isBold,
      fontFamily: settings.fontFamily,
      trackingPoints: heroFontSize * settings.tracking.emFactor,
      lineHeight: ceil((heroAsc + heroDesc) * 1.05),
      ascent: heroAsc,
      descent: heroDesc,
      padding: padding,
      outerOutset: outset,
      referenceSize: boxSize,
      unit: unit
    )
  }

  private static func prepareLines(
    rawText: String,
    settings: VideoEditorCaptionSettings,
    maxTextWidth: CGFloat,
    heroFontSize: CGFloat,
    heroWeight: Int,
    heroItalic: Bool,
    clampedWidthFraction: CGFloat
  ) -> [(text: String, isHero: Bool)] {
    let explicitParagraphs = rawText
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !explicitParagraphs.isEmpty else { return [] }

    let heroCharCap: Int? = clampedWidthFraction > 0.905 ? nil : max(1, settings.maxCharsPerLine)
    let heroTracking = heroFontSize * settings.tracking.emFactor
    let leadSize = max(4, heroFontSize * 0.56)
    let leadTracking = leadSize * -0.016

    if settings.dualLineHero {
      if explicitParagraphs.count >= 2 {
        var out: [(String, Bool)] = []
        for leadWrapped in wrapParagraph(
          explicitParagraphs[0],
          maxTextWidth: maxTextWidth,
          maxCharsLimit: nil,
          fontSize: leadSize,
          customFontId: settings.customFontId,
          weight: 500,
          italic: false,
          tracking: leadTracking
        ) {
          out.append((leadWrapped, false))
        }
        for heroRaw in explicitParagraphs.dropFirst() {
          let cased = settings.textCase.apply(to: heroRaw)
          for wrapped in wrapParagraph(
            cased,
            maxTextWidth: maxTextWidth,
            maxCharsLimit: heroCharCap,
            fontSize: heroFontSize,
            customFontId: settings.customFontId,
            weight: heroWeight,
            italic: heroItalic,
            tracking: heroTracking
          ) {
            out.append((wrapped, true))
          }
        }
        return out
      }

      let words = explicitParagraphs[0].split(whereSeparator: \.isWhitespace).map(String.init)
      if words.count >= 4 {
        let leadCount = max(2, min(words.count - 2, Int((Double(words.count) * 0.42).rounded(.down))))
        let leadText = words.prefix(leadCount).joined(separator: " ")
        let heroRaw = words.dropFirst(leadCount).joined(separator: " ")
        let heroCased = settings.textCase.apply(to: heroRaw)
        var out: [(String, Bool)] = []
        for leadWrapped in wrapParagraph(
          leadText,
          maxTextWidth: maxTextWidth,
          maxCharsLimit: nil,
          fontSize: leadSize,
          customFontId: settings.customFontId,
          weight: 500,
          italic: false,
          tracking: leadTracking
        ) {
          out.append((leadWrapped, false))
        }
        for hl in wrapParagraph(
          heroCased,
          maxTextWidth: maxTextWidth,
          maxCharsLimit: heroCharCap,
          fontSize: heroFontSize,
          customFontId: settings.customFontId,
          weight: heroWeight,
          italic: heroItalic,
          tracking: heroTracking
        ) {
          out.append((hl, true))
        }
        return out
      }
    }

    let casedText = settings.textCase.apply(to: rawText)
    return casedText
      .split(whereSeparator: \.isNewline)
      .flatMap {
        wrapParagraph(
          String($0),
          maxTextWidth: maxTextWidth,
          maxCharsLimit: heroCharCap,
          fontSize: heroFontSize,
          customFontId: settings.customFontId,
          weight: heroWeight,
          italic: heroItalic,
          tracking: heroTracking
        )
      }
      .map { ($0, true) }
  }

  private static func wrapParagraph(
    _ text: String,
    maxTextWidth: CGFloat,
    maxCharsLimit: Int?,
    fontSize: CGFloat,
    customFontId: String,
    weight: Int,
    italic: Bool,
    tracking: CGFloat
  ) -> [String] {
    let tokens = breakTokens(text)
    guard !tokens.isEmpty else { return [] }
    var lines: [String] = []
    var current = ""
    for token in tokens {
      let candidate = current.isEmpty ? token : VideoEditorCaptionSegmenter.join([current, token])
      if !current.isEmpty {
        let exceedsChars = maxCharsLimit.map { candidate.count > $0 } ?? false
        let exceedsWidth = width(
          of: candidate,
          fontSize: fontSize,
          customFontId: customFontId,
          weight: weight,
          italic: italic,
          tracking: tracking
        ) > maxTextWidth
        if exceedsChars || exceedsWidth {
          lines.append(current)
          current = token
          continue
        }
      }
      current = candidate
    }
    if !current.isEmpty {
      lines.append(current)
    }
    return lines
  }

  private static func breakTokens(_ text: String) -> [String] {
    var tokens: [String] = []
    for word in text.split(whereSeparator: \.isWhitespace) {
      var latin = ""
      for character in word {
        if VideoEditorCaptionSegmenter.isCJK(character) {
          if !latin.isEmpty {
            tokens.append(latin)
            latin = ""
          }
          tokens.append(String(character))
        } else {
          latin.append(character)
        }
      }
      if !latin.isEmpty {
        tokens.append(latin)
      }
    }
    return tokens
  }

  func frame(in videoRect: CGRect, settings: VideoEditorCaptionSettings) -> CGRect {
    let margin = settings.margin * videoRect.height
    let y: CGFloat = switch settings.position {
    case .top:
      videoRect.minY + margin
    case .center:
      videoRect.midY - size.height / 2
    case .bottom:
      videoRect.maxY - margin - size.height
    }
    return CGRect(x: videoRect.midX - size.width / 2, y: y, width: size.width, height: size.height)
  }

  func bitmapFrame(in videoRect: CGRect, settings: VideoEditorCaptionSettings) -> CGRect {
    let logical = frame(in: videoRect, settings: settings)
    let delta = outerOutset * unit
    return logical.insetBy(dx: -delta, dy: -delta)
  }

  static func makeFont(
    size: CGFloat,
    bold: Bool,
    italic: Bool = false,
    family: VideoEditorCaptionSettings.FontFamily = .montserratBold,
    customFontId: String = VideoEditorFontResolver.defaultFamilyId,
    explicitWeight: Int? = nil
  ) -> CTFont {
    let wght = explicitWeight ?? (bold ? max(700, family.baseWeight) : min(600, family.baseWeight))
    let ital = italic || family.isIntrinsicItalic
    return VideoEditorFontResolver.resolveFont(
      familyId: customFontId,
      size: size,
      weight: wght,
      italic: ital
    ).font
  }

  static func width(
    of line: String,
    fontSize: CGFloat,
    customFontId: String = VideoEditorFontResolver.defaultFamilyId,
    weight: Int = 700,
    italic: Bool = false,
    tracking: CGFloat = 0
  ) -> CGFloat {
    let resolved = VideoEditorFontResolver.resolveFont(
      familyId: customFontId,
      size: fontSize,
      weight: weight,
      italic: italic
    )
    let ctLine = CTLineCreateWithAttributedString(
      attributed(
        line,
        font: resolved.font,
        color: nil,
        tracking: tracking,
        strokeWidth: resolved.needsSyntheticBoldStroke ? -2.2 : 0,
        strokeColor: nil
      )
    )
    let overhang: CGFloat = italic ? fontSize * 0.14 : 0
    return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)) + overhang
  }

  static func attributed(
    _ text: String,
    font: CTFont,
    color: CGColor?,
    tracking: CGFloat = 0,
    strokeWidth: CGFloat = 0,
    strokeColor: CGColor? = nil
  ) -> NSAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [
      .init(kCTFontAttributeName as String): font,
    ]
    if abs(tracking) > 0.001 {
      attributes[.init(kCTKernAttributeName as String)] = tracking as NSNumber
    }
    if let color {
      attributes[.init(kCTForegroundColorAttributeName as String)] = color
    }
    if strokeWidth != 0 {
      attributes[.init(kCTStrokeWidthAttributeName as String)] = strokeWidth as NSNumber
      if let strokeColor {
        attributes[.init(kCTStrokeColorAttributeName as String)] = strokeColor
      }
    }
    return NSAttributedString(string: text, attributes: attributes)
  }

  fileprivate static func leadingAccessoryAdvance(
    fontSize: CGFloat,
    surface: VideoEditorCaptionSettings.SurfaceStyle
  ) -> CGFloat {
    switch surface {
    case .monoTag:
      fontSize * 0.42
    case .accentRule:
      fontSize * 0.20
    default:
      0
    }
  }

  private static func horizontalPadding(
    fontSize: CGFloat,
    surface: VideoEditorCaptionSettings.SurfaceStyle
  ) -> CGFloat {
    switch surface {
    case .classicPill:
      fontSize * 0.55
    case .solarPill:
      fontSize * 0.50
    case .monoTag:
      fontSize * 0.48
    case .rangeHighlight:
      fontSize * 0.28
    case .selectionFrame:
      fontSize * 0.44
    case .studioGlass, .editorialPaper:
      fontSize * 0.56
    case .accentRule:
      fontSize * 0.64
    case .glowBloom, .cinemaClean:
      fontSize * 0.28
    }
  }

  private static func verticalPadding(
    fontSize: CGFloat,
    surface: VideoEditorCaptionSettings.SurfaceStyle
  ) -> CGFloat {
    switch surface {
    case .classicPill:
      fontSize * 0.30
    case .solarPill, .monoTag:
      fontSize * 0.25
    case .rangeHighlight:
      fontSize * 0.14
    case .selectionFrame:
      fontSize * 0.22
    case .studioGlass, .editorialPaper, .accentRule:
      fontSize * 0.30
    case .glowBloom, .cinemaClean:
      fontSize * 0.14
    }
  }
}

/// Anti-slop bitmap renderer supporting per-word cascades, typewriter cursor, split-tone &
/// hollow-hero treatments, synthetic bold/italic, and restrained studio surfaces.
nonisolated enum VideoEditorCaptionRenderer {
  private static let leadLineInk = CGColor(srgbRed: 0.98, green: 0.98, blue: 0.988, alpha: 1)

  static func image(
    _ layout: VideoEditorCaptionLayout,
    settings: VideoEditorCaptionSettings,
    activeWordIndex: Int? = nil,
    activeWordArrivalProgress: CGFloat? = nil,
    subwordKind: VideoEditorCaptionMotionState.SubwordAnimationKind? = nil,
    subwordProgress: CGFloat? = nil,
    scale: CGFloat = 1
  ) -> CGImage? {
    let width = Int(ceil(layout.bitmapSize.width * scale))
    let height = Int(ceil(layout.bitmapSize.height * scale))
    guard width > 0, height > 0,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    context.scaleBy(x: scale * layout.unit, y: scale * layout.unit)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setShouldSmoothFonts(false)

    let box = CGRect(
      x: layout.outerOutset,
      y: layout.outerOutset,
      width: layout.referenceSize.width,
      height: layout.referenceSize.height
    )

    drawSurface(in: context, box: box, layout: layout, settings: settings)

    let totalWords = max(1, layout.flatWords.count)
    let totalUTF16Chars = max(1, layout.lines.map { ($0 as NSString).length }.reduce(0, +))
    var runningCharOffset = 0
    var cursorTopY = box.maxY - layout.padding.height
    let accessoryLead = VideoEditorCaptionLayout.leadingAccessoryAdvance(
      fontSize: layout.fontSize,
      surface: settings.surfaceStyle
    )

    let wordArrival = activeWordArrivalProgress ?? 1.0
    let wordTransform: VideoEditorWordKineticTransform = (settings.wordMode != .fullLine && settings
      .wordAnimation != .none)
      ? VideoEditorCaptionMotion.wordMotionTransform(style: settings.wordAnimation, arrivalProgress: wordArrival)
      : .identity
    let isAnimatingActiveWord = settings.wordMode != .fullLine
      && settings.wordAnimation != .none
      && wordArrival < 0.999

    for (lineIdx, spec) in layout.lineSpecs.enumerated() {
      let line = spec.text
      let nsLineLen = (line as NSString).length
      defer { runningCharOffset += nsLineLen }

      let resolved = VideoEditorFontResolver.resolveFont(
        familyId: spec.customFontId,
        size: spec.fontSize,
        weight: spec.weight,
        italic: spec.isItalic
      )
      let font = resolved.font
      let syntheticBoldStroke: CGFloat = resolved.needsSyntheticBoldStroke ? -2.2 : 0

      let baseCTLine = CTLineCreateWithAttributedString(
        VideoEditorCaptionLayout.attributed(
          line,
          font: font,
          color: spec.isHero ? settings.textCGColor : leadLineInk,
          tracking: spec.trackingPoints,
          strokeWidth: syntheticBoldStroke,
          strokeColor: spec.isHero ? settings.textCGColor : leadLineInk
        )
      )
      let lineWidth = CGFloat(CTLineGetTypographicBounds(baseCTLine, nil, nil, nil))
      let lineX: CGFloat = switch settings.surfaceStyle {
      case .accentRule, .monoTag:
        box.minX + layout.padding.width + accessoryLead
      default:
        box.midX - lineWidth / 2
      }
      let baseline = cursorTopY - spec.ascent
      cursorTopY -= spec.lineHeight

      let spans = lineIdx < layout.lineWordSpans.count ? layout.lineWordSpans[lineIdx] : []
      let activeSpanOnLine = activeWordIndex.flatMap { idx in spans.first { $0.globalIndex == idx } }
      let drawAnimatedWordSeparately = isAnimatingActiveWord && activeSpanOnLine != nil

      // Fast staggered per-word entrance (`wordCascade` / `wordFocus`)
      if let kind = subwordKind,
         let p = subwordProgress,
         kind == .wordCascade || kind == .wordFocus,
         p < 0.999 {
        drawStaggeredWordsLine(
          in: context,
          baseCTLine: baseCTLine,
          spans: spans,
          spec: spec,
          lineX: lineX,
          baseline: baseline,
          totalWords: totalWords,
          kind: kind,
          progress: p,
          syntheticBoldStroke: syntheticBoldStroke,
          settings: settings
        )
        continue
      }

      // Character-level Typewriter Pro with live accent cursor bar
      if subwordKind == .typewriter, let p = subwordProgress, p < 0.999 {
        let visibleGlobalChars = max(1, Int((CGFloat(totalUTF16Chars) * p).rounded(.up)))
        let localVisible = min(nsLineLen, max(0, visibleGlobalChars - runningCharOffset))
        if localVisible > 0 {
          drawTypewriterLine(
            in: context,
            line: line,
            baseCTLine: baseCTLine,
            visibleUTF16Count: localVisible,
            drawCursor: visibleGlobalChars >= runningCharOffset && visibleGlobalChars <= runningCharOffset + nsLineLen,
            font: font,
            spec: spec,
            lineX: lineX,
            baseline: baseline,
            syntheticBoldStroke: syntheticBoldStroke,
            settings: settings
          )
        }
        continue
      }

      // 1. Active word highlight pill (with smooth word-to-word glide & spring scale physics)
      let hasActivePillOnThisLine: Bool
      if settings.wordMode == .activeHighlight,
         let activeIdx = activeWordIndex,
         let activeSpan = activeSpanOnLine {
        hasActivePillOnThisLine = true
        let startOff = CTLineGetOffsetForStringIndex(baseCTLine, activeSpan.utf16Location, nil)
        let endOff = CTLineGetOffsetForStringIndex(baseCTLine, activeSpan.utf16Location + activeSpan.utf16Length, nil)
        var wordMinX = lineX + min(startOff, endOff)
        var wordMaxX = lineX + max(startOff, endOff)

        if isAnimatingActiveWord,
           activeIdx > 0,
           let prevSpan = spans.first(where: { $0.globalIndex == activeIdx - 1 }) {
          let prevStart = CTLineGetOffsetForStringIndex(baseCTLine, prevSpan.utf16Location, nil)
          let prevEnd = CTLineGetOffsetForStringIndex(baseCTLine, prevSpan.utf16Location + prevSpan.utf16Length, nil)
          let prevMinX = lineX + min(prevStart, prevEnd)
          let prevMaxX = lineX + max(prevStart, prevEnd)
          let slide = min(1.04, max(0, wordTransform.pillSlideProgress))
          wordMinX = prevMinX + (wordMinX - prevMinX) * slide
          wordMaxX = prevMaxX + (wordMaxX - prevMaxX) * slide
        }

        let padX = max(4.5, spec.fontSize * 0.16)
        let padY = max(2.0, spec.fontSize * 0.07)
        let pillYShift = isAnimatingActiveWord ? (wordTransform.offsetYEm * spec.fontSize * 0.42) : 0
        let pillXShift = isAnimatingActiveWord ? (wordTransform.offsetXEm * spec.fontSize * 0.42) : 0
        let rawPillRect = CGRect(
          x: wordMinX - padX + pillXShift,
          y: baseline - spec.descent - padY + pillYShift,
          width: max(8, (wordMaxX - wordMinX) + 2 * padX),
          height: spec.ascent + spec.descent + 2 * padY
        )
        let pillScale = isAnimatingActiveWord ? (1.0 + (wordTransform.scale - 1.0) * 0.55) : 1.0
        let pillRadius = min(spec.fontSize * 0.18, rawPillRect.height / 2)
        context.saveGState()
        if abs(pillScale - 1.0) > 0.002 {
          context.translateBy(x: rawPillRect.midX, y: rawPillRect.midY)
          context.scaleBy(x: pillScale, y: pillScale * wordTransform.scaleY)
          context.translateBy(x: -rawPillRect.midX, y: -rawPillRect.midY)
        }
        if isAnimatingActiveWord, wordTransform.glowBoost > 0.02 {
          context.setShadow(
            offset: .zero,
            blur: max(6, spec.fontSize * 0.24),
            color: settings.accentCGColor.copy(alpha: min(0.55, wordTransform.glowBoost * 0.65)) ?? settings
              .accentCGColor
          )
        }
        context.addPath(CGPath(
          roundedRect: rawPillRect,
          cornerWidth: pillRadius,
          cornerHeight: pillRadius,
          transform: nil
        ))
        context.setFillColor(settings.accentCGColor.copy(alpha: wordTransform.opacity) ?? settings.accentCGColor)
        context.fillPath()
        context.restoreGState()
      } else {
        hasActivePillOnThisLine = false
      }

      // 2. Restrained Studio Optical Aura + Crisp Grounding Shadow
      if spec.isHero, settings.glowIntensity > 0.01 {
        let auraProbe = buildStyledCTLine(
          line: line,
          spans: spans,
          totalWords: totalWords,
          font: font,
          tracking: spec.trackingPoints,
          primaryInk: settings.glowCGColor,
          settings: settings,
          activeWordIndex: activeWordIndex,
          asStrokeOnly: false,
          strokeWidth: syntheticBoldStroke,
          omitActiveHighlightWord: drawAnimatedWordSeparately,
          applyTreatment: false
        )
        let auraAlpha = min(0.46, 0.78 * settings.glowIntensity)
        context.saveGState()
        context.setShadow(
          offset: .zero,
          blur: max(9, spec.fontSize * 0.34),
          color: CGColor(
            srgbRed: settings.glowColor.red,
            green: settings.glowColor.green,
            blue: settings.glowColor.blue,
            alpha: auraAlpha
          )
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.textPosition = CGPoint(x: lineX, y: baseline)
        CTLineDraw(auraProbe, context)
        context.endTransparencyLayer()
        context.restoreGState()
      }

      if !settings.surfaceStyle.drawsBackdropBox, settings.surfaceStyle != .cinemaClean {
        let shadowProbe = buildStyledCTLine(
          line: line,
          spans: spans,
          totalWords: totalWords,
          font: font,
          tracking: spec.trackingPoints,
          primaryInk: spec.isHero ? settings.textCGColor : leadLineInk,
          settings: settings,
          activeWordIndex: activeWordIndex,
          asStrokeOnly: false,
          strokeWidth: syntheticBoldStroke,
          omitActiveHighlightWord: drawAnimatedWordSeparately,
          applyTreatment: spec.isHero
        )
        context.saveGState()
        context.setShadow(
          offset: CGSize(width: 0, height: -max(1.5, spec.fontSize * 0.042)),
          blur: max(3.2, spec.fontSize * 0.085),
          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.68)
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.textPosition = CGPoint(x: lineX, y: baseline)
        CTLineDraw(shadowProbe, context)
        context.endTransparencyLayer()
        context.restoreGState()
      }

      // 3. Optical stroke pass for `.cinemaClean` or 0%-opacity `.classicPill`
      let needsOpticalStroke = settings.surfaceStyle == .cinemaClean
        || (settings.surfaceStyle == .classicPill && settings.backgroundOpacity < 0.2)

      if needsOpticalStroke {
        let strokeLine = buildStyledCTLine(
          line: line,
          spans: spans,
          totalWords: totalWords,
          font: font,
          tracking: spec.trackingPoints,
          primaryInk: spec.isHero ? settings.textCGColor : leadLineInk,
          settings: settings,
          activeWordIndex: activeWordIndex,
          asStrokeOnly: true,
          strokeWidth: 4.0,
          omitActiveHighlightWord: drawAnimatedWordSeparately,
          applyTreatment: false
        )
        context.saveGState()
        if settings.surfaceStyle == .cinemaClean {
          context.setShadow(
            offset: CGSize(width: 0, height: -max(2, spec.fontSize * 0.06)),
            blur: max(5, spec.fontSize * 0.16),
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
          )
        }
        context.textPosition = CGPoint(x: lineX, y: baseline)
        CTLineDraw(strokeLine, context)
        context.restoreGState()
      }

      // 4. Foreground Fill Pass (Tonal Gradient or Treatment-Styled Ink)
      if spec.isHero, settings.useGradientText, settings.textTreatment == .solid,
         let gradient = CGGradient(
           colorsSpace: space,
           colors: [settings.textCGColor, settings.textGradientEndCGColor] as CFArray,
           locations: [0.0, 1.0]
         ) {
        let maskLine = buildStyledCTLine(
          line: line,
          spans: spans,
          totalWords: totalWords,
          font: font,
          tracking: spec.trackingPoints,
          primaryInk: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
          settings: settings,
          activeWordIndex: activeWordIndex,
          asStrokeOnly: false,
          strokeWidth: syntheticBoldStroke,
          omitActiveHighlightWord: hasActivePillOnThisLine || drawAnimatedWordSeparately,
          applyTreatment: false
        )
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.textPosition = CGPoint(x: lineX, y: baseline)
        CTLineDraw(maskLine, context)
        context.setBlendMode(.sourceIn)
        context.drawLinearGradient(
          gradient,
          start: CGPoint(x: box.midX - lineWidth * 0.12, y: baseline + spec.ascent * 0.92),
          end: CGPoint(x: box.midX + lineWidth * 0.12, y: baseline - spec.descent * 0.45),
          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.endTransparencyLayer()
        context.restoreGState()

        if hasActivePillOnThisLine, !drawAnimatedWordSeparately, let activeIdx = activeWordIndex {
          let activeOnlyLine = buildActiveWordOnlyCTLine(
            line: line,
            spans: spans,
            font: font,
            tracking: spec.trackingPoints,
            activeWordIndex: activeIdx,
            ink: settings.contrastInkOnAccentCGColor,
            syntheticBoldStroke: syntheticBoldStroke
          )
          context.textPosition = CGPoint(x: lineX, y: baseline)
          CTLineDraw(activeOnlyLine, context)
        }
      } else {
        let fillLine = buildStyledCTLine(
          line: line,
          spans: spans,
          totalWords: totalWords,
          font: font,
          tracking: spec.trackingPoints,
          primaryInk: spec.isHero ? settings.textCGColor : leadLineInk,
          settings: settings,
          activeWordIndex: activeWordIndex,
          asStrokeOnly: false,
          strokeWidth: syntheticBoldStroke,
          omitActiveHighlightWord: drawAnimatedWordSeparately,
          applyTreatment: spec.isHero
        )
        context.textPosition = CGPoint(x: lineX, y: baseline)
        CTLineDraw(fillLine, context)
      }

      // 5. Kinetic Per-Word Arrival Pass (`activeHighlight` & `progressiveReveal`)
      if drawAnimatedWordSeparately, let activeSpan = activeSpanOnLine {
        drawKineticActiveWord(
          in: context,
          baseCTLine: baseCTLine,
          activeSpan: activeSpan,
          font: font,
          spec: spec,
          lineX: lineX,
          baseline: baseline,
          syntheticBoldStroke: syntheticBoldStroke,
          transform: wordTransform,
          settings: settings
        )
      }
    }

    return context.makeImage()
  }

  // MARK: - Subword Cascade & Typewriter Renderers

  private static func drawStaggeredWordsLine(
    in context: CGContext,
    baseCTLine: CTLine,
    spans: [VideoEditorCaptionLayout.WordSpan],
    spec: VideoEditorCaptionLayout.LineSpec,
    lineX: CGFloat,
    baseline: CGFloat,
    totalWords: Int,
    kind: VideoEditorCaptionMotionState.SubwordAnimationKind,
    progress: CGFloat,
    syntheticBoldStroke: CGFloat,
    settings: VideoEditorCaptionSettings
  ) {
    let font = VideoEditorFontResolver.resolveFont(
      familyId: spec.customFontId,
      size: spec.fontSize,
      weight: spec.weight,
      italic: spec.isItalic
    ).font
    let stagger: CGFloat = 0.28
    let totalSpan = 1.0 + stagger * CGFloat(max(0, totalWords - 1))

    for span in spans {
      let localRaw = min(1, max(0, (progress * totalSpan) - CGFloat(span.globalIndex) * stagger))
      guard localRaw > 0.005 else { continue }
      let p = VideoEditorCaptionMotion.easeOutExpo(localRaw)
      let alpha = VideoEditorCaptionMotion.easeOutQuart(min(1, localRaw * 1.25))
      let yShift: CGFloat = kind == .wordCascade ? -(1 - p) * spec.fontSize * 0.34 : 0

      let wordOffsetX = CTLineGetOffsetForStringIndex(baseCTLine, span.utf16Location, nil)
      let isLastWord = totalWords > 1 && span.globalIndex == totalWords - 1
      let wordInk: CGColor = if spec.isHero, settings.textTreatment == .splitAccent, isLastWord {
        settings.accentCGColor
      } else if spec.isHero, settings.useGradientText {
        settings.textGradientEndCGColor
      } else {
        spec.isHero ? settings.textCGColor : leadLineInk
      }

      var attrs: [NSAttributedString.Key: Any] = [
        .init(kCTFontAttributeName as String): font,
        .init(kCTForegroundColorAttributeName as String): wordInk.copy(alpha: alpha) ?? wordInk,
      ]
      if abs(spec.trackingPoints) > 0.001 {
        attrs[.init(kCTKernAttributeName as String)] = spec.trackingPoints as NSNumber
      }
      if syntheticBoldStroke != 0 {
        attrs[.init(kCTStrokeWidthAttributeName as String)] = syntheticBoldStroke as NSNumber
        attrs[.init(kCTStrokeColorAttributeName as String)] = wordInk.copy(alpha: alpha) ?? wordInk
      }

      let wordCT = CTLineCreateWithAttributedString(NSAttributedString(string: span.text, attributes: attrs))
      context.saveGState()
      if !settings.surfaceStyle.drawsBackdropBox {
        context.setShadow(
          offset: CGSize(width: 0, height: -max(1.4, spec.fontSize * 0.04)),
          blur: max(3.0, spec.fontSize * 0.08),
          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.65 * alpha)
        )
      }
      context.textPosition = CGPoint(x: lineX + wordOffsetX, y: baseline + yShift)
      CTLineDraw(wordCT, context)
      context.restoreGState()
    }
  }

  private static func drawTypewriterLine(
    in context: CGContext,
    line: String,
    baseCTLine: CTLine,
    visibleUTF16Count: Int,
    drawCursor: Bool,
    font: CTFont,
    spec: VideoEditorCaptionLayout.LineSpec,
    lineX: CGFloat,
    baseline: CGFloat,
    syntheticBoldStroke: CGFloat,
    settings: VideoEditorCaptionSettings
  ) {
    let nsLen = (line as NSString).length
    let ink = spec.isHero ? settings.textCGColor : leadLineInk
    let transparent = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    var attrs: [NSAttributedString.Key: Any] = [
      .init(kCTFontAttributeName as String): font,
      .init(kCTForegroundColorAttributeName as String): ink,
    ]
    if abs(spec.trackingPoints) > 0.001 {
      attrs[.init(kCTKernAttributeName as String)] = spec.trackingPoints as NSNumber
    }
    if syntheticBoldStroke != 0 {
      attrs[.init(kCTStrokeWidthAttributeName as String)] = syntheticBoldStroke as NSNumber
      attrs[.init(kCTStrokeColorAttributeName as String)] = ink
    }

    let mutable = NSMutableAttributedString(string: line, attributes: attrs)
    if visibleUTF16Count < nsLen {
      let hiddenRange = NSRange(location: visibleUTF16Count, length: nsLen - visibleUTF16Count)
      mutable.addAttribute(.init(kCTForegroundColorAttributeName as String), value: transparent, range: hiddenRange)
      if syntheticBoldStroke != 0 {
        mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: transparent, range: hiddenRange)
      }
    }

    let typedCT = CTLineCreateWithAttributedString(mutable)
    context.textPosition = CGPoint(x: lineX, y: baseline)
    CTLineDraw(typedCT, context)

    if drawCursor {
      let caretX = lineX + CTLineGetOffsetForStringIndex(baseCTLine, visibleUTF16Count, nil) + max(
        2,
        spec.fontSize * 0.05
      )
      let caretW = max(2.2, spec.fontSize * 0.055)
      let caretRect = CGRect(
        x: caretX,
        y: baseline - spec.descent * 0.75,
        width: caretW,
        height: spec.ascent + spec.descent * 0.65
      )
      context.setFillColor(settings.accentCGColor)
      context.fill(caretRect)
    }
  }

  // MARK: - Surface Renderers

  private static func drawSurface(
    in context: CGContext,
    box: CGRect,
    layout: VideoEditorCaptionLayout,
    settings: VideoEditorCaptionSettings
  ) {
    let opacity = min(max(settings.backgroundOpacity, 0), 1)

    switch settings.surfaceStyle {
    case .classicPill:
      guard opacity > 0 else { return }
      let radius = min(layout.fontSize * 0.35, box.height / 2)
      context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
      context.setFillColor(settings.backgroundCGColor)
      context.fillPath()

    case .solarPill:
      guard opacity > 0.01 else { return }
      let radius = min(layout.fontSize * 0.22, box.height * 0.26)
      let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -max(2.5, layout.fontSize * 0.07)),
        blur: max(8, layout.fontSize * 0.22),
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34 * opacity)
      )
      context.addPath(path)
      context.setFillColor(settings.backgroundCGColor)
      context.fillPath()
      context.restoreGState()

    case .monoTag:
      // Teenage Engineering / Linear technical tag: matte slate frame + 1px hairline + leading status dot
      guard opacity > 0.01 else { return }
      let radius = min(layout.fontSize * 0.20, box.height * 0.24)
      let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -max(2.5, layout.fontSize * 0.07)),
        blur: max(8, layout.fontSize * 0.20),
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.40 * opacity)
      )
      context.addPath(path)
      context.setFillColor(settings.backgroundCGColor)
      context.fillPath()
      context.restoreGState()

      context.addPath(CGPath(
        roundedRect: box.insetBy(dx: 0.75, dy: 0.75),
        cornerWidth: max(1, radius - 0.75),
        cornerHeight: max(1, radius - 0.75),
        transform: nil
      ))
      context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14 * opacity))
      context.setLineWidth(1.2)
      context.strokePath()

      let dotD = max(5.5, layout.fontSize * 0.20)
      let dotX = box.minX + layout.padding.width + dotD * 0.15
      let dotY = box.midY - dotD / 2
      context.setFillColor(settings.accentCGColor)
      context.fillEllipse(in: CGRect(x: dotX, y: dotY, width: dotD, height: dotD))

    case .rangeHighlight:
      if opacity > 0.01 {
        context.setFillColor(settings.backgroundCGColor)
        context.fill(box)
      }
      let stemW = max(2.0, layout.fontSize * 0.05)
      let pinR = max(3.6, layout.fontSize * 0.095)
      context.setFillColor(settings.accentCGColor)
      context.fill(CGRect(x: box.minX - stemW / 2, y: box.minY, width: stemW, height: box.height))
      context.fillEllipse(in: CGRect(x: box.minX - pinR, y: box.maxY - pinR * 0.3, width: pinR * 2, height: pinR * 2))
      context.fill(CGRect(x: box.maxX - stemW / 2, y: box.minY, width: stemW, height: box.height))
      context.fillEllipse(in: CGRect(x: box.maxX - pinR, y: box.minY - pinR * 1.7, width: pinR * 2, height: pinR * 2))

    case .selectionFrame:
      context.setStrokeColor(settings.accentCGColor)
      context.setLineWidth(max(1.25, layout.fontSize * 0.028))
      context.stroke(box)

      let handleSide = max(4.8, layout.fontSize * 0.105)
      let half = handleSide / 2
      let anchors: [CGPoint] = [
        CGPoint(x: box.minX, y: box.minY),
        CGPoint(x: box.midX, y: box.minY),
        CGPoint(x: box.maxX, y: box.minY),
        CGPoint(x: box.minX, y: box.midY),
        CGPoint(x: box.maxX, y: box.midY),
        CGPoint(x: box.minX, y: box.maxY),
        CGPoint(x: box.midX, y: box.maxY),
        CGPoint(x: box.maxX, y: box.maxY),
      ]
      for pt in anchors {
        let hRect = CGRect(x: pt.x - half, y: pt.y - half, width: handleSide, height: handleSide)
        context.setFillColor(CGColor(srgbRed: 0.99, green: 0.99, blue: 1, alpha: 1))
        context.fill(hRect)
        context.setStrokeColor(settings.accentCGColor)
        context.setLineWidth(max(1.2, layout.fontSize * 0.026))
        context.stroke(hRect)
      }

    case .studioGlass:
      guard opacity > 0.01 else { return }
      let radius = min(layout.fontSize * 0.34, box.height / 2)
      let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -max(3, layout.fontSize * 0.08)),
        blur: max(9, layout.fontSize * 0.24),
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.42 * opacity)
      )
      context.addPath(path)
      context.setFillColor(settings.backgroundCGColor)
      context.fillPath()
      context.restoreGState()

      let insetBox = box.insetBy(dx: 0.75, dy: 0.75)
      context.addPath(CGPath(
        roundedRect: insetBox,
        cornerWidth: max(1, radius - 0.75),
        cornerHeight: max(1, radius - 0.75),
        transform: nil
      ))
      context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12 * opacity))
      context.setLineWidth(1.2)
      context.strokePath()

    case .editorialPaper:
      guard opacity > 0.01 else { return }
      let radius = min(layout.fontSize * 0.20, box.height / 2)
      let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -max(2.5, layout.fontSize * 0.07)),
        blur: max(8, layout.fontSize * 0.20),
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.24 * opacity)
      )
      context.addPath(path)
      context.setFillColor(settings.backgroundCGColor)
      context.fillPath()
      context.restoreGState()

    case .accentRule:
      guard opacity > 0.01 else { return }
      let radius = min(layout.fontSize * 0.22, box.height / 2)
      let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -max(3, layout.fontSize * 0.08)),
        blur: max(8, layout.fontSize * 0.20),
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34 * opacity)
      )
      context.addPath(path)
      context.setFillColor(settings.backgroundCGColor)
      context.fillPath()
      context.restoreGState()

      let barW = max(3.5, layout.fontSize * 0.10)
      let insetY = max(6, box.height * 0.18)
      let barRect = CGRect(
        x: box.minX + max(6, layout.fontSize * 0.18),
        y: box.minY + insetY,
        width: barW,
        height: max(6, box.height - 2 * insetY)
      )
      context.addPath(CGPath(roundedRect: barRect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
      context.setFillColor(settings.accentCGColor)
      context.fillPath()

    case .glowBloom, .cinemaClean:
      break
    }
  }

  private static func buildStyledCTLine(
    line: String,
    spans: [VideoEditorCaptionLayout.WordSpan],
    totalWords: Int,
    font: CTFont,
    tracking: CGFloat,
    primaryInk: CGColor,
    settings: VideoEditorCaptionSettings,
    activeWordIndex: Int?,
    asStrokeOnly: Bool,
    strokeWidth: CGFloat,
    omitActiveHighlightWord: Bool = false,
    applyTreatment: Bool
  ) -> CTLine {
    let baseColor: CGColor = asStrokeOnly
      ? CGColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: 0.92)
      : primaryInk
    let transparent = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    var baseAttrs: [NSAttributedString.Key: Any] = [
      .init(kCTFontAttributeName as String): font,
      .init(kCTForegroundColorAttributeName as String): baseColor,
    ]
    if abs(tracking) > 0.001 {
      baseAttrs[.init(kCTKernAttributeName as String)] = tracking as NSNumber
    }
    if asStrokeOnly || strokeWidth != 0 {
      baseAttrs[.init(kCTStrokeColorAttributeName as String)] = baseColor
      baseAttrs[.init(kCTStrokeWidthAttributeName as String)] = strokeWidth as NSNumber
    }

    let mutable = NSMutableAttributedString(string: line, attributes: baseAttrs)

    // Editorial multi-word contrast treatments (`splitAccent` & `hollowHero`)
    if applyTreatment, !asStrokeOnly, totalWords >= 2 {
      switch settings.textTreatment {
      case .solid:
        break
      case .splitAccent:
        for span in spans where span.globalIndex == totalWords - 1 {
          let r = NSRange(location: span.utf16Location, length: span.utf16Length)
          mutable.addAttribute(
            .init(kCTForegroundColorAttributeName as String),
            value: settings.accentCGColor,
            range: r
          )
          if strokeWidth != 0 {
            mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: settings.accentCGColor, range: r)
          }
        }
      case .hollowHero:
        // Preceding words: crisp hollow outline (`+3.6` positive stroke = stroke only, transparent interior!)
        for span in spans where span.globalIndex < totalWords - 1 {
          let r = NSRange(location: span.utf16Location, length: span.utf16Length)
          mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: primaryInk, range: r)
          mutable.addAttribute(.init(kCTStrokeWidthAttributeName as String), value: 3.6 as NSNumber, range: r)
        }
      }
    }

    guard let activeIdx = activeWordIndex else {
      return CTLineCreateWithAttributedString(mutable)
    }

    switch settings.wordMode {
    case .fullLine:
      break

    case .activeHighlight:
      for span in spans where span.globalIndex == activeIdx {
        let nsRange = NSRange(location: span.utf16Location, length: span.utf16Length)
        if omitActiveHighlightWord {
          mutable.addAttribute(.init(kCTForegroundColorAttributeName as String), value: transparent, range: nsRange)
          mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: transparent, range: nsRange)
        } else if !asStrokeOnly {
          let targetInk = settings.contrastInkOnAccentCGColor
          mutable.addAttribute(.init(kCTForegroundColorAttributeName as String), value: targetInk, range: nsRange)
          if strokeWidth != 0 {
            mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: targetInk, range: nsRange)
          }
        }
      }

    case .progressiveReveal:
      for span in spans {
        let nsRange = NSRange(location: span.utf16Location, length: span.utf16Length)
        if span.globalIndex > activeIdx || (omitActiveHighlightWord && span.globalIndex == activeIdx) {
          mutable.addAttribute(.init(kCTForegroundColorAttributeName as String), value: transparent, range: nsRange)
          mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: transparent, range: nsRange)
        } else if span.globalIndex == activeIdx, !asStrokeOnly, !settings.useGradientText,
                  settings.surfaceStyle != .editorialPaper {
          mutable.addAttribute(
            .init(kCTForegroundColorAttributeName as String),
            value: settings.accentCGColor,
            range: nsRange
          )
        }
      }
    }

    return CTLineCreateWithAttributedString(mutable)
  }

  private static func drawKineticActiveWord(
    in context: CGContext,
    baseCTLine: CTLine,
    activeSpan: VideoEditorCaptionLayout.WordSpan,
    font: CTFont,
    spec: VideoEditorCaptionLayout.LineSpec,
    lineX: CGFloat,
    baseline: CGFloat,
    syntheticBoldStroke: CGFloat,
    transform: VideoEditorWordKineticTransform,
    settings: VideoEditorCaptionSettings
  ) {
    let startOff = CTLineGetOffsetForStringIndex(baseCTLine, activeSpan.utf16Location, nil)
    let endOff = CTLineGetOffsetForStringIndex(
      baseCTLine,
      activeSpan.utf16Location + activeSpan.utf16Length,
      nil
    )
    let wordMinX = lineX + min(startOff, endOff)
    let wordMaxX = lineX + max(startOff, endOff)
    let centerX = (wordMinX + wordMaxX) / 2
    let centerY = baseline + spec.ascent * 0.36

    let baseInk: CGColor = if settings.wordMode == .activeHighlight {
      settings.contrastInkOnAccentCGColor
    } else if settings.useGradientText {
      settings.textGradientEndCGColor
    } else if settings.surfaceStyle == .editorialPaper {
      spec.isHero ? settings.textCGColor : leadLineInk
    } else {
      settings.accentCGColor
    }

    let alpha = min(1, max(0.05, transform.opacity))
    let inkWithAlpha = baseInk.copy(alpha: alpha) ?? baseInk

    var attrs: [NSAttributedString.Key: Any] = [
      .init(kCTFontAttributeName as String): font,
      .init(kCTForegroundColorAttributeName as String): inkWithAlpha,
    ]
    if abs(spec.trackingPoints) > 0.001 {
      attrs[.init(kCTKernAttributeName as String)] = spec.trackingPoints as NSNumber
    }
    if syntheticBoldStroke != 0 {
      attrs[.init(kCTStrokeWidthAttributeName as String)] = syntheticBoldStroke as NSNumber
      attrs[.init(kCTStrokeColorAttributeName as String)] = inkWithAlpha
    }

    let wordCT = CTLineCreateWithAttributedString(
      NSAttributedString(string: activeSpan.text, attributes: attrs)
    )

    let dx = transform.offsetXEm * spec.fontSize
    let dy = transform.offsetYEm * spec.fontSize

    context.saveGState()
    context.translateBy(x: centerX + dx, y: centerY + dy)
    context.scaleBy(x: transform.scale, y: transform.scale * transform.scaleY)
    context.translateBy(x: -centerX, y: -centerY)

    if settings.wordMode == .progressiveReveal, transform.glowBoost > 0.02 {
      context.setShadow(
        offset: .zero,
        blur: max(6, spec.fontSize * 0.24),
        color: settings.accentCGColor.copy(alpha: min(0.60, transform.glowBoost * 0.72 * alpha)) ?? settings
          .accentCGColor
      )
    } else if settings.wordMode == .progressiveReveal, !settings.surfaceStyle.drawsBackdropBox {
      context.setShadow(
        offset: CGSize(width: 0, height: -max(1.4, spec.fontSize * 0.04)),
        blur: max(3.0, spec.fontSize * 0.08),
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.65 * alpha)
      )
    }

    context.textPosition = CGPoint(x: wordMinX, y: baseline)
    CTLineDraw(wordCT, context)
    context.restoreGState()
  }

  private static func buildActiveWordOnlyCTLine(
    line: String,
    spans: [VideoEditorCaptionLayout.WordSpan],
    font: CTFont,
    tracking: CGFloat,
    activeWordIndex: Int,
    ink: CGColor,
    syntheticBoldStroke: CGFloat
  ) -> CTLine {
    let transparent = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    var baseAttrs: [NSAttributedString.Key: Any] = [
      .init(kCTFontAttributeName as String): font,
      .init(kCTForegroundColorAttributeName as String): transparent,
    ]
    if abs(tracking) > 0.001 {
      baseAttrs[.init(kCTKernAttributeName as String)] = tracking as NSNumber
    }
    let mutable = NSMutableAttributedString(string: line, attributes: baseAttrs)
    for span in spans where span.globalIndex == activeWordIndex {
      let nsRange = NSRange(location: span.utf16Location, length: span.utf16Length)
      mutable.addAttribute(.init(kCTForegroundColorAttributeName as String), value: ink, range: nsRange)
      if syntheticBoldStroke != 0 {
        mutable.addAttribute(
          .init(kCTStrokeWidthAttributeName as String),
          value: syntheticBoldStroke as NSNumber,
          range: nsRange
        )
        mutable.addAttribute(.init(kCTStrokeColorAttributeName as String), value: ink, range: nsRange)
      }
    }
    return CTLineCreateWithAttributedString(mutable)
  }
}
