//
//  ExportSettings.swift
//  Snapzy
//
//  Export configuration models for video editor
//

import AVFoundation
import Foundation

// MARK: - Export Quality

enum ExportQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .low: return L10n.Common.low
        case .medium: return L10n.Common.medium
        case .high: return L10n.Common.high
        }
    }

    /// Maps to AVAssetExportSession preset
    var exportPreset: String {
        switch self {
        case .low: return AVAssetExportPresetMediumQuality
        case .medium: return AVAssetExportPresetHighestQuality
        case .high: return AVAssetExportPresetHighestQuality
        }
    }

    /// Bitrate multiplier for file size estimation
    var bitrateMultiplier: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 1.0
        }
    }
}

// MARK: - Audio Export Mode

enum AudioExportMode: String, CaseIterable, Identifiable {
    case keep = "Keep Original"
    case mute = "Mute"
    case custom = "Custom Volume"

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .keep: return L10n.VideoEditor.keepOriginal
        case .mute: return L10n.VideoEditor.mute
        case .custom: return L10n.VideoEditor.customVolume
        }
    }

    var icon: String {
        switch self {
        case .keep: return "speaker.wave.2"
        case .mute: return "speaker.slash"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Export Dimensions

enum ExportDimensionPreset: String, CaseIterable, Identifiable {
  case original = "Original"
  case percent90 = "90%"
  case percent80 = "80%"
  case percent60 = "60%"
  case percent50 = "50%"
  case percent40 = "40%"
  case percent30 = "30%"
  case percent20 = "20%"
  case custom = "Custom"

  var id: String { rawValue }

  /// Returns scale factor for percentage-based presets
  var scaleFactor: CGFloat? {
    switch self {
    case .percent90: return 0.90
    case .percent80: return 0.80
    case .percent60: return 0.60
    case .percent50: return 0.50
    case .percent40: return 0.40
    case .percent30: return 0.30
    case .percent20: return 0.20
    default: return nil
    }
  }

  /// Display label showing dimensions when available
  func displayLabel(for naturalSize: CGSize) -> String {
    // Guard against invalid dimensions (before video loads)
    guard naturalSize.width > 0 && naturalSize.height > 0 else {
      return rawValue
    }

    switch self {
    case .original:
      return L10n.VideoEditor.originalDimensionsLabel(
        Int(naturalSize.width),
        Int(naturalSize.height)
      )
    case .percent90, .percent80, .percent60, .percent50, .percent40, .percent30, .percent20:
      guard let scale = scaleFactor else { return rawValue }
      let width = Int(naturalSize.width * scale)
      let height = Int(naturalSize.height * scale)
      // Ensure even dimensions in display
      let evenWidth = width - (width % 2)
      let evenHeight = height - (height % 2)
      return "\(rawValue) (\(evenWidth)×\(evenHeight))"
    case .custom:
      return L10n.Common.custom
    }
  }
}

// MARK: - Export Settings Container

struct ExportSettings: Equatable {
    var quality: ExportQuality = .high
    var dimensionPreset: ExportDimensionPreset = .original
    var customWidth: Int = 1920
    var customHeight: Int = 1080
    var aspectRatioLocked: Bool = true
    var audioMode: AudioExportMode = .keep
    var audioVolume: Float = 1.0 // 0.0 to 2.0 (0% to 200%)

  /// Compute actual export dimensions for VIDEO CONTENT ONLY
  /// Note: Background padding is applied separately during rendering
  func exportSize(from naturalSize: CGSize) -> CGSize {
    switch dimensionPreset {
    case .original:
      return naturalSize

    case .percent90, .percent80, .percent60, .percent50, .percent40, .percent30, .percent20:
      guard let scale = dimensionPreset.scaleFactor else {
        return naturalSize
      }
      var targetWidth = Int(naturalSize.width * scale)
      var targetHeight = Int(naturalSize.height * scale)
      // Ensure even dimensions for video encoding
      targetWidth = targetWidth - (targetWidth % 2)
      targetHeight = targetHeight - (targetHeight % 2)
      return CGSize(width: targetWidth, height: targetHeight)

    case .custom:
      // Ensure even dimensions for video encoding
      let evenWidth = customWidth - (customWidth % 2)
      let evenHeight = customHeight - (customHeight % 2)
      return CGSize(width: evenWidth, height: evenHeight)
    }
  }

    /// Check if audio should be included in export
    var shouldIncludeAudio: Bool {
        audioMode != .mute
    }

    /// Get effective volume (0.0 to 2.0)
    var effectiveVolume: Float {
        switch audioMode {
        case .keep: return 1.0
        case .mute: return 0.0
        case .custom: return audioVolume
        }
    }
}
