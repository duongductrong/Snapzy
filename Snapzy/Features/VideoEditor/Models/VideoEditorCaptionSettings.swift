//
//  VideoEditorCaptionSettings.swift
//  Snapzy
//
//  Unified anti-slop typography, custom/downloaded font family binding, explicit weight
//  (400–900) + Bold + Italic controls, 12 architectural & cinema style formats, and
//  per-word / directional / optical motion settings shared by Text (`Aa`) and Captions.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorCaptionSettings: Codable, Hashable, Sendable {
  enum Position: String, Codable, CaseIterable, Hashable, Sendable {
    case bottom
    case center
    case top
  }

  /// Legacy weight-tier enum retained for backward compatibility with older session manifests.
  enum FontFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case montserratMedium
    case montserratSemiBold
    case montserratBold
    case montserratExtraBold
    case montserratBlack
    case montserratItalic
    case montserratBoldItalic
    case montserratBlackItalic

    init(from decoder: Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(String.self)
      if let exact = FontFamily(rawValue: raw) {
        self = exact
        return
      }
      switch raw {
      case "sfHeavy", "condensedImpact":
        self = .montserratExtraBold
      case "serifItalic", "playfairItalic":
        self = .montserratBoldItalic
      case "cinemaClassic":
        self = .montserratMedium
      case "editorialSerif":
        self = .montserratSemiBold
      default:
        self = .montserratBold
      }
    }

    var baseWeight: Int {
      switch self {
      case .montserratMedium, .montserratItalic: 500
      case .montserratSemiBold: 600
      case .montserratBold, .montserratBoldItalic: 700
      case .montserratExtraBold: 800
      case .montserratBlack, .montserratBlackItalic: 900
      }
    }

    var isIntrinsicItalic: Bool {
      switch self {
      case .montserratItalic, .montserratBoldItalic, .montserratBlackItalic:
        true
      default:
        false
      }
    }
  }

  /// Explicit CSS/OpenType numeric weight (`400 ... 900`).
  enum WeightTier: Int, Codable, CaseIterable, Hashable, Sendable {
    case regular = 400
    case medium = 500
    case semiBold = 600
    case bold = 700
    case extraBold = 800
    case black = 900
  }

  /// Multi-word ink treatment for modern editorial contrast without AI slop.
  enum TextTreatment: String, Codable, CaseIterable, Hashable, Sendable {
    /// Uniform solid or subtle tonal gradient across the line.
    case solid
    /// Final key word rendered in crisp `accentColor` while preceding words stay `textColor`.
    case splitAccent
    /// Preceding words rendered in crisp hollow vector outline; final hero word in solid ink.
    case hollowHero
  }

  enum SurfaceStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case classicPill
    case glowBloom
    case rangeHighlight
    case selectionFrame
    case solarPill
    case studioGlass
    case editorialPaper
    case monoTag
    case accentRule
    case cinemaClean

    init(from decoder: Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(String.self)
      self = SurfaceStyle(rawValue: raw) ?? .studioGlass
    }

    var drawsBackdropBox: Bool {
      switch self {
      case .glowBloom, .selectionFrame, .cinemaClean:
        false
      case .classicPill, .rangeHighlight, .solarPill, .studioGlass, .editorialPaper, .monoTag, .accentRule:
        true
      }
    }
  }

  enum TextCase: String, Codable, CaseIterable, Hashable, Sendable {
    case standard
    case uppercase
    case lowercase

    func apply(to text: String) -> String {
      switch self {
      case .standard: text
      case .uppercase: text.localizedUppercase
      case .lowercase: text.localizedLowercase
      }
    }
  }

  enum TrackingPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case tight
    case normal
    case wide
    case cinema

    var emFactor: CGFloat {
      switch self {
      case .tight: -0.026
      case .normal: -0.008
      case .wide: 0.035
      case .cinema: 0.075
      }
    }
  }

  enum WordMode: String, Codable, CaseIterable, Hashable, Sendable {
    case fullLine
    case activeHighlight
    case progressiveReveal
  }

  enum AnimationStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    /// Staggered per-word upward glide (`60ms` overlap on `expo.out`).
    case wordCascade
    /// Staggered per-word optical focus reveal (zero vertical jump).
    case wordBlurIn
    /// Crisp character-by-character typing with a live accent cursor bar.
    case typewriterPro
    /// Sleek X-axis mechanical/cinema title flip (`scaleY 0.06 -> 1.0` + vertical blur).
    case shutterFlip
    /// Wide cinema tracking smoothly pulling into settled kerning (`expo.out`).
    case trackingPull
    case opticalBlur
    case maskSlideUp
    case elasticBounce
    case whipBlur
    case neonFlicker
    case springRise
    case studioPop
    case editorialWipe
    case cinematicFade
    case driftSlide
  }

  /// 12 restrained, anti-slop studio presets. Preserves any custom/downloaded `customFontId`
  /// chosen by the user while updating weight, italic, treatment, surface, palette, and motion.
  enum EditorialPreset: String, CaseIterable, Identifiable, Sendable {
    case cyberCyan
    case velvetSerif
    case splitTone
    case hollowHero
    case rangeHighlight
    case selectFrame
    case solarSheen
    case goldSlide
    case editorialInk
    case kineticPulse
    case monoTag
    case cinemaIvory

    var id: String {
      rawValue
    }
  }

  static let fontSizeRange: ClosedRange<CGFloat> = 0.020 ... 0.160
  static let maxWidthFractionRange: ClosedRange<CGFloat> = 0.18 ... 0.96
  static let marginRange: ClosedRange<CGFloat> = 0 ... 0.28
  static let animationDurationRange: ClosedRange<TimeInterval> = 0.12 ... 0.65

  static func clampMaxWidthFraction(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0.90 }
    return min(maxWidthFractionRange.upperBound, max(maxWidthFractionRange.lowerBound, value))
  }

  var isEnabled: Bool = true
  var languageIdentifier: String?
  /// Registered font family ID in `VideoEditorFontManager` (`"system"` default,
  /// `"installed:<FamilyName>"`, or `"custom-<slug>"`).
  var customFontId: String = VideoEditorFontResolver.defaultFamilyId
  /// Explicit OpenType weight (`400 ... 900`).
  var fontWeight: Int = 700
  var fontSize: CGFloat = 0.045
  var isBold: Bool = true
  var isItalic: Bool = false
  var fontFamily: FontFamily = .montserratBold
  var textTreatment: TextTreatment = .solid
  var surfaceStyle: SurfaceStyle = .classicPill
  var textCase: TextCase = .standard
  var tracking: TrackingPreset = .normal
  var wordMode: WordMode = .fullLine
  var animationIn: AnimationStyle = .none
  var animationOut: AnimationStyle = .none
  var wordAnimation: AnimationStyle = .springRise
  var animationDuration: TimeInterval = 0.26

  var textColor = VideoEditorRGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
  var useGradientText: Bool = false
  var textGradientEndColor = VideoEditorRGBAColor(red: 0.235, green: 0.710, blue: 0.925, alpha: 1)
  var glowIntensity: CGFloat = 0
  var glowColor = VideoEditorRGBAColor(red: 0.22, green: 0.72, blue: 0.96, alpha: 1)
  var dualLineHero: Bool = false
  var shimmerSweep: Bool = false

  var backgroundColor = VideoEditorRGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
  var accentColor = VideoEditorRGBAColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
  var backgroundOpacity: CGFloat = 0.6
  var position: Position = .bottom
  var margin: CGFloat = 0.06
  /// Maximum horizontal width fraction of the video canvas (`0.18 ... 0.96`).
  var maxWidthFraction: CGFloat = 0.90
  var maxCharsPerLine: Int = 42
  var maxLines: Int = 2
  var hideDuringFastSpeed: Bool = true

  static let `default` = VideoEditorCaptionSettings()

  static var studioDefault: VideoEditorCaptionSettings {
    var s = VideoEditorCaptionSettings()
    s.apply(preset: .cyberCyan)
    return s
  }

  /// Resolved numeric weight (`400 ... 900`) honoring both `fontWeight` and `isBold`.
  var resolvedWeight: Int {
    if isBold {
      return max(700, fontWeight)
    }
    return min(600, fontWeight >= 700 ? 500 : fontWeight)
  }

  /// Resolved italic state honoring both `isItalic` and legacy `fontFamily`.
  var resolvedItalic: Bool {
    isItalic || fontFamily.isIntrinsicItalic
  }

  mutating func setWeightTier(_ tier: WeightTier) {
    fontWeight = tier.rawValue
    isBold = tier.rawValue >= 700
    syncLegacyFontFamilyEnum()
  }

  mutating func toggleBold() {
    isBold.toggle()
    if isBold, fontWeight < 700 {
      fontWeight = 700
    } else if !isBold, fontWeight >= 700 {
      fontWeight = 500
    }
    syncLegacyFontFamilyEnum()
  }

  mutating func toggleItalic() {
    isItalic.toggle()
    if !isItalic, fontFamily.isIntrinsicItalic {
      fontFamily = isBold ? .montserratBold : .montserratMedium
    }
    syncLegacyFontFamilyEnum()
  }

  mutating func syncLegacyFontFamilyEnum() {
    if isItalic {
      fontFamily = fontWeight >= 850 ? .montserratBlackItalic :
        (fontWeight >= 650 ? .montserratBoldItalic : .montserratItalic)
    } else {
      switch fontWeight {
      case 850...: fontFamily = .montserratBlack
      case 750 ..< 850: fontFamily = .montserratExtraBold
      case 650 ..< 750: fontFamily = .montserratBold
      case 550 ..< 650: fontFamily = .montserratSemiBold
      default: fontFamily = .montserratMedium
      }
    }
  }

  mutating func apply(preset: EditorialPreset) {
    isItalic = false
    useGradientText = false
    glowIntensity = 0
    dualLineHero = false
    shimmerSweep = false
    textTreatment = .solid
    wordAnimation = .springRise

    switch preset {
    case .cyberCyan:
      fontWeight = 800
      isBold = true
      surfaceStyle = .glowBloom
      textCase = .uppercase
      tracking = .tight
      wordMode = .fullLine
      dualLineHero = true
      useGradientText = true
      textColor = VideoEditorRGBAColor(red: 0.565, green: 0.925, blue: 1.0, alpha: 1)
      textGradientEndColor = VideoEditorRGBAColor(red: 0.235, green: 0.710, blue: 0.925, alpha: 1)
      glowIntensity = 0.32
      glowColor = VideoEditorRGBAColor(red: 0.145, green: 0.635, blue: 0.882, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.235, green: 0.710, blue: 0.925, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.052
      animationIn = .wordCascade
      animationOut = .cinematicFade
      animationDuration = 0.30

    case .velvetSerif:
      fontWeight = 700
      isBold = true
      isItalic = true
      surfaceStyle = .glowBloom
      textCase = .standard
      tracking = .tight
      wordMode = .fullLine
      dualLineHero = true
      useGradientText = true
      textColor = VideoEditorRGBAColor(red: 0.76, green: 0.66, blue: 1.0, alpha: 1)
      textGradientEndColor = VideoEditorRGBAColor(red: 0.549, green: 0.424, blue: 1.0, alpha: 1) // #8C6CFF
      glowIntensity = 0.34
      glowColor = VideoEditorRGBAColor(red: 0.549, green: 0.424, blue: 1.0, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.549, green: 0.424, blue: 1.0, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.054
      animationIn = .maskSlideUp
      animationOut = .whipBlur
      animationDuration = 0.26

    case .splitTone:
      // Apple / Vercel keynote dual-ink headline: pure `#FAFAFA` + crisp sky-gold/cyan final word
      fontWeight = 800
      isBold = true
      textTreatment = .splitAccent
      surfaceStyle = .glowBloom
      textCase = .standard
      tracking = .tight
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.235, green: 0.780, blue: 1.0, alpha: 1)
      glowIntensity = 0.18
      glowColor = VideoEditorRGBAColor(red: 0.235, green: 0.780, blue: 1.0, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.052
      animationIn = .wordBlurIn
      animationOut = .cinematicFade
      animationDuration = 0.30

    case .hollowHero:
      // Architectural hollow stroke lead words + solid Black 900 punchword + 3D Shutter Flip
      fontWeight = 900
      isBold = true
      textTreatment = .hollowHero
      surfaceStyle = .glowBloom
      textCase = .uppercase
      tracking = .normal
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.054
      animationIn = .shutterFlip
      animationOut = .springRise
      animationDuration = 0.26

    case .rangeHighlight:
      fontWeight = 600
      isBold = false
      surfaceStyle = .rangeHighlight
      textCase = .standard
      tracking = .tight
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
      backgroundColor = VideoEditorRGBAColor(red: 0.09, green: 0.33, blue: 0.74, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.29, green: 0.64, blue: 0.99, alpha: 1)
      backgroundOpacity = 0.74
      fontSize = 0.046
      animationIn = .editorialWipe
      animationOut = .cinematicFade
      animationDuration = 0.24

    case .selectFrame:
      fontWeight = 600
      isBold = false
      surfaceStyle = .selectionFrame
      textCase = .standard
      tracking = .tight
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.046
      animationIn = .studioPop
      animationOut = .cinematicFade
      animationDuration = 0.22

    case .solarSheen:
      fontWeight = 700
      isBold = true
      surfaceStyle = .solarPill
      textCase = .standard
      tracking = .tight
      wordMode = .fullLine
      shimmerSweep = true
      textColor = VideoEditorRGBAColor(red: 0.035, green: 0.035, blue: 0.045, alpha: 1)
      backgroundColor = VideoEditorRGBAColor(red: 1.0, green: 0.863, blue: 0.0, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 1.0, green: 0.863, blue: 0.0, alpha: 1)
      backgroundOpacity = 1.0
      fontSize = 0.046
      animationIn = .elasticBounce
      animationOut = .studioPop
      animationDuration = 0.26

    case .goldSlide:
      fontWeight = 900
      isBold = true
      surfaceStyle = .glowBloom
      textCase = .uppercase
      tracking = .tight
      wordMode = .fullLine
      useGradientText = true
      textColor = VideoEditorRGBAColor(red: 0.996, green: 0.925, blue: 0.45, alpha: 1)
      textGradientEndColor = VideoEditorRGBAColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1)
      glowIntensity = 0.26
      glowColor = VideoEditorRGBAColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.052
      animationIn = .maskSlideUp
      animationOut = .springRise
      animationDuration = 0.24

    case .editorialInk:
      fontWeight = 700
      isBold = true
      surfaceStyle = .editorialPaper
      textCase = .standard
      tracking = .tight
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
      backgroundColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.549, green: 0.424, blue: 1.0, alpha: 1)
      backgroundOpacity = 0.98
      fontSize = 0.045
      animationIn = .springRise
      animationOut = .opticalBlur
      animationDuration = 0.24

    case .kineticPulse:
      fontWeight = 700
      isBold = true
      surfaceStyle = .studioGlass
      textCase = .standard
      tracking = .tight
      wordMode = .activeHighlight
      wordAnimation = .studioPop
      textColor = VideoEditorRGBAColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
      backgroundColor = VideoEditorRGBAColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.235, green: 0.710, blue: 0.925, alpha: 1)
      backgroundOpacity = 0.88
      fontSize = 0.046
      animationIn = .opticalBlur
      animationOut = .cinematicFade
      animationDuration = 0.22

    case .monoTag:
      fontWeight = 600
      isBold = false
      surfaceStyle = .monoTag
      textCase = .standard
      tracking = .normal
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 0.945, green: 0.961, blue: 0.976, alpha: 1)
      backgroundColor = VideoEditorRGBAColor(red: 0.035, green: 0.051, blue: 0.086, alpha: 1)
      accentColor = VideoEditorRGBAColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1) // #10B981
      backgroundOpacity = 0.94
      fontSize = 0.042
      animationIn = .typewriterPro
      animationOut = .cinematicFade
      animationDuration = 0.34

    case .cinemaIvory:
      fontWeight = 500
      isBold = false
      isItalic = true
      surfaceStyle = .cinemaClean
      textCase = .standard
      tracking = .cinema
      wordMode = .fullLine
      textColor = VideoEditorRGBAColor(red: 1.0, green: 0.965, blue: 0.835, alpha: 1) // Warm 35mm Ivory
      accentColor = VideoEditorRGBAColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 1)
      backgroundOpacity = 0.0
      fontSize = 0.045
      animationIn = .trackingPull
      animationOut = .cinematicFade
      animationDuration = 0.32
    }

    syncLegacyFontFamilyEnum()
  }

  var matchingPreset: EditorialPreset? {
    for preset in EditorialPreset.allCases {
      var probe = self
      probe.apply(preset: preset)
      if probe.surfaceStyle == surfaceStyle,
         probe.textTreatment == textTreatment,
         probe.wordMode == wordMode,
         probe.textCase == textCase,
         probe.useGradientText == useGradientText,
         probe.dualLineHero == dualLineHero,
         probe.shimmerSweep == shimmerSweep,
         probe.isItalic == isItalic,
         probe.fontWeight == fontWeight {
        return preset
      }
    }
    return nil
  }

  var segmenterOptions: VideoEditorCaptionSegmenterOptions {
    var options = VideoEditorCaptionSegmenterOptions()
    options.maxCharsPerLine = maxCharsPerLine
    options.maxLines = maxLines
    return options
  }

  var textCGColor: CGColor {
    CGColor(srgbRed: textColor.red, green: textColor.green, blue: textColor.blue, alpha: textColor.alpha)
  }

  var textGradientEndCGColor: CGColor {
    CGColor(
      srgbRed: textGradientEndColor.red,
      green: textGradientEndColor.green,
      blue: textGradientEndColor.blue,
      alpha: textGradientEndColor.alpha
    )
  }

  var glowCGColor: CGColor {
    CGColor(srgbRed: glowColor.red, green: glowColor.green, blue: glowColor.blue, alpha: glowColor.alpha)
  }

  var backgroundCGColor: CGColor {
    let alpha = min(max(backgroundOpacity, 0), 1)
    return CGColor(srgbRed: backgroundColor.red, green: backgroundColor.green, blue: backgroundColor.blue, alpha: alpha)
  }

  var accentCGColor: CGColor {
    CGColor(srgbRed: accentColor.red, green: accentColor.green, blue: accentColor.blue, alpha: accentColor.alpha)
  }

  var contrastInkOnAccentCGColor: CGColor {
    let luminance = 0.2126 * accentColor.red + 0.7152 * accentColor.green + 0.0722 * accentColor.blue
    return luminance > 0.56
      ? CGColor(srgbRed: 0.035, green: 0.04, blue: 0.06, alpha: 1)
      : CGColor(srgbRed: 0.99, green: 0.99, blue: 1.0, alpha: 1)
  }

  private enum CodingKeys: String, CodingKey {
    case isEnabled, languageIdentifier, customFontId, fontWeight
    case fontSize, isBold, isItalic, fontFamily, textTreatment, surfaceStyle
    case textCase, tracking, wordMode
    case animationIn, animationOut, wordAnimation, animationDuration
    case textColor, useGradientText, textGradientEndColor
    case glowIntensity, glowColor, dualLineHero, shimmerSweep
    case backgroundColor, accentColor, backgroundOpacity
    case position, margin, maxWidthFraction, maxCharsPerLine, maxLines, hideDuringFastSpeed
  }

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = VideoEditorCaptionSettings.default
    isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
    languageIdentifier = (try? c.decodeIfPresent(String.self, forKey: .languageIdentifier))
      .map { String($0.prefix(32)) }
    let rawFontId = (try? c.decodeIfPresent(String.self, forKey: .customFontId)) ?? d.customFontId
    customFontId = rawFontId.isEmpty ? d.customFontId : String(rawFontId.prefix(128))
    let rawFontSize = (try? c.decodeIfPresent(CGFloat.self, forKey: .fontSize)) ?? d.fontSize
    fontSize = rawFontSize.isFinite
      ? min(Self.fontSizeRange.upperBound, max(Self.fontSizeRange.lowerBound, rawFontSize))
      : d.fontSize
    isBold = (try? c.decodeIfPresent(Bool.self, forKey: .isBold)) ?? d.isBold
    isItalic = (try? c.decodeIfPresent(Bool.self, forKey: .isItalic)) ?? d.isItalic
    fontFamily = (try? c.decodeIfPresent(String.self, forKey: .fontFamily))
      .flatMap(FontFamily.init(rawValue:)) ?? d.fontFamily
    let rawWeight = (try? c.decodeIfPresent(Int.self, forKey: .fontWeight))
      ?? (isBold ? max(700, fontFamily.baseWeight) : fontFamily.baseWeight)
    fontWeight = min(900, max(300, rawWeight))
    textTreatment = (try? c.decodeIfPresent(String.self, forKey: .textTreatment))
      .flatMap(TextTreatment.init(rawValue:)) ?? d.textTreatment
    surfaceStyle = (try? c.decodeIfPresent(String.self, forKey: .surfaceStyle))
      .flatMap(SurfaceStyle.init(rawValue:)) ?? d.surfaceStyle
    textCase = (try? c.decodeIfPresent(String.self, forKey: .textCase))
      .flatMap(TextCase.init(rawValue:)) ?? d.textCase
    tracking = (try? c.decodeIfPresent(String.self, forKey: .tracking))
      .flatMap(TrackingPreset.init(rawValue:)) ?? d.tracking
    wordMode = (try? c.decodeIfPresent(String.self, forKey: .wordMode))
      .flatMap(WordMode.init(rawValue:)) ?? d.wordMode
    animationIn = (try? c.decodeIfPresent(String.self, forKey: .animationIn))
      .flatMap(AnimationStyle.init(rawValue:)) ?? d.animationIn
    animationOut = (try? c.decodeIfPresent(String.self, forKey: .animationOut))
      .flatMap(AnimationStyle.init(rawValue:)) ?? d.animationOut
    wordAnimation = (try? c.decodeIfPresent(String.self, forKey: .wordAnimation))
      .flatMap(AnimationStyle.init(rawValue:)) ?? d.wordAnimation
    let rawAnimDur = (try? c.decodeIfPresent(TimeInterval.self, forKey: .animationDuration)) ?? d.animationDuration
    animationDuration = rawAnimDur.isFinite
      ? min(Self.animationDurationRange.upperBound, max(Self.animationDurationRange.lowerBound, rawAnimDur))
      : d.animationDuration
    textColor = Self
      .sanitizeColor((try? c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .textColor)) ?? d.textColor)
    useGradientText = (try? c.decodeIfPresent(Bool.self, forKey: .useGradientText)) ?? d.useGradientText
    textGradientEndColor = Self.sanitizeColor(
      (try? c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .textGradientEndColor)) ?? d.textGradientEndColor
    )
    let rawGlow = (try? c.decodeIfPresent(CGFloat.self, forKey: .glowIntensity)) ?? d.glowIntensity
    glowIntensity = rawGlow.isFinite ? min(1, max(0, rawGlow)) : d.glowIntensity
    glowColor = Self
      .sanitizeColor((try? c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .glowColor)) ?? d.glowColor)
    dualLineHero = (try? c.decodeIfPresent(Bool.self, forKey: .dualLineHero)) ?? d.dualLineHero
    shimmerSweep = (try? c.decodeIfPresent(Bool.self, forKey: .shimmerSweep)) ?? d.shimmerSweep
    backgroundColor = Self.sanitizeColor(
      (try? c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .backgroundColor)) ?? d.backgroundColor
    )
    accentColor = Self.sanitizeColor(
      (try? c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .accentColor)) ?? d.accentColor
    )
    let rawBgOpacity = (try? c.decodeIfPresent(CGFloat.self, forKey: .backgroundOpacity)) ?? d.backgroundOpacity
    backgroundOpacity = rawBgOpacity.isFinite ? min(1, max(0, rawBgOpacity)) : d.backgroundOpacity
    position = (try? c.decodeIfPresent(String.self, forKey: .position))
      .flatMap(Position.init(rawValue:)) ?? d.position
    let rawMargin = (try? c.decodeIfPresent(CGFloat.self, forKey: .margin)) ?? d.margin
    margin = rawMargin.isFinite
      ? min(Self.marginRange.upperBound, max(Self.marginRange.lowerBound, rawMargin))
      : d.margin
    let rawMaxWidth = (try? c.decodeIfPresent(CGFloat.self, forKey: .maxWidthFraction)) ?? d.maxWidthFraction
    maxWidthFraction = Self.clampMaxWidthFraction(rawMaxWidth)
    let rawMaxChars = (try? c.decodeIfPresent(Int.self, forKey: .maxCharsPerLine)) ?? d.maxCharsPerLine
    maxCharsPerLine = min(120, max(8, rawMaxChars))
    let rawMaxLines = (try? c.decodeIfPresent(Int.self, forKey: .maxLines)) ?? d.maxLines
    maxLines = min(6, max(1, rawMaxLines))
    hideDuringFastSpeed = (try? c.decodeIfPresent(Bool.self, forKey: .hideDuringFastSpeed)) ?? d.hideDuringFastSpeed
  }

  private static func sanitizeColor(_ c: VideoEditorRGBAColor) -> VideoEditorRGBAColor {
    VideoEditorRGBAColor(
      red: c.red.isFinite ? min(1, max(0, c.red)) : 1,
      green: c.green.isFinite ? min(1, max(0, c.green)) : 1,
      blue: c.blue.isFinite ? min(1, max(0, c.blue)) : 1,
      alpha: c.alpha.isFinite ? min(1, max(0, c.alpha)) : 1
    )
  }
}

nonisolated struct VideoEditorCaptions: Codable, Equatable, Sendable {
  static let maxSegmentCount: Int = 5_000

  var segments: [CaptionSegment] = []
  var settings = VideoEditorCaptionSettings.default

  static let empty = VideoEditorCaptions()

  var isEmpty: Bool {
    segments.isEmpty
  }

  private enum CodingKeys: String, CodingKey { case segments, settings }

  private struct LossyDecodableSegment: Decodable {
    let segment: CaptionSegment?

    init(from decoder: Decoder) throws {
      segment = try? CaptionSegment(from: decoder)
    }
  }

  init(segments: [CaptionSegment] = [], settings: VideoEditorCaptionSettings = .default) {
    self.segments = Self.deduplicatingAndCapping(segments)
    self.settings = settings
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let rawSegments = ((try? c.decodeIfPresent([LossyDecodableSegment].self, forKey: .segments)) ?? [])
      .compactMap(\.segment)
    segments = Self.deduplicatingAndCapping(rawSegments)
    settings = (try? c.decodeIfPresent(VideoEditorCaptionSettings.self, forKey: .settings)) ?? .default
  }

  static func deduplicatingAndCapping(_ raw: [CaptionSegment]) -> [CaptionSegment] {
    var seen: Set<UUID> = []
    var out: [CaptionSegment] = []
    out.reserveCapacity(min(raw.count, maxSegmentCount))
    for seg in raw {
      guard out.count < maxSegmentCount else { break }
      guard seg.start.isFinite, seg.end.isFinite, seg.end > seg.start else { continue }
      let clampedStart = min(max(0, seg.start), 864_000)
      let clampedEnd = min(max(clampedStart + 0.01, seg.end), 864_000)
      let resolvedId = seen.insert(seg.id).inserted ? seg.id : UUID()
      seen.insert(resolvedId)
      var copy = seg
      copy.id = resolvedId
      copy.sourceRange = clampedStart ... clampedEnd
      copy.text = String(seg.text.prefix(1_000))
      if let words = seg.words {
        let sanitizedWords = words.compactMap { word -> VideoEditorTranscriptWord? in
          guard word.start.isFinite, word.duration.isFinite, word.start >= 0, word.duration >= 0 else {
            return nil
          }
          return VideoEditorTranscriptWord(
            start: min(word.start, 864_000),
            duration: min(word.duration, 864_000),
            text: String(word.text.prefix(200))
          )
        }
        copy.words = sanitizedWords.isEmpty && !words.isEmpty ? nil : sanitizedWords
      }
      out.append(copy)
    }
    return out
  }
}
