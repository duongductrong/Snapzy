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
  case warm
  case cool
  case dramatic
  case matte
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
    case .warm: return L10n.AnnotateAdjust.presetWarm
    case .cool: return L10n.AnnotateAdjust.presetCool
    case .dramatic: return L10n.AnnotateAdjust.presetDramatic
    case .matte: return L10n.AnnotateAdjust.presetMatte
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

/// Slider values in UI units plus the selected preset. Identity values leave the source image
/// untouched (no Core Image pass at all).
nonisolated struct ImageAdjustments: Equatable, Hashable, Codable, Sendable {
  static let toneRange: ClosedRange<Double> = -100 ... 100
  static let positiveRange: ClosedRange<Double> = 0 ... 100
  static let sharpnessRange = positiveRange
  static let presetIntensityRange = positiveRange
  static let identity = ImageAdjustments()

  // Light
  /// -100…100 → ±2 EV, 0 = unchanged.
  var exposure: Double = 0
  /// -100…100, 0 = unchanged.
  var brightness: Double = 0
  /// -100…100, 0 = unchanged.
  var contrast: Double = 0
  /// -100…100, 0 = unchanged; recovers (−) or lifts (+) the bright tones.
  var highlights: Double = 0
  /// -100…100, 0 = unchanged; deepens (−) or opens (+) the dark tones.
  var shadows: Double = 0
  /// -100…100, 0 = unchanged; white point.
  var whites: Double = 0
  /// -100…100, 0 = unchanged; black point.
  var blacks: Double = 0

  // Color
  /// -100…100, 0 = unchanged; − cooler, + warmer.
  var temperature: Double = 0
  /// -100…100, 0 = unchanged; − green, + magenta.
  var tint: Double = 0
  /// -100…100, 0 = unchanged; -100 = grayscale.
  var saturation: Double = 0
  /// -100…100, 0 = unchanged; saturation weighted toward muted colors.
  var vibrance: Double = 0

  // Effects
  /// -100…100, 0 = unchanged; local (mid-tone) contrast.
  var clarity: Double = 0
  /// 0…100, 0 = unchanged.
  var sharpness: Double = 0
  /// -100…100, 0 = unchanged; − darkens, + lightens the corners.
  var vignette: Double = 0

  var preset: ImageFilterPreset = .none
  /// 0…100 strength of `preset` blended over the slider result; 100 = full preset.
  var presetIntensity: Double = 100

  init(
    exposure: Double = 0,
    brightness: Double = 0,
    contrast: Double = 0,
    highlights: Double = 0,
    shadows: Double = 0,
    whites: Double = 0,
    blacks: Double = 0,
    temperature: Double = 0,
    tint: Double = 0,
    saturation: Double = 0,
    vibrance: Double = 0,
    clarity: Double = 0,
    sharpness: Double = 0,
    vignette: Double = 0,
    preset: ImageFilterPreset = .none,
    presetIntensity: Double = 100
  ) {
    self.exposure = exposure
    self.brightness = brightness
    self.contrast = contrast
    self.highlights = highlights
    self.shadows = shadows
    self.whites = whites
    self.blacks = blacks
    self.temperature = temperature
    self.tint = tint
    self.saturation = saturation
    self.vibrance = vibrance
    self.clarity = clarity
    self.sharpness = sharpness
    self.vignette = vignette
    self.preset = preset
    self.presetIntensity = presetIntensity
  }

  /// No visible change: every slider at 0 and no preset (or a preset at 0% strength).
  var isIdentity: Bool {
    !hasLightChanges && !hasColorChanges && !hasEffectChanges && !hasVisiblePreset
  }

  var hasLightChanges: Bool {
    exposure != 0 || brightness != 0 || contrast != 0 || hasToneCurveChanges
  }

  var hasToneCurveChanges: Bool {
    highlights != 0 || shadows != 0 || whites != 0 || blacks != 0
  }

  var hasColorChanges: Bool {
    temperature != 0 || tint != 0 || saturation != 0 || vibrance != 0
  }

  var hasEffectChanges: Bool {
    clarity != 0 || sharpness != 0 || vignette != 0
  }

  var hasVisiblePreset: Bool {
    preset != .none && presetIntensity > 0
  }

  /// Brightness/contrast/saturation share one `CIColorControls` pass.
  var hasColorControlChanges: Bool {
    brightness != 0 || contrast != 0 || saturation != 0
  }

  /// Values clamped into their ranges (sidecars and text-field input are untrusted).
  var clamped: ImageAdjustments {
    let tone = Self.toneRange
    return ImageAdjustments(
      exposure: Self.clamp(exposure, to: tone),
      brightness: Self.clamp(brightness, to: tone),
      contrast: Self.clamp(contrast, to: tone),
      highlights: Self.clamp(highlights, to: tone),
      shadows: Self.clamp(shadows, to: tone),
      whites: Self.clamp(whites, to: tone),
      blacks: Self.clamp(blacks, to: tone),
      temperature: Self.clamp(temperature, to: tone),
      tint: Self.clamp(tint, to: tone),
      saturation: Self.clamp(saturation, to: tone),
      vibrance: Self.clamp(vibrance, to: tone),
      clarity: Self.clamp(clarity, to: tone),
      sharpness: Self.clamp(sharpness, to: Self.sharpnessRange),
      vignette: Self.clamp(vignette, to: tone),
      preset: preset,
      presetIntensity: Self.clamp(presetIntensity, to: Self.presetIntensityRange, fallback: 100)
    )
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double = 0) -> Double {
    guard value.isFinite else { return fallback }
    return min(max(value, range.lowerBound), range.upperBound)
  }

  // MARK: Codable (tolerant: missing keys = default, unknown preset = none)

  private enum CodingKeys: String, CodingKey {
    case exposure, brightness, contrast, highlights, shadows, whites, blacks
    case temperature, tint, saturation, vibrance
    case clarity, sharpness, vignette
    case preset, presetIntensity
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value(_ key: CodingKeys, default fallback: Double = 0) throws -> Double {
      try container.decodeIfPresent(Double.self, forKey: key) ?? fallback
    }
    exposure = try value(.exposure)
    brightness = try value(.brightness)
    contrast = try value(.contrast)
    highlights = try value(.highlights)
    shadows = try value(.shadows)
    whites = try value(.whites)
    blacks = try value(.blacks)
    temperature = try value(.temperature)
    tint = try value(.tint)
    saturation = try value(.saturation)
    vibrance = try value(.vibrance)
    clarity = try value(.clarity)
    sharpness = try value(.sharpness)
    vignette = try value(.vignette)
    presetIntensity = try value(.presetIntensity, default: 100)
    let presetRaw = try container.decodeIfPresent(String.self, forKey: .preset)
    preset = presetRaw.flatMap(ImageFilterPreset.init(rawValue:)) ?? .none
    self = clamped
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(exposure, forKey: .exposure)
    try container.encode(brightness, forKey: .brightness)
    try container.encode(contrast, forKey: .contrast)
    try container.encode(highlights, forKey: .highlights)
    try container.encode(shadows, forKey: .shadows)
    try container.encode(whites, forKey: .whites)
    try container.encode(blacks, forKey: .blacks)
    try container.encode(temperature, forKey: .temperature)
    try container.encode(tint, forKey: .tint)
    try container.encode(saturation, forKey: .saturation)
    try container.encode(vibrance, forKey: .vibrance)
    try container.encode(clarity, forKey: .clarity)
    try container.encode(sharpness, forKey: .sharpness)
    try container.encode(vignette, forKey: .vignette)
    try container.encode(preset.rawValue, forKey: .preset)
    try container.encode(presetIntensity, forKey: .presetIntensity)
  }
}

// MARK: - Slider groups

/// Slider groups shown in the Adjust tab, in pipeline order.
nonisolated enum ImageAdjustmentGroup: String, CaseIterable, Identifiable, Sendable {
  case light
  case color
  case effects

  var id: String { rawValue }

  var title: String {
    switch self {
    case .light: return L10n.AnnotateAdjust.groupLight
    case .color: return L10n.AnnotateAdjust.groupColor
    case .effects: return L10n.AnnotateAdjust.groupEffects
    }
  }

  var parameters: [ImageAdjustmentParameter] {
    ImageAdjustmentParameter.allCases.filter { $0.group == self }
  }

  /// True when any slider in this group moved off 0.
  func isModified(in adjustments: ImageAdjustments) -> Bool {
    parameters.contains { adjustments[keyPath: $0.keyPath] != 0 }
  }

  /// `adjustments` with this group's sliders back at 0 (preset untouched).
  func reset(_ adjustments: ImageAdjustments) -> ImageAdjustments {
    var updated = adjustments
    for parameter in parameters {
      updated[keyPath: parameter.keyPath] = 0
    }
    return updated
  }
}

/// One adjustment slider: label, key path, range and track style.
nonisolated enum ImageAdjustmentParameter: String, CaseIterable, Identifiable, Sendable {
  case exposure, brightness, contrast, highlights, shadows, whites, blacks
  case temperature, tint, vibrance, saturation
  case clarity, sharpness, vignette

  var id: String { rawValue }

  var group: ImageAdjustmentGroup {
    switch self {
    case .exposure, .brightness, .contrast, .highlights, .shadows, .whites, .blacks: return .light
    case .temperature, .tint, .vibrance, .saturation: return .color
    case .clarity, .sharpness, .vignette: return .effects
    }
  }

  var keyPath: WritableKeyPath<ImageAdjustments, Double> {
    switch self {
    case .exposure: return \.exposure
    case .brightness: return \.brightness
    case .contrast: return \.contrast
    case .highlights: return \.highlights
    case .shadows: return \.shadows
    case .whites: return \.whites
    case .blacks: return \.blacks
    case .temperature: return \.temperature
    case .tint: return \.tint
    case .vibrance: return \.vibrance
    case .saturation: return \.saturation
    case .clarity: return \.clarity
    case .sharpness: return \.sharpness
    case .vignette: return \.vignette
    }
  }

  var range: ClosedRange<Double> {
    self == .sharpness ? ImageAdjustments.sharpnessRange : ImageAdjustments.toneRange
  }

  var label: String {
    switch self {
    case .exposure: return L10n.AnnotateAdjust.exposure
    case .brightness: return L10n.AnnotateAdjust.brightness
    case .contrast: return L10n.AnnotateAdjust.contrast
    case .highlights: return L10n.AnnotateAdjust.highlights
    case .shadows: return L10n.AnnotateAdjust.shadows
    case .whites: return L10n.AnnotateAdjust.whites
    case .blacks: return L10n.AnnotateAdjust.blacks
    case .temperature: return L10n.AnnotateAdjust.temperature
    case .tint: return L10n.AnnotateAdjust.tint
    case .vibrance: return L10n.AnnotateAdjust.vibrance
    case .saturation: return L10n.AnnotateAdjust.saturation
    case .clarity: return L10n.AnnotateAdjust.clarity
    case .sharpness: return L10n.AnnotateAdjust.sharpness
    case .vignette: return L10n.AnnotateAdjust.vignette
    }
  }
}
