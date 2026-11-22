//
//  VideoEditorMotionBlurSettings.swift
//  Snapzy
//
//  Motion blur configuration for Studio screen recordings, preview, and export.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorMotionBlurSettings: Codable, Equatable, Hashable, Sendable {
  static let strengthRange: ClosedRange<Double> = 0.0 ... 1.0
  static let defaultShutterStrength: Double = 0.65

  static let `default` = VideoEditorMotionBlurSettings(
    isEnabled: true,
    shutterStrength: defaultShutterStrength,
    cursorBlurEnabled: true
  )

  static let disabled = VideoEditorMotionBlurSettings(
    isEnabled: false,
    shutterStrength: 0,
    cursorBlurEnabled: false
  )

  var isEnabled: Bool
  /// 0 = sharp (0° shutter), 0.5 = 180° cinema shutter, 1.0 = maximum liquid-smooth blur.
  var shutterStrength: Double
  /// Apply directional velocity blur to fast cursor flicks independently of camera zoom.
  var cursorBlurEnabled: Bool

  init(
    isEnabled: Bool = true,
    shutterStrength: Double = VideoEditorMotionBlurSettings.defaultShutterStrength,
    cursorBlurEnabled: Bool = true
  ) {
    self.isEnabled = isEnabled
    self.shutterStrength = Self.clampStrength(shutterStrength)
    self.cursorBlurEnabled = cursorBlurEnabled
  }

  private enum CodingKeys: String, CodingKey {
    case isEnabled, shutterStrength, cursorBlurEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = Self.default
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
    shutterStrength = Self.clampStrength(
      try container.decodeIfPresent(Double.self, forKey: .shutterStrength) ?? fallback.shutterStrength
    )
    cursorBlurEnabled = try container.decodeIfPresent(Bool.self, forKey: .cursorBlurEnabled) ?? fallback.cursorBlurEnabled
  }

  var effectiveCameraStrength: Double {
    guard isEnabled else { return 0 }
    return Self.clampStrength(shutterStrength)
  }

  var effectiveCursorStrength: Double {
    guard isEnabled, cursorBlurEnabled else { return 0 }
    return Self.clampStrength(shutterStrength)
  }

  var hasActiveBlur: Bool {
    effectiveCameraStrength > 0.001 || effectiveCursorStrength > 0.001
  }

  var strengthDisplayValue: String {
    "\(Int((shutterStrength * 100).rounded()))%"
  }

  static func clampStrength(_ value: Double) -> Double {
    min(max(value, strengthRange.lowerBound), strengthRange.upperBound)
  }
}
