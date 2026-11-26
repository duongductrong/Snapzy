//
//  AutomationStepConfigs.swift
//  Snapzy
//
//  Per-kind step settings. Every config decodes tolerantly: a missing or
//  malformed key falls back to its default, so a hand-edited TOML or a recipe
//  from another Snapzy version never drops the whole step.
//

import Foundation

nonisolated extension KeyedDecodingContainer {
  /// `decodeIfPresent` that also swallows type mismatches, returning `fallback`.
  func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
    (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
  }
}

/// What a payload holds at a point in the chain. File kinds mirror `AutomationFileKind`.
nonisolated enum AutomationPayloadKind: String, Codable, CaseIterable, Sendable {
  case image
  case video
  case gif
  case text
  case link

  init(_ fileKind: AutomationFileKind) {
    switch fileKind {
    case .image: self = .image
    case .video: self = .video
    case .gif: self = .gif
    }
  }

  var fileKind: AutomationFileKind? {
    switch self {
    case .image: .image
    case .video: .video
    case .gif: .gif
    case .text, .link: nil
    }
  }

  static let files: Set<AutomationPayloadKind> = [.image, .video, .gif]
  static let all = Set(allCases)
}

// MARK: - Transform configs

nonisolated struct AutomationCanvasPresetConfig: Codable, Equatable, Sendable {
  /// Annotate canvas preset; `nil` uses the preset marked as default.
  var presetID: UUID?

  init(presetID: UUID? = nil) {
    self.presetID = presetID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    presetID = container.value(.presetID, default: nil)
  }
}

nonisolated struct AutomationResizeConfig: Codable, Equatable, Sendable {
  enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Longest edge at most `maxDimension` pixels.
    case maxDimension
    /// `scalePercent` of the current size.
    case scalePercent

    var id: String { rawValue }
  }

  static let dimensionRange = 16...16384
  static let percentRange = 1...100

  var mode: Mode
  var maxDimension: Int
  var scalePercent: Int

  init(mode: Mode = .maxDimension, maxDimension: Int = 1600, scalePercent: Int = 50) {
    self.mode = mode
    self.maxDimension = maxDimension
    self.scalePercent = scalePercent
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    mode = container.value(.mode, default: defaults.mode)
    maxDimension = container.value(.maxDimension, default: defaults.maxDimension)
    scalePercent = container.value(.scalePercent, default: defaults.scalePercent)
  }

  var clampedMaxDimension: Int {
    min(max(maxDimension, Self.dimensionRange.lowerBound), Self.dimensionRange.upperBound)
  }

  var clampedScalePercent: Int {
    min(max(scalePercent, Self.percentRange.lowerBound), Self.percentRange.upperBound)
  }
}

nonisolated struct AutomationConvertConfig: Codable, Equatable, Sendable {
  var format: QuickAccessOptimizeFormat
  var quality: Int
  /// Upper bound in kilobytes (1 KB = 1000 bytes); quality, then size, drop to fit.
  var maxFileSizeKB: Int?
  /// A Quick Access Optimize preset; when set it overrides the fields above.
  var optimizePresetID: UUID?

  init(
    format: QuickAccessOptimizeFormat = .webp,
    quality: Int = 85,
    maxFileSizeKB: Int? = nil,
    optimizePresetID: UUID? = nil
  ) {
    self.format = format
    self.quality = quality
    self.maxFileSizeKB = maxFileSizeKB
    self.optimizePresetID = optimizePresetID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    format = container.value(.format, default: defaults.format)
    quality = container.value(.quality, default: defaults.quality)
    maxFileSizeKB = container.value(.maxFileSizeKB, default: nil)
    optimizePresetID = container.value(.optimizePresetID, default: nil)
  }

  /// Settings for the Optimize pipeline (no rescaling; Resize is its own step).
  var optimizeSettings: QuickAccessOptimizeSettings {
    QuickAccessOptimizeSettings(
      scalePercent: 100,
      format: format,
      qualityPercent: quality,
      maxFileSize: maxFileSizeKB.map { $0 * 1000 }
    )
  }
}

nonisolated struct AutomationOCRConfig: Codable, Equatable, Sendable {
  /// BCP-47 recognition language hint; `nil` detects automatically.
  var languageIdentifier: String?
  /// Also decode QR codes and append their payloads.
  var includeQR: Bool

  init(languageIdentifier: String? = nil, includeQR: Bool = false) {
    self.languageIdentifier = languageIdentifier
    self.includeQR = includeQR
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    languageIdentifier = container.value(.languageIdentifier, default: nil)
    includeQR = container.value(.includeQR, default: false)
  }
}

nonisolated struct AutomationTranslateConfig: Codable, Equatable, Sendable {
  /// Target language identifier; `nil` uses the Snip to Translate target.
  var targetLanguage: String?

  init(targetLanguage: String? = nil) {
    self.targetLanguage = targetLanguage
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    targetLanguage = container.value(.targetLanguage, default: nil)
  }
}

nonisolated struct AutomationGIFConfig: Codable, Equatable, Sendable {
  static let fpsOptions = [10, 15, 20, 24, 30]
  static let widthOptions = [480, 640, 800, 960, 1280]

  var fps: Int
  var maxWidth: Int

  init(fps: Int = 15, maxWidth: Int = 960) {
    self.fps = fps
    self.maxWidth = maxWidth
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fps = container.value(.fps, default: 15)
    maxWidth = container.value(.maxWidth, default: 960)
  }

  var clampedFPS: Int { min(max(fps, 1), 60) }
  var clampedMaxWidth: Int { min(max(maxWidth, 64), 4096) }
}

// MARK: - Deliver configs

/// How an uploaded link is written to the pasteboard.
nonisolated enum AutomationLinkStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case url
  case markdown
  case html
  case bbcode
  case custom

  var id: String { rawValue }
}

nonisolated struct AutomationLinkTemplate: Codable, Equatable, Sendable {
  var style: AutomationLinkStyle
  /// Template for `.custom`, e.g. `<{link}>` — see `AutomationVariables`.
  var custom: String

  init(style: AutomationLinkStyle = .url, custom: String = "") {
    self.style = style
    self.custom = custom
  }

  init(_ format: AutomationLinkFormat) {
    self.init(style: format == .markdown ? .markdown : .url)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    style = container.value(.style, default: .url)
    custom = container.value(.custom, default: "")
  }

  /// Template rendered for `.html`, `.bbcode` and `.custom`. `.url` / `.markdown`
  /// go through `CloudShareService.linkText` (escaping, video links).
  var template: String {
    switch style {
    case .url: "{link}"
    case .markdown: "![{file.basename}]({link})"
    case .html: "<img src=\"{link}\" alt=\"{file.basename}\">"
    case .bbcode: "[img]{link}[/img]"
    case .custom: custom
    }
  }

  var escape: AutomationEscape {
    style == .html ? .html : .none
  }
}

nonisolated struct AutomationTextTemplate: Codable, Equatable, Sendable {
  static let defaultTemplate = "{text}"

  var template: String

  init(template: String = Self.defaultTemplate) {
    self.template = template
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    template = container.value(.template, default: Self.defaultTemplate)
  }

  var usesText: Bool { template.contains("{text}") }
  var usesLink: Bool { template.contains("{link}") }
}

/// A destination folder: the export folder from Settings → General, or a
/// folder the user picked, kept as a bookmark in `AutomationFolderAccessStore`.
nonisolated enum AutomationFolderRef: Equatable, Hashable, Sendable {
  case exportDirectory
  case bookmark(UUID)
}

nonisolated extension AutomationFolderRef: Codable {
  static let exportToken = "export"

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    if raw == Self.exportToken {
      self = .exportDirectory
    } else if let id = UUID(uuidString: raw) {
      self = .bookmark(id)
    } else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown folder \(raw)"))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .exportDirectory: try container.encode(Self.exportToken)
    case .bookmark(let id): try container.encode(id.uuidString)
    }
  }
}

nonisolated enum AutomationConflictPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
  /// `name_2.png`, `name_3.png`, …
  case uniquify
  /// Replace an existing file with the same name.
  case overwrite

  var id: String { rawValue }
}

nonisolated struct AutomationSaveToFolderConfig: Codable, Equatable, Sendable {
  static let defaultNameTemplate = "{file.basename}"

  /// `nil` until the user picks a folder (the step then "needs setup").
  var folder: AutomationFolderRef?
  /// Last known path of a bookmarked folder: shown in the editor, written to TOML.
  var folderPath: String?
  /// Base name without extension; `/` creates sub-folders. See `AutomationVariables`.
  var nameTemplate: String
  var conflict: AutomationConflictPolicy

  init(
    folder: AutomationFolderRef? = nil,
    folderPath: String? = nil,
    nameTemplate: String = Self.defaultNameTemplate,
    conflict: AutomationConflictPolicy = .uniquify
  ) {
    self.folder = folder
    self.folderPath = folderPath
    self.nameTemplate = nameTemplate
    self.conflict = conflict
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    folder = container.value(.folder, default: nil)
    folderPath = container.value(.folderPath, default: nil)
    nameTemplate = container.value(.nameTemplate, default: Self.defaultNameTemplate)
    conflict = container.value(.conflict, default: .uniquify)
  }
}
