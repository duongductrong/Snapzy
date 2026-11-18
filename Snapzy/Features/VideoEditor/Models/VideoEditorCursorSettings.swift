//
//  VideoEditorCursorSettings.swift
//  Snapzy
//
//  Editable cursor layer settings for Studio recordings (cursor captured as data).
//

import CoreGraphics
import Foundation

nonisolated enum VideoEditorCursorClickEffect: String, Codable, CaseIterable, Sendable {
  case none
  case ripple
  case ring
}

/// sRGB color with alpha, Codable for persistence.
nonisolated struct VideoEditorRGBAColor: Codable, Equatable, Hashable, Sendable {
  var red: CGFloat
  var green: CGFloat
  var blue: CGFloat
  var alpha: CGFloat

  static let defaultClick = VideoEditorRGBAColor(red: 0.2, green: 0.55, blue: 1, alpha: 0.6)
}

nonisolated struct VideoEditorCursorSettings: Codable, Equatable, Sendable {
  static let scaleRange: ClosedRange<CGFloat> = 0.5 ... 3
  static let idleDelayRange: ClosedRange<TimeInterval> = 0.5 ... 5
  static let idleFadeDuration: TimeInterval = 0.2

  var isVisible: Bool = true
  /// Multiplier on the captured cursor size.
  var scale: CGFloat = 1
  /// 0 = raw samples, 1 = heaviest smoothing.
  var smoothing: Double = 0.5
  var hideWhenIdle: Bool = false
  var idleDelay: TimeInterval = 1.5
  var clickEffect: VideoEditorCursorClickEffect = .ripple
  var clickColor: VideoEditorRGBAColor = .defaultClick
  /// Replace every captured cursor with the arrow.
  var alwaysUseArrow: Bool = false
  /// Decision D4: off by default.
  var clickSound: Bool = false
  var clickSoundVolume: Double = 0.6

  static let `default` = VideoEditorCursorSettings()

  /// Matches the cursor as it looked while recording (flatten pass).
  static func recorded(clickEffect: VideoEditorCursorClickEffect, clickColor: VideoEditorRGBAColor) -> Self {
    var settings = VideoEditorCursorSettings()
    settings.smoothing = 0
    settings.clickEffect = clickEffect
    settings.clickColor = clickColor
    return settings
  }

  init() {}

  private enum CodingKeys: String, CodingKey {
    case isVisible, scale, smoothing, hideWhenIdle, idleDelay, clickEffect, clickColor
    case alwaysUseArrow, clickSound, clickSoundVolume
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = VideoEditorCursorSettings.default
    isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? d.isVisible
    scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? d.scale
    smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? d.smoothing
    hideWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .hideWhenIdle) ?? d.hideWhenIdle
    idleDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .idleDelay) ?? d.idleDelay
    clickEffect = try c.decodeIfPresent(VideoEditorCursorClickEffect.self, forKey: .clickEffect) ?? d.clickEffect
    clickColor = try c.decodeIfPresent(VideoEditorRGBAColor.self, forKey: .clickColor) ?? d.clickColor
    alwaysUseArrow = try c.decodeIfPresent(Bool.self, forKey: .alwaysUseArrow) ?? d.alwaysUseArrow
    clickSound = try c.decodeIfPresent(Bool.self, forKey: .clickSound) ?? d.clickSound
    clickSoundVolume = try c.decodeIfPresent(Double.self, forKey: .clickSoundVolume) ?? d.clickSoundVolume
  }
}
