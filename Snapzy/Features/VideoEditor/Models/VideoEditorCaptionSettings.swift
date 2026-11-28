//
//  VideoEditorCaptionSettings.swift
//  Snapzy
//
//  Caption style and behavior. Sizes are fractions of the VIDEO rect height, so the
//  preview (any window size) and the export (any resolution) lay out the same lines.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorCaptionSettings: Codable, Hashable, Sendable {
  enum Position: String, Codable, CaseIterable, Hashable, Sendable {
    case bottom
    case top
  }

  static let fontSizeRange: ClosedRange<CGFloat> = 0.025 ... 0.1
  static let marginRange: ClosedRange<CGFloat> = 0 ... 0.25
  static let fontWeightRange: ClosedRange<Int> = 300 ... 900

  /// Captions are drawn on the video (preview and burned into the export).
  var isEnabled: Bool = true
  /// Speech language (`Locale.identifier`); `nil` = app language, then system locale.
  var languageIdentifier: String?
  /// Registered font family ID in `VideoEditorFontManager` (`"system"` default,
  /// `"installed:<Family>"`, OFL catalog ID, or imported `"custom-*"` ID).
  var customFontId: String = VideoEditorFontResolver.defaultFamilyId
  /// Explicit CSS/OpenType numeric weight (`300 ... 900`).
  var fontWeight: Int = 700
  /// Italic slant toggle.
  var isItalic: Bool = false
  /// Font size as a fraction of the video height.
  var fontSize: CGFloat = 0.045
  var isBold: Bool = true
  var textColor = VideoEditorRGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
  /// Opacity of the black pill behind the text (0 = outline only).
  var backgroundOpacity: CGFloat = 0.6
  var position: Position = .bottom
  /// Distance from the top/bottom edge as a fraction of the video height.
  var margin: CGFloat = 0.06
  var maxCharsPerLine: Int = 42
  var maxLines: Int = 2
  /// Hide captions while a speed segment plays faster than 2×.
  var hideDuringFastSpeed: Bool = true

  static let `default` = VideoEditorCaptionSettings()

  var resolvedWeight: Int {
    let clamped = min(max(fontWeight, Self.fontWeightRange.lowerBound), Self.fontWeightRange.upperBound)
    if isBold, clamped < 650 {
      return 700
    }
    if !isBold, clamped >= 700 {
      return 500
    }
    return clamped
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

  private enum CodingKeys: String, CodingKey {
    case isEnabled, languageIdentifier, customFontId, fontWeight, isItalic
    case fontSize, isBold, textColor, backgroundOpacity
    case position, margin, maxCharsPerLine, maxLines, hideDuringFastSpeed
  }

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = VideoEditorCaptionSettings.default
    isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
    languageIdentifier = try c.decodeIfPresent(String.self, forKey: .languageIdentifier)
    let decodedFontId = try c.decodeIfPresent(String.self, forKey: .customFontId)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    customFontId = (decodedFontId?.isEmpty == false) ? String(decodedFontId!.prefix(256)) : d.customFontId
    let rawBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? d.isBold
    isBold = rawBold
    if let rawWeight = try c.decodeIfPresent(Int.self, forKey: .fontWeight) {
      fontWeight = min(max(rawWeight, Self.fontWeightRange.lowerBound), Self.fontWeightRange.upperBound)
    } else {
      fontWeight = rawBold ? 700 : 400
    }
    isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? d.isItalic
    let rawSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? d.fontSize
    fontSize = rawSize.isFinite ? min(max(rawSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound) : d
      .fontSize
    textColor = try c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .textColor) ?? d.textColor
    let rawOpacity = try c.decodeIfPresent(CGFloat.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
    backgroundOpacity = rawOpacity.isFinite ? min(max(rawOpacity, 0), 1) : d.backgroundOpacity
    position = try c.decodeIfPresent(Position.self, forKey: .position) ?? d.position
    let rawMargin = try c.decodeIfPresent(CGFloat.self, forKey: .margin) ?? d.margin
    margin = rawMargin.isFinite ? min(max(rawMargin, Self.marginRange.lowerBound), Self.marginRange.upperBound) : d
      .margin
    maxCharsPerLine = try min(max((c.decodeIfPresent(Int.self, forKey: .maxCharsPerLine)) ?? d.maxCharsPerLine, 8), 200)
    maxLines = try min(max((c.decodeIfPresent(Int.self, forKey: .maxLines)) ?? d.maxLines, 1), 10)
    hideDuringFastSpeed = try c.decodeIfPresent(Bool.self, forKey: .hideDuringFastSpeed) ?? d.hideDuringFastSpeed
  }
}

/// Everything the caption feature edits, undone as one value.
nonisolated struct VideoEditorCaptions: Codable, Equatable, Sendable {
  /// Sorted by start, in SOURCE time of the primary recording.
  var segments: [CaptionSegment] = []
  var settings = VideoEditorCaptionSettings.default

  static let empty = VideoEditorCaptions()

  var isEmpty: Bool {
    segments.isEmpty
  }

  private enum CodingKeys: String, CodingKey { case segments, settings }

  init(segments: [CaptionSegment] = [], settings: VideoEditorCaptionSettings = .default) {
    self.segments = segments
    self.settings = settings
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    segments = try (c.decodeIfPresent([CaptionSegment].self, forKey: .segments)) ?? []
    settings = try (c.decodeIfPresent(VideoEditorCaptionSettings.self, forKey: .settings)) ?? .default
  }
}
