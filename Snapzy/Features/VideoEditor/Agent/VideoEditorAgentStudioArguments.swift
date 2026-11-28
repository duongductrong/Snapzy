//
//  VideoEditorAgentStudioArguments.swift
//  Snapzy
//
//  Arguments of the Studio, caption, font, and gap agent tools (snake_case JSON).
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct VideoEditorAgentCursorArguments: Decodable {
  var visible: Bool?
  var scale: Double?
  var smoothing: Double?
  var hideWhenIdle: Bool?
  var clickEffect: String?
  var clickSound: Bool?
  var idleDelay: Double?
  var alwaysArrow: Bool?
  var clickColor: String?
  var clickVolume: Double?
}

nonisolated struct VideoEditorAgentCameraArguments: Decodable {
  var visible: Bool?
  var shape: String?
  var size: Double?
  var position: String?
  var center: [Double]?
  var mirrored: Bool?
  var hideStart: VideoEditorAgentTime?
  var hideEnd: VideoEditorAgentTime?
  var hideDuringZooms: Bool?
  var showHidden: [String]?
  var clearHidden: Bool?
  var reset: Bool?
}

nonisolated struct VideoEditorAgentCaptionArguments: Decodable {
  var language: String?
  var showOnVideo: Bool?
}

nonisolated struct VideoEditorAgentCaptionEditArguments: Decodable {
  var id: String?
  var text: String?
  var start: VideoEditorAgentTime?
  var end: VideoEditorAgentTime?
  var showOnVideo: Bool?
  var position: String?
  var textSize: Double?
  var font: String?
  var fontWeight: Int?
  var bold: Bool?
  var italic: Bool?
  var textColor: String?
  var backgroundOpacity: Double?
  var hideWhenFast: Bool?
}

nonisolated struct VideoEditorAgentCloseGapsArguments: Decodable {
  var clip: String?
}

nonisolated struct VideoEditorAgentCaptionRangeArguments: Decodable {
  var start: VideoEditorAgentTime?
  var end: VideoEditorAgentTime?
}

nonisolated struct VideoEditorAgentAddCaptionArguments: Decodable {
  var start: VideoEditorAgentTime
  var end: VideoEditorAgentTime
  var text: String
}

nonisolated struct VideoEditorAgentCaptionIDsArguments: Decodable {
  var ids: [String]
}

nonisolated struct VideoEditorAgentReplaceCaptionArguments: Decodable {
  var find: String
  var replace: String
  var matchCase: Bool?
  var wholeWord: Bool?
}

nonisolated struct VideoEditorAgentTranslateCaptionArguments: Decodable {
  var language: String
}

nonisolated enum VideoEditorAgentStudioTools {
  /// Named camera anchors (alignments, as `VideoEditorCameraSettings.anchors`).
  static let cameraPositions: [(name: String, anchor: CGPoint)] = [
    ("top_left", CGPoint(x: 0, y: 0)), ("top", CGPoint(x: 0.5, y: 0)), ("top_right", CGPoint(x: 1, y: 0)),
    ("left", CGPoint(x: 0, y: 0.5)), ("center", CGPoint(x: 0.5, y: 0.5)), ("right", CGPoint(x: 1, y: 0.5)),
    ("bottom_left", CGPoint(x: 0, y: 1)), ("bottom", CGPoint(x: 0.5, y: 1)), ("bottom_right", CGPoint(x: 1, y: 1)),
  ]
  /// Captions get_timeline lists before it only counts them.
  static let maximumListedCaptions = 40
  /// Captions one get_captions call lists; the rest is offered through `next_start`.
  static let maximumCaptionPage = 80
  /// Clicks get_activity lists before it only counts them.
  static let maximumListedClicks = 60
  /// Shortest caption a tool may leave.
  static let minimumCaptionDuration: TimeInterval = 0.2

  /// `TranslationLanguage.all`, readable off the main actor for the tool schema.
  static let translationTargets = [
    "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pl",
    "pt", "ru", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
  ]

  /// Overflow-safe conversion from a 1-based index (`1 ... maxCount`) to 0-based (`Int.min` never traps).
  static func clampedZeroBasedIndex(_ rawOneBased: Int, maxCount: Int) -> Int {
    let clamped = min(max(rawOneBased, 1), max(1, maxCount))
    return clamped - 1
  }

  static func normalizedToken(_ raw: String) -> String {
    raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: " ", with: "")
  }

  /// "vi", "vi-VN", "Vietnamese", "zh-TW" → a `translationTargets` id.
  static func translationTarget(_ raw: String) -> String? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let lower = text.lowercased().replacingOccurrences(of: "_", with: "-")
    if let exact = translationTargets.first(where: { $0.lowercased() == lower }) {
      return exact
    }
    if lower.hasPrefix("zh") || lower.contains("chinese") {
      let traditional = ["hant", "tw", "hk", "mo", "traditional"].contains { lower.contains($0) }
      return traditional ? "zh-Hant" : "zh-Hans"
    }
    let code = String(lower.split(separator: "-").first ?? Substring(lower))
    if let byCode = translationTargets.first(where: { $0 == code }) {
      return byCode
    }
    let english = Locale(identifier: "en")
    return translationTargets.first { english.localizedString(forIdentifier: $0)?.lowercased() == lower }
  }

  /// Caption and click-effect colors: a name or hex, through Annotate's color parser.
  /// `alpha` replaces the parsed opacity unless the text spells one out (#RRGGBBAA).
  @MainActor
  static func color(_ raw: String, name: String, alpha: CGFloat? = nil) throws -> VideoEditorRGBAColor {
    let hex = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    let spellsAlpha = hex.count == 8 && UInt64(hex, radix: 16) != nil
    guard let color = AnnotateAgentColor.parse(raw),
          let ns = NSColor(color).usingColorSpace(.sRGB)
    else {
      throw VideoEditorAgentToolError.invalidArguments("\(name) must be \(AnnotateAgentColor.validValuesDescription).")
    }
    return VideoEditorRGBAColor(
      red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent,
      alpha: spellsAlpha ? ns.alphaComponent : (alpha ?? ns.alphaComponent)
    )
  }

  /// Resolves a font identifier strictly from fonts ALREADY available locally on this Mac
  /// (System SF Pro, installed macOS font families, already-downloaded OFL catalog fonts,
  /// or user-imported fonts). Never triggers any network download from AI prompts.
  @MainActor
  static func resolveFontId(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = normalizedToken(trimmed)
    if token.isEmpty || token == "system" || token == "sfpro" || token == "sfprodisplay" {
      return VideoEditorFontResolver.defaultFamilyId
    }

    let manager = VideoEditorFontManager.shared

    if let catalogMatch = VideoEditorFontManager.curatedCatalog.first(where: {
      normalizedToken($0.id) == token || normalizedToken($0.displayName) == token
    }) {
      if manager.downloadedCatalogIds.contains(catalogMatch.id) {
        return catalogMatch.id
      }
      if let sysName = VideoEditorFontResolver.installedFamilyName(for: catalogMatch.displayName) {
        return VideoEditorFontResolver.installedFamilyId(for: sysName)
      }
      throw VideoEditorAgentToolError.unavailable(
        "Font '\(catalogMatch.displayName)' is not downloaded yet. Click Download (OFL) in the Font Library first, or choose an installed font."
      )
    }

    if let importedMatch = manager.importedFonts.first(where: {
      normalizedToken($0.id) == token || normalizedToken($0.displayName) == token
    }) {
      return importedMatch.id
    }

    if let sysName = VideoEditorFontResolver.installedFamilyName(for: trimmed) {
      return VideoEditorFontResolver.installedFamilyId(for: sysName)
    }
    if let installedMatch = manager.installedFamilies.first(where: {
      normalizedToken($0.id) == token || normalizedToken($0.familyName) == token
    }) {
      return installedMatch.id
    }

    throw VideoEditorAgentToolError.unavailable(
      "Font '\(trimmed)' is not installed on this Mac. Choose system, an installed macOS font, or download/import the font in the Font Library first."
    )
  }
}
