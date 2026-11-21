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

  /// Captions are drawn on the video (preview and burned into the export).
  var isEnabled: Bool = true
  /// Speech language (`Locale.identifier`); `nil` = app language, then system locale.
  var languageIdentifier: String?
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
    case isEnabled, languageIdentifier, fontSize, isBold, textColor, backgroundOpacity
    case position, margin, maxCharsPerLine, maxLines, hideDuringFastSpeed
  }

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = VideoEditorCaptionSettings.default
    isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
    languageIdentifier = try c.decodeIfPresent(String.self, forKey: .languageIdentifier)
    fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? d.fontSize
    isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? d.isBold
    textColor = try c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .textColor) ?? d.textColor
    backgroundOpacity = try c.decodeIfPresent(CGFloat.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
    position = try c.decodeIfPresent(Position.self, forKey: .position) ?? d.position
    margin = try c.decodeIfPresent(CGFloat.self, forKey: .margin) ?? d.margin
    maxCharsPerLine = try c.decodeIfPresent(Int.self, forKey: .maxCharsPerLine) ?? d.maxCharsPerLine
    maxLines = try c.decodeIfPresent(Int.self, forKey: .maxLines) ?? d.maxLines
    hideDuringFastSpeed = try c.decodeIfPresent(Bool.self, forKey: .hideDuringFastSpeed) ?? d.hideDuringFastSpeed
  }
}

/// Everything the caption feature edits, undone as one value.
nonisolated struct VideoEditorCaptions: Codable, Equatable, Sendable {
  /// Sorted by start, in SOURCE time of the primary recording.
  var segments: [CaptionSegment] = []
  var settings = VideoEditorCaptionSettings.default

  static let empty = VideoEditorCaptions()

  var isEmpty: Bool { segments.isEmpty }

  private enum CodingKeys: String, CodingKey { case segments, settings }

  init(segments: [CaptionSegment] = [], settings: VideoEditorCaptionSettings = .default) {
    self.segments = segments
    self.settings = settings
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    segments = try c.decodeIfPresent([CaptionSegment].self, forKey: .segments) ?? []
    settings = try c.decodeIfPresent(VideoEditorCaptionSettings.self, forKey: .settings) ?? .default
  }
}
