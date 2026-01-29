//
//  ExportSettings.swift
//  ClaudeShot
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
  case percent75 = "75%"
  case percent50 = "50%"
  case percent25 = "25%"
  case hd1080 = "1080p"
  case hd720 = "720p"
  case sd480 = "480p"
  case custom = "Custom"

  var id: String { rawValue }

  /// Returns target height for fixed presets (width calculated from aspect ratio)
  var targetHeight: Int? {
    switch self {
    case .original, .percent75, .percent50, .percent25, .custom:
      return nil
    case .hd1080:
      return 1080
    case .hd720:
      return 720
    case .sd480:
      return 480
    }
  }

  /// Returns scale factor for percentage-based presets
  var scaleFactor: CGFloat? {
    switch self {
    case .percent75:
      return 0.75
    case .percent50:
      return 0.50
    case .percent25:
      return 0.25
    default:
      return nil
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
      return "Original (\(Int(naturalSize.width))×\(Int(naturalSize.height)))"
    case .percent75, .percent50, .percent25:
      guard let scale = scaleFactor else { return rawValue }
      let width = Int(naturalSize.width * scale)
      let height = Int(naturalSize.height * scale)
      // Ensure even dimensions in display
      let evenWidth = width - (width % 2)
      let evenHeight = height - (height % 2)
      return "\(rawValue) (\(evenWidth)×\(evenHeight))"
    case .hd1080, .hd720, .sd480:
      guard let targetH = targetHeight else { return rawValue }
      let aspectRatio = naturalSize.width / naturalSize.height
      var targetW = Int(CGFloat(targetH) * aspectRatio)
      targetW = targetW - (targetW % 2)
      let evenH = targetH - (targetH % 2)
      return "\(rawValue) (\(targetW)×\(evenH))"
    case .custom:
      return "Custom"
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

    case .percent75, .percent50, .percent25:
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

    case .hd1080, .hd720, .sd480:
      guard let targetHeight = dimensionPreset.targetHeight else {
        return naturalSize
      }
      let aspectRatio = naturalSize.width / naturalSize.height
      var targetWidth = Int(CGFloat(targetHeight) * aspectRatio)
      // Ensure even dimensions for video encoding
      targetWidth = targetWidth - (targetWidth % 2)
      let evenHeight = targetHeight - (targetHeight % 2)
      return CGSize(width: targetWidth, height: evenHeight)
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
