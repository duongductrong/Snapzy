//
//  AnnotateImageAdjustments.swift
//  Snapzy
//
//  Non-destructive tone adjustments and filter presets applied to the source image
//  (after background cutout, before annotations).
//

import Foundation

/// Filter preset applied on top of the tone sliders. Raw values are persisted in
/// session sidecars, so keep them stable.
nonisolated enum ImageFilterPreset: String, CaseIterable, Codable, Sendable, Identifiable {
  case none
  case vivid
  case mono
  case noir
  case tonal
  case sepia
  case chrome
  case fade
  case instant
  case process
  case transfer

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .none: return L10n.AnnotateAdjust.presetOriginal
    case .vivid: return L10n.AnnotateAdjust.presetVivid
    case .mono: return L10n.AnnotateAdjust.presetMono
    case .noir: return L10n.AnnotateAdjust.presetNoir
    case .tonal: return L10n.AnnotateAdjust.presetTonal
    case .sepia: return L10n.AnnotateAdjust.presetSepia
    case .chrome: return L10n.AnnotateAdjust.presetChrome
    case .fade: return L10n.AnnotateAdjust.presetFade
    case .instant: return L10n.AnnotateAdjust.presetInstant
    case .process: return L10n.AnnotateAdjust.presetProcess
    case .transfer: return L10n.AnnotateAdjust.presetTransfer
    }
  }
}

/// Tone slider values in UI units plus the selected preset. Identity values leave the
/// source image untouched (no Core Image pass at all).
nonisolated struct ImageAdjustments: Equatable, Hashable, Codable, Sendable {
  static let toneRange: ClosedRange<Double> = -100 ... 100
  static let sharpnessRange: ClosedRange<Double> = 0 ... 100
  static let identity = ImageAdjustments()

  /// -100…100, 0 = unchanged.
  var brightness: Double = 0
  /// -100…100, 0 = unchanged.
  var contrast: Double = 0
  /// -100…100, 0 = unchanged; -100 = grayscale.
  var saturation: Double = 0
  /// 0…100, 0 = unchanged.
  var sharpness: Double = 0
  var preset: ImageFilterPreset = .none

  init(
    brightness: Double = 0,
    contrast: Double = 0,
    saturation: Double = 0,
    sharpness: Double = 0,
    preset: ImageFilterPreset = .none
  ) {
    self.brightness = brightness
    self.contrast = contrast
    self.saturation = saturation
    self.sharpness = sharpness
    self.preset = preset
  }

  var isIdentity: Bool { self == .identity }

  var hasToneChanges: Bool {
    brightness != 0 || contrast != 0 || saturation != 0
  }

  /// Values clamped into their ranges (sidecars and text-field input are untrusted).
  var clamped: ImageAdjustments {
    ImageAdjustments(
      brightness: Self.clamp(brightness, to: Self.toneRange),
      contrast: Self.clamp(contrast, to: Self.toneRange),
      saturation: Self.clamp(saturation, to: Self.toneRange),
      sharpness: Self.clamp(sharpness, to: Self.sharpnessRange),
      preset: preset
    )
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, range.lowerBound), range.upperBound)
  }

  // MARK: Codable (tolerant: missing keys = 0, unknown preset = none)

  private enum CodingKeys: String, CodingKey {
    case brightness, contrast, saturation, sharpness, preset
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
    contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
    saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
    sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
    let presetRaw = try container.decodeIfPresent(String.self, forKey: .preset)
    preset = presetRaw.flatMap(ImageFilterPreset.init(rawValue:)) ?? .none
    self = clamped
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(brightness, forKey: .brightness)
    try container.encode(contrast, forKey: .contrast)
    try container.encode(saturation, forKey: .saturation)
    try container.encode(sharpness, forKey: .sharpness)
    try container.encode(preset.rawValue, forKey: .preset)
  }
}
